import SwiftUI

extension Color {
    /// Cor a partir de "#RRGGBB" ou "RRGGBB". Volta para cinza se o texto for
    /// inválido, para nunca quebrar a tela por causa de um dado salvo errado.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Palette {
    /// Cores oferecidas quando você cria uma conta, cartão, categoria ou meta.
    static let picks: [String] = [
        "#2F6FED", "#5E5CE6", "#8E44AD", "#C0399F", "#E5484D",
        "#F2994A", "#E8B931", "#1D9A6C", "#00A6A6", "#36618E",
        "#7A5C3E", "#5B6472"
    ]

    static let positive = Color(hex: "#1D9A6C")
    static let negative = Color(hex: "#E5484D")
    static let warning = Color(hex: "#F2994A")
    static let neutral = Color(hex: "#8E8E93")

    /// Verde para entrada, vermelho para saída, cinza para zero.
    static func amount(_ value: Decimal) -> Color {
        if value > 0 { return positive }
        if value < 0 { return .primary }
        return neutral
    }

    /// Semáforo do orçamento pelo percentual consumido.
    static func budget(_ ratio: Double) -> Color {
        switch ratio {
        case ..<0.75: return positive
        case ..<1.0: return warning
        default: return negative
        }
    }
}

/// Cartão padrão usado em todas as telas, para a interface ficar coesa.
struct CardSurface<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}
