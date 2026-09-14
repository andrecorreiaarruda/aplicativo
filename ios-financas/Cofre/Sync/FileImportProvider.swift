import Foundation

/// O provedor padrão: você baixa o extrato do banco e o app lê o arquivo.
///
/// Não pede senha de banco, não usa servidor e nada sai do aparelho. É o modo
/// que funciona com qualquer instituição, hoje, de graça.
final class FileImportProvider: FinanceSyncProvider {
    let id = "arquivo"
    let displayName = "Extrato do banco (OFX/CSV)"
    let summary = "Você exporta o extrato ou a fatura pelo app do banco e importa aqui. Nada sai do aparelho."
    var isAvailable: Bool { true }

    /// Arquivo não tem catálogo de contas: a escolha do destino é feita por você
    /// na tela de importação.
    func listItems() async throws -> [SyncItem] { [] }

    func fetchTransactions(itemID: String, since: Date) async throws -> [StatementRow] { [] }

    /// Extensões que a tela de importação aceita.
    static let supportedExtensions = ["ofx", "qfx", "csv", "txt", "tsv"]
}
