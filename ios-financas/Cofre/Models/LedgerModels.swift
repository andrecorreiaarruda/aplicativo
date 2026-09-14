import Foundation
import SwiftData

/// Categoria de gasto ou receita. `keywords` alimenta a categorização
/// automática da importação.
@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "tag"
    var colorHex: String = "#8E8E93"
    var groupRaw: String = CategoryGroup.estiloDeVida.rawValue
    /// Categorias do sistema não podem ser apagadas, só renomeadas.
    var isSystem: Bool = false
    var keywords: [String] = []
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Txn.category)
    var transactions: [Txn]? = []

    var group: CategoryGroup {
        get { CategoryGroup(rawValue: groupRaw) ?? .estiloDeVida }
        set { groupRaw = newValue.rawValue }
    }

    init(
        name: String,
        symbol: String = "tag",
        colorHex: String = "#8E8E93",
        group: CategoryGroup = .estiloDeVida,
        keywords: [String] = [],
        isSystem: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.groupRaw = group.rawValue
        self.keywords = keywords
        self.isSystem = isSystem
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }
}

/// Um lançamento: compra, recebimento, transferência ou aporte.
///
/// O sinal fica sempre em `amount` — negativo é saída, positivo é entrada — para
/// que somar uma lista seja sempre o resultado correto, sem olhar o `kind`.
@Model
final class Txn {
    var id: UUID = UUID()
    /// Data da operação (quando você gastou).
    var date: Date = Date()
    /// Texto cru do extrato, preservado para conferência e deduplicação.
    var rawDescription: String = ""
    /// Nome limpo mostrado na interface.
    var displayName: String = ""
    var amount: Decimal = 0
    var kindRaw: String = TxKind.expense.rawValue
    var sourceRaw: String = TxSource.manual.rawValue
    var notes: String = ""
    /// Fora do orçamento e dos totais, mas continua no extrato.
    var isIgnored: Bool = false
    /// Marcado quando você confere o lançamento contra o extrato do banco.
    var isReconciled: Bool = false

    /// Identificador único do banco (FITID do OFX). Quando existe, é a chave
    /// mais confiável para não importar a mesma operação duas vezes.
    var externalID: String?
    /// Impressão digital calculada (conta + data + valor + descrição) usada na
    /// deduplicação quando o arquivo não traz um identificador.
    var fingerprint: String = ""
    var importBatchID: UUID?

    /// Fatura à qual a compra pertence, no formato "aaaa-MM" (só para cartão).
    var invoiceKey: String?
    var installmentIndex: Int?
    var installmentTotal: Int?

    var account: Account?
    var card: CreditCard?
    var category: Category?
    /// Contraparte de uma transferência entre contas próprias.
    var transferPairID: UUID?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var source: TxSource {
        get { TxSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Valor sem sinal, para exibição.
    var absAmount: Decimal { amount < 0 ? -amount : amount }

    /// Entra nas contas de "gastei" / "ganhei" do mês?
    var countsInBudget: Bool { !isIgnored && !kind.isNeutral }

    var isOnCard: Bool { card != nil }

    var installmentLabel: String? {
        guard let index = installmentIndex, let total = installmentTotal, total > 1 else { return nil }
        return "\(index)/\(total)"
    }

    init(
        date: Date,
        displayName: String,
        amount: Decimal,
        kind: TxKind = .expense,
        source: TxSource = .manual,
        rawDescription: String? = nil,
        account: Account? = nil,
        card: CreditCard? = nil,
        category: Category? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.displayName = displayName
        self.rawDescription = rawDescription ?? displayName
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.account = account
        self.card = card
        self.category = category
        self.notes = ""
        self.isIgnored = false
        self.isReconciled = false
        self.fingerprint = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Regra aprendida: quando você recategoriza um lançamento, o app guarda o
/// padrão do estabelecimento para acertar sozinho da próxima vez.
@Model
final class MerchantRule {
    var id: UUID = UUID()
    /// Trecho normalizado (sem acento, maiúsculas) procurado na descrição.
    var pattern: String = ""
    /// Nome bonito que substitui o texto do extrato.
    var displayName: String?
    var category: Category?
    var hits: Int = 0
    /// Regras criadas pelo app a partir do seu comportamento, não digitadas.
    var isLearned: Bool = true
    var createdAt: Date = Date()

    init(pattern: String, category: Category?, displayName: String? = nil, isLearned: Bool = true) {
        self.id = UUID()
        self.pattern = pattern
        self.category = category
        self.displayName = displayName
        self.isLearned = isLearned
        self.hits = 0
        self.createdAt = Date()
    }
}

/// Registro de uma importação, para você poder auditar ou desfazer.
@Model
final class ImportBatch {
    var id: UUID = UUID()
    var fileName: String = ""
    var importedAt: Date = Date()
    var sourceRaw: String = TxSource.ofx.rawValue
    var destinationName: String = ""
    var totalRows: Int = 0
    var inserted: Int = 0
    var duplicatesSkipped: Int = 0
    var periodStart: Date?
    var periodEnd: Date?

    var source: TxSource {
        get { TxSource(rawValue: sourceRaw) ?? .ofx }
        set { sourceRaw = newValue.rawValue }
    }

    init(fileName: String, source: TxSource, destinationName: String) {
        self.id = UUID()
        self.fileName = fileName
        self.sourceRaw = source.rawValue
        self.destinationName = destinationName
        self.importedAt = Date()
    }
}
