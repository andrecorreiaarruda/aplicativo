import SwiftUI
import SwiftData
import Charts

/// Como sua renda é dividida entre essencial, estilo de vida e o que você guarda
/// ou investe. O padrão é 50/30/20, mas as fatias são suas.
struct AllocationView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query private var plans: [AllocationPlan]
    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]

    @State private var month = MonthKey.current
    @State private var editingIncome = false
    @State private var draftIncome: Decimal = 0
    @State private var draftUseAuto = true

    private var plan: AllocationPlan? { plans.first }

    var body: some View {
        List {
            if let plan {
                let income = FinanceEngine.baseIncome(plan: plan, transactions: transactions)
                let statuses = FinanceEngine.allocationStatuses(plan: plan, month: month, transactions: transactions)

                Section {
                    MonthStepper(month: $month)
                        .listRowBackground(Color.clear)
                }

                Section("Renda considerada") {
                    Button {
                        draftIncome = plan.manualMonthlyIncome
                        draftUseAuto = plan.useAutoIncome
                        editingIncome = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.display(income))
                                    .font(.title3.weight(.semibold))
                                Text(plan.useAutoIncome
                                     ? "média das receitas dos últimos \(plan.autoIncomeMonths) meses"
                                     : "valor informado por você")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if income > 0 {
                    Section("Plano do mês") {
                        Chart(statuses) { status in
                            BarMark(
                                x: .value("Valor", status.planned.doubleValue),
                                y: .value("Bolso", status.bucket.name)
                            )
                            .foregroundStyle(Color(hex: status.bucket.colorHex).opacity(0.35))

                            BarMark(
                                x: .value("Valor", status.actual.doubleValue),
                                y: .value("Bolso", status.bucket.name)
                            )
                            .foregroundStyle(Color(hex: status.bucket.colorHex))
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let number = value.as(Double.self) {
                                        Text(Money.short(Decimal(number))).font(.caption2)
                                    }
                                }
                            }
                        }
                        .frame(height: CGFloat(max(statuses.count, 1)) * 52)
                        .padding(.vertical, 4)

                        InlineNote(symbol: "info.circle", text: "A barra clara é o planejado; a escura é o realizado.")
                    }
                }

                Section("Fatias") {
                    ForEach(plan.sortedBuckets) { bucket in
                        bucketRow(bucket, income: income, statuses: statuses)
                    }
                    .onDelete { offsets in
                        let buckets = plan.sortedBuckets
                        for index in offsets { context.delete(buckets[index]) }
                        try? context.save()
                    }

                    Button {
                        addBucket(to: plan)
                    } label: {
                        Label("Adicionar fatia", systemImage: "plus.circle")
                    }
                }

                Section {
                    HStack {
                        Text("Total das fatias")
                        Spacer()
                        Text("\(percentText(plan.totalPercentage))")
                            .foregroundStyle(plan.totalPercentage == 100 ? Palette.positive : Palette.warning)
                            .fontWeight(.semibold)
                    }
                } footer: {
                    if plan.totalPercentage > 100 {
                        Text("Você está distribuindo mais do que ganha. Some 100% para o plano fechar.")
                    } else if plan.totalPercentage < 100 {
                        Text("Sobram \(percentText(100 - plan.totalPercentage)) sem destino. Aumente alguma fatia ou crie outra.")
                    } else {
                        Text("Plano fechado em 100%.")
                    }
                }

                Section {
                    Button("Voltar ao 50 / 30 / 20") { resetToDefault(plan) }
                }
            } else {
                Section {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: "Sem plano de alocação",
                        message: "Crie o plano padrão 50/30/20 e ajuste as fatias depois.",
                        actionTitle: "Criar plano",
                        action: createPlan
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Divisão da renda")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingIncome) { incomeSheet }
    }

    private func bucketRow(
        _ bucket: AllocationBucket,
        income: Decimal,
        statuses: [FinanceEngine.AllocationStatus]
    ) -> some View {
        let status = statuses.first { $0.bucket.id == bucket.id }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconBadge(symbol: bucket.symbol, hex: bucket.colorHex, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bucket.name)
                    if income > 0 {
                        Text(Money.string(Money.rounded(income * bucket.percentage / 100)) + " por mês")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(percentText(bucket.percentage))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { bucket.percentage.doubleValue },
                    set: { newValue in
                        bucket.percentage = Decimal(round(newValue))
                        try? context.save()
                    }
                ),
                in: 0...100,
                step: 1
            )
            .tint(Color(hex: bucket.colorHex))

            if let status, status.planned > 0 {
                HStack {
                    Text("realizado \(settings.displayAbs(status.actual))")
                    Spacer()
                    Text(status.difference >= 0
                         ? "sobra \(Money.abs(status.difference))"
                         : "passou \(Money.abs(status.difference))")
                        .foregroundStyle(differenceColor(status))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Em «investir e guardar», gastar mais do que o planejado é bom — a cor tem
    /// que refletir isso, senão o app pune o comportamento certo.
    private func differenceColor(_ status: FinanceEngine.AllocationStatus) -> Color {
        if status.bucket.group == .investimento {
            return status.difference <= 0 ? Palette.positive : Palette.warning
        }
        return status.difference >= 0 ? Palette.positive : Palette.negative
    }

    private var incomeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Calcular pela média das receitas", isOn: $draftUseAuto)
                } footer: {
                    Text("Com a média ligada, o app usa o que realmente entrou nos últimos meses. Renda variável fica mais honesta assim.")
                }

                if !draftUseAuto {
                    Section("Renda mensal") {
                        CurrencyField(title: "Valor", value: $draftIncome)
                    }
                } else {
                    Section {
                        let average = FinanceEngine.averageIncome(months: plan?.autoIncomeMonths ?? 3, transactions: transactions)
                        LabeledContent("Média calculada", value: Money.string(average))
                        if average == 0 {
                            InlineNote(
                                symbol: "exclamationmark.circle",
                                text: "Ainda não há receitas registradas. Importe um extrato ou informe a renda manualmente.",
                                tint: Palette.warning
                            )
                        }
                    }
                }
            }
            .navigationTitle("Renda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { editingIncome = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        plan?.useAutoIncome = draftUseAuto
                        plan?.manualMonthlyIncome = Money.rounded(draftIncome)
                        try? context.save()
                        editingIncome = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func percentText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).intValue
        return "\(number)%"
    }

    private func createPlan() {
        context.insert(SeedData.defaultAllocationPlan())
        try? context.save()
    }

    private func addBucket(to plan: AllocationPlan) {
        let bucket = AllocationBucket(
            name: "Nova fatia",
            percentage: 0,
            group: .estiloDeVida,
            symbol: "circle",
            colorHex: Palette.picks.randomElement() ?? "#2F6FED",
            sortIndex: (plan.sortedBuckets.last?.sortIndex ?? 0) + 1
        )
        bucket.plan = plan
        context.insert(bucket)
        try? context.save()
    }

    private func resetToDefault(_ plan: AllocationPlan) {
        for bucket in plan.buckets ?? [] { context.delete(bucket) }
        let fresh = SeedData.defaultAllocationPlan()
        plan.name = fresh.name
        for bucket in fresh.buckets ?? [] {
            bucket.plan = plan
            context.insert(bucket)
        }
        try? context.save()
    }
}
