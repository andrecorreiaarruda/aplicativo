import SwiftUI
import SwiftData

/// Edita um lançamento existente ou cria um novo à mão.
///
/// O que veio do banco continua visível em "texto original": editar o nome nunca
/// apaga o que o extrato dizia.
struct TransactionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.name) private var cards: [CreditCard]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    let txn: Txn?

    @State private var date = Date()
    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var kind: TxKind = .expense
    @State private var categoryID: UUID?
    @State private var destinationID: UUID?
    @State private var notes = ""
    @State private var isIgnored = false
    @State private var installmentIndex = 0
    @State private var installmentTotal = 0
    @State private var learnRule = true

    private var isNew: Bool { txn == nil }

    private var originalCategoryID: UUID? { txn?.category?.id }

    private var selectedCard: CreditCard? {
        cards.first { $0.id == destinationID }
    }

    /// Receita entra positiva, o resto sai negativo. O usuário digita sempre um
    /// número sem sinal e o app decide a direção pelo tipo.
    private var signedAmount: Decimal {
        let magnitude = amount < 0 ? -amount : amount
        switch kind {
        case .income, .refund: return magnitude
        default: return -magnitude
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Descrição", text: $name)
                        .textInputAutocapitalization(.sentences)

                    CurrencyField(title: "Valor", value: $amount)

                    DatePicker("Data", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "pt_BR"))

                    Picker("Tipo", selection: $kind) {
                        ForEach(TxKind.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                }

                Section("Onde") {
                    Picker("Conta ou cartão", selection: $destinationID) {
                        Text("Não definir").tag(UUID?.none)
                        if !accounts.isEmpty {
                            Section("Contas") {
                                ForEach(accounts) { account in
                                    Label(account.name, systemImage: account.type.symbol)
                                        .tag(UUID?.some(account.id))
                                }
                            }
                        }
                        if !cards.isEmpty {
                            Section("Cartões") {
                                ForEach(cards) { card in
                                    Label(card.name, systemImage: "creditcard")
                                        .tag(UUID?.some(card.id))
                                }
                            }
                        }
                    }

                    if let card = selectedCard {
                        let cycle = InvoiceCalculator.cycle(for: card, containing: date)
                        InlineNote(
                            symbol: "calendar",
                            text: "Entra na fatura de \(cycle.monthKey.longName), com vencimento em \(DateFormatters.short.string(from: cycle.dueDate))."
                        )
                    }
                }

                Section("Categoria") {
                    Picker("Categoria", selection: $categoryID) {
                        Text("Sem categoria").tag(UUID?.none)
                        ForEach(CategoryGroup.allCases) { group in
                            let items = categories.filter { $0.group == group }
                            if !items.isEmpty {
                                Section(group.label) {
                                    ForEach(items) { category in
                                        Label(category.name, systemImage: category.symbol)
                                            .tag(UUID?.some(category.id))
                                    }
                                }
                            }
                        }
                    }

                    if !isNew, categoryID != originalCategoryID, categoryID != nil {
                        Toggle("Aprender para próximas importações", isOn: $learnRule)
                            .font(.subheadline)
                    }
                }

                Section("Parcelamento") {
                    Stepper("Parcela \(installmentIndex == 0 ? "—" : "\(installmentIndex)")",
                            value: $installmentIndex, in: 0...99)
                    Stepper("De \(installmentTotal == 0 ? "—" : "\(installmentTotal)")",
                            value: $installmentTotal, in: 0...99)
                }

                Section {
                    Toggle("Ignorar nos totais", isOn: $isIgnored)
                    TextField("Observações", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("Um lançamento ignorado continua no extrato, mas fica fora do orçamento e dos gráficos.")
                }

                if let txn, !isNew {
                    Section("Origem") {
                        LabeledContent("Importado de", value: txn.source.label)
                        if !txn.rawDescription.isEmpty, txn.rawDescription != txn.displayName {
                            LabeledContent("Texto original") {
                                Text(txn.rawDescription)
                                    .font(.caption)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        if let externalID = txn.externalID, !externalID.isEmpty {
                            LabeledContent("Id do banco") {
                                Text(externalID).font(.caption.monospaced())
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) { delete() } label: {
                            Label("Apagar lançamento", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Novo lançamento" : "Lançamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount == 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let txn else {
            destinationID = accounts.first?.id
            return
        }
        date = txn.date
        name = txn.displayName
        amount = txn.absAmount
        kind = txn.kind
        categoryID = txn.category?.id
        destinationID = txn.account?.id ?? txn.card?.id
        notes = txn.notes
        isIgnored = txn.isIgnored
        installmentIndex = txn.installmentIndex ?? 0
        installmentTotal = txn.installmentTotal ?? 0
    }

    private func save() {
        let target = txn ?? Txn(date: date, displayName: name, amount: 0)
        let categoryChanged = target.category?.id != categoryID

        target.date = date.startOfDay
        target.displayName = name.trimmingCharacters(in: .whitespaces)
        target.amount = Money.rounded(signedAmount)
        target.kind = kind
        target.notes = notes
        target.isIgnored = isIgnored
        target.category = categories.first { $0.id == categoryID }
        target.installmentIndex = installmentIndex == 0 ? nil : installmentIndex
        target.installmentTotal = installmentTotal == 0 ? nil : installmentTotal
        target.updatedAt = Date()

        if isNew {
            target.rawDescription = target.displayName
            target.source = .manual
        }

        // Um lançamento pertence a uma conta ou a um cartão, nunca aos dois.
        if let account = accounts.first(where: { $0.id == destinationID }) {
            target.account = account
            target.card = nil
            target.invoiceKey = nil
        } else if let card = cards.first(where: { $0.id == destinationID }) {
            target.card = card
            target.account = nil
            target.invoiceKey = InvoiceCalculator.cycle(for: card, containing: target.date).monthKey.key
        } else {
            target.account = nil
            target.card = nil
            target.invoiceKey = nil
        }

        if target.fingerprint.isEmpty {
            let destination = target.account?.id.uuidString ?? target.card?.id.uuidString ?? "sem-destino"
            target.fingerprint = ImportService.fingerprint(
                destination: destination,
                date: target.date,
                amount: target.amount,
                description: target.rawDescription
            )
        }

        if isNew { context.insert(target) }
        try? context.save()

        if !isNew, categoryChanged, learnRule, target.category != nil {
            try? ImportService(context: context).learn(from: target)
        }

        dismiss()
    }

    private func delete() {
        guard let txn else { return }
        context.delete(txn)
        try? context.save()
        dismiss()
    }
}
