import Foundation

/// Natureza da conta. `dinheiro` cobre carteira física; `investimento` entra no
/// patrimônio mas fica fora do orçamento do mês.
enum AccountType: String, Codable, CaseIterable, Identifiable {
    case corrente, poupanca, pagamentos, investimento, dinheiro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .corrente: return "Conta corrente"
        case .poupanca: return "Poupança"
        case .pagamentos: return "Conta de pagamentos"
        case .investimento: return "Investimento"
        case .dinheiro: return "Dinheiro"
        }
    }

    var symbol: String {
        switch self {
        case .corrente: return "building.columns"
        case .poupanca: return "banknote"
        case .pagamentos: return "wallet.bifold"
        case .investimento: return "chart.line.uptrend.xyaxis"
        case .dinheiro: return "dollarsign.circle"
        }
    }

    /// Investimento e poupança contam como reserva, não como saldo disponível do mês.
    var isReserve: Bool { self == .investimento || self == .poupanca }
}

enum CardBrand: String, Codable, CaseIterable, Identifiable {
    case visa, mastercard, elo, amex, hipercard, outra

    var id: String { rawValue }

    var label: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .elo: return "Elo"
        case .amex: return "American Express"
        case .hipercard: return "Hipercard"
        case .outra: return "Outra"
        }
    }
}

/// O que a operação representa no fluxo de caixa.
enum TxKind: String, Codable, CaseIterable, Identifiable {
    /// Saída de dinheiro (compra, boleto, débito).
    case expense
    /// Entrada (salário, reembolso recebido, rendimento).
    case income
    /// Movimento entre contas próprias — neutro no orçamento.
    case transfer
    /// Pagamento de fatura de cartão — neutro, a despesa já foi contada na compra.
    case cardPayment
    /// Estorno/devolução que reduz uma despesa anterior.
    case refund
    /// Aporte em investimento — sai da conta mas continua sendo seu patrimônio.
    case investment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expense: return "Despesa"
        case .income: return "Receita"
        case .transfer: return "Transferência"
        case .cardPayment: return "Pagamento de fatura"
        case .refund: return "Estorno"
        case .investment: return "Aporte"
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "arrow.down.left"
        case .income: return "arrow.up.right"
        case .transfer: return "arrow.left.arrow.right"
        case .cardPayment: return "creditcard"
        case .refund: return "arrow.uturn.left"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }

    /// Movimentos neutros não entram em "quanto gastei" nem em "quanto ganhei".
    var isNeutral: Bool { self == .transfer || self == .cardPayment }
}

/// De onde o lançamento veio. Serve para o app nunca sobrescrever o que o banco
/// mandou com uma edição manual sem o usuário saber.
enum TxSource: String, Codable, CaseIterable, Identifiable {
    case manual, ofx, csv, aggregator

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .ofx: return "Extrato OFX"
        case .csv: return "Planilha CSV"
        case .aggregator: return "Sincronização"
        }
    }
}

/// Agrupamento macro usado no plano de alocação (padrão 50/30/20).
enum CategoryGroup: String, Codable, CaseIterable, Identifiable {
    case essencial, estiloDeVida, investimento, receita, neutro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .essencial: return "Essencial"
        case .estiloDeVida: return "Estilo de vida"
        case .investimento: return "Investir e guardar"
        case .receita: return "Receita"
        case .neutro: return "Neutro"
        }
    }

    var hex: String {
        switch self {
        case .essencial: return "#2F6FED"
        case .estiloDeVida: return "#F2994A"
        case .investimento: return "#1D9A6C"
        case .receita: return "#00A6A6"
        case .neutro: return "#8E8E93"
        }
    }
}

enum GoalKind: String, Codable, CaseIterable, Identifiable {
    case reserva, compra, viagem, quitarDivida, investir

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reserva: return "Reserva de emergência"
        case .compra: return "Compra planejada"
        case .viagem: return "Viagem"
        case .quitarDivida: return "Quitar dívida"
        case .investir: return "Investimento"
        }
    }

    var symbol: String {
        switch self {
        case .reserva: return "shield.lefthalf.filled"
        case .compra: return "bag"
        case .viagem: return "airplane"
        case .quitarDivida: return "scissors"
        case .investir: return "chart.pie"
        }
    }
}

/// O que acontece com o saldo de um envelope na virada do mês.
///
/// É a diferença entre o método dos envelopes e um simples teto mensal: no
/// envelope, o que sobra continua lá. É esse acúmulo que transforma economizar
/// num placar que sobe, em vez de um limite que zera e desmotiva.
enum RolloverPolicy: String, Codable, CaseIterable, Identifiable {
    /// Sobra e falta atravessam o mês. É o método clássico e o padrão: se você
    /// estourou, o dinheiro saiu de algum lugar de verdade, e o buraco
    /// acompanha até ser coberto.
    case accumulate
    /// A sobra acumula, a falta é perdoada. Menos fiel à realidade do dinheiro,
    /// mas evita que um mês ruim contamine os seguintes.
    case surplusOnly
    /// Começa do zero todo mês. É o teto mensal de sempre — bom para gastos que
    /// não fazem sentido guardar, como delivery.
    case reset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accumulate: return "Acumula sobra e falta"
        case .surplusOnly: return "Acumula só a sobra"
        case .reset: return "Zera todo mês"
        }
    }

    var detail: String {
        switch self {
        case .accumulate:
            return "O que sobrar continua no envelope no mês seguinte. Se estourar, o envelope começa negativo até você cobrir."
        case .surplusOnly:
            return "O que sobrar continua no envelope. Se estourar, o mês seguinte começa do zero."
        case .reset:
            return "O envelope volta ao valor do aporte todo dia 1º, sem guardar sobra nem dívida."
        }
    }

    var symbol: String {
        switch self {
        case .accumulate: return "arrow.trianglehead.2.clockwise"
        case .surplusOnly: return "arrow.up.forward.circle"
        case .reset: return "arrow.counterclockwise"
        }
    }

    /// Quanto do saldo disponível de um mês atravessa para o mês seguinte.
    func carryOut(_ available: Decimal) -> Decimal {
        switch self {
        case .accumulate: return available
        case .surplusOnly: return max(available, 0)
        case .reset: return 0
        }
    }
}
