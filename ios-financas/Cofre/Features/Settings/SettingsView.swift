import SwiftUI
import SwiftData

/// Ajustes, privacidade, histórico de importações e exportação dos dados.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: AppLock

    @Query(sort: \ImportBatch.importedAt, order: .reverse) private var batches: [ImportBatch]
    @Query private var transactions: [Txn]
    @Query private var accounts: [Account]
    @Query private var cards: [CreditCard]

    @State private var exportURL: URL?
    @State private var showingEraseConfirmation = false
    @State private var showingSampleConfirmation = false
    @State private var showingProviders = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $settings.requireBiometrics) {
                        Label("Exigir \(lock.biometryName) ao abrir", systemImage: "faceid")
                    }
                    Toggle(isOn: $settings.hideAmounts) {
                        Label("Esconder valores na tela", systemImage: "eye.slash")
                    }
                } header: {
                    Text("Privacidade")
                } footer: {
                    Text("Os dados ficam em um banco local dentro do app, protegido pela criptografia do iOS. Não há conta, login nem servidor.")
                }

                Section {
                    NavigationLink {
                        ReadOnlyExplanationView()
                    } label: {
                        Label("O que este app não faz", systemImage: "hand.raised")
                    }

                    Button {
                        showingProviders = true
                    } label: {
                        Label("Fontes de dados", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Section("Histórico de importações") {
                    if batches.isEmpty {
                        Text("Nenhuma importação ainda.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(batches.prefix(15)) { batch in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(batch.fileName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(batch.inserted) importados • \(batch.duplicatesSkipped) repetidos • \(batch.destinationName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(DateFormatters.full.string(from: batch.importedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    try? ImportService(context: context).undo(batch: batch)
                                } label: {
                                    Label("Desfazer", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Exportar lançamentos em CSV", systemImage: "square.and.arrow.up")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Compartilhar arquivo gerado", systemImage: "paperplane")
                        }
                    }
                } header: {
                    Text("Seus dados")
                } footer: {
                    Text("O arquivo sai com tudo: data, descrição original, valor, categoria e onde foi. Você continua dono dos seus dados mesmo se parar de usar o app.")
                }

                Section("Manutenção") {
                    Button {
                        showingSampleConfirmation = true
                    } label: {
                        Label("Carregar dados de exemplo", systemImage: "wand.and.stars")
                    }

                    Button(role: .destructive) {
                        showingEraseConfirmation = true
                    } label: {
                        Label("Apagar tudo e recomeçar", systemImage: "trash")
                    }
                }

                Section {
                    LabeledContent("Lançamentos", value: "\(transactions.count)")
                    LabeledContent("Contas", value: "\(accounts.count)")
                    LabeledContent("Cartões", value: "\(cards.count)")
                    LabeledContent("Versão", value: appVersion)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Pronto") { dismiss() } }
            }
            .sheet(isPresented: $showingProviders) { SyncProvidersView() }
            .confirmationDialog(
                "Isso apaga contas, cartões, lançamentos e metas. Não dá para desfazer.",
                isPresented: $showingEraseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Apagar tudo", role: .destructive) {
                    SeedData.eraseEverything(in: context)
                }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog(
                "Carregar uma conta, um cartão e alguns meses de lançamentos fictícios?",
                isPresented: $showingSampleConfirmation,
                titleVisibility: .visible
            ) {
                Button("Carregar exemplo") {
                    SeedData.installSampleLedger(in: context)
                    // Recua o início dos envelopes para os meses de exemplo
                    // aparecerem já com saldo acumulado.
                    settings.envelopeStartMonth = MonthKey.current.adding(months: -4)
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Gera um CSV com ponto e vírgula e vírgula decimal — abre direto no Excel
    /// e no Numbers em português.
    private func exportCSV() {
        var lines = ["data;descricao;texto_original;valor;tipo;categoria;origem;ignorado"]

        for txn in transactions.sorted(by: { $0.date < $1.date }) {
            let fields = [
                DateFormatters.short.string(from: txn.date),
                escape(txn.displayName),
                escape(txn.rawDescription),
                Money.plain(txn.amount),
                txn.kind.label,
                escape(txn.category?.name ?? ""),
                escape(txn.account?.name ?? txn.card?.name ?? ""),
                txn.isIgnored ? "sim" : "nao"
            ]
            lines.append(fields.joined(separator: ";"))
        }

        let csv = lines.joined(separator: "\n")
        let name = "cofre-lancamentos-\(DateFormatters.short.string(from: Date()).replacingOccurrences(of: "/", with: "-")).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        // BOM para o Excel reconhecer os acentos.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(csv.data(using: .utf8) ?? Data())
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }

    private func escape(_ text: String) -> String {
        guard text.contains(";") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Explica em palavras diretas o que o app não consegue fazer, e por quê.
struct ReadOnlyExplanationView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Este app só lê.")
                        .font(.title3.weight(.semibold))
                    Text("Ele não tem nenhum código capaz de mover dinheiro. Não é uma configuração que dá para ligar: a capacidade simplesmente não existe no aplicativo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("O que ele não faz") {
                item("hand.raised", "Não faz transferência, Pix nem pagamento.")
                item("key.slash", "Não pede sua senha do banco nem guarda credencial de acesso.")
                item("network.slash", "Não envia seus lançamentos para nenhum servidor.")
                item("person.2.slash", "Não tem conta de usuário, login nem sincronização entre aparelhos.")
                item("chart.bar.xaxis", "Não usa seus dados para publicidade nem para nada além de mostrar na tela.")
            }

            Section("O que ele faz") {
                item("doc.text", "Lê arquivos de extrato e fatura que você mesmo baixou do banco.")
                item("square.and.pencil", "Aceita lançamentos digitados à mão.")
                item("chart.pie", "Calcula saldos, faturas, orçamento e metas com esses dados.")
                item("square.and.arrow.up", "Exporta tudo em CSV quando você quiser levar embora.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("E a sincronização automática?")
                        .font(.subheadline.weight(.semibold))
                    Text("O acesso direto ao Open Finance do Banco Central é reservado a instituições autorizadas. Para um app pessoal, o caminho seria um agregador (Pluggy, Belvo), que exige conta própria e faz seus dados passarem por um terceiro. O app já tem o encaixe pronto para isso, mas ele vem desligado — e continua sem poder mover dinheiro, porque essa capacidade não está descrita em lugar nenhum do código.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Somente leitura")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

/// Lista as fontes de dados disponíveis e o estado de cada uma.
struct SyncProvidersView: View {
    @Environment(\.dismiss) private var dismiss
    private let registry = SyncProviderRegistry.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(registry.providers, id: \.id) { provider in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(provider.displayName).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(provider.isAvailable ? "ativo" : "desligado")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        (provider.isAvailable ? Palette.positive : Palette.neutral).opacity(0.15)
                                    )
                                )
                                .foregroundStyle(provider.isAvailable ? Palette.positive : Palette.neutral)
                        }
                        Text(provider.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    InlineNote(
                        symbol: "info.circle",
                        text: "Qualquer fonte que venha a ser ligada aqui continua sendo só de leitura: o app não tem função de pagamento."
                    )
                }
            }
            .navigationTitle("Fontes de dados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Pronto") { dismiss() } }
            }
        }
    }
}
