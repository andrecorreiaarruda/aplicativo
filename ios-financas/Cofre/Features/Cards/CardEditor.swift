import SwiftUI
import SwiftData

/// Cadastro e edição de cartão de crédito.
struct CardEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Institution.name) private var institutions: [Institution]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name) private var accounts: [Account]

    let card: CreditCard?

    @State private var name = ""
    @State private var brand: CardBrand = .outra
    @State private var lastFour = ""
    @State private var creditLimit: Decimal = 0
    @State private var closingDay = 25
    @State private var dueDay = 5
    @State private var colorHex = Palette.picks[1]
    @State private var institutionName = ""
    @State private var paymentAccountID: UUID?
    @State private var showingDeleteConfirmation = false

    private var isNew: Bool { card == nil }

    /// Mostra ao vivo em qual fatura uma compra de hoje cairia — é o jeito mais
    /// direto de conferir se os dias foram digitados certo.
    private var previewText: String {
        let cycle = InvoiceCalculator.currentCycle(closingDay: closingDay, dueDay: dueDay)
        return "Uma compra feita hoje entra na fatura de \(cycle.monthKey.longName), que vence em \(DateFormatters.short.string(from: cycle.dueDate))."
    }

    var body: some View {
        Form {
            Section {
                TextField("Apelido do cartão", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Bandeira", selection: $brand) {
                    ForEach(CardBrand.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                TextField("Últimos 4 dígitos", text: $lastFour)
                    .keyboardType(.numberPad)
                    .onChange(of: lastFour) { _, value in
                        lastFour = String(value.filter(\.isNumber).prefix(4))
                    }

                TextField("Banco ou emissor", text: $institutionName)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("Os 4 dígitos são só para você reconhecer o cartão na lista. Nenhum número completo é pedido nem armazenado.")
            }

            Section {
                Picker("Fecha no dia", selection: $closingDay) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Vence no dia", selection: $dueDay) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
            } header: {
                Text("Ciclo da fatura")
            } footer: {
                Text(previewText)
            }

            Section("Limite") {
                CurrencyField(title: "Limite total", value: $creditLimit)
            }

            Section("Pagamento") {
                Picker("Debita da conta", selection: $paymentAccountID) {
                    Text("Não definir").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
            }

            Section("Aparência") {
                ColorPickerGrid(hex: $colorHex)
            }

            if let card, !isNew {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Apagar cartão", systemImage: "trash")
                    }
                } footer: {
                    Text("Apaga também os \((card.transactions ?? []).count) lançamentos deste cartão.")
                }
            }
        }
        .navigationTitle(isNew ? "Novo cartão" : "Editar cartão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Apagar este cartão e seus lançamentos?",
                            isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) { delete() }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let card else { return }
        name = card.name
        brand = card.brand
        lastFour = card.lastFourDigits
        creditLimit = card.creditLimit
        closingDay = card.closingDay
        dueDay = card.dueDay
        colorHex = card.colorHex
        institutionName = card.institution?.name ?? ""
        paymentAccountID = card.paymentAccount?.id
    }

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
        let target = card ?? CreditCard(name: name)
        let daysChanged = target.closingDay != closingDay

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.brand = brand
        target.lastFourDigits = lastFour
        target.creditLimit = Money.rounded(creditLimit)
        target.closingDay = closingDay
        target.dueDay = dueDay
        target.colorHex = colorHex
        target.institution = resolveInstitution()
        target.paymentAccount = accounts.first { $0.id == paymentAccountID }

        if card == nil {
            context.insert(target)
        } else if daysChanged {
            // Mudar o dia de fechamento realoca as compras já importadas, senão
            // as faturas antigas passariam a mostrar o período errado.
            for txn in target.transactions ?? [] {
                txn.invoiceKey = InvoiceCalculator.cycle(for: target, containing: txn.date).monthKey.key
            }
        }

        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let card else { return }
        context.delete(card)
        try? context.save()
        dismiss()
    }
}
