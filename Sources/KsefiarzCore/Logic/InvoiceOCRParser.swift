import Foundation

/// Pola faktury rozpoznane z tekstu OCR skanu/PDF — wszystkie opcjonalne
/// (`nil` = nie rozpoznano; pole formularza pozostaje nietknięte).
/// OCR jest heurystyczny: wynik zawsze wymaga weryfikacji użytkownika.
public struct InvoiceOCRExtraction: Equatable, Sendable {
    public var documentNumber: String?
    public var issueDate: Date?
    public var saleDate: Date?
    public var sellerName: String?
    /// Polski NIP (10 cyfr, poprawna suma kontrolna) albo zagraniczny
    /// identyfikator VAT z prefiksem kraju UE (np. "DE123456789").
    public var sellerTaxID: String?
    public var sellerAddress: String?
    public var netAmount: Double?
    public var vatAmount: Double?
    public var grossAmount: Double?
    public var currency: String?
    /// Rachunek sprzedawcy (26-cyfrowy NRB z poprawną sumą kontrolną).
    public var bankAccount: String?
    public var paymentDueDate: Date?
    public var paymentForm: PaymentForm?

    public init(
        documentNumber: String? = nil,
        issueDate: Date? = nil,
        saleDate: Date? = nil,
        sellerName: String? = nil,
        sellerTaxID: String? = nil,
        sellerAddress: String? = nil,
        netAmount: Double? = nil,
        vatAmount: Double? = nil,
        grossAmount: Double? = nil,
        currency: String? = nil,
        bankAccount: String? = nil,
        paymentDueDate: Date? = nil,
        paymentForm: PaymentForm? = nil
    ) {
        self.documentNumber = documentNumber
        self.issueDate = issueDate
        self.saleDate = saleDate
        self.sellerName = sellerName
        self.sellerTaxID = sellerTaxID
        self.sellerAddress = sellerAddress
        self.netAmount = netAmount
        self.vatAmount = vatAmount
        self.grossAmount = grossAmount
        self.currency = currency
        self.bankAccount = bankAccount
        self.paymentDueDate = paymentDueDate
        self.paymentForm = paymentForm
    }

    /// Nic nie rozpoznano.
    public var isEmpty: Bool {
        self == InvoiceOCRExtraction()
    }

    /// Kwoty netto i VAT wyprowadzone z rozpoznanych wartości.
    /// Etykietowana para netto+VAT jest najbardziej wiarygodna — „do
    /// zapłaty" bywa saldem po częściowej wpłacie, nie kwotą brutto,
    /// więc przy komplecie kwot brutto nie nadpisuje pary. Gdy znana jest
    /// jedna kwota z pary, druga wynika z równania netto + VAT = brutto;
    /// ujemny wynik odejmowania (brutto = saldo) nie jest ufany.
    /// Samo brutto (np. paragon) trafia w całości do netto z VAT = 0.
    public func resolvedAmounts() -> (net: Double, vat: Double)? {
        func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        switch (netAmount, vatAmount, grossAmount) {
        case let (net?, vat?, _):
            return (rounded(net), rounded(vat))
        case let (net?, nil, gross?):
            let vat = gross - net
            return (rounded(net), vat >= 0 ? rounded(vat) : 0)
        case let (nil, vat?, gross?):
            let net = gross - vat
            return net >= 0 ? (rounded(net), rounded(vat)) : (rounded(gross), 0)
        case let (net?, nil, nil):
            return (rounded(net), 0)
        case let (nil, nil, gross?):
            return (rounded(gross), 0)
        default:
            return nil
        }
    }

    /// Nanosi rozpoznane pola na szkic zakupu — tylko pola, które udało się
    /// rozpoznać; pozostałe (w tym dane nabywcy, status opłacenia, uwagi,
    /// kategoria i kurs) zostają bez zmian.
    public func applied(to draft: ManualPurchaseDraft) -> ManualPurchaseDraft {
        var result = draft
        if let documentNumber { result.documentNumber = documentNumber }
        if let issueDate { result.issueDate = issueDate }
        if let saleDate { result.saleDate = saleDate }
        if let sellerName { result.sellerName = sellerName }
        if let sellerTaxID { result.sellerTaxID = sellerTaxID }
        if let sellerAddress { result.sellerAddress = sellerAddress }
        if let amounts = resolvedAmounts(), !keepsExistingSplit(of: draft) {
            result.netAmount = amounts.net
            result.vatAmount = amounts.vat
        }
        if let currency { result.currency = currency }
        if let bankAccount { result.paymentBankAccount = bankAccount }
        if let paymentDueDate { result.paymentDueDate = paymentDueDate }
        if let paymentForm { result.paymentForm = paymentForm }
        return result
    }

    /// Rozpoznane samo brutto zgodne z brutto edytowanego szkicu nie może
    /// zniszczyć istniejącego podziału netto/VAT (zerując VAT).
    private func keepsExistingSplit(of draft: ManualPurchaseDraft) -> Bool {
        guard netAmount == nil, vatAmount == nil, let gross = grossAmount else { return false }
        return abs(draft.grossAmount) > 0.005 && abs(draft.grossAmount - gross) <= 0.01
    }

    /// Polskie nazwy rozpoznanych pól — do komunikatu w formularzu.
    public var recognizedFieldNames: [String] {
        var names: [String] = []
        if documentNumber != nil { names.append("numer dokumentu") }
        if issueDate != nil { names.append("data wystawienia") }
        if saleDate != nil { names.append("data sprzedaży") }
        if sellerName != nil { names.append("nazwa sprzedawcy") }
        if sellerTaxID != nil { names.append("NIP/VAT ID sprzedawcy") }
        if sellerAddress != nil { names.append("adres sprzedawcy") }
        if netAmount != nil || vatAmount != nil || grossAmount != nil { names.append("kwoty") }
        if currency != nil { names.append("waluta") }
        if bankAccount != nil { names.append("numer rachunku") }
        if paymentDueDate != nil { names.append("termin płatności") }
        if paymentForm != nil { names.append("forma płatności") }
        return names
    }
}

/// Czysta logika wyciągania pól polskiej faktury z linii tekstu
/// rozpoznanych przez OCR (albo z warstwy tekstowej PDF).
/// Heurystyki po etykietach ("Sprzedawca", "Data wystawienia",
/// "Do zapłaty" itd.) z tolerancją na brak polskich znaków —
/// OCR często gubi diakrytyki.
public enum InvoiceOCRParser {

    /// Parsuje tekst rozpoznany ze skanu faktury.
    /// - Parameters:
    ///   - lines: linie tekstu w kolejności czytania,
    ///   - ownNIP: NIP firmy użytkownika (nabywcy) — pomijany przy
    ///     wyborze NIP sprzedawcy.
    public static func parse(lines rawLines: [String], ownNIP: String? = nil) -> InvoiceOCRExtraction {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return InvoiceOCRExtraction() }
        let folded = lines.map(normalized)

        var extraction = InvoiceOCRExtraction()
        extraction.documentNumber = documentNumber(lines: lines, folded: folded)
        parseDates(into: &extraction, lines: lines, folded: folded)
        parseSeller(into: &extraction, lines: lines, folded: folded, ownNIP: ownNIP)
        parseAmounts(into: &extraction, lines: lines, folded: folded)
        extraction.currency = currency(lines: lines)
        extraction.bankAccount = bankAccount(lines: lines, folded: folded)
        extraction.paymentForm = paymentForm(lines: lines, folded: folded)
        return extraction
    }

    /// Wygodny wariant dla tekstu z warstwy tekstowej PDF.
    public static func parse(text: String, ownNIP: String? = nil) -> InvoiceOCRExtraction {
        parse(lines: text.components(separatedBy: .newlines), ownNIP: ownNIP)
    }

    // MARK: - Normalizacja

    /// Małe litery bez polskich znaków — dopasowanie etykiet niezależne od
    /// diakrytyków ("płatności" == "platnosci"). `ł` nie jest znakiem
    /// składanym, więc wymaga jawnej zamiany przed foldingiem.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
    }

    /// Tekst oryginalnej linii następujący po etykiecie znalezionej w wersji
    /// znormalizowanej (folding zachowuje liczbę znaków dla polskich liter).
    private static func value(after label: String, inFolded foldedLine: String, original: String) -> String? {
        guard let range = foldedLine.range(of: label) else { return nil }
        let offset = foldedLine.distance(from: foldedLine.startIndex, to: range.upperBound)
        guard offset <= original.count else { return nil }
        let start = original.index(original.startIndex, offsetBy: offset)
        // Separator etykiety (dwukropek/kropka/myślnik) tylko z początku —
        // końcówka wartości może być znacząca ("Sp. z o.o.").
        var tail = Substring(original[start...])
        let separators = CharacterSet(charactersIn: " :.-\t")
        while let first = tail.first, first.unicodeScalars.allSatisfy(separators.contains) {
            tail = tail.dropFirst()
        }
        let value = tail.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - Numer dokumentu

    private static let numberLabels = ["numer faktury", "nr faktury", "numer dokumentu", "nr dokumentu", "numer paragonu", "nr paragonu"]
    private static let numberHeaderRegex = try? NSRegularExpression(pattern: #"(nr\.?|numer)[:\s]"#)

    private static func documentNumber(lines: [String], folded: [String]) -> String? {
        // 1. "Faktura (VAT) nr <numer>" — najczęstszy nagłówek. „Rachunek”
        //    bywa dokumentem sprzedaży, ale „rachunek bankowy nr …”
        //    to numer konta, nie dokumentu.
        for (idx, fold) in folded.enumerated() {
            guard fold.contains("faktura") || fold.contains("paragon")
                || (fold.contains("rachunek") && !fold.contains("bankow") && !fold.contains("konto")) else { continue }
            guard let regex = numberHeaderRegex else { break }
            let foldNS = fold as NSString
            guard let match = regex.firstMatch(in: fold, range: NSRange(location: 0, length: foldNS.length)),
                  let matchRange = Range(match.range, in: fold) else { continue }
            let labelEnd = fold.distance(from: fold.startIndex, to: matchRange.upperBound)
            let original = lines[idx]
            guard labelEnd <= original.count else { continue }
            let tail = String(original[original.index(original.startIndex, offsetBy: labelEnd)...])
            if let number = numberToken(from: tail) { return number }
            // Etykieta na końcu linii — numer w linii następnej.
            if idx + 1 < lines.count, let number = numberToken(from: lines[idx + 1]) { return number }
        }
        // 2. Etykieta "Numer faktury:" z wartością w tej samej albo następnej linii.
        for (idx, fold) in folded.enumerated() {
            for label in numberLabels where fold.contains(label) {
                if let tail = value(after: label, inFolded: fold, original: lines[idx]),
                   let number = numberToken(from: tail) {
                    return number
                }
                if idx + 1 < lines.count, let number = numberToken(from: lines[idx + 1]) {
                    return number
                }
            }
        }
        // 3. Nagłówek "Faktura VAT FV/07/2026" — numer bez słowa "nr".
        for (idx, fold) in folded.enumerated() where fold.hasPrefix("faktura") {
            var tail = lines[idx]
            for prefix in ["faktura", "vat", "koryguj", "zaliczkow", "koncow"] {
                guard normalized(tail).hasPrefix(prefix) else { continue }
                // Usuwa całe pierwsze słowo ("Faktura", "korygująca", ...) —
                // do pierwszej spacji; bez spacji linia jest samą etykietą.
                if let space = tail.firstIndex(of: " ") {
                    tail = String(tail[tail.index(after: space)...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    tail = ""
                }
            }
            if let number = numberToken(from: tail) { return number }
        }
        return nil
    }

    private static let numberTokenRegex = try? NSRegularExpression(pattern: #"^[A-Za-z0-9/\-\._#]+$"#)
    /// Cała-datowe tokeny z kropkami/myślnikami — to daty, nie numery.
    /// Zapis z ukośnikami ("1/07/2026") jest typowym polskim numerem
    /// faktury (nr/miesiąc/rok), więc NIE jest odrzucany.
    private static let dottedDateTokenRegex = try? NSRegularExpression(
        pattern: #"^(\d{1,2}[.-]\d{1,2}[.-]\d{4}|\d{4}-\d{2}-\d{2})$"#
    )

    /// Wyciąga numer dokumentu z tekstu: słowa z dozwolonego zestawu znaków
    /// do pierwszego słowa-daty albo spójnika ("z dnia ..."). Numer musi
    /// zawierać cyfrę; czysta data nie jest numerem.
    static func numberToken(from text: String) -> String? {
        let stopWords: Set<String> = ["z", "dnia", "data", "wystawienia", "wystawiona", "wystawiono", "oryginal", "oryginał", "kopia", "duplikat"]
        var tokens: [String] = []
        for word in text.split(separator: " ") {
            let token = String(word).trimmingCharacters(in: CharacterSet(charactersIn: ":,;"))
            if stopWords.contains(normalized(token)) { break }
            guard matches(numberTokenRegex, token) else { break }
            if matches(dottedDateTokenRegex, token) { break } // data zamiast numeru
            tokens.append(token)
            if tokens.count >= 3 { break }
        }
        let joined = tokens.joined(separator: " ")
        guard joined.contains(where: \.isNumber), joined.count <= 40 else { return nil }
        return joined
    }

    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: - Daty

    private static let issueLabels = ["data wystawienia", "wystawiono dnia", "wystawiona dnia", "data faktury"]
    private static let saleLabels = ["data sprzedazy", "data dostawy", "data wykonania", "data zakonczenia dostawy"]
    private static let dueLabels = ["termin platnosci", "termin zaplaty", "platne do", "zaplata do", "data platnosci"]
    /// Słowa sugerujące, że data w linii NIE jest datą wystawienia
    /// (termin/zapłata) — używane przez fallback jedynej daty.
    private static let nonIssueDateHints = ["termin", "platnos", "zaplat", "do dnia"]

    private static func parseDates(into extraction: inout InvoiceOCRExtraction, lines: [String], folded: [String]) {
        extraction.issueDate = labeledDate(labels: issueLabels, lines: lines, folded: folded)
        extraction.saleDate = labeledDate(labels: saleLabels, lines: lines, folded: folded)
        extraction.paymentDueDate = labeledDate(labels: dueLabels, lines: lines, folded: folded)

        // Bez etykiety: jedyna data w dokumencie to niemal na pewno
        // data wystawienia (np. "Kraków, 12.03.2026") — o ile nie została
        // już rozpoznana jako inna data i nie stoi przy słowach
        // sugerujących termin/zapłatę.
        if extraction.issueDate == nil {
            let consumed = Set([extraction.saleDate, extraction.paymentDueDate].compactMap { $0 })
            var candidates: Set<Date> = []
            for (idx, line) in lines.enumerated() {
                guard let found = date(in: line), !consumed.contains(found) else { continue }
                guard !nonIssueDateHints.contains(where: { folded[idx].contains($0) }) else { continue }
                candidates.insert(found)
            }
            if candidates.count == 1 { extraction.issueDate = candidates.first }
        }
    }

    private static func labeledDate(labels: [String], lines: [String], folded: [String]) -> Date? {
        for (idx, fold) in folded.enumerated() {
            for label in labels where fold.contains(label) {
                if let tail = value(after: label, inFolded: fold, original: lines[idx]),
                   let found = date(in: tail) {
                    return found
                }
                // Etykieta i wartość w osobnych liniach (układ kolumnowy).
                if idx + 1 < lines.count, let found = date(in: lines[idx + 1]) {
                    return found
                }
            }
        }
        return nil
    }

    /// Wzorce dat: numeryczne z kolejnością grup (dzień, miesiąc, rok).
    private static let numericDateRegexes: [(regex: NSRegularExpression, order: (day: Int, month: Int, year: Int))] = {
        var result: [(regex: NSRegularExpression, order: (day: Int, month: Int, year: Int))] = []
        if let dmy = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?!\d)"#) {
            result.append((regex: dmy, order: (day: 1, month: 2, year: 3)))
        }
        if let ymd = try? NSRegularExpression(pattern: #"(?<!\d)(\d{4})[./-](\d{1,2})[./-](\d{1,2})(?!\d)"#) {
            result.append((regex: ymd, order: (day: 3, month: 2, year: 1)))
        }
        return result
    }()
    private static let wordDateRegex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})\s+([a-z]+)\s+(\d{4})(?!\d)"#)

    /// Pierwsza data w tekście: `dd.MM.yyyy` (kropki/myślniki/ukośniki),
    /// `yyyy-MM-dd` albo słownie "12 czerwca 2026".
    static func date(in text: String) -> Date? {
        let ns = text as NSString
        for (regex, order) in numericDateRegexes {
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            var day = Int(ns.substring(with: match.range(at: order.day))) ?? 0
            var month = Int(ns.substring(with: match.range(at: order.month))) ?? 0
            let year = Int(ns.substring(with: match.range(at: order.year))) ?? 0
            if month > 12, day <= 12 { swap(&day, &month) } // zapis amerykański
            if let date = makeDate(year: year, month: month, day: day) { return date }
        }
        // "12 czerwca 2026"
        let foldedText = normalized(text)
        let foldedNS = foldedText as NSString
        if let regex = wordDateRegex,
           let match = regex.firstMatch(in: foldedText, range: NSRange(location: 0, length: foldedNS.length)) {
            let day = Int(foldedNS.substring(with: match.range(at: 1))) ?? 0
            let monthWord = foldedNS.substring(with: match.range(at: 2))
            let year = Int(foldedNS.substring(with: match.range(at: 3))) ?? 0
            if let month = polishMonth(from: monthWord),
               let date = makeDate(year: year, month: month, day: day) {
                return date
            }
        }
        return nil
    }

    private static func polishMonth(from word: String) -> Int? {
        let prefixes: [(String, Int)] = [
            ("styczn", 1), ("lut", 2), ("mar", 3), ("kwie", 4), ("maj", 5), ("czerw", 6),
            ("lip", 7), ("sierp", 8), ("wrzes", 9), ("pazdzier", 10), ("listopad", 11), ("grud", 12),
        ]
        return prefixes.first { word.hasPrefix($0.0) }?.1
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (2000...2099).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil } // odrzuca np. 31.02
        return date
    }

    // MARK: - Sprzedawca

    private static let sellerLabels = ["sprzedawca", "wystawca", "dostawca"]
    private static let buyerLabels = ["nabywca", "kupujacy", "odbiorca"]

    private static func parseSeller(into extraction: inout InvoiceOCRExtraction, lines: [String], folded: [String], ownNIP: String?) {
        let sellerLabelIdx = folded.firstIndex { fold in sellerLabels.contains { fold.hasPrefix($0) } }
        let buyerLabelIdx = folded.firstIndex { fold in buyerLabels.contains { fold.hasPrefix($0) } }
        extraction.sellerTaxID = sellerTaxID(
            lines: lines, folded: folded, ownNIP: ownNIP,
            sellerLabelIdx: sellerLabelIdx, buyerLabelIdx: buyerLabelIdx
        )

        guard let labelIdx = sellerLabelIdx else { return }
        // Nazwa: reszta linii etykiety albo pierwsza sensowna linia poniżej.
        var nameIdx: Int?
        if let inline = value(after: sellerLabels.first(where: { folded[labelIdx].hasPrefix($0) }) ?? "", inFolded: folded[labelIdx], original: lines[labelIdx]),
           isPlausibleName(inline) {
            extraction.sellerName = inline
            nameIdx = labelIdx
        } else {
            for idx in (labelIdx + 1)..<min(labelIdx + 3, lines.count) where isPlausibleName(lines[idx]) {
                extraction.sellerName = lines[idx]
                nameIdx = idx
                break
            }
        }
        // Adres: do dwóch linii pod nazwą wyglądających na adres
        // (kod pocztowy XX-XXX albo przedrostek ulicy).
        guard let nameIdx else { return }
        var addressParts: [String] = []
        for idx in (nameIdx + 1)..<min(nameIdx + 4, lines.count) {
            let fold = folded[idx]
            if buyerLabels.contains(where: { fold.hasPrefix($0) }) || fold.contains("nip") { break }
            let looksLikeAddress = fold.range(of: #"\d{2}-\d{3}"#, options: .regularExpression) != nil
                || fold.hasPrefix("ul.") || fold.hasPrefix("ul ") || fold.hasPrefix("al.")
                || fold.hasPrefix("os.") || fold.hasPrefix("pl.")
            if looksLikeAddress {
                addressParts.append(lines[idx])
                if addressParts.count == 2 { break }
            } else if !addressParts.isEmpty {
                break
            }
        }
        if !addressParts.isEmpty {
            extraction.sellerAddress = addressParts.joined(separator: ", ")
        }
    }

    /// Nazwa firmy: zawiera litery, nie jest kolejną etykietą ani samym
    /// numerem/datą.
    private static func isPlausibleName(_ text: String) -> Bool {
        let fold = normalized(text)
        guard text.contains(where: \.isLetter), text.count >= 3 else { return false }
        let labelPrefixes = sellerLabels + buyerLabels + ["nip", "ul.", "adres", "data", "faktura", "regon"]
        return !labelPrefixes.contains { fold.hasPrefix($0) }
    }

    private static let nipRegex = try? NSRegularExpression(
        pattern: #"(?<![\dA-Za-z])(?:PL[ -]?)?(\d{3}[- ]?\d{3}[- ]?\d{2}[- ]?\d{2}|\d{3}[- ]?\d{2}[- ]?\d{2}[- ]?\d{3}|\d{10})(?!\d)"#
    )
    /// Zagraniczny VAT ID: prefiks kraju UE + min. 7 znaków numeru —
    /// krótsze dopasowania to zwykle fragmenty IBAN ("PL61") albo skróty.
    private static let euVatRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])([A-Z]{2})[ -]?([0-9A-Z]{7,13})(?![A-Za-z0-9])"#
    )

    private static func sellerTaxID(lines: [String], folded: [String], ownNIP: String?, sellerLabelIdx: Int?, buyerLabelIdx: Int?) -> String? {
        let ownDigits = (ownNIP ?? "").filter(\.isNumber)
        // Kandydaci: poprawne polskie NIP-y (suma kontrolna) z pozycjami.
        var candidates: [(line: Int, nip: String)] = []
        guard let regex = nipRegex else { return nil }
        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let digits = ns.substring(with: match.range(at: 1)).filter(\.isNumber)
                guard digits.count == 10, InvoiceValidator.isValidNIP(digits), digits != ownDigits else { continue }
                if !candidates.contains(where: { $0.nip == digits }) {
                    candidates.append((idx, digits))
                }
            }
        }
        if let sellerIdx = sellerLabelIdx {
            // Sekcja sprzedawcy: od etykiety „Sprzedawca” do etykiety
            // „Nabywca” (jeśli następuje po niej); NIP z nagłówka papieru
            // firmowego (nad etykietą) jest lepszy niż NIP nabywcy.
            let sectionEnd = (buyerLabelIdx.map { $0 > sellerIdx ? $0 : lines.count }) ?? lines.count
            if let inSection = candidates.first(where: { $0.line >= sellerIdx && $0.line < sectionEnd }) {
                return inSection.nip
            }
            if let header = candidates.last(where: { $0.line < sellerIdx }) {
                return header.nip
            }
        }
        if let first = candidates.first { return first.nip }

        // Zagraniczny VAT ID (prefiks kraju UE) — tylko w linii z "VAT"/"NIP".
        // Polskie numery muszą przejść walidację sumy kontrolnej powyżej,
        // więc prefiks PL jest tu pomijany.
        guard let euRegex = euVatRegex else { return nil }
        for (idx, line) in lines.enumerated() {
            guard folded[idx].contains("vat") || folded[idx].contains("nip") else { continue }
            let ns = line as NSString
            for match in euRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let prefix = ns.substring(with: match.range(at: 1))
                let number = ns.substring(with: match.range(at: 2))
                guard prefix != "PL",
                      VIESVerification.viesCountryCodes.contains(prefix),
                      number.contains(where: \.isNumber) else { continue }
                return prefix + number
            }
        }
        return nil
    }

    // MARK: - Kwoty

    /// Kwota z separatorem dziesiętnym (przecinek/kropka, 2 miejsca)
    /// i opcjonalnymi separatorami tysięcy (spacja, twarda spacja, kropka).
    /// Wyklucza fragmenty dat, dłuższych liczb i stawek procentowych.
    private static let amountRegex = try? NSRegularExpression(
        pattern: #"(?<![\d,.])(\d{1,3}(?:[ \x{00A0}.]\d{3})+|\d+)[,.](\d{2})(?!\s*%|[.,]?\d)"#
    )

    /// Wszystkie kwoty w linii, w kolejności występowania.
    static func amounts(in text: String) -> [Double] {
        guard let regex = amountRegex else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let integerPart = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: ".", with: "")
            let fraction = ns.substring(with: match.range(at: 2))
            return Double("\(integerPart).\(fraction)")
        }
    }

    private static let grossLabels = ["do zaplaty", "kwota do zaplaty", "razem do zaplaty", "suma brutto", "razem brutto", "wartosc brutto", "kwota brutto", "brutto"]
    private static let netLabels = ["suma netto", "razem netto", "wartosc netto", "kwota netto", "netto"]
    private static let vatLabels = ["suma vat", "razem vat", "kwota vat", "podatek vat", "vat"]

    private static func parseAmounts(into extraction: inout InvoiceOCRExtraction, lines: [String], folded: [String]) {
        // 1. Wiersz podsumowania tabeli: "Razem 1 000,00 230,00 1 230,00" —
        //    netto + VAT = brutto (ostatnia kwota) uwiarygodnia cały komplet.
        //    Klasyczny układ kolumn to „… netto VAT brutto”, więc para
        //    bezpośrednio przed brutto ma pierwszeństwo przed dalszymi
        //    kombinacjami (wiersz może zawierać też stawkę albo sumy
        //    częściowe, które przypadkiem spełnią równanie).
        for (idx, fold) in folded.enumerated() where fold.contains("razem") || fold.contains("suma") || fold.contains("ogolem") {
            let found = amounts(in: lines[idx])
            guard found.count >= 3, let gross = found.last else { continue }
            let rest = Array(found.dropLast())
            var pairs: [(Double, Double)] = [(rest[rest.count - 2], rest[rest.count - 1])]
            for i in rest.indices {
                for j in rest.indices where j > i {
                    pairs.append((rest[i], rest[j]))
                }
            }
            for (a, b) in pairs where abs(a + b - gross) <= 0.02 {
                extraction.netAmount = max(a, b)
                extraction.vatAmount = min(a, b)
                extraction.grossAmount = gross
                return
            }
        }
        // 2. Osobno etykietowane kwoty (wartość w tej samej albo następnej linii).
        extraction.grossAmount = labeledAmount(labels: grossLabels, lines: lines, folded: folded)
        extraction.netAmount = labeledAmount(labels: netLabels, lines: lines, folded: folded, excluding: ["brutto"])
        extraction.vatAmount = labeledAmount(labels: vatLabels, lines: lines, folded: folded, excluding: ["nip", "faktura", "netto", "brutto", "stawka"])
    }

    /// Kwota z linii zawierającej etykietę — ostatnia kwota w linii
    /// (wartości stoją zwykle po prawej), a przy jej braku pierwsza kwota
    /// z linii następnej, o ile ta jest samą kwotą.
    private static func labeledAmount(labels: [String], lines: [String], folded: [String], excluding: [String] = []) -> Double? {
        for label in labels {
            for (idx, fold) in folded.enumerated() where fold.contains(label) {
                guard !excluding.contains(where: { fold.contains($0) }) else { continue }
                if let amount = amounts(in: lines[idx]).last { return amount }
                if idx + 1 < lines.count {
                    let nextAmounts = amounts(in: lines[idx + 1])
                    let nextIsBareAmount = nextAmounts.count == 1
                        && lines[idx + 1].filter(\.isLetter).count <= 3 // dopuszcza kod waluty
                    if nextIsBareAmount, let amount = nextAmounts.first { return amount }
                }
            }
        }
        return nil
    }

    // MARK: - Waluta

    private static let currencyRegexes: [(code: String, regex: NSRegularExpression)] = {
        ["PLN", "EUR", "USD", "GBP", "CHF", "CZK", "SEK", "NOK", "DKK"].compactMap { code in
            (try? NSRegularExpression(pattern: "(?<![A-Za-z])\(code)(?![A-Za-z])"))
                .map { (code: code, regex: $0) }
        }
    }()
    private static let zlotyRegex = try? NSRegularExpression(pattern: #"(?<![a-złó])(zł|zl)(?![a-z])"#)

    private static func currency(lines: [String]) -> String? {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            for (code, regex) in currencyRegexes {
                let occurrences = regex.numberOfMatches(in: line, range: range)
                if occurrences > 0 {
                    counts[code, default: 0] += occurrences
                    if firstSeen[code] == nil { firstSeen[code] = idx }
                }
            }
            if let zlotyRegex {
                let lowered = line.lowercased()
                let zlCount = zlotyRegex.numberOfMatches(
                    in: lowered, range: NSRange(location: 0, length: (lowered as NSString).length)
                )
                if zlCount > 0 {
                    counts["PLN", default: 0] += zlCount
                    if firstSeen["PLN"] == nil { firstSeen["PLN"] = idx }
                }
            }
        }
        return counts.max { lhs, rhs in
            lhs.value != rhs.value
                ? lhs.value < rhs.value
                : firstSeen[lhs.key, default: .max] > firstSeen[rhs.key, default: .max]
        }?.key
    }

    // MARK: - Rachunek bankowy

    private static let nrbRegex = try? NSRegularExpression(
        pattern: #"(?<![\dA-Za-z])(?:PL[ ]?)?(\d{2}(?:[ -]?\d{4}){6})(?!\d)"#
    )
    private static func bankAccount(lines: [String], folded: [String]) -> String? {
        guard let regex = nrbRegex else { return nil }
        // Rachunek w kontekście nabywcy ("z rachunku nabywcy...") to nasze
        // własne konto — używane tylko, gdy nie ma innego numeru.
        var buyerContextFallback: String?
        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let account = ElixirPaymentExporter.normalizedNRB(ns.substring(with: match.range(at: 1)))
                guard ElixirPaymentExporter.isValidNRB(account) else { continue }
                if folded[idx].contains("nabywc") {
                    if buyerContextFallback == nil { buyerContextFallback = account }
                    continue
                }
                return account
            }
        }
        return buyerContextFallback
    }

    // MARK: - Forma płatności

    private static let paymentFormLabels = ["forma platnosci", "sposob platnosci", "sposob zaplaty", "forma zaplaty", "platnosc"]

    private static func paymentForm(lines: [String], folded: [String]) -> PaymentForm? {
        for (idx, fold) in folded.enumerated() {
            guard paymentFormLabels.contains(where: { fold.contains($0) }) else { continue }
            if let form = paymentForm(fromFolded: fold) { return form }
            if idx + 1 < lines.count, let form = paymentForm(fromFolded: folded[idx + 1]) { return form }
        }
        // Bez etykiety: wzmianka o przelewie wystarcza (typowe "płatne
        // przelewem na konto ...").
        if folded.contains(where: { $0.contains("przelew") }) { return .transfer }
        return nil
    }

    private static func paymentForm(fromFolded fold: String) -> PaymentForm? {
        if fold.contains("przelew") { return .transfer }
        if fold.contains("gotowk") { return .cash }
        if fold.contains("kart") { return .card }
        return nil
    }
}
