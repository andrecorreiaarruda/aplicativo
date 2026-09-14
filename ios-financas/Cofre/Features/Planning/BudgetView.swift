import SwiftUI
import SwiftData

/// Teto de gasto por categoria, com o realizado do mês ao lado.
struct BudgetView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var lines: [BudgetLine]
    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]

    @State var month: MonthKey
    @State private var editingCategory: Category?
    @State private var draftLimit: Decimal = 0
    @State private var applyToAllMonths = true

    private var summary: FinanceEngine.MonthSummary {
        FinanceEngine.summary(for: month, transactions: transactions)
    }

    private var statuses: [FinanceEngine.BudgetStatus] {
        FinanceEngine.budgetStatuses(month: month, categories: categories, lines: lines, transactions: transactions)
    }

    private var budgetedTotal: Decimal {
        statuses.reduce(Decimal(0)) { $0 + $1.limit }
    }

    private var spentInBudgeted: Decimal {
        statuses.reduce(Decimal(0)) { $0 + $1.spent }
    }

    /// Categorias com gasto no mês mas sem teto definido — o buraco por onde o
    /// orçamento vaza.
    private var unbudgeted: [(category: Category, spent: Decimal)] {
        let withLimit = Set(statuses.map(\.category.id))
        return summary.byCategory.compactMap { entry in
            guard let category = entry.category,
                  !withLimit.contains(category.id),
                  category.group != .receita, category.group != .neutro,
                  entry.total > 0
            else { return nil }
            return (category, entry.total)
        }
    }

    /// Categorias que não têm teto nem gasto no mês — ficam no fim da lista
    /// como opções para você começar a controlar.
    private var untouched: [Category] {
        let withLimit = Set(statuses.map(\.category.id))
        let withSpend = Set(unbudgeted.map(\.category.id))
        return categories.filter { category in
            guard category.group != .receita, category.group != .neutro else { return false }
            return !withLimit.contains(category.id) && !withSpend.contains(category.id)
        }
    }

    var body: some View {
        List {
            Section {
                MonthStepper(month: $month)
                    .listRowBackground(Color.clear)
            }

            if !statuses.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            StatTile(title: "Orçado", value: settings.display(budgetedTotal))
                            StatTile(
                                title: "Gasto",
                                value: settings.display(spentInBudgeted),
                                tint: spentInBudgeted > budgetedTotal ? Palette.negative : .primary
                            )
                            StatTile(
                                title: "Resta",
                                value: settings.display(budgetedTotal - spentInBudgeted, signed: true),
                                tint: budgetedTotal - spentInBudgeted >= 0 ? Palette.positive : Palette.negative
                            )
                        }
                        MeterBar(
                            ratio: budgetedTotal > 0 ? spentInBudgeted.doubleValue / budgetedTotal.doubleValue : 0,
                            tint: Palette.budget(budgetedTotal > 0 ? spentInBudgeted.doubleValue / budgetedTotal.doubleValue : 0),
                            pace: month == MonthKey.current ? FinanceEngine.paceFraction(of: month) : nil
                        )
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Com teto definido") {
                if statuses.isEmpty {
                    EmptyStateView(
                        symbol: "target",
                        title: "Nenhum teto definido",
                        message: "Escolha abaixo uma categoria e diga quanto você quer gastar nela por mês."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(statuses) { status in
                        Button {
                            startEditing(status.category)
                        } label: {
                            budgetRow(status)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeLimit(for: status.category)
                            } label: {
                                Label("Remover teto", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !unbudgeted.isEmpty {
                Section {
                    ForEach(unbudgeted, id: \.category.id) { entry in
                        Button {
                            draftLimit = Money.rounded(entry.spent)
                            editingCategory = entry.category
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(symbol: entry.category.symbol, hex: entry.category.colorHex, size: 30)
                                Text(entry.category.name)
                                Spacer()
                                Text(settings.displayAbs(entry.spent))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Gastou, mas não tem teto")
                } footer: {
                    Text("Toque para transformar o gasto deste mês em teto.")
                }
            }

            Section("Outras categorias") {
                ForEach(untouched) { category in
                    Button {
                        draftLimit = 0
                        editingCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: category.symbol, hex: category.colorHex, size: 30)
                            Text(category.name)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Metas de gasto")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingCategory) { category in
            limitSheet(for: category)
        }
    }

    private func budgetRow(_ status: FinanceEngine.BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                IconBadge(symbol: status.category.symbol, hex: status.category.colorHex, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.category.name)
                    Text(status.isOver
                         ? "passou \(Money.abs(status.remaining))"
                         : "ainda dá para gastar \(Money.abs(status.remaining))")
                        .font(.caption)
                        .foregroundStyle(status.isOver ? Palette.negative : .secondary)
                }
                Spacer()
                Text("\(settings.displayAbs(status.spent)) / \(settings.displayAbs(status.limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MeterBar(
                ratio: status.ratio,
                tint: Palette.budget(status.ratio),
                pace: month == MonthKey.current ? FinanceEngine.paceFraction(of: month) : nil,
                height: 8
            )
        }
        .padding(.vertical, 4)
    }

    private func limitSheet(for category: Category) -> some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        IconBadge(symbol: category.symbol, hex: category.colorHex)
                        Text(category.name).font(.headline)
                    }
                    CurrencyField(title: "Teto por mês", value: $draftLimit)
                }

                Section {
                    Toggle("Valer para todos os meses", isOn: $applyToAllMonths)
                } footer: {
                    Text(applyToAllMonths
                         ? "O teto passa a valer como padrão, inclusive nos meses seguintes."
                         : "O teto vale só em \(month.longName). Os outros meses continuam com o padrão.")
                }

                Section {
                    let spent = statuses.first { $0.category.id == category.id }?.spent
                        ?? summary.byCategory.first { $0.category?.id == category.id }?.total
                        ?? 0
                    LabeledContent("Gasto em \(month.shortName)", value: Money.string(spent))
                    let average = averageSpend(for: category)
                    if average > 0 {
                        LabeledContent("Média dos últimos 3 meses", value: Money.string(average))
                        Button("Usar a média como teto") {
                            draftLimit = average
                        }
                    }
                }
            }
            .navigationTitle("Teto de gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { editingCategory = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { saveLimit(for: category) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func averageSpend(for category: Category) -> Decimal {
        let keys = (1...3).map { month.adding(months: -$0) }
        let totals = keys.map { key in
            FinanceEngine.summary(for: key, transactions: transactions)
                .byCategory.first { $0.category?.id == category.id }?.total ?? 0
        }
        let sum = totals.reduce(Decimal(0), +)
        return sum == 0 ? 0 : Money.rounded(sum / 3)
    }

    private func startEditing(_ category: Category) {
        draftLimit = FinanceEngine.limit(for: category, month: month, lines: lines) ?? 0
        applyToAllMonths = !lines.contains { $0.category?.id == category.id && $0.monthKey == month.key }
        editingCategory = category
    }

    private func saveLimit(for category: Category) {
        let key = applyToAllMonths ? BudgetLine.defaultKey : month.key
        let existing = lines.first { $0.category?.id == category.id && $0.monthKey == key }

        if draftLimit <= 0 {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.limit = Money.rounded(draftLimit)
        } else {
            context.insert(BudgetLine(category: category, limit: Money.rounded(draftLimit), monthKey: key))
        }

        try? context.save()
        editingCategory = nil
    }

    private func removeLimit(for category: Category) {
        for line in lines where line.category?.id == category.id {
            context.delete(line)
        }
        try? context.save()
    }
}
