import SwiftUI
import SwiftData

/// Cartões de crédito com a fatura aberta em destaque.
struct CardsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(sort: \CreditCard.name) private var allCards: [CreditCard]

    @State private var showingArchived = false
    @State private var creating = false
    @State private var editing: CreditCard?

    private var cards: [CreditCard] {
        allCards.filter { showingArchived || !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    EmptyStateView(
                        symbol: "creditcard",
                        title: "Nenhum cartão cadastrado",
                        message: "Informe o dia de fechamento e o de vencimento. O app usa isso para saber em qual fatura cada compra cai.",
                        actionTitle: "Cadastrar cartão",
                        action: { creating = true }
                    )
                } else {
                    List {
                        Section {
                            StatTile(
                                title: "Total das faturas abertas",
                                value: settings.display(cards.reduce(Decimal(0)) { $0 + FinanceEngine.openInvoiceTotal(for: $1) }),
                                caption: "fatura atual mais a anterior ainda dentro do prazo",
                                tint: Palette.negative
                            )
                            .padding(.vertical, 4)
                        }

                        ForEach(cards) { card in
                            Section {
                                NavigationLink {
                                    CardDetailView(card: card)
                                } label: {
                                    cardRow(card)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        card.isArchived.toggle()
                                        try? context.save()
                                    } label: {
                                        Label(card.isArchived ? "Reativar" : "Arquivar",
                                              systemImage: card.isArchived ? "tray.and.arrow.up" : "archivebox")
                                    }
                                    .tint(.orange)

                                    Button { editing = card } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }

                        Section {
                            Toggle("Mostrar cartões arquivados", isOn: $showingArchived)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Cartões")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Novo cartão")
                }
            }
            .sheet(isPresented: $creating) { NavigationStack { CardEditor(card: nil) } }
            .sheet(item: $editing) { card in NavigationStack { CardEditor(card: card) } }
        }
    }

    private func cardRow(_ card: CreditCard) -> some View {
        let cycle = InvoiceCalculator.currentCycle(for: card)
        let total = FinanceEngine.invoiceTotal(of: card, in: cycle)
        let usage = FinanceEngine.limitUsage(for: card)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(symbol: "creditcard.fill", hex: card.colorHex)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.body)
                    Text(cardSubtitle(card))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(settings.display(total))
                        .font(.subheadline.weight(.semibold))
                    Text(cycle.isOpen ? "fatura aberta" : "fatura fechada")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if card.creditLimit > 0 {
                MeterBar(ratio: usage, tint: Palette.budget(usage), height: 6)
                HStack {
                    Text("\(settings.display(FinanceEngine.availableLimit(for: card))) livres")
                    Spacer()
                    Text("limite \(settings.display(card.creditLimit))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(card.isArchived ? 0.5 : 1)
    }

    private func cardSubtitle(_ card: CreditCard) -> String {
        var parts: [String] = [card.brand.label]
        if !card.lastFourDigits.isEmpty { parts.append("•••• \(card.lastFourDigits)") }
        parts.append("fecha dia \(card.closingDay)")
        return parts.joined(separator: " • ")
    }
}

/// Uma fatura por vez, com navegação entre os ciclos.
struct CardDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context

    let card: CreditCard

    @State private var month: MonthKey = MonthKey.current
    @State private var editing = false
    @State private var showingImport = false

    private var cycle: InvoiceCycle {
        InvoiceCalculator.cycle(for: card, in: month)
    }

    private var transactions: [Txn] {
        FinanceEngine.transactions(of: card, in: cycle)
    }

    private var total: Decimal {
        FinanceEngine.invoiceTotal(of: card, in: cycle)
    }

    var body: some View {
        List {
            Section {
                MonthStepper(month: $month, allowFuture: true)
                    .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(cycle.isOpen ? "Fatura aberta" : "Fatura fechada")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(settings.display(total))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    if cycle.isOpen, total > 0 {
                        let projected = FinanceEngine.projectedInvoiceTotal(of: card, cycle: cycle)
                        if projected > total {
                            Text("no ritmo atual, deve fechar perto de \(settings.display(projected))")
                                .font(.caption)
                                .foregroundStyle(Palette.warning)
                        }
                    }

                    Divider()

                    HStack(alignment: .top) {
                        StatTile(title: "Compras de", value: periodText, symbol: "calendar")
                        StatTile(title: "Vence em", value: DateFormatters.short.string(from: cycle.dueDate), symbol: "clock")
                    }

                    let future = FinanceEngine.futureInstallments(for: card, after: cycle)
                    if future > 0 {
                        InlineNote(
                            symbol: "calendar.badge.clock",
                            text: "Você já tem \(Money.string(future)) em parcelas contratadas para as próximas faturas."
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            if card.creditLimit > 0 {
                Section("Limite") {
                    VStack(alignment: .leading, spacing: 8) {
                        MeterBar(
                            ratio: FinanceEngine.limitUsage(for: card),
                            tint: Palette.budget(FinanceEngine.limitUsage(for: card))
                        )
                        HStack {
                            Text("\(settings.display(FinanceEngine.availableLimit(for: card))) disponíveis")
                            Spacer()
                            Text("de \(settings.display(card.creditLimit))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Lançamentos da fatura") {
                if transactions.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "Fatura sem lançamentos",
                        message: "Importe o arquivo da fatura (OFX ou CSV) que o banco disponibiliza.",
                        actionTitle: "Importar fatura",
                        action: { showingImport = true }
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(transactions) { txn in
                        NavigationLink {
                            TransactionEditor(txn: txn)
                        } label: {
                            TransactionRow(txn: txn, hideAmounts: settings.hideAmounts)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(transactions[index]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingImport = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Importar fatura")
                Button { editing = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Editar cartão")
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { CardEditor(card: card) } }
        .sheet(isPresented: $showingImport) { ImportFlowView(preselected: .card(card)) }
        .onAppear { month = InvoiceCalculator.currentCycle(for: card).monthKey }
    }

    private var periodText: String {
        let start = DateFormatters.dayMonth.string(from: cycle.periodStart)
        let end = DateFormatters.dayMonth.string(from: cycle.periodEnd)
        return "\(start) a \(end)"
    }
}
