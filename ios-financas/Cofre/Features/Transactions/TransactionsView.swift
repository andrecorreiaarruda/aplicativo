import SwiftUI
import SwiftData

/// Todos os lançamentos, com busca e filtros. É a tela para responder "onde foi
/// parar aquele dinheiro".
struct TransactionsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.name) private var cards: [CreditCard]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var search = ""
    @State private var month: MonthKey? = MonthKey.current
    @State private var kindFilter: TxKind?
    @State private var categoryFilter: UUID?
    @State private var sourceFilter: UUID?
    @State private var showingFilters = false
    @State private var creating = false

    private var filtered: [Txn] {
        let needle = TextNormalizer.normalize(search)

        return transactions.filter { txn in
            if let month, !month.contains(txn.date) { return false }
            if let kindFilter, txn.kind != kindFilter { return false }
            if let categoryFilter, txn.category?.id != categoryFilter { return false }
            if let sourceFilter, txn.account?.id != sourceFilter && txn.card?.id != sourceFilter { return false }
            guard !needle.isEmpty else { return true }
            let haystack = TextNormalizer.normalize(txn.displayName + " " + txn.rawDescription + " " + txn.notes)
            return haystack.contains(needle)
        }
    }

    /// Agrupa por dia para o extrato ficar legível.
    private var sections: [(day: Date, items: [Txn])] {
        let groups = Dictionary(grouping: filtered) { $0.date.startOfDay }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    private var total: Decimal {
        filtered.filter(\.countsInBudget).reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var hasActiveFilters: Bool {
        kindFilter != nil || categoryFilter != nil || sourceFilter != nil || month != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(filtered.count) lançamento\(filtered.count == 1 ? "" : "s")")
                            .font(.subheadline)
                        Spacer()
                        Text(settings.display(total, signed: true))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.amount(total))
                    }
                    if let month {
                        MonthStepper(month: Binding(get: { month }, set: { self.month = $0 }))
                    }
                }

                ForEach(sections, id: \.day) { section in
                    Section(DateFormatters.weekdayDay.string(from: section.day).capitalizedFirst) {
                        ForEach(section.items) { txn in
                            NavigationLink {
                                TransactionEditor(txn: txn)
                            } label: {
                                TransactionRow(txn: txn, showAccount: true, hideAmounts: settings.hideAmounts)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    txn.isIgnored.toggle()
                                    try? context.save()
                                } label: {
                                    Label(txn.isIgnored ? "Considerar" : "Ignorar",
                                          systemImage: txn.isIgnored ? "eye" : "eye.slash")
                                }
                                .tint(.gray)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(txn)
                                    try? context.save()
                                } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if filtered.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "Nada encontrado",
                            message: hasActiveFilters
                                ? "Tente limpar os filtros ou mudar o mês."
                                : "Importe um extrato ou registre um lançamento à mão.",
                            actionTitle: hasActiveFilters ? "Limpar filtros" : nil,
                            action: hasActiveFilters ? clearFilters : nil
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar por descrição")
            .navigationTitle("Lançamentos")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingFilters = true } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filtros")

                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Novo lançamento")
                }
            }
            .sheet(isPresented: $creating) { TransactionEditor(txn: nil) }
            .sheet(isPresented: $showingFilters) { filterSheet }
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Período") {
                    Toggle("Filtrar por mês", isOn: Binding(
                        get: { month != nil },
                        set: { month = $0 ? MonthKey.current : nil }
                    ))
                    if let current = month {
                        MonthStepper(month: Binding(get: { current }, set: { month = $0 }))
                    }
                }

                Section("Tipo") {
                    Picker("Tipo", selection: $kindFilter) {
                        Text("Todos").tag(TxKind?.none)
                        ForEach(TxKind.allCases) { kind in
                            Text(kind.label).tag(TxKind?.some(kind))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Categoria") {
                    Picker("Categoria", selection: $categoryFilter) {
                        Text("Todas").tag(UUID?.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(UUID?.some(category.id))
                        }
                    }
                }

                Section("Conta ou cartão") {
                    Picker("Origem", selection: $sourceFilter) {
                        Text("Todas").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Label(account.name, systemImage: account.type.symbol).tag(UUID?.some(account.id))
                        }
                        ForEach(cards) { card in
                            Label(card.name, systemImage: "creditcard").tag(UUID?.some(card.id))
                        }
                    }
                }

                Section {
                    Button("Limpar filtros", role: .destructive, action: clearFilters)
                }
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { showingFilters = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func clearFilters() {
        kindFilter = nil
        categoryFilter = nil
        sourceFilter = nil
        month = MonthKey.current
    }
}
