import SwiftUI
import SwiftData

@main
struct CofreApp: App {
    /// Um único contêiner para todo o app, criado uma vez.
    private let container = DataStore.makeContainer()

    @StateObject private var lock = AppLock()
    @StateObject private var settings = AppSettings()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(lock)
                .environmentObject(settings)
                .task {
                    SeedData.installIfNeeded(in: container.mainContext)
                    await lock.unlockIfNeeded(requireBiometrics: settings.requireBiometrics)
                }
                .onChange(of: scenePhase) { _, phase in
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
