import SwiftUI
import SwiftData

/// Metas de economia e de investimento: quanto falta, até quando e quanto
/// guardar por mês para chegar lá.
struct GoalsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]
    @Query(sort: \Txn.date, order: .reverse) private var transactions: [Txn]
    @Query private var plans: [AllocationPlan]

    @State private var showingArchived = false
    @State private var creating = false
    @State private var editing: Goal?

    private var goals: [Goal] {
        allGoals.filter { showingArchived || !$0.isArchived }
    }

    private var totalSaved: Decimal {
        goals.reduce(Decimal(0)) { $0 + $1.savedAmount }
    }

    private var totalMonthlyNeeded: Decimal {
        goals.compactMap(\.monthlyNeeded).reduce(Decimal(0), +)
    }

    /// Quanto o plano de alocação reserva para guardar e investir por mês.
    private var plannedForSaving: Decimal? {
        guard let plan = plans.first else { return nil }
        let income = FinanceEngine.baseIncome(plan: plan, transactions: transactions)
        guard income > 0 else { return nil }
        let percentage = plan.sortedBuckets
            .filter { $0.group == .investimento }
            .reduce(Decimal(0)) { $0 + $1.percentage }
        return Money.rounded(income * percentage / 100)
    }

    var body: some View {
        List {
            if !goals.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            StatTile(title: "Já guardado", value: settings.display(totalSaved), tint: Palette.positive)
                            StatTile(title: "Por mês para cumprir tudo", value: settings.display(totalMonthlyNeeded))
                        }

                        if let planned = plannedForSaving {
                            if totalMonthlyNeeded > planned {
                                InlineNote(
                                    symbol: "exclamationmark.triangle",
                                    text: "Seu plano reserva \(Money.string(planned)) por mês para guardar, mas as metas pedem \(Money.string(totalMonthlyNeeded)). Ou aumenta a fatia, ou estica algum prazo.",
                                    tint: Palette.warning
                                )
                            } else {
                                InlineNote(
                                    symbol: "checkmark.circle",
                                    text: "Seu plano reserva \(Money.string(planned)) por mês — dá para cumprir todas as metas no prazo.",
                                    tint: Palette.positive
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if goals.isEmpty {
                    EmptyStateView(
                        symbol: "flag",
                        title: "Nenhuma meta ainda",
                        message: "Uma reserva de emergência de 6 meses de despesas costuma ser o primeiro objetivo.",
                        actionTitle: "Criar meta",
                        action: { creating = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(goals) { goal in
                        NavigationLink {
                            GoalDetailView(goal: goal)
                        } label: {
                            goalRow(goal)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                goal.isArchived.toggle()
                                try? context.save()
                            } label: {
                                Label(goal.isArchived ? "Reativar" : "Arquivar",
                                      systemImage: goal.isArchived ? "tray.and.arrow.up" : "archivebox")
                            }
                            .tint(.orange)
                            Button { editing = goal } label: { Label("Editar", systemImage: "pencil") }
                                .tint(.blue)
                        }
                    }
                }
            }

            Section {
                Toggle("Mostrar metas arquivadas", isOn: $showingArchived)
                    .font(.subheadline)
            }
        }
        .navigationTitle("Metas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nova meta")
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { GoalEditor(goal: nil) } }
        .sheet(item: $editing) { goal in NavigationStack { GoalEditor(goal: goal) } }
    }

    private func goalRow(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconBadge(symbol: goal.symbol, hex: goal.colorHex)
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.name)
                    Text(caption(for: goal))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(hex: goal.colorHex))
            }
            MeterBar(ratio: goal.progress, tint: Color(hex: goal.colorHex), height: 8)
            HStack {
                Text(settings.displayAbs(goal.savedAmount))
                Spacer()
                Text("falta \(settings.displayAbs(goal.remainingAmount))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(goal.isArchived ? 0.5 : 1)
    }

    private func caption(for goal: Goal) -> String {
        if let needed = goal.monthlyNeeded, let months = goal.monthsRemaining {
            return "\(Money.string(needed)) por mês nos próximos \(months) meses"
        }
        if goal.remainingAmount == 0 { return "meta alcançada" }
        return goal.kind.label
    }
}

/// Detalhe da meta, com o histórico de aportes.
struct GoalDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    let goal: Goal

    @State private var contributionAmount: Decimal = 0
    @State private var contributionDate = Date()
    @State private var contributionNote = ""
    @State private var showingContribution = false
    @State private var editing = false

    private var contributions: [GoalContribution] {
        (goal.contributions ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: goal.symbol, hex: goal.colorHex, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(.headline)
                            Text(goal.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    MeterBar(ratio: goal.progress, tint: Color(hex: goal.colorHex), height: 12)

                    HStack(alignment: .top) {
                        StatTile(title: "Guardado", value: settings.display(goal.savedAmount), tint: Palette.positive)
                        StatTile(title: "Falta", value: settings.display(goal.remainingAmount))
                        if let needed = goal.monthlyNeeded {
                            StatTile(title: "Por mês", value: settings.display(needed), caption: "para chegar no prazo")
                        }
                    }

                    if let targetDate = goal.targetDate {
                        InlineNote(symbol: "calendar", text: "Prazo: \(DateFormatters.full.string(from: targetDate)).")
                    }
                    if let account = goal.linkedAccount {
                        InlineNote(
                            symbol: "building.columns",
                            text: "O dinheiro está em \(account.name), que hoje tem \(Money.string(FinanceEngine.balance(of: account)))."
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    contributionAmount = 0
                    contributionDate = Date()
                    contributionNote = ""
                    showingContribution = true
                } label: {
                    Label("Registrar aporte", systemImage: "plus.circle")
                }
            }

            Section("Aportes") {
                if contributions.isEmpty {
                    Text("Nenhum aporte registrado ainda.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contributions) { contribution in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DateFormatters.full.string(from: contribution.date))
                                    .font(.subheadline)
                                if !contribution.note.isEmpty {
                                    Text(contribution.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(settings.display(contribution.amount))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.positive)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(contributions[index]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { GoalEditor(goal: goal) } }
        .sheet(isPresented: $showingContribution) {
            NavigationStack {
                Form {
                    CurrencyField(title: "Valor", value: $contributionAmount)
                    DatePicker("Data", selection: $contributionDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "pt_BR"))
                    TextField("Observação", text: $contributionNote)
                }
                .navigationTitle("Novo aporte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showingContribution = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salvar") { saveContribution() }
                            .disabled(contributionAmount <= 0)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func saveContribution() {
        let contribution = GoalContribution(
            date: contributionDate.startOfDay,
            amount: Money.rounded(contributionAmount),
            note: contributionNote
        )
        contribution.goal = goal
        context.insert(contribution)
        try? context.save()
        showingContribution = false
    }
}

/// Cadastro e edição de meta.
struct GoalEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name) private var accounts: [Account]

    let goal: Goal?

    @State private var name = ""
    @State private var kind: GoalKind = .reserva
    @State private var targetAmount: Decimal = 0
    @State private var hasDeadline = true
    @State private var targetDate = Date().adding(months: 12)
    @State private var colorHex = "#1D9A6C"
    @State private var accountID: UUID?
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isNew: Bool { goal == nil }

    private var monthlyPreview: Decimal? {
        guard hasDeadline, targetAmount > 0 else { return nil }
        let months = max(Calendar.brazil.dateComponents([.month], from: Date(), to: targetDate).month ?? 1, 1)
        let saved = goal?.savedAmount ?? 0
        let remaining = max(targetAmount - saved, 0)
        guard remaining > 0 else { return nil }
        return Money.rounded(remaining / Decimal(months))
    }

    var body: some View {
        Form {
            Section {
                TextField("Nome da meta", text: $name)
                    .textInputAutocapitalization(.sentences)

                Picker("Tipo", selection: $kind) {
                    ForEach(GoalKind.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }

                CurrencyField(title: "Quanto quero juntar", value: $targetAmount)
            }

            Section {
                Toggle("Tem prazo", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Até", selection: $targetDate, in: Date()..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "pt_BR"))
                }
            } footer: {
                if let monthly = monthlyPreview {
                    Text("Isso dá \(Money.string(monthly)) por mês.")
                } else {
                    Text("Sem prazo, a meta acompanha o progresso mas não sugere um valor mensal.")
                }
            }

            Section {
                Picker("Dinheiro guardado em", selection: $accountID) {
                    Text("Não definir").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.type.symbol).tag(UUID?.some(account.id))
                    }
                }
            } footer: {
                Text("Serve só para você lembrar onde o dinheiro está. O app não move nada entre contas.")
            }

            Section("Aparência") {
                ColorPickerGrid(hex: $colorHex)
            }

            Section {
                TextField("Observações", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("Apagar meta", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Nova meta" : "Editar meta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || targetAmount <= 0)
            }
        }
        .confirmationDialog("Apagar esta meta?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) { delete() }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let goal else { return }
        name = goal.name
        kind = goal.kind
        targetAmount = goal.targetAmount
        hasDeadline = goal.targetDate != nil
        targetDate = goal.targetDate ?? Date().adding(months: 12)
        colorHex = goal.colorHex
        accountID = goal.linkedAccount?.id
        notes = goal.notes
    }

    private func save() {
        let target = goal ?? Goal(name: name, targetAmount: targetAmount)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kind = kind
        target.symbol = kind.symbol
        target.targetAmount = Money.rounded(targetAmount)
        target.targetDate = hasDeadline ? targetDate.startOfDay : nil
        target.colorHex = colorHex
        target.linkedAccount = accounts.first { $0.id == accountID }
        target.notes = notes

        if goal == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let goal else { return }
        context.delete(goal)
        try? context.save()
        dismiss()
    }
}
