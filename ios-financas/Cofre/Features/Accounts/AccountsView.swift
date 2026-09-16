import SwiftUI
import SwiftData

/// Lista de contas agrupadas por instituição, com o patrimônio no topo.
struct AccountsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }) private var cards: [CreditCard]

    @State private var showingArchived = false
    @State private var editing: Account?
    @State private var creating = false

    private var accounts: [Account] {
        allAccounts.filter { showingArchived || !$0.isArchived }
    }

    /// Tipo nomeado em vez de tupla: o ForEach precisa de um key path para o
    /// identificador, e Swift não forma key path para elemento de tupla.
    private struct InstitutionGroup: Identifiable {
        let name: String
        let accounts: [Account]
        var id: String { name }
    }

    private var grouped: [InstitutionGroup] {
        let groups = Dictionary(grouping: accounts) { $0.institution?.name ?? "Sem instituição" }
        return groups
            .map { InstitutionGroup(name: $0.key, accounts: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if !accounts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            StatTile(
                                title: "Patrimônio",
                                value: settings.display(FinanceEngine.netWorth(accounts: allAccounts.filter { !$0.isArchived }, cards: cards)),
                                caption: "saldo das contas menos as faturas abertas"
                            )
                            Divider()
                            HStack(alignment: .top) {
                                StatTile(
                                    title: "Disponível",
                                    value: settings.display(FinanceEngine.availableBalance(accounts: accounts))
                                )
                                StatTile(
                                    title: "Guardado",
                                    value: settings.display(FinanceEngine.reserveBalance(accounts: accounts)),
                                    tint: Palette.positive
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(grouped) { group in
                    Section(group.name) {
                        ForEach(group.accounts) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                accountRow(account)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    account.isArchived.toggle()
                                    try? context.save()
                                } label: {
                                    Label(account.isArchived ? "Reativar" : "Arquivar",
                                          systemImage: account.isArchived ? "tray.and.arrow.up" : "archivebox")
                                }
                                .tint(.orange)

                                Button {
                                    editing = account
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                if accounts.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "building.columns",
                            title: "Nenhuma conta ainda",
                            message: "Cadastre suas contas com o saldo de hoje. Depois é só importar o extrato que o app monta o histórico.",
                            actionTitle: "Cadastrar conta",
                            action: { creating = true }
                        )
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Toggle("Mostrar contas arquivadas", isOn: $showingArchived)
                        .font(.subheadline)
                }
            }
            .navigationTitle("Contas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Nova conta")
                }
            }
            .sheet(isPresented: $creating) {
                NavigationStack { AccountEditor(account: nil) }
            }
            .sheet(item: $editing) { account in
                NavigationStack { AccountEditor(account: account) }
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: account.type.symbol, hex: account.colorHex)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .lineLimit(1)
                Text(account.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(settings.display(FinanceEngine.balance(of: account)))
                    .font(.subheadline.weight(.medium))
                if account.isArchived {
                    Text("arquivada").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(account.isArchived ? 0.5 : 1)
    }
}

/// Extrato da conta, mês a mês, com a conferência contra o saldo do banco.
struct AccountDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    let account: Account

    @State private var month = MonthKey.current
    @State private var editing = false
    @State private var showingImport = false

    private var monthTransactions: [Txn] {
        (account.transactions ?? [])
            .filter { month.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    /// Saldo no último dia do mês exibido — é o número que deve bater com o
    /// extrato do banco.
    private var closingBalance: Decimal {
        FinanceEngine.balance(of: account, asOf: month.end)
    }

    private var monthIn: Decimal {
        monthTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var monthOut: Decimal {
        monthTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Saldo atual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settings.display(FinanceEngine.balance(of: account)))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    Divider()

                    HStack(alignment: .top) {
                        StatTile(title: "Entrou no mês", value: settings.display(monthIn), tint: Palette.positive)
                        StatTile(title: "Saiu no mês", value: settings.display(monthOut))
                        StatTile(title: "Fecha o mês com", value: settings.display(closingBalance))
                    }

                    InlineNote(
                        symbol: "checkmark.circle",
                        text: "Saldo inicial de \(Money.string(account.openingBalance)) em \(DateFormatters.short.string(from: account.openingDate)) mais tudo que foi importado. Se não bater com o banco, falta ou sobra algum lançamento."
                    )
                }
                .padding(.vertical, 4)
            }

            Section {
                MonthStepper(month: $month)
                    .listRowBackground(Color.clear)
            }

            Section("Lançamentos") {
                if monthTransactions.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "Nada em \(month.longName)",
                        message: "Importe o extrato deste mês ou registre um lançamento à mão.",
                        actionTitle: "Importar extrato",
                        action: { showingImport = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(monthTransactions) { txn in
                        NavigationLink {
                            TransactionEditor(txn: txn)
                        } label: {
                            TransactionRow(txn: txn, hideAmounts: settings.hideAmounts)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(monthTransactions[index]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingImport = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Importar extrato")
                Button { editing = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Editar conta")
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { AccountEditor(account: account) }
        }
        .sheet(isPresented: $showingImport) {
            ImportFlowView(preselected: .account(account))
        }
    }
}
