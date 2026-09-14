import SwiftUI
import SwiftData

/// Cadastro e edição de conta.
struct AccountEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Institution.name) private var institutions: [Institution]

    /// nil cria uma conta nova.
    let account: Account?

    @State private var name = ""
    @State private var type: AccountType = .corrente
    @State private var openingBalance: Decimal = 0
    @State private var openingDate = Date()
    @State private var colorHex = Palette.picks[0]
    @State private var includeInNetWorth = true
    @State private var notes = ""
    @State private var institutionName = ""
    @State private var showingDeleteConfirmation = false

    private var isNew: Bool { account == nil }

    var body: some View {
        Form {
            Section {
                TextField("Apelido da conta", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }

                TextField("Banco ou instituição", text: $institutionName)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("O tipo muda onde a conta aparece: poupança e investimento contam como dinheiro guardado, não como saldo do dia a dia.")
            }

            Section {
                CurrencyField(title: "Saldo hoje", value: $openingBalance, allowNegative: true)
                DatePicker("Data desse saldo", selection: $openingDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "pt_BR"))
            } header: {
                Text("Ponto de partida")
            } footer: {
                Text("Coloque o saldo que o banco mostra agora. Todo lançamento importado com data posterior será somado a ele.")
            }

            Section("Aparência") {
                ColorPickerGrid(hex: $colorHex)
            }

            Section {
                Toggle("Somar no patrimônio", isOn: $includeInNetWorth)
                TextField("Observações", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            if let account, !isNew {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Apagar conta", systemImage: "trash")
                    }
                } footer: {
                    Text("Apagar a conta remove também os \((account.transactions ?? []).count) lançamentos ligados a ela. Se quiser só tirar da lista, arquive.")
                }
            }
        }
        .navigationTitle(isNew ? "Nova conta" : "Editar conta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Apagar esta conta e todos os seus lançamentos?",
                            isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) { delete() }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let account else { return }
        name = account.name
        type = account.type
        openingBalance = account.openingBalance
        openingDate = account.openingDate
        colorHex = account.colorHex
        includeInNetWorth = account.includeInNetWorth
        notes = account.notes
        institutionName = account.institution?.name ?? ""
    }

    /// Reaproveita a instituição existente em vez de criar duplicatas com o
    /// mesmo nome.
    private func resolveInstitution() -> Institution? {
        let trimmed = institutionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = institutions.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let created = Institution(name: trimmed, colorHex: colorHex)
        context.insert(created)
        return created
    }

    private func save() {
        let target = account ?? Account(name: name)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.type = type
        target.openingBalance = Money.rounded(openingBalance)
        target.openingDate = openingDate.startOfDay
        target.colorHex = colorHex
        target.includeInNetWorth = includeInNetWorth
        target.notes = notes
        target.institution = resolveInstitution()

        if account == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let account else { return }
        context.delete(account)
        try? context.save()
        dismiss()
    }
}
