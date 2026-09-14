import Foundation
import SwiftData

/// Onde os lançamentos importados vão parar.
enum ImportDestination: Hashable {
    case account(Account)
    case card(CreditCard)

    var name: String {
        switch self {
        case .account(let a): return a.name
        case .card(let c): return c.name
        }
    }

    var isCard: Bool {
        if case .card = self { return true }
        return false
    }

    var identifier: String {
        switch self {
        case .account(let a): return a.id.uuidString
        case .card(let c): return c.id.uuidString
        }
    }

    // Hashable escrito à mão: o identificador já distingue os destinos e assim
    // não dependemos de como o SwiftData implementa igualdade nos modelos.
    static func == (lhs: ImportDestination, rhs: ImportDestination) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

/// Uma linha do arquivo já casada com o que existe no app, pronta para você
/// revisar antes de gravar.
struct ImportPreviewItem: Identifiable {
    let id = UUID()
    var row: StatementRow
    var suggestion: Categorizer.Suggestion
    /// Já existe um lançamento igual — por padrão não será importado.
    var isDuplicate: Bool
    /// Você pode incluir ou excluir cada linha na revisão.
    var include: Bool
}

/// Lê arquivos, monta a prévia e grava os lançamentos.
///
/// O serviço nunca conversa com banco nenhum: ele só interpreta um arquivo que
/// você já baixou. É isso que mantém o app estritamente de leitura.
@MainActor
final class ImportService {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Leitura

    /// Escolhe o leitor pela extensão e, em último caso, pelo conteúdo.
    static func read(data: Data, fileName: String, mapping: CSVMapping? = nil) throws -> StatementFile {
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "ofx", "qfx":
            return try OFXParser.parse(data: data, fileName: fileName)
        case "csv", "txt", "tsv":
            let table = try CSVReader.read(data: data)
            let resolved = mapping ?? CSVImporter.suggestMapping(for: table).mapping
            return try CSVImporter.rows(from: table, mapping: resolved, fileName: fileName)
        case "":
            // Sem extensão: decide pelo conteúdo.
            if let text = String(data: data.prefix(4096), encoding: .utf8) ?? String(data: data.prefix(4096), encoding: .isoLatin1),
               text.uppercased().contains("<OFX") || text.uppercased().contains("OFXHEADER") {
                return try OFXParser.parse(data: data, fileName: fileName)
            }
            let table = try CSVReader.read(data: data)
            let resolved = mapping ?? CSVImporter.suggestMapping(for: table).mapping
            return try CSVImporter.rows(from: table, mapping: resolved, fileName: fileName)
        default:
            throw ImportError.unsupportedFormat(ext)
        }
    }

    // MARK: - Prévia

    /// Impressão digital que identifica o mesmo lançamento entre importações.
    ///
    /// `nonisolated` porque é cálculo puro e precisa rodar também fora da main
    /// actor (a carga de dados de exemplo, por exemplo).
    nonisolated static func fingerprint(destination: String, date: Date, amount: Decimal, description: String) -> String {
        let day = DateFormatters.short.string(from: date)
        let value = NSDecimalNumber(decimal: Money.rounded(amount)).stringValue
        let text = TextNormalizer.normalize(description).prefix(40)
        return "\(destination)|\(day)|\(value)|\(text)"
    }

    /// Monta a prévia marcando o que já existe.
    ///
    /// A comparação usa o identificador do banco quando ele vem no arquivo, e a
    /// impressão digital quando não vem. Reimportar o mesmo extrato duas vezes é
    /// o erro mais comum, e ele não pode duplicar nada.
    func preview(
        file: StatementFile,
        destination: ImportDestination,
        categories: [Category],
        rules: [MerchantRule]
    ) -> [ImportPreviewItem] {
        let existing = existingTransactions(for: destination)
        let existingIDs = Set(existing.compactMap(\.externalID).filter { !$0.isEmpty })
        var existingFingerprints = Set(existing.map(\.fingerprint).filter { !$0.isEmpty })

        return file.rows.map { row in
            let suggestion = Categorizer.suggest(
                for: row,
                categories: categories,
                rules: rules,
                isCard: destination.isCard
            )

            let print = ImportService.fingerprint(
                destination: destination.identifier,
                date: row.date,
                amount: row.amount,
                description: row.description
            )

            var duplicate = false
            if let externalID = row.externalID, !externalID.isEmpty, existingIDs.contains(externalID) {
                duplicate = true
            } else if existingFingerprints.contains(print) {
                duplicate = true
            } else {
                // Duas compras idênticas no mesmo dia são possíveis; aceitamos a
                // primeira e marcamos as seguintes do mesmo arquivo como novas
                // removendo a digital já consumida.
                existingFingerprints.insert(print)
            }

            return ImportPreviewItem(
                row: row,
                suggestion: suggestion,
                isDuplicate: duplicate,
                include: !duplicate
            )
        }
    }

    private func existingTransactions(for destination: ImportDestination) -> [Txn] {
        switch destination {
        case .account(let account): return account.transactions ?? []
        case .card(let card): return card.transactions ?? []
        }
    }

    // MARK: - Gravação

    @discardableResult
    func commit(
        items: [ImportPreviewItem],
        file: StatementFile,
        destination: ImportDestination
    ) throws -> ImportBatch {
        let batch = ImportBatch(
            fileName: file.fileName,
            source: file.source,
            destinationName: destination.name
        )
        batch.totalRows = items.count
        batch.duplicatesSkipped = items.filter { $0.isDuplicate && !$0.include }.count
        batch.periodStart = file.periodStart
        batch.periodEnd = file.periodEnd

        var inserted = 0

        for item in items where item.include {
            let txn = Txn(
                date: item.row.date,
                displayName: item.suggestion.displayName,
                amount: item.row.amount,
                kind: item.suggestion.kind,
                source: file.source,
                rawDescription: item.row.description
            )
            txn.externalID = item.row.externalID
            txn.fingerprint = ImportService.fingerprint(
                destination: destination.identifier,
                date: item.row.date,
                amount: item.row.amount,
                description: item.row.description
            )
            txn.importBatchID = batch.id
            txn.category = item.suggestion.category
            txn.installmentIndex = item.row.installmentIndex
            txn.installmentTotal = item.row.installmentTotal

            switch destination {
            case .account(let account):
                txn.account = account
            case .card(let card):
                txn.card = card
                txn.invoiceKey = InvoiceCalculator.cycle(for: card, containing: item.row.date).monthKey.key
            }

            context.insert(txn)
            inserted += 1
        }

        batch.inserted = inserted
        context.insert(batch)
        try context.save()
        return batch
    }

    /// Desfaz uma importação inteira, apagando só o que ela criou.
    func undo(batch: ImportBatch) throws {
        let id = batch.id
        let descriptor = FetchDescriptor<Txn>(predicate: #Predicate { $0.importBatchID == id })
        for txn in try context.fetch(descriptor) {
            context.delete(txn)
        }
        context.delete(batch)
        try context.save()
    }

    /// Registra a correção de categoria como regra, para acertar da próxima vez.
    func learn(from txn: Txn) throws {
        guard let category = txn.category else { return }
        let pattern = Categorizer.learnPattern(from: txn.rawDescription)
        guard !pattern.isEmpty else { return }

        let descriptor = FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.pattern == pattern })
        if let existing = try context.fetch(descriptor).first {
            existing.category = category
            existing.displayName = txn.displayName
            existing.hits += 1
        } else {
            let rule = MerchantRule(pattern: pattern, category: category, displayName: txn.displayName)
            rule.hits = 1
            context.insert(rule)
        }
        try context.save()
    }
}
