import Foundation

/// Todo o cálculo do app em funções puras sobre listas já carregadas.
///
/// Nada aqui toca o banco: as telas buscam com `@Query` e passam os arrays. Isso
/// evita as limitações de predicado do SwiftData e deixa cada número conferível.
enum FinanceEngine {

    // MARK: - Saldos

    /// Saldo da conta: o saldo inicial mais tudo que entrou e saiu até a data.
    static func balance(of account: Account, asOf date: Date = .distantFuture) -> Decimal {
        let movements = (account.transactions ?? [])
            .filter { $0.date <= date }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return account.openingBalance + movements
    }

    /// Soma das contas marcadas para entrar no patrimônio, já sem as arquivadas.
    static func netWorth(accounts: [Account], cards: [CreditCard]) -> Decimal {
        let assets = accounts
            .filter { !$0.isArchived && $0.includeInNetWorth }
            .reduce(Decimal(0)) { $0 + balance(of: $1) }
        let debt = cards
            .filter { !$0.isArchived }
            .reduce(Decimal(0)) { $0 + openInvoiceTotal(for: $1) }
        return assets - debt
    }

    /// Saldo que dá para usar hoje: só contas líquidas, sem poupança nem
    /// investimento.
    static func availableBalance(accounts: [Account]) -> Decimal {
        accounts
            .filter { !$0.isArchived && !$0.type.isReserve }
            .reduce(Decimal(0)) { $0 + balance(of: $1) }
    }

    static func reserveBalance(accounts: [Account]) -> Decimal {
        accounts
            .filter { !$0.isArchived && $0.type.isReserve }
            .reduce(Decimal(0)) { $0 + balance(of: $1) }
    }

    // MARK: - Cartões

    /// Lançamentos de uma fatura específica.
    static func transactions(of card: CreditCard, in cycle: InvoiceCycle) -> [Txn] {
        (card.transactions ?? [])
            .filter { $0.invoiceKey == cycle.monthKey.key }
            .sorted { $0.date > $1.date }
    }

    /// Total de uma fatura. Compras entram positivas porque fatura é dívida.
    static func invoiceTotal(of card: CreditCard, in cycle: InvoiceCycle) -> Decimal {
        transactions(of: card, in: cycle)
            .filter { !$0.isIgnored }
            .reduce(Decimal(0)) { $0 - $1.amount }
    }

    /// Soma de todas as faturas ainda não pagas (a aberta mais as fechadas com
    /// vencimento à frente).
    static func openInvoiceTotal(for card: CreditCard) -> Decimal {
        let current = InvoiceCalculator.currentCycle(for: card)
        let previous = InvoiceCalculator.cycle(for: card, in: current.monthKey.adding(months: -1))
        var total = invoiceTotal(of: card, in: current)
        if Date().startOfDay <= previous.dueDate {
            total += invoiceTotal(of: card, in: previous)
        }
        return max(total, 0)
    }

    /// Limite ainda disponível no cartão.
    static func availableLimit(for card: CreditCard) -> Decimal {
        max(card.creditLimit - openInvoiceTotal(for: card), 0)
    }

    /// 0...1 de uso do limite. Zero quando o limite não foi informado.
    static func limitUsage(for card: CreditCard) -> Double {
        guard card.creditLimit > 0 else { return 0 }
        return min(openInvoiceTotal(for: card).doubleValue / card.creditLimit.doubleValue, 1)
    }

    /// Estimativa de onde a fatura aberta deve terminar, extrapolando o ritmo do
    /// período. Só faz sentido enquanto a fatura está aberta.
    static func projectedInvoiceTotal(of card: CreditCard, cycle: InvoiceCycle) -> Decimal {
        let current = invoiceTotal(of: card, in: cycle)
        let elapsed = cycle.elapsedFraction
        guard cycle.isOpen, elapsed > 0.05 else { return current }
        return Money.rounded(Decimal(current.doubleValue / elapsed))
    }

    /// Parcelas que já estão contratadas e vão cair em faturas futuras.
    static func futureInstallments(for card: CreditCard, after cycle: InvoiceCycle) -> Decimal {
        (card.transactions ?? [])
            .filter { txn in
                guard let key = txn.invoiceKey, let month = MonthKey(key: key) else { return false }
                return month > cycle.monthKey && !txn.isIgnored
            }
            .reduce(Decimal(0)) { $0 - $1.amount }
    }

    // MARK: - Resumo do mês

    struct MonthSummary {
        let month: MonthKey
        let income: Decimal
        let expenses: Decimal
        let invested: Decimal
        let byGroup: [CategoryGroup: Decimal]
        let byCategory: [(category: Category?, total: Decimal)]
        let transactionCount: Int

        /// Sobra do mês (receitas menos despesas, aportes incluídos como saída).
        var net: Decimal { income - expenses }

        /// Quanto de cada real recebido sobrou. Nulo quando não houve receita.
        var savingsRate: Double? {
            guard income > 0 else { return nil }
            return net.doubleValue / income.doubleValue
        }
    }

    static func summary(for month: MonthKey, transactions all: [Txn]) -> MonthSummary {
        let txns = all.filter { month.contains($0.date) && $0.countsInBudget }

        var income = Decimal(0)
        var expenses = Decimal(0)
        var invested = Decimal(0)
        var byGroup: [CategoryGroup: Decimal] = [:]
        var byCategoryID: [UUID?: (Category?, Decimal)] = [:]

        for txn in txns {
            switch txn.kind {
            case .income:
                income += txn.absAmount
            case .investment:
                invested += txn.absAmount
                expenses += txn.absAmount
            case .refund:
                // Estorno reduz a despesa do mês em vez de virar receita.
                expenses -= txn.absAmount
            case .expense:
                expenses += txn.absAmount
            case .transfer, .cardPayment:
                continue
            }

            guard txn.kind != .income else { continue }

            let group = txn.category?.group ?? .estiloDeVida
            let delta = txn.kind == .refund ? -txn.absAmount : txn.absAmount
            byGroup[group, default: 0] += delta

            let key = txn.category?.id
            let existing = byCategoryID[key] ?? (txn.category, Decimal(0))
            byCategoryID[key] = (existing.0 ?? txn.category, existing.1 + delta)
        }

        let ranked = byCategoryID.values
            .map { (category: $0.0, total: $0.1) }
            .filter { $0.total != 0 }
            .sorted { $0.total > $1.total }

        return MonthSummary(
            month: month,
            income: income,
            expenses: expenses,
            invested: invested,
            byGroup: byGroup,
            byCategory: ranked,
            transactionCount: txns.count
        )
    }

    /// Média de receita dos últimos `months` meses fechados, usada como base do
    /// plano de alocação quando a renda não é digitada à mão.
    static func averageIncome(months: Int, transactions all: [Txn]) -> Decimal {
        guard months > 0 else { return 0 }
        let current = MonthKey.current
        let keys = (1...months).map { current.adding(months: -$0) }
        let totals = keys.map { key in
            all.filter { key.contains($0.date) && $0.kind == .income && !$0.isIgnored }
                .reduce(Decimal(0)) { $0 + $1.absAmount }
        }
        let sum = totals.reduce(Decimal(0), +)
        return sum == 0 ? 0 : Money.rounded(sum / Decimal(months))
    }

    // MARK: - Ritmo do mês

    /// Quanto já deveria ter sido gasto a esta altura do mês, se o gasto fosse
    /// distribuído por igual. Serve de linha de referência ("no ritmo certo").
    static func paceFraction(of month: MonthKey, on date: Date = Date()) -> Double {
        guard month.contains(date) else { return date >= month.end ? 1 : 0 }
        let day = Calendar.brazil.component(.day, from: date)
        return Double(day) / Double(month.numberOfDays)
    }

    // MARK: - Alocação

    struct AllocationStatus: Identifiable {
        let bucket: AllocationBucket
        let planned: Decimal
        let actual: Decimal

        var id: UUID { bucket.id }
        var difference: Decimal { planned - actual }
        var ratio: Double {
            guard planned > 0 else { return actual > 0 ? 1 : 0 }
            return actual.doubleValue / planned.doubleValue
        }
    }

    /// Renda base do plano: a média automática ou o valor digitado.
    static func baseIncome(plan: AllocationPlan, transactions all: [Txn]) -> Decimal {
        if plan.useAutoIncome {
            let average = averageIncome(months: plan.autoIncomeMonths, transactions: all)
            return average > 0 ? average : plan.manualMonthlyIncome
        }
        return plan.manualMonthlyIncome
    }

    static func allocationStatuses(
        plan: AllocationPlan,
        month: MonthKey,
        transactions all: [Txn]
    ) -> [AllocationStatus] {
        let income = baseIncome(plan: plan, transactions: all)
        let summary = summary(for: month, transactions: all)

        return plan.sortedBuckets.map { bucket in
            let planned = Money.rounded(income * bucket.percentage / 100)
            let actual = summary.byGroup[bucket.group] ?? 0
            return AllocationStatus(bucket: bucket, planned: planned, actual: max(actual, 0))
        }
    }

    // MARK: - Contas fixas

    struct BillStatus: Identifiable {
        let bill: RecurringBill
        let dueDate: Date
        let matchedTransaction: Txn?

        var id: UUID { bill.id }
        var isPaid: Bool { matchedTransaction != nil }
        var daysUntilDue: Int {
            Calendar.brazil.dateComponents([.day], from: Date().startOfDay, to: dueDate).day ?? 0
        }
        var isOverdue: Bool { !isPaid && daysUntilDue < 0 }
    }

    /// Confere se cada conta fixa já apareceu no extrato do mês. O casamento é
    /// por nome parecido e valor próximo — é um lembrete, não uma cobrança.
    static func billStatuses(month: MonthKey, bills: [RecurringBill], transactions all: [Txn]) -> [BillStatus] {
        let monthTxns = all.filter { month.contains($0.date) && $0.kind == .expense && !$0.isIgnored }

        return bills.filter { !$0.isArchived }.map { bill in
            let due = InvoiceCalculator.date(year: month.year, month: month.month, day: bill.dueDay)
            let needle = TextNormalizer.normalize(bill.name)

            let match = monthTxns.first { txn in
                let haystack = TextNormalizer.normalize(txn.displayName + " " + txn.rawDescription)
                guard !needle.isEmpty, haystack.contains(needle) else { return false }
                guard !bill.isVariableAmount, bill.expectedAmount > 0 else { return true }
                let tolerance = bill.expectedAmount * Decimal(0.2)
                return abs((txn.absAmount - bill.expectedAmount).doubleValue) <= tolerance.doubleValue
            }

            return BillStatus(bill: bill, dueDate: due, matchedTransaction: match)
        }
        .sorted { lhs, rhs in
            if lhs.isPaid != rhs.isPaid { return !lhs.isPaid }
            return lhs.dueDate < rhs.dueDate
        }
    }

    // MARK: - Série histórica

    struct MonthPoint: Identifiable {
        let month: MonthKey
        let income: Decimal
        let expenses: Decimal
        var id: String { month.key }
        var net: Decimal { income - expenses }
    }

    /// Últimos `count` meses terminando no mês atual, para os gráficos.
    static func history(months count: Int, transactions all: [Txn]) -> [MonthPoint] {
        let current = MonthKey.current
        return (0..<count).reversed().map { offset in
            let key = current.adding(months: -offset)
            let s = summary(for: key, transactions: all)
            return MonthPoint(month: key, income: s.income, expenses: s.expenses)
        }
    }
}
