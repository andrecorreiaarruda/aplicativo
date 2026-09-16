import Foundation

/// O método dos envelopes.
///
/// A diferença para um teto mensal está numa linha só: o saldo de um mês
/// atravessa para o mês seguinte. Gastou menos em setembro? Outubro começa com
/// a sobra dentro do envelope. Estourou? O buraco vai junto, porque o dinheiro
/// saiu de algum lugar de verdade.
///
/// Por isso não dá para calcular um mês isolado: o saldo de setembro depende de
/// agosto, que depende de julho. O cálculo varre os meses desde o início
/// escolhido e vai acumulando — por isso tudo aqui é feito numa passada só, e
/// não uma consulta por envelope.
enum EnvelopeEngine {

    /// Situação de um envelope num mês.
    struct State: Identifiable {
        let category: Category
        let month: MonthKey
        /// Saldo que veio do mês anterior, já filtrado pela política de virada.
        let carriedIn: Decimal
        /// Aporte do mês.
        let allocated: Decimal
        /// Reforços, retiradas e transferências feitas à mão neste mês.
        let adjusted: Decimal
        let spent: Decimal

        var id: UUID { category.id }

        /// Tudo que havia para gastar neste mês.
        var funded: Decimal { carriedIn + allocated + adjusted }

        /// O número que importa: quanto ainda dá para gastar.
        var available: Decimal { funded - spent }

        var isOverdrawn: Bool { available < 0 }

        /// Quanto vai atravessar para o mês seguinte.
        var carriesOut: Decimal { category.rollover.carryOut(available) }

        /// 0...∞ do envelope consumido. Passa de 1 quando estourou.
        var ratio: Double {
            guard funded > 0 else { return spent > 0 ? 1 : 0 }
            return spent.doubleValue / funded.doubleValue
        }

        /// Um envelope que só existe por causa da sobra acumulada — sem aporte
        /// nem gasto neste mês.
        var isDormant: Bool { allocated == 0 && adjusted == 0 && spent == 0 }
    }

    // MARK: - Aporte

    /// Aporte que vale para a categoria no mês: o ajuste daquele mês, se
    /// existir, senão o valor padrão.
    static func allocation(
        for category: Category,
        month: MonthKey,
        allocations: [EnvelopeAllocation]
    ) -> Decimal? {
        let mine = allocations.filter { $0.category?.id == category.id }
        if let specific = mine.first(where: { $0.monthKey == month.key }) {
            return specific.amount
        }
        return mine.first(where: { $0.isDefault })?.amount
    }

    /// Existe envelope para esta categoria? Basta ter aporte ou algum ajuste.
    static func hasEnvelope(
        _ category: Category,
        allocations: [EnvelopeAllocation],
        adjustments: [EnvelopeAdjustment]
    ) -> Bool {
        guard category.acceptsEnvelope else { return false }
        if allocations.contains(where: { $0.category?.id == category.id }) { return true }
        return adjustments.contains(where: { $0.category?.id == category.id })
    }

    // MARK: - Cálculo

    /// Gasto por categoria e por mês, numa passada só sobre os lançamentos.
    ///
    /// Segue as mesmas regras do resumo mensal: transferência e pagamento de
    /// fatura não contam, estorno abate o gasto, e receita não entra em
    /// envelope nenhum.
    static func spendingByMonth(_ transactions: [Txn]) -> [String: [UUID: Decimal]] {
        var result: [String: [UUID: Decimal]] = [:]

        for txn in transactions where txn.countsInBudget && txn.kind != .income {
            guard let categoryID = txn.category?.id else { continue }
            let key = MonthKey(date: txn.date).key
            let delta = txn.kind == .refund ? -txn.absAmount : txn.absAmount
            result[key, default: [:]][categoryID, default: 0] += delta
        }
        return result
    }

    /// Situação de todos os envelopes em `month`, varrendo desde `start`.
    ///
    /// Meses anteriores a `start` são ignorados: é onde você decidiu começar a
    /// usar envelopes, e todo envelope nasce zerado ali.
    static func states(
        month: MonthKey,
        start: MonthKey,
        categories: [Category],
        allocations: [EnvelopeAllocation],
        adjustments: [EnvelopeAdjustment],
        transactions: [Txn]
    ) -> [State] {
        let envelopes = categories.filter { hasEnvelope($0, allocations: allocations, adjustments: adjustments) }
        guard !envelopes.isEmpty else { return [] }

        // Um mês antes do início não existe, então tudo começa em zero.
        guard month >= start else {
            return envelopes.map {
                State(category: $0, month: month, carriedIn: 0, allocated: 0, adjusted: 0, spent: 0)
            }
        }

        let spending = spendingByMonth(transactions)

        var adjustmentsByMonth: [String: [UUID: Decimal]] = [:]
        for adjustment in adjustments {
            guard let categoryID = adjustment.category?.id else { continue }
            adjustmentsByMonth[adjustment.monthKey, default: [:]][categoryID, default: 0] += adjustment.amount
        }

        var carried: [UUID: Decimal] = [:]
        var current = start
        var result: [State] = []

        while true {
            let monthSpending = spending[current.key] ?? [:]
            let monthAdjustments = adjustmentsByMonth[current.key] ?? [:]
            var states: [State] = []

            for category in envelopes {
                let state = State(
                    category: category,
                    month: current,
                    carriedIn: carried[category.id] ?? 0,
                    allocated: allocation(for: category, month: current, allocations: allocations) ?? 0,
                    adjusted: monthAdjustments[category.id] ?? 0,
                    spent: monthSpending[category.id] ?? 0
                )
                states.append(state)
                carried[category.id] = state.carriesOut
            }

            if current == month {
                result = states
                break
            }
            current = current.adding(months: 1)
        }

        // Estourados primeiro, depois os mais apertados.
        return result.sorted { lhs, rhs in
            if lhs.isOverdrawn != rhs.isOverdrawn { return lhs.isOverdrawn }
            return lhs.ratio > rhs.ratio
        }
    }

    // MARK: - Totais

    struct Totals {
        let available: Decimal
        let funded: Decimal
        let spent: Decimal
        let allocated: Decimal
        let carriedIn: Decimal
        let overdrawnCount: Int

        var ratio: Double {
            guard funded > 0 else { return spent > 0 ? 1 : 0 }
            return spent.doubleValue / funded.doubleValue
        }
    }

    static func totals(_ states: [State]) -> Totals {
        Totals(
            available: states.reduce(Decimal(0)) { $0 + $1.available },
            funded: states.reduce(Decimal(0)) { $0 + $1.funded },
            spent: states.reduce(Decimal(0)) { $0 + $1.spent },
            allocated: states.reduce(Decimal(0)) { $0 + $1.allocated },
            carriedIn: states.reduce(Decimal(0)) { $0 + $1.carriedIn },
            overdrawnCount: states.filter(\.isOverdrawn).count
        )
    }

    /// Gasto de uma categoria num mês, para quem ainda não tem envelope.
    static func spent(for category: Category, month: MonthKey, transactions: [Txn]) -> Decimal {
        spendingByMonth(transactions)[month.key]?[category.id] ?? 0
    }
}
