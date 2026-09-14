import Foundation

/// Adivinha a categoria de um lançamento pela descrição.
///
/// A ordem importa: primeiro as regras que você mesmo ensinou (ao recategorizar
/// algo), depois as palavras-chave das categorias. Assim uma correção sua nunca
/// é desfeita por uma regra genérica do app.
enum Categorizer {

    struct Suggestion {
        var category: Category?
        var displayName: String
        var kind: TxKind
        /// Verdadeiro quando veio de uma regra aprendida com você.
        var fromLearnedRule: Bool
    }

    static func suggest(
        for row: StatementRow,
        categories: [Category],
        rules: [MerchantRule],
        isCard: Bool
    ) -> Suggestion {
        let normalized = TextNormalizer.normalize(row.description)
        let kind = inferKind(normalized: normalized, amount: row.amount, isCard: isCard)

        // 1. Regras aprendidas, da mais específica (padrão mais longo) para a
        //    mais genérica.
        let sorted = rules.sorted { $0.pattern.count > $1.pattern.count }
        for rule in sorted where !rule.pattern.isEmpty && normalized.contains(rule.pattern) {
            return Suggestion(
                category: rule.category,
                displayName: rule.displayName ?? TextNormalizer.prettyName(row.description),
                kind: kind,
                fromLearnedRule: true
            )
        }

        // 2. Palavras-chave das categorias.
        var best: (category: Category, weight: Int)?
        for category in categories {
            for keyword in category.keywords {
                let needle = TextNormalizer.normalize(keyword)
                guard !needle.isEmpty, normalized.contains(needle) else { continue }
                if best == nil || needle.count > best!.weight {
                    best = (category, needle.count)
                }
            }
        }

        // Receita e aporte nunca devem cair numa categoria de despesa.
        let expected: CategoryGroup? = {
            switch kind {
            case .income: return .receita
            case .investment: return .investimento
            case .transfer, .cardPayment: return .neutro
            default: return nil
            }
        }()

        var chosen = best?.category
        if let expected, chosen?.group != expected {
            chosen = categories.first { $0.group == expected }
        }

        return Suggestion(
            category: chosen,
            displayName: TextNormalizer.prettyName(row.description),
            kind: kind,
            fromLearnedRule: false
        )
    }

    private static let incomeMarkers = [
        "SALARIO", "PROVENTO", "PAGAMENTO RECEBIDO", "PIX RECEBIDO", "TED RECEBIDA",
        "DEPOSITO", "RENDIMENTO", "REMUNERACAO", "RESTITUICAO", "ESTORNO", "REEMBOLSO",
        "TRANSFERENCIA RECEBIDA", "CREDITO EM CONTA", "13 SALARIO", "FERIAS"
    ]

    private static let transferMarkers = [
        "TRANSFERENCIA ENTRE CONTAS", "APLICACAO", "RESGATE", "TRANSF CC",
        "TRANSFERENCIA MESMA TITULARIDADE"
    ]

    private static let cardPaymentMarkers = [
        "PAGAMENTO DE FATURA", "PAGTO FATURA", "PAGAMENTO FATURA", "PAGAMENTO CARTAO",
        "PAGAMENTO RECEBIDO OBRIGADO", "PAGAMENTO EM", "FATURA CARTAO"
    ]

    private static let investmentMarkers = [
        "APLICACAO CDB", "APLICACAO TESOURO", "TESOURO DIRETO", "INVESTIMENTO",
        "COMPRA DE ATIVO", "APLIC FINANCEIRA", "CDB", "LCI", "LCA", "FUNDO"
    ]

    /// Deduz a natureza do lançamento. Numa fatura de cartão, um valor positivo
    /// quase sempre é estorno ou pagamento, não receita.
    static func inferKind(normalized: String, amount: Decimal, isCard: Bool) -> TxKind {
        if cardPaymentMarkers.contains(where: { normalized.contains($0) }) { return .cardPayment }
        if transferMarkers.contains(where: { normalized.contains($0) }) { return .transfer }

        if amount > 0 {
            if isCard { return .refund }
            if investmentMarkers.contains(where: { normalized.contains($0) }) { return .transfer }
            if incomeMarkers.contains(where: { normalized.contains($0) }) { return .income }
            return .income
        }

        if investmentMarkers.contains(where: { normalized.contains($0) }) { return .investment }
        return .expense
    }

    /// Guarda o padrão do estabelecimento quando você corrige uma categoria.
    /// O padrão são as primeiras palavras do nome normalizado, o que costuma ser
    /// estável entre compras do mesmo lugar.
    static func learnPattern(from description: String) -> String {
        let normalized = TextNormalizer.normalize(description)
        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return normalized }
        return tokens.prefix(3).joined(separator: " ")
    }
}
