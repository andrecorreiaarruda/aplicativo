import SwiftUI
import SwiftData

/// Onde ficam as três perguntas do planejamento: quanto posso gastar, como
/// divido a renda e para onde estou juntando dinheiro.
struct PlanningView: View {
    @EnvironmentObject private var settings: AppSettings

    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var allocations: [EnvelopeAllocation]
    @Query private var envelopeAdjustments: [EnvelopeAdjustment]
    @Query(filter: #Predicate<Goal> { !$0.isArchived }) private var goals: [Goal]
    @Query private var plans: [AllocationPlan]

    private let month = MonthKey.current

    private var envelopeStates: [EnvelopeEngine.State] {
        EnvelopeEngine.states(
            month: month,
            start: settings.envelopeStartMonth,
            categories: categories,
            allocations: allocations,
            adjustments: envelopeAdjustments,
            transactions: transactions
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        EnvelopesView(month: month)
                    } label: {
                        row(
                            symbol: "envelope",
                            hex: "#F2994A",
                            title: "Envelopes",
                            subtitle: envelopeSubtitle
                        )
                    }

                    NavigationLink {
                        AllocationView()
                    } label: {
                        row(
                            symbol: "chart.pie",
                            hex: "#2F6FED",
                            title: "Divisão da renda",
                            subtitle: allocationSubtitle
                        )
                    }

                    NavigationLink {
                        GoalsView()
                    } label: {
                        row(
                            symbol: "flag",
                            hex: "#1D9A6C",
                            title: "Metas de economia e investimento",
                            subtitle: goals.isEmpty ? "Nenhuma meta criada" : "\(goals.count) meta(s) em andamento"
                        )
                    }
                }

                Section {
                    NavigationLink {
                        BillsView()
                    } label: {
                        row(symbol: "calendar", hex: "#5E5CE6", title: "Contas fixas",
                            subtitle: "Aluguel, assinaturas, mensalidades")
                    }

                    NavigationLink {
                        CategoriesView()
                    } label: {
                        row(symbol: "tag", hex: "#8E44AD", title: "Categorias",
                            subtitle: "\(categories.count) cadastradas")
                    }
                }

                if !goals.isEmpty {
                    Section("Resumo das metas") {
                        ForEach(goals) { goal in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(goal.name).font(.subheadline)
                                    Spacer()
                                    Text("\(Int(goal.progress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                MeterBar(ratio: goal.progress, tint: Color(hex: goal.colorHex), height: 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Planejar")
        }
    }

    private var envelopeSubtitle: String {
        let states = envelopeStates
        guard !states.isEmpty else { return "Separe um valor por categoria" }
        let totals = EnvelopeEngine.totals(states)
        if totals.overdrawnCount > 0 {
            return "\(settings.display(totals.available)) disponíveis • \(totals.overdrawnCount) no vermelho"
        }
        return "\(settings.display(totals.available)) disponíveis em \(states.count) envelope(s)"
    }

    private var allocationSubtitle: String {
        guard let plan = plans.first else { return "Configure o plano" }
        let income = FinanceEngine.baseIncome(plan: plan, transactions: transactions)
        guard income > 0 else { return "Informe sua renda mensal" }
        return "\(plan.name) sobre \(settings.display(income)) por mês"
    }

    private func row(symbol: String, hex: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, hex: hex)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
