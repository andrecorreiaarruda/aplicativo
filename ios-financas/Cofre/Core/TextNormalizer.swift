import Foundation

/// Normalização de descrições de extrato.
///
/// Bancos escrevem o mesmo estabelecimento de dez jeitos diferentes
/// ("PADARIA SAO JOSE LTDA", "Pag*PadariaSaoJose", "PADARIA SÃO JOSÉ  02/06").
/// Reduzir tudo a uma forma comum é o que faz a deduplicação e a categorização
/// automática funcionarem.
enum TextNormalizer {

    /// Maiúsculas, sem acento, sem pontuação, com espaços colapsados.
    static func normalize(_ text: String) -> String {
        fold(text, keeping: [])
    }

    /// Igual à `normalize`, mas preserva a barra. A detecção de parcela depende
    /// dela: "2/10" vira "2 10" na normalização comum e a parcela se perde.
    static func normalizeKeepingSlashes(_ text: String) -> String {
        fold(text, keeping: ["/"])
    }

    private static func fold(_ text: String, keeping extras: Set<Character>) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let allowed = folded.map { ch -> Character in
            if ch.isLetter || ch.isNumber || extras.contains(ch) { return ch }
            return " "
        }
        return String(allowed)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .uppercased()
    }

    /// Prefixos de maquininha e carteira digital que só atrapalham a leitura.
    private static let noisePrefixes = [
        "PAG ", "PAGSEGURO ", "PAGS ", "MP ", "MERCADOPAGO ", "MERCADO PAGO ",
        "PICPAY ", "IFD ", "IFOOD ", "PIX ENVIADO ", "PIX RECEBIDO ",
        "COMPRA CARTAO ", "COMPRA COM CARTAO ", "DEBITO ", "CREDITO ",
        "TARIFA ", "TED ", "DOC ", "SUMUP ", "STONE ", "CIELO ", "REDE ", "EC "
    ]

    private static let noiseTokens: Set<String> = [
        "LTDA", "ME", "EPP", "SA", "EIRELI", "COMERCIO", "BRASIL", "BR", "BRA"
    ]

    /// Nome curto e legível para mostrar na lista — "Padaria Sao Jose".
    static func prettyName(_ raw: String) -> String {
        var text = normalize(raw)

        for prefix in noisePrefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }

        // Tira sufixos de data e parcela que o banco cola na descrição.
        var tokens = text.split(separator: " ").map(String.init)
        while let last = tokens.last, isNoiseSuffix(last) {
            tokens.removeLast()
        }
        tokens.removeAll { noiseTokens.contains($0) }

        guard !tokens.isEmpty else { return raw.trimmingCharacters(in: .whitespaces) }

        return tokens
            .prefix(5)
            .map { $0.count <= 2 ? $0 : $0.prefix(1) + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func isNoiseSuffix(_ token: String) -> Bool {
        if token.allSatisfy(\.isNumber) && token.count >= 4 { return true }
        return false
    }

    /// Detecta "3/10", "PARC 03 10", "03 DE 10" na descrição e devolve a parcela.
    static func installment(in raw: String) -> (index: Int, total: Int)? {
        let patterns = [
            #"(\d{1,2})\s*/\s*(\d{1,2})"#,
            #"PARC(?:ELA)?\s*(\d{1,2})\s*(?:DE|/)?\s*(\d{1,2})"#,
            #"(\d{1,2})\s+DE\s+(\d{1,2})"#
        ]
        let text = normalizeKeepingSlashes(raw)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 3,
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text),
                  let index = Int(text[r1]), let total = Int(text[r2])
            else { continue }

            if total > 1, total <= 99, index >= 1, index <= total {
                return (index, total)
            }
        }
        return nil
    }
}
