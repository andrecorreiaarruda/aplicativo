import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        Group {
            if lock.isUnlocked {
                MainTabView()
                    .transition(.opacity)
            } else {
                LockScreen()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isUnlocked)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Resumo", systemImage: "square.grid.2x2") }
                .tag(0)

            AccountsView()
                .tabItem { Label("Contas", systemImage: "building.columns") }
                .tag(1)

            CardsView()
                .tabItem { Label("Cartões", systemImage: "creditcard") }
                .tag(2)

            TransactionsView()
                .tabItem { Label("Lançamentos", systemImage: "list.bullet") }
                .tag(3)

            PlanningView()
                .tabItem { Label("Planejar", systemImage: "target") }
                .tag(4)
        }
        .onAppear { selection = settings.startTab }
    }
}

struct LockScreen: View {
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Cofre")
                    .font(.largeTitle.bold())
                Text("Suas finanças ficam só neste aparelho.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = lock.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.negative)
            }

            Button {
                Task { await lock.authenticate() }
            } label: {
                Label("Desbloquear com \(lock.biometryName)", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
