import SwiftUI

/// Ícone colorido dentro de um quadrado arredondado — usado em conta, cartão,
/// categoria e meta para a interface ter uma linguagem só.
struct IconBadge: View {
    let symbol: String
    let hex: String
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(hex: hex).opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color(hex: hex))
            )
    }
}

/// Número grande com rótulo, para os destaques do resumo.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = .primary
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Barra de progresso com marcador opcional de "ritmo esperado".
struct MeterBar: View {
    let ratio: Double
    var tint: Color = .accentColor
    var pace: Double?
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))

                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * min(ratio, 1), ratio > 0 ? 4 : 0))

                if let pace, pace > 0, pace < 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: height + 4)
                        .offset(x: geo.size.width * pace)
                }
            }
        }
        .frame(height: height)
    }
}

/// Estado vazio com uma ação clara, em vez de uma tela em branco.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

/// Seletor de mês com setas, presente em quase todas as telas.
struct MonthStepper: View {
    @Binding var month: MonthKey
    var allowFuture: Bool = false

    private var canGoForward: Bool {
        allowFuture || month < MonthKey.current
    }

    var body: some View {
        HStack {
            Button {
                month = month.adding(months: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 32)
            }

            Spacer()

            VStack(spacing: 0) {
                Text(month.longName.capitalizedFirst)
                    .font(.headline)
                if month == MonthKey.current {
                    Text("mês atual")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                month = month.adding(months: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 32)
            }
            .disabled(!canGoForward)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}

/// Campo de dinheiro. Guarda o texto enquanto você digita e converte para
/// `Decimal` ao sair, aceitando "1.234,56" e "1234.56".
struct CurrencyField: View {
    let title: String
    @Binding var value: Decimal
    var allowNegative: Bool = false

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0,00", text: $text)
                .keyboardType(allowNegative ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onAppear { text = value == 0 ? "" : Money.plain(value) }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        if value == 0 { text = "" }
                    } else {
                        commit()
                    }
                }
                .onSubmit { commit() }
        }
    }

    private func commit() {
        guard let parsed = Money.parse(text) else {
            value = 0
            text = ""
            return
        }
        let final = allowNegative ? parsed : (parsed < 0 ? -parsed : parsed)
        value = Money.rounded(final)
        text = Money.plain(value)
    }
}

/// Grade de cores para personalizar contas, cartões, categorias e metas.
struct ColorPickerGrid: View {
    @Binding var hex: String

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Palette.picks, id: \.self) { option in
                Circle()
                    .fill(Color(hex: option))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: hex == option ? 2.5 : 0)
                            .padding(-3)
                    )
                    .onTapGesture { hex = option }
                    .accessibilityLabel(Text("Cor"))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Linha de lançamento reutilizada no extrato, na fatura e na busca.
struct TransactionRow: View {
    let txn: Txn
    var showAccount: Bool = false
    var hideAmounts: Bool = false

    private var tint: String {
        txn.category?.colorHex ?? "#8E8E93"
    }

    private var symbol: String {
        txn.category?.symbol ?? txn.kind.symbol
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, hex: tint)
                .opacity(txn.isIgnored ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(txn.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .strikethrough(txn.isIgnored, color: .secondary)

                HStack(spacing: 6) {
                    Text(DateFormatters.relativeDay(txn.date))
                    if let installment = txn.installmentLabel {
                        Text("•")
                        Text(installment)
                    }
                    if let category = txn.category {
                        Text("•")
                        Text(category.name).lineLimit(1)
                    }
                    if showAccount {
                        if let account = txn.account {
                            Text("•")
                            Text(account.name).lineLimit(1)
                        } else if let card = txn.card {
                            Text("•")
                            Text(card.name).lineLimit(1)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(hideAmounts ? "R$ ••••" : Money.signed(txn.amount))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.amount(txn.amount))
                    .lineLimit(1)
                if txn.kind.isNeutral {
                    Text(txn.kind.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Aviso curto e discreto, usado para explicar comportamento em vez de esconder.
struct InlineNote: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
