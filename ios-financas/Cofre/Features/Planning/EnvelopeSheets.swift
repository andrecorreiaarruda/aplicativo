import SwiftUI
import SwiftData

/// Ajuste de um envelope: quanto entra por mês, o que acontece na virada, e os
/// reforços e retiradas feitos à mão.
struct EnvelopeEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allocations: [EnvelopeAllocation]
    @Query private var adjustments: [EnvelopeAdjustment]
    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]

    let category: Category
    let month: MonthKey
    /// Situação atual, quando o envelope já existe.
    let state: EnvelopeEngine.State?

    @State private var amount: Decimal = 0
    @State private var policy: RolloverPolicy = .accumulate
    @State private var applyToAllMonths = true
    @State private var showingAdjustment = false
    @State private var adjustmentAmount: Decimal = 0
    @State private var adjustmentIsWithdrawal = false
    @State private var adjustmentNote = ""

    private var myAdjustments: [EnvelopeAdjustment] {
        adjustments
            .filter { $0.category?.id == category.id && $0.monthKey == month.key }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Média de gasto dos três meses anteriores — o melhor chute para o aporte.
    private var averageSpend: Decimal {
        let spending = EnvelopeEngine.spendingByMonth(transactions)
        let totals = (1...3).map { spending[month.adding(months: -$0).key]?[category.id] ?? 0 }
        let sum = totals.reduce(Decimal(0), +)
        return sum == 0 ? 0 : Money.rounded(sum / 3)
    }

    /// Como ficaria o disponível se o aporte digitado fosse salvo agora.
    private var projectedAvailable: Decimal {
        guard let state else { return amount }
        return state.carriedIn + amount + state.adjusted - state.spent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        IconBadge(symbol: category.symbol, hex: category.colorHex, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name).font(.headline)
                            Text(month.longName.capitalizedFirst)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.string(projectedAvailable))
                                .font(.headline)
                                .foregroundStyle(projectedAvailable < 0 ? Palette.negative : Palette.positive)
                            Text("disponível").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    CurrencyField(title: "Aporte do mês", value: $amount)
                    Toggle("Valer para todos os meses", isOn: $applyToAllMonths)
                } header: {
                    Text("Quanto entra no envelope")
                } footer: {
                    Text(applyToAllMonths
                         ? "O valor passa a ser o aporte padrão, inclusive nos meses seguintes."
                         : "O valor vale só em \(month.longName). Os outros meses seguem o aporte padrão.")
                }

                if averageSpend > 0 {
                    Section {
                        Button {
                            amount = averageSpend
                        } label: {
                            HStack {
                                Label("Usar a média dos 3 meses", systemImage: "chart.bar")
                                Spacer()
                                Text(Money.string(averageSpend)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker("Na virada do mês", selection: $policy) {
                        ForEach(RolloverPolicy.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                } header: {
                    Text("Acúmulo")
                } footer: {
                    Text(policy.detail)
                }

                if let state {
                    Section("Como chegou nesse número") {
                        breakdownRow("Veio do mês passado", state.carriedIn, signed: true)
                        breakdownRow("Aporte", state.allocated)
                        if state.adjusted != 0 {
                            breakdownRow("Ajustes e transferências", state.adjusted, signed: true)
                        }
                        breakdownRow("Gasto", -state.spent, signed: true)
                        Divider()
                        breakdownRow("Disponível", state.available, emphasis: true)
                        if state.category.rollover != .reset {
                            LabeledContent("Atravessa para \(month.adding(months: 1).shortName)") {
                                Text(Money.signed(state.carriesOut))
                                    .foregroundStyle(state.carriesOut < 0 ? Palette.negative : Palette.positive)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section {
                    Button {
                        adjustmentAmount = 0
                        adjustmentNote = ""
                        adjustmentIsWithdrawal = false
                        showingAdjustment = true
                    } label: {
                        Label("Reforçar ou retirar", systemImage: "plusminus.circle")
                    }

                    ForEach(myAdjustments) { adjustment in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(adjustment.note.isEmpty
                                     ? (adjustment.isTransfer ? "Transferência" : "Ajuste manual")
                                     : adjustment.note)
                                    .font(.subheadline)
                                Text(DateFormatters.short.string(from: adjustment.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.signed(adjustment.amount))
                                .font(.subheadline)
                                .foregroundStyle(adjustment.amount >= 0 ? Palette.positive : Palette.negative)
                        }
                    }
                    .onDelete(perform: deleteAdjustments)
                } header: {
                    Text("Ajustes de \(month.shortName)")
                } footer: {
                    Text("Apagar uma transferência desfaz as duas pontas.")
                }

                if state != nil {
                    Section {
                        Button(role: .destructive) { removeEnvelope() } label: {
                            Label("Remover o envelope", systemImage: "trash")
                        }
                    } footer: {
                        Text("A categoria continua existindo e os gastos continuam no extrato. Só o envelope some.")
                    }
                }
            }
            .navigationTitle("Envelope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() } }
            }
            .sheet(isPresented: $showingAdjustment) { adjustmentSheet }
            .onAppear(perform: load)
        }
    }

    private func breakdownRow(_ title: String, _ value: Decimal, signed: Bool = false, emphasis: Bool = false) -> some View {
        LabeledContent(title) {
            Text(signed ? Money.signed(value) : Money.string(value))
                .foregroundStyle(emphasis ? (value < 0 ? Palette.negative : Palette.positive) : .primary)
                .fontWeight(emphasis ? .semibold : .regular)
        }
        .font(.subheadline)
    }

    private var adjustmentSheet: some View {
        NavigationStack {
            Form {
                Picker("Movimento", selection: $adjustmentIsWithdrawal) {
                    Text("Reforçar").tag(false)
                    Text("Retirar").tag(true)
                }
                .pickerStyle(.segmented)

                CurrencyField(title: "Valor", value: $adjustmentAmount)
                TextField("Motivo (opcional)", text: $adjustmentNote)
            }
            .navigationTitle(adjustmentIsWithdrawal ? "Retirar do envelope" : "Reforçar envelope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showingAdjustment = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { saveAdjustment() }
                        .disabled(adjustmentAmount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Ações

    private func load() {
        policy = category.rollover
        let mine = allocations.filter { $0.category?.id == category.id }
        if let specific = mine.first(where: { $0.monthKey == month.key }) {
            amount = specific.amount
            applyToAllMonths = false
        } else if let fallback = mine.first(where: { $0.isDefault }) {
            amount = fallback.amount
            applyToAllMonths = true
        } else {
            // Envelope novo: o gasto do mês já é um chute melhor que zero.
            amount = state?.spent ?? EnvelopeEngine.spent(for: category, month: month, transactions: transactions)
            applyToAllMonths = true
        }
    }

    private func save() {
        category.rollover = policy

        let key = applyToAllMonths ? EnvelopeAllocation.defaultKey : month.key
        let existing = allocations.first { $0.category?.id == category.id && $0.monthKey == key }

        if amount <= 0 {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.amount = Money.rounded(amount)
        } else {
            context.insert(EnvelopeAllocation(category: category, amount: Money.rounded(amount), monthKey: key))
        }

        try? context.save()
        dismiss()
    }

    private func saveAdjustment() {
        let value = Money.rounded(adjustmentAmount)
        context.insert(
            EnvelopeAdjustment(
                category: category,
                amount: adjustmentIsWithdrawal ? -value : value,
                monthKey: month.key,
                note: adjustmentNote
            )
        )
        try? context.save()
        showingAdjustment = false
    }

    private func deleteAdjustments(at offsets: IndexSet) {
        let list = myAdjustments
        for index in offsets {
            let adjustment = list[index]
            // Transferência tem duas pontas: apagar uma sem a outra criaria
            // dinheiro do nada.
            if let pair = adjustment.transferPairID {
                for other in adjustments where other.transferPairID == pair {
                    context.delete(other)
                }
            } else {
                context.delete(adjustment)
            }
        }
        try? context.save()
    }

    private func removeEnvelope() {
        for allocation in allocations where allocation.category?.id == category.id {
            context.delete(allocation)
        }
        for adjustment in adjustments where adjustment.category?.id == category.id {
            context.delete(adjustment)
        }
        try? context.save()
        dismiss()
    }
}

/// Transferência entre envelopes — tirar do lazer e pôr no mercado, como se
/// fazia com as notas de papel.
struct EnvelopeTransferSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let month: MonthKey
    let states: [EnvelopeEngine.State]

    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var amount: Decimal = 0
    @State private var note = ""

    private var source: EnvelopeEngine.State? { states.first { $0.category.id == sourceID } }
    private var destination: EnvelopeEngine.State? { states.first { $0.category.id == destinationID } }

    private var isValid: Bool {
        source != nil && destination != nil && sourceID != destinationID && amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("De") {
                    Picker("Origem", selection: $sourceID) {
                        Text("Escolher").tag(UUID?.none)
                        ForEach(states) { state in
                            Label(state.category.name, systemImage: state.category.symbol)
                                .tag(UUID?.some(state.category.id))
                        }
                    }
                    if let source {
                        LabeledContent("Disponível hoje", value: Money.string(source.available))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Para") {
                    Picker("Destino", selection: $destinationID) {
                        Text("Escolher").tag(UUID?.none)
                        ForEach(states.filter { $0.category.id != sourceID }) { state in
                            Label(state.category.name, systemImage: state.category.symbol)
                                .tag(UUID?.some(state.category.id))
                        }
                    }
                    if let destination {
                        LabeledContent("Disponível hoje", value: Money.string(destination.available))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    CurrencyField(title: "Valor", value: $amount)
                    TextField("Motivo (opcional)", text: $note)
                }

                if isValid, let source, let destination {
                    Section("Como fica") {
                        LabeledContent(source.category.name) {
                            Text(Money.string(source.available - amount))
                                .foregroundStyle(source.available - amount < 0 ? Palette.negative : .primary)
                        }
                        LabeledContent(destination.category.name) {
                            Text(Money.string(destination.available + amount))
                                .foregroundStyle(Palette.positive)
                        }
                    }
                }

                if let source, amount > source.available, source.available >= 0 {
                    Section {
                        InlineNote(
                            symbol: "exclamationmark.triangle",
                            text: "Você está tirando mais do que há em \(source.category.name). Dá para fazer, mas o envelope fica negativo.",
                            tint: Palette.warning
                        )
                    }
                }
            }
            .navigationTitle("Transferir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transferir") { transfer() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func transfer() {
        guard let source = source?.category, let destination = destination?.category else { return }

        // As duas pontas compartilham um id para poderem ser desfeitas juntas.
        let pairID = UUID()
        let value = Money.rounded(amount)
        let label = note.isEmpty ? "Para \(destination.name)" : note

        context.insert(
            EnvelopeAdjustment(category: source, amount: -value, monthKey: month.key,
                               note: label, transferPairID: pairID)
        )
        context.insert(
            EnvelopeAdjustment(category: destination, amount: value, monthKey: month.key,
                               note: note.isEmpty ? "De \(source.name)" : note, transferPairID: pairID)
        )
        try? context.save()
        dismiss()
    }
}
