import SwiftUI
import SwiftData
import Charts

/// A tela de abertura: onde você está agora, como está o mês e o que precisa de
/// atenção. Tudo aqui é resumo com atalho — o detalhe mora nas outras abas.
struct DashboardView: View {
    @EnvironmentObject private var settings: AppSettings

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name)
    private var accounts: [Account]

    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.name)
    private var cards: [CreditCard]

    @Query(sort: \Txn.date, order: .reverse)
    private var transactions: [Txn]

    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt)
    private var goals: [Goal]

    @Query(sort: \Category.sortIndex)
    private var categories: [Category]

    @Query private var allocations: [EnvelopeAllocation]

    @Query private var envelopeAdjustments: [EnvelopeAdjustment]

    @Query(filter: #Predicate<RecurringBill> { !$0.isArchived }, sort: \RecurringBill.dueDay)
    private var bills: [RecurringBill]

    @Query private var plans: [AllocationPlan]

    @State private var month = MonthKey.current
    @State private var showingImport = false
    @State private var showingSettings = false
    @State private var showingNewTransaction = false

    private var summary: FinanceEngine.MonthSummary {
        FinanceEngine.summary(for: month, transactions: transactions)
    }

    private var isEmpty: Bool {
        accounts.isEmpty && cards.isEmpty && transactions.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isEmpty {
                    welcome
                } else {
                    VStack(spacing: 16) {
                        netWorthCard
                        MonthStepper(month: $month)
                            .padding(.horizontal, 4)
                        monthCard
                        if !cards.isEmpty { invoicesCard }
                        budgetCard
                        allocationCard
                        if !bills.isEmpty { billsCard }
                        if !goals.isEmpty { goalsCard }
                        historyCard
                        recentCard
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Resumo")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        settings.hideAmounts.toggle()
                    } label: {
                        Image(systemName: settings.hideAmounts ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(settings.hideAmounts ? "Mostrar valores" : "Esconder valores")

                    Menu {
                        Button {
                            showingNewTransaction = true
                        } label: {
                            Label("Novo lançamento", systemImage: "plus.circle")
                        }
                        Button {
                            showingImport = true
                        } label: {
                            Label("Importar extrato", systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Ajustes", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingImport) { ImportFlowView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingNewTransaction) { TransactionEditor(txn: nil) }
        }
    }

    // MARK: - Primeira abertura

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 40)

            Text("Tudo começa com uma conta")
                .font(.title2.bold())

            Text("O Cofre só lê. Ele não conecta em banco, não move dinheiro e não manda nada para lugar nenhum — os dados ficam neste iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                NavigationLink {
                    AccountEditor(account: nil)
                } label: {
                    Label("Cadastrar uma conta", systemImage: "building.columns")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    CardEditor(card: nil)
                } label: {
                    Label("Cadastrar um cartão", systemImage: "creditcard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingImport = true
                } label: {
                    Label("Importar um extrato OFX ou CSV", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    // MARK: - Patrimônio

    private var netWorthCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                Text("Patrimônio")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(settings.display(FinanceEngine.netWorth(accounts: accounts, cards: cards)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    StatTile(
                        title: "Disponível",
                        value: settings.display(FinanceEngine.availableBalance(accounts: accounts)),
                        caption: "contas do dia a dia",
                        symbol: "wallet.bifold"
                    )
                    StatTile(
                        title: "Guardado",
                        value: settings.display(FinanceEngine.reserveBalance(accounts: accounts)),
                        caption: "poupança e investimentos",
                        tint: Palette.positive,
                        symbol: "shield.lefthalf.filled"
                    )
                    StatTile(
                        title: "Faturas abertas",
                        value: settings.display(cards.reduce(Decimal(0)) { $0 + FinanceEngine.openInvoiceTotal(for: $1) }),
                        caption: "ainda a pagar",
                        tint: Palette.negative,
                        symbol: "creditcard"
                    )
                }
            }
        }
    }

    // MARK: - Mês

    private var monthCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    StatTile(title: "Entrou", value: settings.display(summary.income),
                             tint: Palette.positive, symbol: "arrow.up.right")
                    StatTile(title: "Saiu", value: settings.display(summary.expenses),
                             symbol: "arrow.down.left")
                    StatTile(
                        title: "Sobrou",
                        value: settings.display(summary.net, signed: true),
                        caption: summary.savingsRate.map { "\(percent($0)) da renda" },
                        tint: summary.net >= 0 ? Palette.positive : Palette.negative,
                        symbol: "equal.circle"
                    )
                }

                if summary.invested > 0 {
                    InlineNote(
                        symbol: "chart.line.uptrend.xyaxis",
                        text: "\(settings.display(summary.invested)) foram para investimento — sai da conta, mas continua sendo seu."
                    )
                }

                if summary.transactionCount == 0 {
                    InlineNote(symbol: "tray", text: "Nenhum lançamento neste mês ainda.")
                }
            }
        }
    }

    // MARK: - Faturas

    private var invoicesCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Faturas", systemImage: "creditcard")

                ForEach(cards) { card in
                    let cycle = InvoiceCalculator.currentCycle(for: card)
                    let total = FinanceEngine.invoiceTotal(of: card, in: cycle)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            IconBadge(symbol: "creditcard", hex: card.colorHex, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.name).font(.subheadline.weight(.medium))
                                Text(closingText(cycle))
                                    .font(.caption)
                                    .foregroundStyle(cycle.daysUntilClosing <= 3 ? Palette.warning : .secondary)
                            }
                            Spacer()
                            Text(settings.display(total))
                                .font(.subheadline.weight(.semibold))
                        }

                        if card.creditLimit > 0 {
                            MeterBar(
                                ratio: FinanceEngine.limitUsage(for: card),
                                tint: Palette.budget(FinanceEngine.limitUsage(for: card)),
                                height: 6
                            )
                            Text("\(settings.display(FinanceEngine.availableLimit(for: card))) de limite livre")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func closingText(_ cycle: InvoiceCycle) -> String {
        let days = cycle.daysUntilClosing
        if days > 1 { return "fecha em \(days) dias • vence \(DateFormatters.short.string(from: cycle.dueDate))" }
        if days == 1 { return "fecha amanhã • vence \(DateFormatters.short.string(from: cycle.dueDate))" }
        if days == 0 { return "fecha hoje • vence \(DateFormatters.short.string(from: cycle.dueDate))" }
        return "fechada • vence \(DateFormatters.short.string(from: cycle.dueDate))"
    }

    // MARK: - Orçamento

    private var budgetCard: some View {
        let states = EnvelopeEngine.states(
            month: month,
            start: settings.envelopeStartMonth,
            categories: categories,
            allocations: allocations,
            adjustments: envelopeAdjustments,
            transactions: transactions
        )
        let totals = EnvelopeEngine.totals(states)
        let pace = month == MonthKey.current ? FinanceEngine.paceFraction(of: month) : nil

        return CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("Envelopes", systemImage: "envelope")
                    Spacer()
                    NavigationLink("Ver tudo") { EnvelopesView(month: month) }
                        .font(.caption)
                }

                if states.isEmpty {
                    InlineNote(
                        symbol: "info.circle",
                        text: "Em Planejar, separe um valor por categoria. O que sobrar continua no envelope no mês seguinte."
                    )
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(settings.display(totals.available))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(totals.available < 0 ? Palette.negative : .primary)
                        Text("ainda disponível")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if totals.carriedIn != 0 {
                            Text("\(Money.signed(totals.carriedIn)) do mês passado")
                                .font(.caption2)
                                .foregroundStyle(totals.carriedIn > 0 ? Palette.positive : Palette.negative)
                        }
                    }

                    // Os que precisam de atenção primeiro: estourados no topo.
                    ForEach(states.prefix(4)) { state in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(state.category.name).font(.subheadline)
                                Spacer()
                                Text(settings.display(state.available))
                                    .font(.caption)
                                    .foregroundStyle(state.isOverdrawn ? Palette.negative : .secondary)
                            }
                            MeterBar(ratio: state.ratio, tint: Palette.budget(state.ratio), pace: pace, height: 8)
                        }
                        .padding(.vertical, 2)
                    }

                    if month == MonthKey.current {
                        InlineNote(symbol: "line.diagonal", text: "O risco na barra marca o ritmo esperado para o dia de hoje.")
                    }
                }
            }
        }
    }

    // MARK: - Alocação

    @ViewBuilder
    private var allocationCard: some View {
        if let plan = plans.first {
            let statuses = FinanceEngine.allocationStatuses(plan: plan, month: month, transactions: transactions)
            let income = FinanceEngine.baseIncome(plan: plan, transactions: transactions)

            CardSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionTitle("Como sua renda foi dividida", systemImage: "chart.pie")
                        Spacer()
                        NavigationLink("Ajustar") { AllocationView() }
                            .font(.caption)
                    }

                    if income <= 0 {
                        InlineNote(
                            symbol: "questionmark.circle",
                            text: "Informe sua renda mensal em Planejar → Alocação para ver o plano funcionando."
                        )
                    } else {
                        ForEach(statuses) { status in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label(status.bucket.name, systemImage: status.bucket.symbol)
                                        .font(.subheadline)
                                        .labelStyle(.titleAndIcon)
                                    Spacer()
                                    Text("\(settings.displayAbs(status.actual)) de \(settings.displayAbs(status.planned))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                MeterBar(
                                    ratio: status.ratio,
                                    tint: status.bucket.group == .investimento
                                        ? (status.ratio >= 1 ? Palette.positive : Palette.warning)
                                        : Palette.budget(status.ratio),
                                    height: 8
                                )
                            }
                            .padding(.vertical, 2)
                        }

                        InlineNote(
                            symbol: "info.circle",
                            text: "Em «investir e guardar», passar da meta é bom — a barra fica verde quando você supera o planejado."
                        )
                    }
                }
            }
        }
    }

    // MARK: - Contas fixas

    private var billsCard: some View {
        let statuses = FinanceEngine.billStatuses(month: month, bills: bills, transactions: transactions)
        let pending = statuses.filter { !$0.isPaid }

        return CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Contas do mês", systemImage: "calendar")

                if pending.isEmpty {
                    Label("Tudo que era previsto já apareceu no extrato.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Palette.positive)
                } else {
                    ForEach(pending.prefix(5)) { status in
                        HStack {
                            Image(systemName: status.isOverdue ? "exclamationmark.circle" : "clock")
                                .foregroundStyle(status.isOverdue ? Palette.negative : Palette.warning)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(status.bill.name).font(.subheadline)
                                Text(billCaption(status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(settings.displayAbs(status.bill.expectedAmount))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    InlineNote(symbol: "hand.raised", text: "O app apenas lembra do vencimento. Ele nunca paga nada por você.")
                }
            }
        }
    }

    private func billCaption(_ status: FinanceEngine.BillStatus) -> String {
        let day = DateFormatters.short.string(from: status.dueDate)
        if status.isOverdue { return "venceu em \(day) e não achei no extrato" }
        if status.daysUntilDue == 0 { return "vence hoje" }
        if status.daysUntilDue == 1 { return "vence amanhã" }
        return "vence em \(status.daysUntilDue) dias (\(day))"
    }

    // MARK: - Metas

    private var goalsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("Metas", systemImage: "flag")
                    Spacer()
                    NavigationLink("Ver tudo") { GoalsView() }
                        .font(.caption)
                }

                ForEach(goals.prefix(3)) { goal in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            IconBadge(symbol: goal.symbol, hex: goal.colorHex, size: 26)
                            Text(goal.name).font(.subheadline)
                            Spacer()
                            Text("\(settings.displayAbs(goal.savedAmount)) de \(settings.displayAbs(goal.targetAmount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        MeterBar(ratio: goal.progress, tint: Color(hex: goal.colorHex), height: 8)
                        if let needed = goal.monthlyNeeded {
                            Text("guardar \(settings.displayAbs(needed)) por mês para chegar no prazo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Histórico

    private var historyCard: some View {
        let points = FinanceEngine.history(months: 6, transactions: transactions)

        return CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Últimos 6 meses", systemImage: "chart.bar")

                Chart {
                    ForEach(points) { point in
                        BarMark(
                            x: .value("Mês", point.month.shortName),
                            y: .value("Valor", point.income.doubleValue)
                        )
                        .foregroundStyle(Palette.positive)
                        .position(by: .value("Tipo", "Entrou"))

                        BarMark(
                            x: .value("Mês", point.month.shortName),
                            y: .value("Valor", point.expenses.doubleValue)
                        )
                        .foregroundStyle(Palette.negative)
                        .position(by: .value("Tipo", "Saiu"))
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(Money.short(Decimal(number)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Recentes

    private var recentCard: some View {
        let recent = Array(transactions.prefix(6))

        return CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("Últimos lançamentos", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    NavigationLink("Ver tudo") { TransactionsView() }
                        .font(.caption)
                }

                if recent.isEmpty {
                    InlineNote(symbol: "tray", text: "Nada registrado ainda.")
                } else {
                    ForEach(recent) { txn in
                        NavigationLink {
                            TransactionEditor(txn: txn)
                        } label: {
                            TransactionRow(txn: txn, showAccount: true, hideAmounts: settings.hideAmounts)
                        }
                        .buttonStyle(.plain)
                        if txn.id != recent.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Auxiliares

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
    }

    private func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }
}

#Preview {
    DashboardView()
        .modelContainer(DataStore.makePreviewContainer())
        .environmentObject(AppSettings())
}
