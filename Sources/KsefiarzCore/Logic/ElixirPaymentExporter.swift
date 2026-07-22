import Foundation

/// Eksport zobowiązań zakupowych do płaskiego formatu Elixir-O używanego
/// przez polską bankowość elektroniczną do importu paczek przelewów.
///
/// Generator tworzy po jednym 16-polowym rekordzie na przelew, bez nagłówka
/// i stopki, z zakończeniem wierszy CRLF. Nie zapisuje pliku ani nie zmienia
/// statusu faktury — te odpowiedzialności pozostają w warstwie widoku.
public enum ElixirPaymentExporter {

    public static let maxTextLineLength = 35
    public static let maxTextLines = 4
    public static let bankAccountLength = 26
    public static let maxAmountInCents: Int64 = 999_999_999_999_999
    /// Pole VAT komunikatu MPP dopuszcza najwyżej 10 cyfr części całkowitej.
    public static let maxSplitPaymentVAT = 9_999_999_999.99
    /// Wspólny bezpieczny limit — mBank przyjmuje maksymalnie 50 dyspozycji
    /// w jednym pliku (inne systemy bankowe mogą dopuszczać więcej).
    public static let maxTransfersPerFile = 50
    private static let paymentTolerance = 0.005

    /// Kodowanie wybierane przy zapisie. Banki obsługują różne podzbiory:
    /// UTF-8 i Windows-1250 są popularne, a ISO-8859-2 jest wymagane m.in.
    /// przez część systemów korporacyjnych.
    public enum TextEncoding: String, CaseIterable, Identifiable, Sendable {
        case utf8
        case windows1250
        case isoLatin2

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .utf8: return "UTF-8"
            case .windows1250: return "Windows-1250"
            case .isoLatin2: return "ISO-8859-2 (Latin-2)"
            }
        }

        fileprivate var foundationEncoding: String.Encoding {
            switch self {
            case .utf8: return .utf8
            case .windows1250: return .windowsCP1250
            case .isoLatin2: return .isoLatin2
            }
        }
    }

    /// Pojedynczy przelew przygotowany z faktury. Typ wartościowy pozwala
    /// widokowi zmienić kwotę VAT MPP bez modyfikowania dokumentu źródłowego.
    public struct Transfer: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let invoiceNumber: String
        public let recipientName: String
        public let recipientAddress: String
        public let recipientNIP: String
        public let recipientAccount: String
        public let amount: Double
        public var vatAmount: Double?
        public let usesSplitPayment: Bool

        public init(
            id: UUID,
            invoiceNumber: String,
            recipientName: String,
            recipientAddress: String,
            recipientNIP: String,
            recipientAccount: String,
            amount: Double,
            vatAmount: Double?,
            usesSplitPayment: Bool
        ) {
            self.id = id
            self.invoiceNumber = invoiceNumber
            self.recipientName = recipientName
            self.recipientAddress = recipientAddress
            self.recipientNIP = recipientNIP
            self.recipientAccount = recipientAccount
            self.amount = amount
            self.vatAmount = vatAmount
            self.usesSplitPayment = usesSplitPayment
        }
    }

    /// Faktura pominięta podczas przygotowania wraz z jawną przyczyną.
    public struct Rejection: Identifiable, Equatable, Sendable {
        public let invoiceID: UUID
        public let invoiceNumber: String
        public let reason: String

        public var id: UUID { invoiceID }
    }

    public struct Preparation: Equatable, Sendable {
        public let transfers: [Transfer]
        public let rejections: [Rejection]
    }

    public struct Options: Sendable {
        public let sourceAccount: String
        public let sourceName: String
        public let sourceAddress: String
        public let executionDate: Date
        public let encoding: TextEncoding

        public init(
            sourceAccount: String,
            sourceName: String,
            sourceAddress: String,
            executionDate: Date,
            encoding: TextEncoding
        ) {
            self.sourceAccount = sourceAccount
            self.sourceName = sourceName
            self.sourceAddress = sourceAddress
            self.executionDate = executionDate
            self.encoding = encoding
        }
    }

    public enum ExportError: LocalizedError, Equatable {
        case noTransfers
        case tooManyTransfers(Int)
        case invalidSourceAccount
        case missingSourceName
        case executionDateInPast
        case invalidTransfer(invoiceNumber: String, reason: String)
        case unsupportedEncoding(String)

        public var errorDescription: String? {
            switch self {
            case .noTransfers:
                return "Wybierz co najmniej jeden poprawny przelew."
            case let .tooManyTransfers(count):
                return "Plik zawiera \(count) przelewów. Dla zgodności z bankami zapisz maksymalnie \(maxTransfersPerFile) dyspozycji w jednej paczce."
            case .invalidSourceAccount:
                return "Rachunek zleceniodawcy musi być poprawnym 26-cyfrowym NRB (z prawidłową sumą kontrolną)."
            case .missingSourceName:
                return "Uzupełnij nazwę firmy zleceniodawcy w Ustawieniach."
            case .executionDateInPast:
                return "Data realizacji przelewu nie może być wcześniejsza niż dzisiaj."
            case let .invalidTransfer(number, reason):
                return "Nie można wyeksportować faktury \(number): \(reason)"
            case let .unsupportedEncoding(name):
                return "Danych nie można zapisać w kodowaniu \(name). Wybierz inne kodowanie."
            }
        }
    }

    /// Buduje listę przelewów możliwych do wyeksportowania i osobną listę
    /// odrzuceń. Do paczki trafiają wyłącznie widoczne, nieopłacone zakupy
    /// krajowe w PLN z poprawnym rachunkiem sprzedawcy.
    @MainActor
    public static func prepare(invoices: [Invoice]) -> Preparation {
        var transfers: [Transfer] = []
        var rejections: [Rejection] = []

        for invoice in invoices {
            let reason: String?
            let account = normalizedNRB(invoice.paymentBankAccount ?? "")
            let recipientNIP = normalizedNIP(invoice.sellerNIP)
            let amount = invoice.outstandingAmount

            if invoice.kind != .purchase {
                reason = "eksport obejmuje wyłącznie faktury zakupowe"
            } else if invoice.isArchivedOrHidden {
                reason = "faktura jest ukryta"
            } else if invoice.isPaid || amount <= paymentTolerance {
                reason = "faktura nie ma salda do zapłaty"
            } else if !CurrencyCode.isPLN(invoice.currency) {
                reason = "Elixir-O obsługuje tu wyłącznie przelewy krajowe w PLN"
            } else if !isValidNRB(account) {
                reason = "brak poprawnego rachunku NRB sprzedawcy"
            } else if sanitizedText(invoice.sellerName).isEmpty {
                reason = "brak nazwy odbiorcy"
            } else if cents(from: amount) == nil {
                reason = "kwota salda jest nieprawidłowa albo przekracza limit formatu"
            } else if invoice.splitPayment && !InvoiceValidator.isValidNIP(recipientNIP) {
                reason = "MPP wymaga poprawnego NIP sprzedawcy"
            } else {
                reason = nil
            }

            if let reason {
                rejections.append(.init(
                    invoiceID: invoice.id,
                    invoiceNumber: invoice.invoiceNumber,
                    reason: reason
                ))
                continue
            }

            let vatAmount: Double?
            if invoice.splitPayment {
                // Przy płatności częściowej podpowiadamy proporcjonalną część
                // VAT. Widok pozwala użytkownikowi skorygować ją przed zapisem.
                let ratio = invoice.grossAmount > paymentTolerance
                    ? min(1, amount / invoice.grossAmount)
                    : 0
                let proportionalVAT = min(amount, max(0, invoice.vatAmount * ratio))
                vatAmount = roundedCurrency(proportionalVAT)
            } else {
                vatAmount = nil
            }

            transfers.append(.init(
                id: invoice.id,
                invoiceNumber: invoice.invoiceNumber,
                recipientName: invoice.sellerName,
                recipientAddress: invoice.sellerAddress,
                recipientNIP: recipientNIP,
                recipientAccount: account,
                amount: amount,
                vatAmount: vatAmount,
                usesSplitPayment: invoice.splitPayment
            ))
        }

        return Preparation(transfers: transfers, rejections: rejections)
    }

    /// Generuje gotowe bajty pliku. `today` jest parametrem wyłącznie po to,
    /// by walidacja daty była deterministyczna w testach.
    public static func data(
        for transfers: [Transfer],
        options: Options,
        today: Date = .now,
        calendar: Calendar = .current
    ) throws -> Data {
        guard !transfers.isEmpty else { throw ExportError.noTransfers }
        guard transfers.count <= maxTransfersPerFile else {
            throw ExportError.tooManyTransfers(transfers.count)
        }

        let sourceAccount = normalizedNRB(options.sourceAccount)
        guard isValidNRB(sourceAccount) else { throw ExportError.invalidSourceAccount }
        guard !sanitizedText(options.sourceName).isEmpty else { throw ExportError.missingSourceName }
        guard calendar.startOfDay(for: options.executionDate) >= calendar.startOfDay(for: today) else {
            throw ExportError.executionDateInPast
        }

        let executionDate = dateField(options.executionDate, calendar: calendar)
        let sourceBank = bankRoutingNumber(from: sourceAccount)
        let sourceDescription = partyDescription(name: options.sourceName, address: options.sourceAddress)

        var records: [String] = []
        for transfer in transfers {
            let recipientAccount = normalizedNRB(transfer.recipientAccount)
            guard isValidNRB(recipientAccount) else {
                throw ExportError.invalidTransfer(
                    invoiceNumber: transfer.invoiceNumber,
                    reason: "niepoprawny rachunek NRB odbiorcy"
                )
            }
            guard let amount = cents(from: transfer.amount) else {
                throw ExportError.invalidTransfer(
                    invoiceNumber: transfer.invoiceNumber,
                    reason: "niepoprawna kwota przelewu"
                )
            }

            let recipientDescription = partyDescription(
                name: transfer.recipientName,
                address: transfer.recipientAddress
            )
            guard !recipientDescription.isEmpty else {
                throw ExportError.invalidTransfer(
                    invoiceNumber: transfer.invoiceNumber,
                    reason: "brak nazwy odbiorcy"
                )
            }

            let details: String
            let documentCode: String
            if transfer.usesSplitPayment {
                let recipientNIP = normalizedNIP(transfer.recipientNIP)
                guard InvoiceValidator.isValidNIP(recipientNIP) else {
                    throw ExportError.invalidTransfer(
                        invoiceNumber: transfer.invoiceNumber,
                        reason: "MPP wymaga poprawnego NIP odbiorcy"
                    )
                }
                guard let vat = transfer.vatAmount,
                      vat > 0,
                      vat <= maxSplitPaymentVAT,
                      vat <= transfer.amount + paymentTolerance,
                      cents(from: vat) != nil else {
                    throw ExportError.invalidTransfer(
                        invoiceNumber: transfer.invoiceNumber,
                        reason: "kwota VAT MPP musi być dodatnia, nie większa od przelewu i mieścić się w limicie 10 cyfr"
                    )
                }
                details = splitPaymentDetails(
                    vatAmount: vat,
                    recipientNIP: recipientNIP,
                    invoiceNumber: transfer.invoiceNumber
                )
                documentCode = "53"
            } else {
                details = wrappedText(transfer.invoiceNumber, maximumLines: maxTextLines)
                guard !details.isEmpty else {
                    throw ExportError.invalidTransfer(
                        invoiceNumber: transfer.invoiceNumber,
                        reason: "brak tytułu przelewu"
                    )
                }
                documentCode = "51"
            }

            let fields = [
                "110",
                executionDate,
                amount,
                sourceBank,
                "0",
                quoted(sourceAccount),
                quoted(recipientAccount),
                quoted(sourceDescription),
                quoted(recipientDescription),
                "0",
                bankRoutingNumber(from: recipientAccount),
                quoted(details),
                quoted(""),
                quoted(""),
                quoted(documentCode),
                quoted(""),
            ]
            records.append(fields.joined(separator: ","))
        }

        let text = records.joined(separator: "\r\n") + "\r\n"
        guard let data = text.data(
            using: options.encoding.foundationEncoding,
            allowLossyConversion: false
        ) else {
            throw ExportError.unsupportedEncoding(options.encoding.displayName)
        }
        return data
    }

    // MARK: - Walidacja NRB

    /// Normalizuje polski IBAN/NRB. Akceptuje opcjonalny prefiks `PL`, spacje
    /// i myślniki; każdy inny znak unieważnia wartość.
    public static func normalizedNRB(_ value: String) -> String {
        let digits = Set("0123456789")
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("PL") { text.removeFirst(2) }
        guard text.allSatisfy({ digits.contains($0) || $0.isWhitespace || $0 == "-" }) else {
            return ""
        }
        return String(text.filter { digits.contains($0) })
    }

    /// Sprawdza długość i sumę kontrolną NRB (IBAN modulo 97 dla kraju PL).
    public static func isValidNRB(_ value: String) -> Bool {
        let account = normalizedNRB(value)
        guard account.count == bankAccountLength else { return false }
        let rearranged = String(account.dropFirst(2)) + "2521" + String(account.prefix(2))
        var remainder = 0
        for character in rearranged {
            guard let digit = character.wholeNumberValue else { return false }
            remainder = (remainder * 10 + digit) % 97
        }
        return remainder == 1
    }

    /// Ośmiocyfrowy numer rozliczeniowy banku zapisany w NRB.
    public static func bankRoutingNumber(from account: String) -> String {
        let normalized = normalizedNRB(account)
        guard normalized.count == bankAccountLength else { return "" }
        return String(normalized.dropFirst(2).prefix(8))
    }

    /// NIP MPP w Elixir musi mieć dokładnie 10 cyfr. Akceptujemy zapis
    /// użytkowy z prefiksem `PL`, spacjami lub myślnikami.
    private static func normalizedNIP(_ value: String) -> String {
        let digits = Set("0123456789")
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("PL") { text.removeFirst(2) }
        guard text.allSatisfy({ digits.contains($0) || $0.isWhitespace || $0 == "-" }) else {
            return ""
        }
        let normalized = String(text.filter { digits.contains($0) })
        return normalized.count == 10 ? normalized : ""
    }

    // MARK: - Pola rekordu

    private static func cents(from amount: Double) -> String? {
        guard amount.isFinite, amount > 0 else { return nil }
        let rounded = (amount * 100).rounded(.toNearestOrAwayFromZero)
        guard rounded.isFinite,
              rounded > 0,
              rounded <= Double(maxAmountInCents) else { return nil }
        return String(Int64(rounded))
    }

    private static func roundedCurrency(_ amount: Double) -> Double {
        (amount * 100).rounded(.toNearestOrAwayFromZero) / 100
    }

    private static func dateField(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func partyDescription(name: String, address: String) -> String {
        let nameLines = textLines(name, maximumLines: 2)
        guard !nameLines.isEmpty else { return "" }
        let addressLines = textLines(address, maximumLines: 2)
        return (nameLines + addressLines).joined(separator: "|")
    }

    private static func splitPaymentDetails(
        vatAmount: Double,
        recipientNIP: String,
        invoiceNumber: String
    ) -> String {
        let vat = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            roundedCurrency(vatAmount)
        ).replacingOccurrences(of: ".", with: ",")
        let nip = recipientNIP.filter(\.isNumber)
        let invoice = String(sanitizedText(invoiceNumber).prefix(maxTextLineLength))
        let raw = "/VAT/\(vat)/IDC/\(nip)/INV/\(invoice)"
        return structuredLines(raw).joined(separator: "|")
    }

    private static func wrappedText(_ value: String, maximumLines: Int) -> String {
        textLines(value, maximumLines: maximumLines).joined(separator: "|")
    }

    /// Łamie zwykły tekst na wiersze po 35 znaków, preferując granice słów.
    private static func textLines(_ value: String, maximumLines: Int) -> [String] {
        var remaining = sanitizedText(value)
        var result: [String] = []

        while !remaining.isEmpty && result.count < maximumLines {
            if remaining.count <= maxTextLineLength {
                result.append(remaining)
                break
            }

            let hardPrefix = String(remaining.prefix(maxTextLineLength))
            let cut: Int
            if let space = hardPrefix.lastIndex(of: " ") {
                let distance = hardPrefix.distance(from: hardPrefix.startIndex, to: space)
                cut = distance >= maxTextLineLength / 2 ? distance : maxTextLineLength
            } else {
                cut = maxTextLineLength
            }
            result.append(String(remaining.prefix(cut)).trimmingCharacters(in: .whitespaces))
            remaining = String(remaining.dropFirst(cut)).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// Komunikatu MPP nie wolno przeciąć wewnątrz znacznika `/VAT/`,
    /// `/IDC/` ani `/INV/`. Wartości mogą przechodzić do kolejnego wiersza.
    private static func structuredLines(_ value: String) -> [String] {
        let markers = ["/VAT/", "/IDC/", "/INV/", "/TXT/"]
        var remaining = value
        var result: [String] = []

        while remaining.count > maxTextLineLength && result.count < maxTextLines - 1 {
            var cut = maxTextLineLength
            let prefix = String(remaining.prefix(cut))
            for marker in markers {
                for length in 1..<marker.count where prefix.hasSuffix(String(marker.prefix(length))) {
                    cut = min(cut, maxTextLineLength - length)
                }
            }
            result.append(String(remaining.prefix(cut)))
            remaining = String(remaining.dropFirst(cut))
        }
        if !remaining.isEmpty {
            result.append(String(remaining.prefix(maxTextLineLength)))
        }
        return result
    }

    /// Zestaw znaków przyjmowany przez bankowe warianty Elixir. Separatory
    /// struktury (`|`, cudzysłów, CR/LF) są zamieniane na pojedynczą spację.
    private static func sanitizedText(_ value: String) -> String {
        let allowed = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
                + "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ?-:().' +/"
        )
        var result = ""
        var previousWasSpace = true
        for character in value.precomposedStringWithCanonicalMapping {
            if allowed.contains(character) {
                if character == " " {
                    guard !previousWasSpace else { continue }
                    previousWasSpace = true
                } else {
                    previousWasSpace = false
                }
                result.append(character)
            } else if !previousWasSpace {
                result.append(" ")
                previousWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func quoted(_ value: String) -> String { "\"\(value)\"" }
}
