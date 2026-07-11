import Foundation

/// Pojedyncza operacja z wyciągu bankowego.
public struct BankTransaction: Equatable, Sendable {
    /// Data waluty operacji.
    public let date: Date
    /// Kwota: dodatnia dla uznań (wpływy), ujemna dla obciążeń (wypływy).
    public let amount: Double
    /// Tytuł operacji (z pola :86:, segmenty ~20–~25 jeśli obecne).
    public let title: String
    /// Nazwa kontrahenta (segmenty ~32–~33), jeśli bank ją wyodrębnia.
    public let counterparty: String

    public init(date: Date, amount: Double, title: String, counterparty: String = "") {
        self.date = date
        self.amount = amount
        self.title = title
        self.counterparty = counterparty
    }
}

/// Parser wyciągów MT940 (SWIFT) — standardowy format eksportu historii
/// operacji w polskich bankach (mBank, PKO BP, ING, Pekao…).
///
/// Obsługiwane elementy: pola `:61:` (data, strona C/D, kwota) i `:86:`
/// (opis operacji; rozpoznawane są podpola `~20`–`~25` jako tytuł oraz
/// `~32`/`~33` jako kontrahent — konwencja polskich banków). Pozostałe
/// pola (salda, nagłówki bloków SWIFT) są pomijane.
public enum MT940Parser {

    /// Parsuje treść wyciągu. Zwraca operacje w kolejności z pliku.
    public static func parse(_ text: String) -> [BankTransaction] {
        var transactions: [BankTransaction] = []
        var pendingEntry: (date: Date, amount: Double)?
        var pendingDescription = ""
        var inDescription = false

        func flush() {
            if let entry = pendingEntry {
                let (title, counterparty) = parseDescription(pendingDescription)
                transactions.append(BankTransaction(
                    date: entry.date,
                    amount: entry.amount,
                    title: title,
                    counterparty: counterparty
                ))
            }
            pendingEntry = nil
            pendingDescription = ""
            inDescription = false
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(":61:") {
                flush()
                pendingEntry = parseStatementLine(String(line.dropFirst(4)))
            } else if line.hasPrefix(":86:") {
                inDescription = pendingEntry != nil
                pendingDescription = String(line.dropFirst(4))
            } else if line.hasPrefix(":") || line.hasPrefix("-") || line.hasPrefix("{") {
                // Kolejne pole SWIFT / koniec bloku — zamyka opis operacji;
                // pola między :61: a :86: (np. salda pośrednie) są pomijane.
                if inDescription { flush() }
            } else if inDescription {
                // Kontynuacja wielolinijkowego pola :86:.
                pendingDescription += "\n" + line
            }
        }
        flush()
        return transactions
    }

    /// Dekoduje dane pliku wyciągu — polskie banki zapisują MT940 w UTF-8,
    /// Windows-1250 albo ISO Latin-2.
    public static func decode(_ data: Data) -> String {
        for encoding in [String.Encoding.utf8, .windowsCP1250, .isoLatin2] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Pole :61: — `RRMMDD[MMDD](C|D|RC|RD)[kod]kwota,grosze...`.
    static func parseStatementLine(_ content: String) -> (Date, Double)? {
        let pattern = #"^(\d{6})(\d{4})?(R?[CD])([A-Z])?(\d+,\d{0,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: content,
                  range: NSRange(content.startIndex..., in: content)
              ) else { return nil }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: content) else { return nil }
            return String(content[range])
        }
        guard let dateText = group(1),
              let sideText = group(3),
              let amountText = group(5) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.timeZone = TimeZone(identifier: "Europe/Warsaw")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateText) else { return nil }

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        // C/RC = uznanie (wpływ), D/RD = obciążenie (wypływ). „R” oznacza
        // storno — odwraca stronę operacji.
        let isCredit = sideText.hasSuffix("C")
        let isReversal = sideText.hasPrefix("R")
        let sign: Double = (isCredit != isReversal) ? 1 : -1
        return (date, sign * amount)
    }

    /// Rozbiór pola :86: — podpola `~NN` wg konwencji polskich banków.
    static func parseDescription(_ description: String) -> (title: String, counterparty: String) {
        let flattened = description
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard flattened.contains("~") else {
            let plain = flattened.trimmingCharacters(in: .whitespaces)
            return (plain, "")
        }

        var fields: [String: String] = [:]
        // Segmenty zaczynają się od ~ i dwucyfrowego kodu.
        let parts = flattened.components(separatedBy: "~").dropFirst()
        for part in parts where part.count >= 2 {
            let code = String(part.prefix(2))
            let value = String(part.dropFirst(2))
            fields[code, default: ""] += value
        }
        let title = (20...25)
            .compactMap { fields[String($0)] }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let counterparty = ["32", "33"]
            .compactMap { fields[$0] }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? flattened.trimmingCharacters(in: .whitespaces) : title, counterparty)
    }
}
