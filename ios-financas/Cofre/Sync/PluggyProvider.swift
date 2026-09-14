import Foundation
import Security

/// Ponto de entrada para sincronização automática via agregador de Open Finance.
///
/// Por que fica desligado: o acesso direto às APIs do Open Finance do Banco
/// Central é reservado a instituições autorizadas. Para um app pessoal, o
/// caminho viável é um agregador (Pluggy, Belvo), que exige conta própria,
/// credenciais e faz os dados passarem por um terceiro.
///
/// A implementação real precisa de três coisas, nesta ordem:
///  1. `clientID` e `clientSecret` guardados no Keychain (nunca no código);
///  2. um `connectToken` de curta duração, trocado no backend do agregador;
///  3. o fluxo de conexão do agregador para o usuário autorizar cada banco.
///
/// Enquanto isso não existir, a classe falha de forma explícita em vez de
/// fingir que sincronizou.
final class PluggyProvider: FinanceSyncProvider {
    let id = "pluggy"
    let displayName = "Open Finance via agregador"
    let summary = "Sincronização automática de contas e cartões. Exige conta em um agregador e seus dados passam por ele."

    /// Só fica disponível quando houver credencial gravada no Keychain.
    var isAvailable: Bool { credentials != nil }

    private var credentials: Credentials? {
        Credentials.load()
    }

    func listItems() async throws -> [SyncItem] {
        guard credentials != nil else { throw SyncError.notConfigured(provider: displayName) }
        throw SyncError.notConfigured(provider: displayName)
    }

    func fetchTransactions(itemID: String, since: Date) async throws -> [StatementRow] {
        guard credentials != nil else { throw SyncError.notConfigured(provider: displayName) }
        throw SyncError.notConfigured(provider: displayName)
    }

    /// Credenciais do agregador. Ficam no Keychain com
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: não vão para backup nem
    /// para outro aparelho.
    struct Credentials {
        let clientID: String
        let clientSecret: String

        private static let service = "com.cofre.sync.pluggy"
        private static let account = "credenciais"

        static func load() -> Credentials? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let decoded = try? JSONDecoder().decode(Stored.self, from: data)
            else { return nil }
            return Credentials(clientID: decoded.clientID, clientSecret: decoded.clientSecret)
        }

        @discardableResult
        static func save(clientID: String, clientSecret: String) -> Bool {
            guard let data = try? JSONEncoder().encode(Stored(clientID: clientID, clientSecret: clientSecret)) else {
                return false
            }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)

            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }

        @discardableResult
        static func clear() -> Bool {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            return SecItemDelete(query as CFDictionary) == errSecSuccess
        }

        private struct Stored: Codable {
            let clientID: String
            let clientSecret: String
        }
    }
}
