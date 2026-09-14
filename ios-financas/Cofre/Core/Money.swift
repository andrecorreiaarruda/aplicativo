import Foundation

/// Formatação e parsing de dinheiro em português do Brasil.
///
/// Tudo no app é `Decimal`: `Double` arredonda centavos de forma imprevisível e
/// em extrato isso vira diferença de saldo.
enum Money {
    static let currencyCode = "BRL"

    private static let locale = Locale(identifier: "pt_BR")

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currencyCode
        return f
    }()

    private static let compactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.maximumFractionDigits = 0
        return f
    }()

    private static let plainFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// "R$ 1.234,56"
    static func string(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "R$ 0,00"
    }

    /// "1.234,56" — sem símbolo, para campos de entrada.
    static func plain(_ value: Decimal) -> String {
        plainFormatter.string(from: value as NSDecimalNumber) ?? "0,00"
    }

    /// Valor sem sinal com o símbolo. Útil quando a direção já é mostrada por
    /// cor ou ícone.
    static func abs(_ value: Decimal) -> String {
        string(value < 0 ? -value : value)
    }

    /// Sinal explícito: "+R$ 300,00" / "−R$ 89,90".
    static func signed(_ value: Decimal) -> String {
        if value == 0 { return string(0) }
        let sign = value > 0 ? "+" : "\u{2212}"
        return sign + string(value < 0 ? -value : value)
    }

    /// "R$ 1,2 mil" / "R$ 34,5 mil" — para rótulos de gráfico.
    static func short(_ value: Decimal) -> String {
        let d = (value as NSDecimalNumber).doubleValue
        let a = Swift.abs(d)
        let sign = d < 0 ? "\u{2212}" : ""
        switch a {
        case 1_000_000...:
            return "\(sign)R$ \(fmt(a / 1_000_000)) mi"
        case 1_000...:
            return "\(sign)R$ \(fmt(a / 1_000)) mil"
        default:
            return "\(sign)R$ " + (compactFormatter.string(from: NSNumber(value: a)) ?? "0")
        }
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Lê um número escrito por gente ou vindo de CSV.
    ///
    /// Aceita "1.234,56", "1,234.56", "R$ 89,90", "(89,90)" (negativo contábil)
    /// e "89.90". A escolha entre vírgula e ponto como decimal é feita pelo
    /// separador que aparece por último, que é a convenção que dá certo nos dois
    /// formatos.
    static func parse(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }

        s = s.replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .trimmingCharacters(in: .whitespaces)

        if s.hasPrefix("-") {
            negative.toggle()
            s = String(s.dropFirst())
        } else if s.hasPrefix("+") {
            s = String(s.dropFirst())
        }

        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            if comma > dot {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        case (.some, .none):
            s = s.replacingOccurrences(of: ",", with: ".")
        default:
            break
        }

        guard !s.isEmpty, let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return negative ? -value : value
    }

    /// Arredonda para centavos, modo bancário padrão de dinheiro.
    static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}

extension Decimal {
    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}
