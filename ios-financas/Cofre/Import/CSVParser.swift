import Foundation

/// Tabela lida de um CSV, ainda sem significado financeiro.
struct CSVTable {
    var header: [String]?
    var rows: [[String]]
    var delimiter: Character

    var columnCount: Int {
        max(header?.count ?? 0, rows.map(\.count).max() ?? 0)
    }

    /// Nome da coluna para mostrar na tela de mapeamento.
    func columnLabel(_ index: Int) -> String {
        if let header, index < header.count, !header[index].isEmpty {
            return header[index]
        }
        return "Coluna \(index + 1)"
    }

    /// Alguns exemplos da coluna, para o usuário conferir que escolheu certo.
    func samples(_ index: Int, limit: Int = 3) -> [String] {
        rows.prefix(limit).compactMap { row in
            index < row.count && !row[index].isEmpty ? row[index] : nil
        }
    }
}

/// Leitor de CSV conforme o RFC 4180: respeita aspas, aspas duplicadas dentro do
/// campo e quebras de linha dentro de um campo entre aspas.
enum CSVReader {

    static func read(data: Data) throws -> CSVTable {
        guard let text = decode(data) else { throw ImportError.unreadableFile }
        return try read(text: text)
    }

    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty { return utf8 }
        if let latin = String(data: data, encoding: .isoLatin1), !latin.isEmpty { return latin }
        return String(data: data, encoding: .windowsCP1252)
    }

    static func read(text raw: String) throws -> CSVTable {
        // BOM do Excel atrapalha a comparação do primeiro cabeçalho.
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        let delimiter = detectDelimiter(text)
        var rows = split(text: text, delimiter: delimiter)
        rows.removeAll { row in row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { throw ImportError.emptyFile }

        let first = rows[0]
        if looksLikeHeader(first) {
            return CSVTable(header: first.map { $0.trimmingCharacters(in: .whitespaces) },
                            rows: Array(rows.dropFirst()),
                            delimiter: delimiter)
        }
        return CSVTable(header: nil, rows: rows, delimiter: delimiter)
    }

    /// Escolhe entre `;`, `,` e tab pela contagem fora de aspas na primeira
    /// linha — `;` é o padrão dos bancos brasileiros por causa da vírgula
    /// decimal.
    static func detectDelimiter(_ text: String) -> Character {
        let sample = text.prefix(4000)
        var counts: [Character: Int] = [";": 0, ",": 0, "\t": 0]
        var inQuotes = false

        for ch in sample {
            if ch == "\"" { inQuotes.toggle(); continue }
            guard !inQuotes else { continue }
            if counts[ch] != nil { counts[ch, default: 0] += 1 }
        }
        if counts[";", default: 0] > 0 { return ";" }
        if counts["\t", default: 0] > counts[",", default: 0] { return "\t" }
        return ","
    }

    /// Varredura caractere a caractere: precisamos enxergar o próximo símbolo
    /// para tratar aspas escapadas ("") e a quebra \r\n do Windows.
    private static func split(text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(ch)
                }
                i += 1
                continue
            }

            switch ch {
            case "\"":
                inQuotes = true
            case delimiter:
                row.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            case "\n":
                row.append(field.trimmingCharacters(in: .whitespaces))
                rows.append(row)
                row = []
                field = ""
            case "\r":
                break
            default:
                field.append(ch)
            }
            i += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: .whitespaces))
            rows.append(row)
        }
        return rows
    }

    /// A primeira linha é cabeçalho quando nenhuma célula parece data ou valor.
    private static func looksLikeHeader(_ row: [String]) -> Bool {
        let meaningful = row.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !meaningful.isEmpty else { return false }
        let dataLike = meaningful.filter { cell in
            CSVImporter.parseDate(cell) != nil || Money.parse(cell) != nil
        }
        return dataLike.isEmpty
    }
}

/// Como as colunas do CSV viram lançamentos.
struct CSVMapping: Hashable {
    var dateColumn: Int = 0
    var descriptionColumn: Int = 1
    /// Coluna única com o valor já sinalizado.
    var amountColumn: Int? = 2
    /// Ou duas colunas separadas, formato comum em extratos de banco.
    var debitColumn: Int?
    var creditColumn: Int?
    /// nil = detecção automática do formato de data.
    var dateFormat: String?
    /// Faturas de cartão costumam listar a compra como positiva; aqui invertemos.
    var invertSign: Bool = false

    var isValid: Bool {
        dateColumn >= 0 && descriptionColumn >= 0 && (amountColumn != nil || debitColumn != nil || creditColumn != nil)
    }
}

/// Modelos prontos para os bancos mais usados, com a opção genérica no fim.
struct CSVPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let mapping: CSVMapping
    /// Palavras do cabeçalho que identificam este banco.
    let headerHints: [String]

    static let all: [CSVPreset] = [
        CSVPreset(
            id: "nubank-conta",
            name: "Nubank — conta",
            detail: "Data, Valor, Identificador, Descrição",
            mapping: CSVMapping(dateColumn: 0, descriptionColumn: 3, amountColumn: 1, dateFormat: "dd/MM/yyyy"),
            headerHints: ["identificador", "descrição"]
        ),
        CSVPreset(
            id: "nubank-cartao",
            name: "Nubank — cartão",
            detail: "date, title, amount (compras positivas)",
            mapping: CSVMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, dateFormat: "yyyy-MM-dd", invertSign: true),
            headerHints: ["title", "amount"]
        ),
        CSVPreset(
            id: "inter",
            name: "Banco Inter",
            detail: "Data Lançamento, Descrição, Valor",
            mapping: CSVMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, dateFormat: "dd/MM/yyyy"),
            headerHints: ["data lancamento", "data lançamento"]
        ),
        CSVPreset(
            id: "itau",
            name: "Itaú",
            detail: "dd/mm/aaaa; descrição; valor",
            mapping: CSVMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, dateFormat: "dd/MM/yyyy"),
            headerHints: ["lancamento", "lançamento"]
        ),
        CSVPreset(
            id: "c6",
            name: "C6 Bank",
            detail: "Data de Compra, Descrição, Valor (USD/BRL)",
            mapping: CSVMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, dateFormat: "dd/MM/yyyy", invertSign: true),
            headerHints: ["data de compra"]
        ),
        CSVPreset(
            id: "generico",
            name: "Genérico",
            detail: "Escolha as colunas manualmente",
            mapping: CSVMapping(),
            headerHints: []
        )
    ]
}

/// Converte uma `CSVTable` em linhas de extrato.
enum CSVImporter {

    private static let dateFormats = [
        "dd/MM/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "dd/MM/yy",
        "dd.MM.yyyy", "yyyy/MM/dd", "MM/dd/yyyy"
    ]

    private static var formatterCache: [String: DateFormatter] = [:]

    private static func formatter(_ format: String) -> DateFormatter {
        if let cached = formatterCache[format] { return cached }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.calendar = Calendar.brazil
        f.timeZone = Calendar.brazil.timeZone
        f.dateFormat = format
        f.isLenient = false
        formatterCache[format] = f
        return f
    }

    /// Lê uma data testando os formatos usuais, do mais provável ao menos.
    static func parseDate(_ raw: String, preferred: String? = nil) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 6 else { return nil }
        // Descarta textos que são claramente número, não data.
        guard text.contains("/") || text.contains("-") || text.contains(".") else { return nil }

        var order = dateFormats
        if let preferred {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }
        for format in order {
            if let date = formatter(format).date(from: text) {
                return date.startOfDay
            }
        }
        return nil
    }

    /// Palpite de mapeamento: usa o preset que casa com o cabeçalho e, se nada
    /// casar, deduz olhando o conteúdo das colunas.
    static func suggestMapping(for table: CSVTable) -> (preset: CSVPreset, mapping: CSVMapping) {
        if let header = table.header {
            let normalized = header.map { TextNormalizer.normalize($0).lowercased() }
            for preset in CSVPreset.all where !preset.headerHints.isEmpty {
                let hints = preset.headerHints.map { TextNormalizer.normalize($0).lowercased() }
                if hints.allSatisfy({ hint in normalized.contains { $0.contains(hint) } }) {
                    return (preset, preset.mapping)
                }
            }
            if let byName = mappingFromHeaderNames(normalized) {
                return (CSVPreset.all.last!, byName)
            }
        }
        return (CSVPreset.all.last!, inferMapping(from: table))
    }

    private static func mappingFromHeaderNames(_ header: [String]) -> CSVMapping? {
        func find(_ needles: [String]) -> Int? {
            for (index, name) in header.enumerated() {
                if needles.contains(where: { name.contains($0) }) { return index }
            }
            return nil
        }

        guard let dateColumn = find(["data", "date", "dt"]) else { return nil }
        guard let descriptionColumn = find(["descricao", "description", "title", "historico", "lancamento", "estabelecimento", "memo"]) else { return nil }

        let debit = find(["debito", "saida", "debit"])
        let credit = find(["credito", "entrada", "credit"])
        let amount = find(["valor", "amount", "montante", "quantia"])

        if let debit, let credit, debit != credit {
            return CSVMapping(dateColumn: dateColumn, descriptionColumn: descriptionColumn,
                              amountColumn: nil, debitColumn: debit, creditColumn: credit)
        }
        guard let amount else { return nil }
        return CSVMapping(dateColumn: dateColumn, descriptionColumn: descriptionColumn, amountColumn: amount)
    }

    /// Sem cabeçalho útil: a primeira coluna que parece data vira data, a que
    /// parece número vira valor, e a de texto mais longo vira descrição.
    private static func inferMapping(from table: CSVTable) -> CSVMapping {
        let count = table.columnCount
        guard count >= 2 else { return CSVMapping() }
        let sample = Array(table.rows.prefix(12))

        func score(_ index: Int, _ test: (String) -> Bool) -> Int {
            sample.filter { row in index < row.count && test(row[index]) }.count
        }

        func dateScore(_ index: Int) -> Int { score(index) { CSVImporter.parseDate($0) != nil } }
        func amountScore(_ index: Int) -> Int { score(index) { Money.parse($0) != nil } }
        func textLength(_ index: Int) -> Int {
            sample.reduce(0) { total, row in total + (index < row.count ? row[index].count : 0) }
        }

        let dateColumn = (0..<count).max { dateScore($0) < dateScore($1) } ?? 0
        let amountColumn = (0..<count)
            .filter { $0 != dateColumn }
            .max { amountScore($0) < amountScore($1) } ?? min(2, count - 1)
        let descriptionColumn = (0..<count)
            .filter { $0 != dateColumn && $0 != amountColumn }
            .max { textLength($0) < textLength($1) } ?? min(1, count - 1)

        return CSVMapping(dateColumn: dateColumn, descriptionColumn: descriptionColumn, amountColumn: amountColumn)
    }

    static func rows(from table: CSVTable, mapping: CSVMapping, fileName: String) throws -> StatementFile {
        guard mapping.isValid else { throw ImportError.missingColumnMapping }

        var rows: [StatementRow] = []
        var skipped = 0

        for row in table.rows {
            guard mapping.dateColumn < row.count,
                  let date = parseDate(row[mapping.dateColumn], preferred: mapping.dateFormat) else {
                skipped += 1
                continue
            }

            var amount: Decimal?
            if let column = mapping.amountColumn, column < row.count {
                amount = Money.parse(row[column])
            } else {
                // Colunas separadas: débito é saída, crédito é entrada.
                let debit = mapping.debitColumn.flatMap { $0 < row.count ? Money.parse(row[$0]) : nil } ?? 0
                let credit = mapping.creditColumn.flatMap { $0 < row.count ? Money.parse(row[$0]) : nil } ?? 0
                let value = credit - abs(debit)
                amount = value == 0 ? nil : value
            }

            guard var value = amount, value != 0 else {
                skipped += 1
                continue
            }
            if mapping.invertSign { value = -value }

            let description = mapping.descriptionColumn < row.count
                ? row[mapping.descriptionColumn]
                : "Lançamento"
            let installment = TextNormalizer.installment(in: description)

            rows.append(
                StatementRow(
                    date: date,
                    description: description.isEmpty ? "Lançamento" : description,
                    amount: value,
                    externalID: nil,
                    installmentIndex: installment?.index,
                    installmentTotal: installment?.total
                )
            )
        }

        guard !rows.isEmpty else { throw ImportError.noTransactionsFound }

        var warnings: [String] = []
        if skipped > 0 {
            warnings.append("\(skipped) linha(s) sem data ou valor legível foram ignoradas.")
        }

        return StatementFile(
            rows: rows.sorted { $0.date < $1.date },
            source: .csv,
            fileName: fileName,
            reportedBalance: nil,
            reportedBalanceDate: nil,
            accountHint: nil,
            warnings: warnings
        )
    }
}
