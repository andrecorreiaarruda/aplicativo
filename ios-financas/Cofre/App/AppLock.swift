import Foundation
import LocalAuthentication

/// Trava de entrada por Face ID / Touch ID.
///
/// A proteção real dos dados é a criptografia do iOS; esta trava serve para o
/// caso comum de alguém pegar o aparelho já desbloqueado.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var lastError: String?
    @Published private(set) var isAuthenticating = false

    /// Qual biometria este aparelho tem, para o texto do botão fazer sentido.
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "código do aparelho"
        }
    }

    var isBiometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lock() {
        isUnlocked = false
    }

    func unlockIfNeeded(requireBiometrics: Bool) async {
        guard requireBiometrics else {
            isUnlocked = true
            return
        }
        await authenticate()
    }

    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        // `deviceOwnerAuthentication` aceita o código do aparelho quando a
        // biometria falha, então ninguém fica trancado para fora dos próprios
        // dados.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            isUnlocked = true
            lastError = nil
            return
        }

        do {
            let granted = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Desbloqueie para ver suas finanças"
            )
            isUnlocked = granted
            lastError = granted ? nil : "Autenticação negada."
        } catch {
            isUnlocked = false
            lastError = (error as NSError).code == LAError.userCancel.rawValue
                ? nil
                : "Não foi possível autenticar."
        }
    }
}
