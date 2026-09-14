import Foundation

/// Contrato de qualquer fonte de dados do app.
///
/// Existe uma regra que não se negocia aqui: o protocolo só sabe **ler**. Não há
/// método para pagar, transferir ou alterar nada na instituição. Um provedor
/// futuro (Pluggy, Belvo) entra por esta porta e continua sem conseguir mover
/// dinheiro, porque a capacidade simplesmente não está descrita.
protocol FinanceSyncProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var summary: String { get }
    /// Falso enquanto faltar credencial ou configuração.
    var isAvailable: Bool { get }

    /// Contas e cartões que a fonte enxerga.
    func listItems() async throws -> [SyncItem]

    /// Lançamentos de um item a partir de uma data.
    func fetchTransactions(itemID: String, since: Date) async throws -> [StatementRow]
}

/// Uma conta ou cartão visto por um provedor, antes de virar `Account`/`CreditCard`.
struct SyncItem: Identifiable, Hashable {
    enum Nature: String { case account, card }

    let id: String
    var name: String
    var institutionName: String
    var nature: Nature
    var lastFourDigits: String?
    var currentBalance: Decimal?
    var creditLimit: Decimal?
}

enum SyncError: LocalizedError {
    case notConfigured(provider: String)
    case authenticationFailed
    case network(String)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "\(provider) ainda não está configurado. Informe as credenciais em Ajustes → Sincronização."
        case .authenticationFailed:
            return "A instituição recusou as credenciais. Refaça a conexão."
        case .network(let detail):
            return "Falha de rede: \(detail)"
        case .itemNotFound:
            return "Conta ou cartão não encontrado no provedor."
        }
    }
}

/// Registro dos provedores conhecidos. Hoje só há o de arquivo; o de agregador
/// aparece na lista como "não configurado" para deixar o caminho visível.
final class SyncProviderRegistry {
    static let shared = SyncProviderRegistry()

    let providers: [FinanceSyncProvider]

    private init() {
        self.providers = [FileImportProvider(), PluggyProvider()]
    }

    func provider(id: String) -> FinanceSyncProvider? {
        providers.first { $0.id == id }
    }
}
