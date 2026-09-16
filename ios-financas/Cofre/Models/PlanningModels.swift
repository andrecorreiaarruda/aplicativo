import Foundation
import SwiftData

/// Quanto entra no envelope de uma categoria a cada mês — o aporte, não um
/// teto. `monthKey` guarda "aaaa-MM" para ajustar um mês específico ou
/// `EnvelopeAllocation.defaultKey` para o valor que vale em todos os meses sem
/// ajuste próprio.
@Model
final class EnvelopeAllocation {
    static let defaultKey = "padrao"

    var id: UUID = UUID()
    var monthKey: String = EnvelopeAllocation.defaultKey
    /// Valor depositado no envelope no início do mês.
    var amount: Decimal = 0
    var category: Category?
    var createdAt: Date = Date()

    var isDefault: Bool { monthKey == EnvelopeAllocation.defaultKey }

    init(category: Category?, amount: Decimal, monthKey: String = EnvelopeAllocation.defaultKey) {
        self.id = UUID()
        self.category = category
        self.amount = amount
        self.monthKey = monthKey
        self.createdAt = Date()
    }
}

/// Mexida manual no saldo de um envelope num mês: um reforço, uma retirada, ou
/// uma das duas pontas de uma transferência entre envelopes.
///
/// É o equivalente digital de tirar uma nota do envelope do lazer e colocar no
/// do mercado — o movimento que o método de papel sempre permitiu e que um teto
/// mensal não sabe representar.
@Model
final class EnvelopeAdjustment {
    var id: UUID = UUID()
    /// Sempre um mês concreto ("aaaa-MM"), nunca o valor padrão.
    var monthKey: String = MonthKey.current.key
    /// Positivo entra no envelope, negativo sai.
    var amount: Decimal = 0
    var note: String = ""
    var category: Category?
    /// Liga as duas pontas de uma transferência, para poder desfazer as duas.
    var transferPairID: UUID?
    var createdAt: Date = Date()

    var isTransfer: Bool { transferPairID != nil }

    init(category: Category?, amount: Decimal, monthKey: String, note: String = "", transferPairID: UUID? = nil) {
        self.id = UUID()
        self.category = category
        self.amount = amount
        self.monthKey = monthKey
        self.note = note
        self.transferPairID = transferPairID
        self.createdAt = Date()
    }
}

/// Meta de economia ou de investimento: quanto você quer juntar, até quando, e
/// quanto já foi separado.
@Model
final class Goal {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = GoalKind.reserva.rawValue
    var targetAmount: Decimal = 0
    var targetDate: Date?
    var colorHex: String = "#1D9A6C"
    var symbol: String = "target"
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()

    /// Conta onde o dinheiro da meta fica guardado, se houver.
    var linkedAccount: Account?

    @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
    var contributions: [GoalContribution]? = []

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .reserva }
        set { kindRaw = newValue.rawValue }
    }

    var savedAmount: Decimal {
        (contributions ?? []).reduce(Decimal(0)) { $0 + $1.amount }
    }

    var remainingAmount: Decimal {
        max(targetAmount - savedAmount, 0)
    }

    /// 0...1. Vale 1 quando a meta não tem alvo definido e já há algo guardado.
    var progress: Double {
        guard targetAmount > 0 else { return savedAmount > 0 ? 1 : 0 }
        let ratio = (savedAmount as NSDecimalNumber).doubleValue / (targetAmount as NSDecimalNumber).doubleValue
        return min(max(ratio, 0), 1)
    }

    /// Meses inteiros que ainda faltam até o prazo (mínimo 1 quando há prazo).
    var monthsRemaining: Int? {
        guard let targetDate else { return nil }
        let months = Calendar.brazil.dateComponents([.month], from: Date(), to: targetDate).month ?? 0
        return max(months, 1)
    }

    /// Quanto precisa ser guardado por mês para bater a meta no prazo.
    var monthlyNeeded: Decimal? {
        guard let months = monthsRemaining, remainingAmount > 0 else { return nil }
        return remainingAmount / Decimal(months)
    }

    init(
        name: String,
        kind: GoalKind = .reserva,
        targetAmount: Decimal,
        targetDate: Date? = nil,
        colorHex: String = "#1D9A6C",
        symbol: String? = nil,
        linkedAccount: Account? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.colorHex = colorHex
        self.symbol = symbol ?? kind.symbol
        self.linkedAccount = linkedAccount
        self.notes = ""
        self.isArchived = false
        self.createdAt = Date()
    }
}

/// Um aporte feito para uma meta.
@Model
final class GoalContribution {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Decimal = 0
    var note: String = ""
    var goal: Goal?

    init(date: Date = Date(), amount: Decimal, note: String = "") {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.note = note
    }
}

/// Plano de alocação da renda: quanto de cada real deve ir para cada bolso.
/// O padrão é 50/30/20, mas as fatias são totalmente editáveis.
@Model
final class AllocationPlan {
    var id: UUID = UUID()
    var name: String = "Meu plano"
    /// Renda mensal usada como base quando `useAutoIncome` está desligado.
    var manualMonthlyIncome: Decimal = 0
    /// Quando ligado, a base é a média das receitas dos últimos meses.
    var useAutoIncome: Bool = true
    var autoIncomeMonths: Int = 3
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \AllocationBucket.plan)
    var buckets: [AllocationBucket]? = []

    var sortedBuckets: [AllocationBucket] {
        (buckets ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var totalPercentage: Decimal {
        (buckets ?? []).reduce(Decimal(0)) { $0 + $1.percentage }
    }

    init(name: String = "Meu plano") {
        self.id = UUID()
        self.name = name
        self.useAutoIncome = true
        self.autoIncomeMonths = 3
        self.createdAt = Date()
    }
}

/// Uma fatia do plano de alocação, ligada a um grupo de categorias para que o
/// app consiga comparar o planejado com o que realmente aconteceu.
@Model
final class AllocationBucket {
    var id: UUID = UUID()
    var name: String = ""
    /// Percentual da renda (0...100).
    var percentage: Decimal = 0
    var symbol: String = "circle"
    var colorHex: String = "#2F6FED"
    var groupRaw: String = CategoryGroup.essencial.rawValue
    var sortIndex: Int = 0
    var plan: AllocationPlan?

    var group: CategoryGroup {
        get { CategoryGroup(rawValue: groupRaw) ?? .essencial }
        set { groupRaw = newValue.rawValue }
    }

    init(name: String, percentage: Decimal, group: CategoryGroup, symbol: String, colorHex: String, sortIndex: Int) {
        self.id = UUID()
        self.name = name
        self.percentage = percentage
        self.groupRaw = group.rawValue
        self.symbol = symbol
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

/// Conta fixa que se repete todo mês (aluguel, assinatura, mensalidade).
/// O app só lembra do vencimento e confere se já apareceu um lançamento
/// parecido no mês — ele nunca paga nada.
@Model
final class RecurringBill {
    var id: UUID = UUID()
    var name: String = ""
    var expectedAmount: Decimal = 0
    var dueDay: Int = 10
    var isVariableAmount: Bool = false
    var isArchived: Bool = false
    var category: Category?
    var account: Account?
    var card: CreditCard?
    var createdAt: Date = Date()

    init(
        name: String,
        expectedAmount: Decimal,
        dueDay: Int,
        isVariableAmount: Bool = false,
        category: Category? = nil,
        account: Account? = nil,
        card: CreditCard? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.expectedAmount = expectedAmount
        self.dueDay = min(max(dueDay, 1), 31)
        self.isVariableAmount = isVariableAmount
        self.category = category
        self.account = account
        self.card = card
        self.createdAt = Date()
    }
}
