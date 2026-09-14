import Foundation

extension Calendar {
    /// Calendário fixo em pt-BR / fuso de São Paulo para que "mês" signifique a
    /// mesma coisa em qualquer aparelho.
    static let brazil: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "pt_BR")
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        c.firstWeekday = 1
        return c
    }()
}

/// Um mês do calendário. Usado como chave estável ("2026-09") em orçamento,
/// faturas e agregações.
struct MonthKey: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    let month: Int

    var id: String { key }

    var key: String { String(format: "%04d-%02d", year, month) }

    init(year: Int, month: Int) {
        let normalized = MonthKey.normalize(year: year, month: month)
        self.year = normalized.year
        self.month = normalized.month
    }

    init(date: Date) {
        let c = Calendar.brazil.dateComponents([.year, .month], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
    }

    init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else {
            return nil
        }
        self.year = y
        self.month = m
    }

    static var current: MonthKey { MonthKey(date: Date()) }

    private static func normalize(year: Int, month: Int) -> (year: Int, month: Int) {
        let zeroBased = month - 1
        let yearDelta = Int(floor(Double(zeroBased) / 12.0))
        let normalizedMonth = zeroBased - yearDelta * 12 + 1
        return (year + yearDelta, normalizedMonth)
    }

    func adding(months: Int) -> MonthKey {
        MonthKey(year: year, month: month + months)
    }

    var start: Date {
        Calendar.brazil.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    /// Primeiro instante do mês seguinte — use como limite superior exclusivo.
    var end: Date {
        adding(months: 1).start
    }

    var range: Range<Date> { start..<end }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    var numberOfDays: Int {
        Calendar.brazil.range(of: .day, in: .month, for: start)?.count ?? 30
    }

    /// "setembro de 2026"
    var longName: String {
        DateFormatters.monthYear.string(from: start)
    }

    /// "set/26"
    var shortName: String {
        DateFormatters.monthYearShort.string(from: start)
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

enum DateFormatters {
    private static let ptBR = Locale(identifier: "pt_BR")

    static let monthYear: DateFormatter = make("LLLL 'de' yyyy")
    static let monthYearShort: DateFormatter = make("LLL/yy")
    static let dayMonth: DateFormatter = make("d 'de' MMM")
    static let full: DateFormatter = make("d 'de' MMMM 'de' yyyy")
    static let short: DateFormatter = make("dd/MM/yyyy")
    static let weekdayDay: DateFormatter = make("EEEE, d 'de' MMMM")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = ptBR
        f.calendar = Calendar.brazil
        f.timeZone = Calendar.brazil.timeZone
        f.dateFormat = format
        return f
    }

    /// "hoje" / "ontem" / "12 de set"
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.brazil
        if cal.isDateInToday(date) { return "hoje" }
        if cal.isDateInYesterday(date) { return "ontem" }
        return dayMonth.string(from: date)
    }
}

extension Date {
    var startOfDay: Date { Calendar.brazil.startOfDay(for: self) }

    var monthKey: MonthKey { MonthKey(date: self) }

    func adding(days: Int) -> Date {
        Calendar.brazil.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(months: Int) -> Date {
        Calendar.brazil.date(byAdding: .month, value: months, to: self) ?? self
    }
}
