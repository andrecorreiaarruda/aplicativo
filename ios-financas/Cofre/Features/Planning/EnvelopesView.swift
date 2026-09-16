import SwiftUI
import SwiftData

/// Os envelopes: quanto entra em cada um por mês, quanto sobrou do mês passado
/// e quanto ainda dá para gastar.
///
/// O número grande de cada linha é o **disponível**, não o gasto. É a diferença
/// de postura entre o método dos envelopes e um teto: você olha o que tem, não
/// o quanto falta para estourar.
struct EnvelopesView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var allocations: [EnvelopeAllocation]
    @Query private var adjustments: [EnvelopeAdjustment]
    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]
    @Query private var plans: [AllocationPlan]

    @State var month: MonthKey

    @State private var editingCategory: Category?
    @State private var showingTransfer = false
    @State private var showingStartMonth = false

    private var states: [EnvelopeEngine.State] {
        EnvelopeEngine.states(
            month: month,
            start: settings.envelopeStartMonth,
            categories: categories,
            allocations: allocations,
            adjustments: adjustments,
            transactions: transactions
        )
    }

    private var totals: EnvelopeEngine.Totals {
        EnvelopeEngine.totals(states)
    }

    /// Renda do mês menos o que já foi para os envelopes — o "ainda não tem
    /// destino", que é a pergunta central do método.
    private var unallocated: Decimal? {
        guard let plan = plans.first else { return nil }
        let income = FinanceEngine.baseIncome(plan: plan, transactions: transactions)
        guard income > 0 else { return nil }
        return income - totals.allocated
    }

    /// Categorias com gasto no mês mas sem envelope — o vazamento do orçamento.
    private var leaking: [(category: Category, spent: Decimal)] {
        let spending = EnvelopeEngine.spendingByMonth(transactions)[month.key] ?? [:]
        return categories.compactMap { category in
            guard category.acceptsEnvelope,
                  !EnvelopeEngine.hasEnvelope(category, allocations: allocations, adjustments: adjustments),
                  let spent = spending[category.id], spent > 0
            else { return nil }
            return (category, spent)
        }
        .sorted { $0.spent > $1.spent }
    }

    private var untouched: [Category] {
        let leakingIDs = Set(leaking.map(\.category.id))
        return categories.filter { category in
            category.acceptsEnvelope
            && !EnvelopeEngine.hasEnvelope(category, allocations: allocations, adjustments: adjustments)
            && !leakingIDs.contains(category.id)
        }
    }

    private var isBeforeStart: Bool { month < settings.envelopeStartMonth }

    var body: some View {
        List {
            Section {
                MonthStepper(month: $month)
                    .listRowBackground(Color.clear)
            }

            if isBeforeStart {
                Section {
                    InlineNote(
                        symbol: "clock.arrow.circlepath",
                        text: "Você começou a usar envelopes em \(settings.envelopeStartMonth.longName). Antes disso não há saldo acumulado.",
                        tint: Palette.warning
                    )
                }
            }

            if !states.isEmpty {
                summarySection
            }

            envelopesSection

            if !leaking.isEmpty {
                leakingSection
            }

            if !untouched.isEmpty {
                untouchedSection
            }

            startMonthSection
        }
        .navigationTitle("Envelopes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingTransfer = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .accessibilityLabel("Transferir entre envelopes")
                .disabled(states.count < 2)
            }
        }
        .sheet(item: $editingCategory) { category in
            EnvelopeEditorSheet(
                category: category,
                month: month,
                state: states.first { $0.category.id == category.id }
            )
        }
        .sheet(isPresented: $showingTransfer) {
            EnvelopeTransferSheet(month: month, states: states)
        }
    }

    // MARK: - Resumo

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Disponível nos envelopes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(settings.display(totals.available))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(totals.available < 0 ? Palette.negative : .primary)

                MeterBar(
                    ratio: totals.ratio,
                    tint: Palette.budget(totals.ratio),
                    pace: month == MonthKey.current ? FinanceEngine.paceFraction(of: month) : nil
                )

                Divider()

                HStack(alignment: .top) {
                    StatTile(
                        title: "Veio do mês passado",
                        value: settings.display(totals.carriedIn, signed: true),
                        tint: totals.carriedIn >= 0 ? Palette.positive : Palette.negative,
                        symbol: "arrow.turn.down.right"
                    )
                    StatTile(title: "Aporte do mês", value: settings.display(totals.allocated), symbol: "plus.circle")
                    StatTile(title: "Gasto", value: settings.display(totals.spent), symbol: "cart")
                }

                if let unallocated {
                    InlineNote(
                        symbol: unallocated >= 0 ? "tray" : "exclamationmark.triangle",
                        text: unallocated >= 0
                            ? "Sobram \(Money.string(unallocated)) da sua renda sem envelope. Todo real com destino é o objetivo do método."
                            : "Seus aportes somam \(Money.abs(unallocated)) a mais do que a sua renda. Reduza algum envelope.",
                        tint: unallocated >= 0 ? .secondary : Palette.warning
                    )
                }

                if totals.overdrawnCount > 0 {
                    InlineNote(
                        symbol: "exclamationmark.circle",
                        text: "\(totals.overdrawnCount) envelope(s) no vermelho. O saldo negativo atravessa para o mês seguinte nos que acumulam.",
                        tint: Palette.negative
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Envelopes

    private var envelopesSection: some View {
        Section("Envelopes") {
            if states.isEmpty {
                EmptyStateView(
                    symbol: "envelope",
                    title: "Nenhum envelope ainda",
                    message: "Escolha uma categoria abaixo e diga quanto você separa para ela por mês. O que sobrar continua lá no mês seguinte.",
                    actionTitle: untouched.isEmpty ? nil : "Criar o primeiro",
                    action: { editingCategory = untouched.first }
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(states) { state in
                    Button { editingCategory = state.category } label: { envelopeRow(state) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeEnvelope(state.category)
                            } label: {
                                Label("Remover", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func envelopeRow(_ state: EnvelopeEngine.State) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                IconBadge(symbol: state.category.symbol, hex: state.category.colorHex, size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.category.name)
                    if state.category.rollover != .accumulate {
                        Text(state.category.rollover.label.lowercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(settings.display(state.available))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.isOverdrawn ? Palette.negative : .primary)
                        .lineLimit(1)
                    Text(state.isOverdrawn ? "estourado" : "disponível")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            MeterBar(
                ratio: state.ratio,
                tint: Palette.budget(state.ratio),
                pace: month == MonthKey.current ? FinanceEngine.paceFraction(of: month) : nil,
                height: 8
            )

            HStack(spacing: 4) {
                Text(breakdown(state))
                Spacer()
                if state.carriedIn != 0 {
                    Label(
                        Money.signed(state.carriedIn),
                        systemImage: state.carriedIn > 0 ? "arrow.turn.down.right" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(state.carriedIn > 0 ? Palette.positive : Palette.negative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// "gastou R$ 740 de R$ 1.060" — sempre sobre o total que havia, não só
    /// sobre o aporte do mês.
    private func breakdown(_ state: EnvelopeEngine.State) -> String {
        guard state.funded != 0 || state.spent != 0 else { return "sem movimento" }
        return "gastou \(Money.abs(state.spent)) de \(Money.abs(state.funded))"
    }

    // MARK: - Sem envelope

    private var leakingSection: some View {
        Section {
            ForEach(leaking, id: \.category.id) { entry in
                Button { editingCategory = entry.category } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: entry.category.symbol, hex: entry.category.colorHex, size: 30)
                        Text(entry.category.name)
                        Spacer()
                        Text(settings.displayAbs(entry.spent))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Gastou, mas não tem envelope")
        } footer: {
            Text("Esse dinheiro saiu sem passar por nenhum envelope. Toque para criar um já com o valor do mês.")
        }
    }

    private var untouchedSection: some View {
        Section("Outras categorias") {
            ForEach(untouched) { category in
                Button { editingCategory = category } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: category.symbol, hex: category.colorHex, size: 30)
                        Text(category.name)
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mês inicial

    private var startMonthSection: some View {
        Section {
            Button {
                showingStartMonth = true
            } label: {
                HStack {
                    Label("Envelopes começam em", systemImage: "calendar.badge.clock")
                    Spacer()
                    Text(settings.envelopeStartMonth.shortName)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showingStartMonth {
                MonthStepper(month: $settings.envelopeStartMonth, allowFuture: false)
            }
        } footer: {
            Text("Todo envelope nasce zerado nesse mês. Mudar a data recalcula o acúmulo desde lá — útil se você quiser começar a contar de um mês mais antigo.")
        }
    }

    // MARK: - Ações

    private func removeEnvelope(_ category: Category) {
        for allocation in allocations where allocation.category?.id == category.id {
            context.delete(allocation)
        }
        for adjustment in adjustments where adjustment.category?.id == category.id {
            context.delete(adjustment)
        }
        try? context.save()
    }
}
