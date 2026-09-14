import Foundation
import SwiftData

/// Banco ou emissor. Existe só para agrupar contas e cartões na interface.
@Model
final class Institution {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var symbol: String = "building.columns"
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Account.institution)
    var accounts: [Account]? = []

    @Relationship(deleteRule: .nullify, inverse: \CreditCard.institution)
    var cards: [CreditCard]? = []

    init(name: String, colorHex: String = "#8E8E93", symbol: String = "building.columns") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.createdAt = Date()
    }
}

/// Conta bancária, de pagamentos, poupança, investimento ou dinheiro em espécie.
///
/// O saldo não é armazenado: ele é sempre `openingBalance` mais a soma dos
/// lançamentos. Assim nenhuma importação ou edição consegue deixar o saldo
/// inconsistente com o extrato.
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.corrente.rawValue
    /// Saldo conhecido em `openingDate`. É o ponto de partida da conciliação.
    var openingBalance: Decimal = 0
    var openingDate: Date = Date()
    var colorHex: String = "#2F6FED"
    var includeInNetWorth: Bool = true
    var isArchived: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()

    var institution: Institution?

    @Relationship(deleteRule: .cascade, inverse: \Txn.account)
    var transactions: [Txn]? = []

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .corrente }
        set { typeRaw = newValue.rawValue }
    }

    init(
        name: String,
        type: AccountType = .corrente,
        openingBalance: Decimal = 0,
        openingDate: Date = Date(),
        colorHex: String = "#2F6FED",
        institution: Institution? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.openingBalance = openingBalance
        self.openingDate = openingDate
        self.colorHex = colorHex
        self.institution = institution
        self.includeInNetWorth = true
        self.isArchived = false
        self.notes = ""
        self.createdAt = Date()
    }
}

/// Cartão de crédito, com o ciclo de fatura (fechamento e vencimento) que
/// define em qual fatura cada compra cai.
@Model
final class CreditCard {
    var id: UUID = UUID()
    var name: String = ""
    var brandRaw: String = CardBrand.outra.rawValue
    var lastFourDigits: String = ""
    var creditLimit: Decimal = 0
    /// Dia do mês em que a fatura fecha (1...31, ajustado para meses curtos).
    var closingDay: Int = 25
    /// Dia do mês do vencimento.
    var dueDay: Int = 5
    var colorHex: String = "#5E5CE6"
    var isArchived: Bool = false
    var createdAt: Date = Date()

    var institution: Institution?
    /// Conta de onde a fatura costuma ser paga.
    var paymentAccount: Account?

    @Relationship(deleteRule: .cascade, inverse: \Txn.card)
    var transactions: [Txn]? = []

    var brand: CardBrand {
        get { CardBrand(rawValue: brandRaw) ?? .outra }
        set { brandRaw = newValue.rawValue }
    }

    init(
        name: String,
        brand: CardBrand = .outra,
        lastFourDigits: String = "",
        creditLimit: Decimal = 0,
        closingDay: Int = 25,
        dueDay: Int = 5,
        colorHex: String = "#5E5CE6",
        institution: Institution? = nil,
        paymentAccount: Account? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.brandRaw = brand.rawValue
        self.lastFourDigits = lastFourDigits
        self.creditLimit = creditLimit
        self.closingDay = min(max(closingDay, 1), 31)
        self.dueDay = min(max(dueDay, 1), 31)
        self.colorHex = colorHex
        self.institution = institution
        self.paymentAccount = paymentAccount
        self.isArchived = false
        self.createdAt = Date()
    }
}
