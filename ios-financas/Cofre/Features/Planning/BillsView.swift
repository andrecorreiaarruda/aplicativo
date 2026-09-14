import SwiftUI
import SwiftData

/// Contas fixas do mês. O app só confere se cada uma já apareceu no extrato —
/// ele não paga, não agenda e não avisa o banco.
struct BillsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \RecurringBill.dueDay) private var allBills: [RecurringBill]
    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]

    @State private var month = MonthKey.current
    @State private var creating = false
    @State private var editing: RecurringBill?

    private var bills: [RecurringBill] { allBills.filter { !$0.isArchived } }

    private var statuses: [FinanceEngine.BillStatus] {
        FinanceEngine.billStatuses(month: month, bills: bills, transactions: transactions)
    }

    private var expectedTotal: Decimal {
        bills.reduce(Decimal(0)) { $0 + $1.expectedAmount }
    }

    var body: some View {
        List {
            Section {
                MonthStepper(month: $month)
                    .listRowBackground(Color.clear)
            }

            if !bills.isEmpty {
                Section {
                    HStack(alignment: .top) {
                        StatTile(title: "Previsto no mês", value: settings.display(expectedTotal))
                        StatTile(
                            title: "Ainda não vi no extrato",
                            value: settings.display(statuses.filter { !$0.isPaid }.reduce(Decimal(0)) { $0 + $1.bill.expectedAmount }),
                            tint: Palette.warning
                        )
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if bills.isEmpty {
                    EmptyStateView(
                        symbol: "calendar",
                        title: "Nenhuma conta fixa",
                        message: "Cadastre aluguel, assinaturas e mensalidades para não ser pego de surpresa.",
                        actionTitle: "Cadastrar conta fixa",
                        action: { creating = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(statuses) { status in
                        Button { editing = status.bill } label: { billRow(status) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(status.bill)
                                    try? context.save()
                                } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                            }
                    }
                }
            } footer: {
                if !bills.isEmpty {
                    Text("O app procura no extrato um lançamento com nome parecido e valor próximo. Se não achar, mostra como pendente — mas a decisão de pagar é sempre sua.")
                }
            }
        }
        .navigationTitle("Contas fixas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nova conta fixa")
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { BillEditor(bill: nil) } }
        .sheet(item: $editing) { bill in NavigationStack { BillEditor(bill: bill) } }
    }

    private func billRow(_ status: FinanceEngine.BillStatus) -> some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: status.isPaid ? "checkmark.circle.fill" : (status.isOverdue ? "exclamationmark.circle.fill" : "clock"),
                hex: status.isPaid ? "#1D9A6C" : (status.isOverdue ? "#E5484D" : "#F2994A"),
                size: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(status.bill.name)
                Text(caption(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(settings.displayAbs(status.matchedTransaction?.absAmount ?? status.bill.expectedAmount))
                    .font(.subheadline.weight(.medium))
                if status.bill.isVariableAmount {
                    Text("valor varia").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func caption(_ status: FinanceEngine.BillStatus) -> String {
        if let match = status.matchedTransaction {
            return "encontrado no extrato em \(DateFormatters.short.string(from: match.date))"
        }
        if status.isOverdue { return "vencia dia \(status.bill.dueDay) e não apareceu" }
        return "vence dia \(status.bill.dueDay)"
    }
}

/// Cadastro e edição de conta fixa.
struct BillEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.name) private var cards: [CreditCard]

    let bill: RecurringBill?

    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var dueDay = 10
    @State private var isVariable = false
    @State private var categoryID: UUID?
    @State private var destinationID: UUID?

    private var isNew: Bool { bill == nil }

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $name)
                    .textInputAutocapitalization(.words)
                CurrencyField(title: isVariable ? "Valor aproximado" : "Valor", value: $amount)
                Picker("Vence no dia", selection: $dueDay) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("O valor muda todo mês", isOn: $isVariable)
            } footer: {
                Text("Use o nome como ele aparece no extrato — é por ele que o app reconhece o pagamento. Ex.: \"Enel\", \"Vivo\", \"Netflix\".")
            }

            Section("Classificação") {
                Picker("Categoria", selection: $categoryID) {
                    Text("Sem categoria").tag(UUID?.none)
                    ForEach(categories.filter { $0.group != .receita }) { category in
                        Label(category.name, systemImage: category.symbol).tag(UUID?.some(category.id))
                    }
                }

                Picker("Paga por", selection: $destinationID) {
                    Text("Não definir").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.type.symbol).tag(UUID?.some(account.id))
                    }
                    ForEach(cards) { card in
                        Label(card.name, systemImage: "creditcard").tag(UUID?.some(card.id))
                    }
                }
            }

            if let bill, !isNew {
                Section {
                    Button(role: .destructive) {
                        context.delete(bill)
                        try? context.save()
                        dismiss()
                    } label: {
                        Label("Apagar conta fixa", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Nova conta fixa" : "Editar conta fixa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let bill else { return }
        name = bill.name
        amount = bill.expectedAmount
        dueDay = bill.dueDay
        isVariable = bill.isVariableAmount
        categoryID = bill.category?.id
        destinationID = bill.account?.id ?? bill.card?.id
    }

    private func save() {
        let target = bill ?? RecurringBill(name: name, expectedAmount: amount, dueDay: dueDay)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.expectedAmount = Money.rounded(amount)
        target.dueDay = dueDay
        target.isVariableAmount = isVariable
        target.category = categories.first { $0.id == categoryID }
        target.account = accounts.first { $0.id == destinationID }
        target.card = cards.first { $0.id == destinationID }

        if bill == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
