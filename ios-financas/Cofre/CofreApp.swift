import SwiftUI
import SwiftData

@main
struct CofreApp: App {
    /// Um único contêiner para todo o app, criado uma vez.
    private let container = DataStore.makeContainer()

    @StateObject private var lock = AppLock()
    @StateObject private var settings = AppSettings()
    @StateObject private var inbox = ImportInbox()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(lock)
                .environmentObject(settings)
                .environmentObject(inbox)
                .task {
                    SeedData.installIfNeeded(in: container.mainContext)
                    inbox.scanSystemInbox()
                    inbox.restorePending()
                    await lock.unlockIfNeeded(requireBiometrics: settings.requireBiometrics)
                }
                // Chega aqui quando você toca em Compartilhar → Cofre no app do
                // banco, e também pelo atalho cofre://importar.
                .onOpenURL { url in
                    inbox.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // O sistema pode ter deixado um arquivo na Inbox
                        // enquanto o app estava em segundo plano.
                        inbox.scanSystemInbox()
                    }
                    // Trancar ao sair da tela evita que o saldo apareça no
                    // seletor de apps.
                    if phase != .active, settings.requireBiometrics {
                        lock.lock()
                    }
                }
        }
        .modelContainer(container)
    }
}
