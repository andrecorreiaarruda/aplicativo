import Foundation

/// Uma linha já normalizada de um extrato, independente do formato do arquivo.
///
/// OFX e CSV chegam aqui do mesmo jeito, e só o `ImportService` sabe virar
/// `Txn`. Um provedor de sincronização futuro (Pluggy, Belvo) entra por este
/// mesmo tipo, sem mexer no resto do app.
struct StatementRow: Identifiable, Hashable {
    let id = UUID()
    var date: Date
    var description: String
    /// Negativo é saída, positivo é entrada — mesma convenção do `Txn`.
    var amount: Decimal
    /// FITID do OFX ou id do agregador, quando existir.
    var externalID: String?
    var installmentIndex: Int?
    var installmentTotal: Int?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: StatementRow, rhs: StatementRow) -> Bool { lhs.id == rhs.id }
}

/// Resultado da leitura de um arquivo, antes de qualquer gravação.
struct StatementFile {
    var rows: [StatementRow]
    var source: TxSource
    var fileName: String
    /// Saldo final informado pelo arquivo (o OFX traz em LEDGERBAL), quando há.
    var reportedBalance: Decimal?
    var reportedBalanceDate: Date?
    /// Últimos dígitos da conta ou cartão informados no arquivo.
    var accountHint: String?
    /// Avisos não fatais para mostrar na prévia (linhas ignoradas, etc.).
    var warnings: [String] = []

    var periodStart: Date? { rows.map(\.date).min() }
    var periodEnd: Date? { rows.map(\.date).max() }

    var totalIn: Decimal { rows.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount } }
    var totalOut: Decimal { rows.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount } }
}

enum ImportError: LocalizedError {
    case unreadableFile
    case emptyFile
    case unsupportedFormat(String)
    case noTransactionsFound
    case missingColumnMapping

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Não consegui ler o arquivo. Verifique se ele não está protegido por senha."
        case .emptyFile:
            return "O arquivo está vazio."
        case .unsupportedFormat(let ext):
            return "Formato .\(ext) não suportado. Use OFX, CSV ou TXT."
        case .noTransactionsFound:
            return "Não encontrei nenhum lançamento neste arquivo."
        case .missingColumnMapping:
            return "Indique quais colunas têm a data, a descrição e o valor."
        }
    }
}
