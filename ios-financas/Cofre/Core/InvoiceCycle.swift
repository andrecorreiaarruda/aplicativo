import Foundation

/// Uma fatura de cartão: o período de compras, quando fecha e quando vence.
///
/// A regra usada é a das operadoras brasileiras: a compra feita **até** o dia do
/// fechamento entra na fatura que fecha naquele dia; a partir do dia seguinte,
/// cai na fatura do mês seguinte. O vencimento é o `dueDay` no mês do
/// fechamento quando ele vem depois do fechamento, ou no mês seguinte quando
/// vem antes (caso comum: fecha dia 25, vence dia 5).
struct InvoiceCycle: Identifiable, Hashable {
    /// Mês em que a fatura fecha. É também a chave gravada em `Txn.invoiceKey`.
    let monthKey: MonthKey
    let closingDate: Date
    let dueDate: Date
    /// Primeiro dia coberto por esta fatura.
    let periodStart: Date
    /// Último dia coberto (inclusive).
    let periodEnd: Date

    var id: String { monthKey.key }

    var isOpen: Bool { Date().startOfDay <= closingDate }

    var isOverdue: Bool { !isOpen && Date().startOfDay > dueDate }

    /// Dias que faltam para fechar. Negativo quando já fechou.
    var daysUntilClosing: Int {
        Calendar.brazil.dateComponents([.day], from: Date().startOfDay, to: closingDate).day ?? 0
    }

    var daysUntilDue: Int {
        Calendar.brazil.dateComponents([.day], from: Date().startOfDay, to: dueDate).day ?? 0
    }

    var title: String { monthKey.longName.capitalizedFirst }

    /// Quanto do período já passou (0...1). Serve para projetar o total final.
    var elapsedFraction: Double {
        let total = Calendar.brazil.dateComponents([.day], from: periodStart, to: closingDate).day ?? 1
        guard total > 0 else { return 1 }
        let done = Calendar.brazil.dateComponents([.day], from: periodStart, to: Date().startOfDay).day ?? 0
        return min(max(Double(done) / Double(total), 0), 1)
    }
}

enum InvoiceCalculator {
    /// Ajusta o dia para caber no mês (dia 31 em fevereiro vira o dia 28 ou 29).
    static func date(year: Int, month: Int, day: Int) -> Date {
        let key = MonthKey(year: year, month: month)
        let clamped = min(day, key.numberOfDays)
        return Calendar.brazil.date(
            from: DateComponents(year: key.year, month: key.month, day: clamped)
        )?.startOfDay ?? key.start
    }

    /// Monta a fatura que fecha em `monthKey`.
    ///
    /// Recebe os dias soltos, e não o cartão, para que a tela de cadastro possa
    /// mostrar a prévia do ciclo sem precisar criar um `CreditCard` provisório.
    static func cycle(closingDay: Int, dueDay: Int, in monthKey: MonthKey) -> InvoiceCycle {
        let closing = date(year: monthKey.year, month: monthKey.month, day: closingDay)

        let previous = monthKey.adding(months: -1)
        let previousClosing = date(year: previous.year, month: previous.month, day: closingDay)
        let periodStart = previousClosing.adding(days: 1)

        // Vence no mesmo mês se o dia do vencimento vem depois do fechamento;
        // caso contrário, no mês seguinte.
        let dueMonth = dueDay > closingDay ? monthKey : monthKey.adding(months: 1)
        let due = date(year: dueMonth.year, month: dueMonth.month, day: dueDay)

        return InvoiceCycle(
            monthKey: monthKey,
            closingDate: closing,
            dueDate: due,
            periodStart: periodStart,
            periodEnd: closing
        )
    }

    /// Em qual fatura uma compra nesta data cai.
    static func cycle(closingDay: Int, dueDay: Int, containing date: Date) -> InvoiceCycle {
        let day = date.startOfDay
        let month = MonthKey(date: day)
        let candidate = cycle(closingDay: closingDay, dueDay: dueDay, in: month)
        if day <= candidate.closingDate {
            return candidate
        }
        return cycle(closingDay: closingDay, dueDay: dueDay, in: month.adding(months: 1))
    }

    static func currentCycle(closingDay: Int, dueDay: Int) -> InvoiceCycle {
        cycle(closingDay: closingDay, dueDay: dueDay, containing: Date())
    }

    static func cycle(for card: CreditCard, in monthKey: MonthKey) -> InvoiceCycle {
        cycle(closingDay: card.closingDay, dueDay: card.dueDay, in: monthKey)
    }

    static func cycle(for card: CreditCard, containing date: Date) -> InvoiceCycle {
        cycle(closingDay: card.closingDay, dueDay: card.dueDay, containing: date)
    }

    /// A fatura aberta hoje — aquela que ainda está recebendo compras.
    static func currentCycle(for card: CreditCard) -> InvoiceCycle {
        cycle(for: card, containing: Date())
    }

    /// Faturas ao redor da atual, da mais antiga para a mais recente.
    static func cycles(for card: CreditCard, back: Int, forward: Int) -> [InvoiceCycle] {
        let current = currentCycle(for: card).monthKey
        return (-back...forward).map { cycle(for: card, in: current.adding(months: $0)) }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
