import Foundation

/// Leitor de arquivos OFX — o "extrato eletrônico" que praticamente todo banco
/// brasileiro exporta (Itaú, Bradesco, BB, Santander, Nubank, Inter, C6...).
///
/// O OFX 1.x é SGML com tags que não fecham e o 2.x é XML de verdade. Em vez de
/// manter dois leitores, o parser trabalha por varredura de tags: acha
/// `<STMTTRN>`, coleta os campos até `</STMTTRN>` e aceita tanto
/// `<TRNAMT>-89.90` quanto `<TRNAMT>-89.90</TRNAMT>`.
enum OFXParser {

    static func parse(data: Data, fileName: String) throws -> StatementFile {
        guard let text = decode(data) else { throw ImportError.unreadableFile }
        return try parse(text: text, fileName: fileName)
    }

    /// OFX brasileiro costuma vir em ISO-8859-1; tentamos UTF-8 primeiro porque
    /// é o que os bancos mais novos usam.
    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty { return utf8 }
        if let latin = String(data: data, encoding: .isoLatin1), !latin.isEmpty { return latin }
        return String(data: data, encoding: .windowsCP1252)
    }

    static func parse(text: String, fileName: String) throws -> StatementFile {
        let body = stripHeader(text)
        guard !body.isEmpty else { throw ImportError.emptyFile }

        var rows: [StatementRow] = []
        var warnings: [String] = []

        for block in blocks(named: "STMTTRN", in: body) {
            let fields = fields(in: block)

            guard let rawDate = fields["DTPOSTED"] ?? fields["DTUSER"] ?? fields["DTAVAIL"],
                  let date = parseDate(rawDate) else {
                warnings.append("Lançamento sem data legível foi ignorado.")
                continue
            }
            guard let rawAmount = fields["TRNAMT"], let amount = Money.parse(rawAmount) else {
                warnings.append("Lançamento sem valor legível foi ignorado.")
                continue
            }

            // MEMO costuma trazer o texto mais completo; NAME é o resumido.
            let memo = fields["MEMO"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = fields["NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = pickDescription(memo: memo, name: name, type: fields["TRNTYPE"] ?? "")

            let installment = TextNormalizer.installment(in: description)

            rows.append(
                StatementRow(
                    date: date.startOfDay,
                    description: description,
                    amount: amount,
                    externalID: fields["FITID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                    installmentIndex: installment?.index,
                    installmentTotal: installment?.total
                )
            )
        }

        guard !rows.isEmpty else { throw ImportError.noTransactionsFound }

        var balance: Decimal?
        var balanceDate: Date?
        if let ledger = blocks(named: "LEDGERBAL", in: body).first {
            let fields = fields(in: ledger)
            balance = fields["BALAMT"].flatMap(Money.parse)
            balanceDate = fields["DTASOF"].flatMap(parseDate)
        }

        let accountFields = fields(in: blocks(named: "BANKACCTFROM", in: body).first
            ?? blocks(named: "CCACCTFROM", in: body).first
            ?? "")
        let hint = accountFields["ACCTID"].map { String($0.suffix(4)) }

        return StatementFile(
            rows: rows.sorted { $0.date < $1.date },
            source: .ofx,
            fileName: fileName,
            reportedBalance: balance,
            reportedBalanceDate: balanceDate,
            accountHint: hint,
            warnings: warnings
        )
    }

    /// Remove o cabeçalho `OFXHEADER:100 ... ` (ou a declaração XML) e devolve
    /// só a partir do primeiro `<OFX>`.
    private static func stripHeader(_ text: String) -> String {
        if let range = text.range(of: "<OFX", options: .caseInsensitive) {
            return String(text[range.lowerBound...])
        }
        return text
    }

    /// Todos os trechos entre `<TAG>` e `</TAG>`.
    private static func blocks(named tag: String, in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var result: [String] = []
        var cursor = text.startIndex

        while cursor < text.endIndex,
              let open = text.range(of: "<\(tag)>", options: .caseInsensitive, range: cursor..<text.endIndex) {
            guard let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) else {
                result.append(String(text[open.upperBound...]))
                break
            }
            result.append(String(text[open.upperBound..<close.lowerBound]))
            cursor = close.upperBound
        }
        return result
    }

    /// Lê os pares tag/valor de um bloco, tolerando tags sem fechamento.
    private static func fields(in block: String) -> [String: String] {
        guard !block.isEmpty else { return [:] }
        var result: [String: String] = [:]
        var cursor = block.startIndex

        while cursor < block.endIndex {
            guard let open = block.range(of: "<", range: cursor..<block.endIndex),
                  let closeBracket = block.range(of: ">", range: open.upperBound..<block.endIndex) else { break }

            let tag = String(block[open.upperBound..<closeBracket.lowerBound]).uppercased()
            cursor = closeBracket.upperBound

            // Tag de fechamento: nada a coletar.
            guard !tag.hasPrefix("/") else { continue }

            // O valor vai até o próximo "<", seja ele o fechamento da própria
            // tag (OFX 2.x) ou a abertura da tag seguinte (OFX 1.x).
            let valueEnd = block.range(of: "<", range: cursor..<block.endIndex)?.lowerBound ?? block.endIndex
            let value = String(block[cursor..<valueEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")

            if !value.isEmpty, result[tag] == nil {
                result[tag] = value
            }
            cursor = valueEnd
        }
        return result
    }

    /// Datas OFX são "AAAAMMDD" com hora e fuso opcionais:
    /// "20260912", "20260912103000", "20260912103000[-3:BRT]".
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.prefix { $0.isNumber }
        guard digits.count >= 8 else { return nil }

        let str = String(digits)
        guard let year = Int(str.prefix(4)),
              let month = Int(str.dropFirst(4).prefix(2)),
              let day = Int(str.dropFirst(6).prefix(2)),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }

        return Calendar.brazil.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// MEMO e NAME se repetem ou se complementam. Ficamos com o mais informativo
    /// e usamos o tipo da operação quando os dois vêm vazios.
    private static func pickDescription(memo: String, name: String, type: String) -> String {
        let candidates = [memo, name].filter { !$0.isEmpty }
        if let best = candidates.max(by: { $0.count < $1.count }), !best.isEmpty {
            return best
        }
        switch type.uppercased() {
        case "CREDIT", "DEP", "DIRECTDEP": return "Crédito"
        case "DEBIT", "PAYMENT": return "Débito"
        case "XFER": return "Transferência"
        case "FEE", "SRVCHG": return "Tarifa"
        case "INT": return "Rendimento"
        default: return "Lançamento"
        }
    }
}
