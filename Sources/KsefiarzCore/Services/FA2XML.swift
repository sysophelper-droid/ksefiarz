import Foundation

// MARK: - Struktury danych dokumentu FA(2)

/// Pozycja faktury sparsowana z dokumentu FA(2) (FaWiersz).
public struct FA2InvoiceLine: Equatable, Sendable {
    public var index: Int
    public var name: String
    public var unit: String
    public var quantity: Double
    public var unitNetPrice: Double
    public var netAmount: Double
    /// Stawka VAT: "23", "8", "5", "0", "zw"…
    public var vatRate: String
    /// Kwota VAT wyliczona ze stawki (nie występuje wprost w XML).
    public var vatAmount: Double
    /// Kod CN lub PKWiU pozycji (elementy PKWiU/CN w FaWiersz).
    public var cnPkwiu: String
    /// Kod GTU pozycji.
    public var gtu: String
    /// Oznaczenie procedury pozycji (element Procedura, np. "WSTO_EE").
    public var procedure: String
    /// Stawka podatku od wartości dodanej dla procedury OSS (dział XII
    /// rozdz. 6a ustawy) — element P_12_XII. Gdy ustawiona, pozycja nie ma
    /// polskiej stawki (P_12), a jej VAT trafia do sum P_13_5/P_14_5.
    public var ossRate: Double?

    public init(
        index: Int,
        name: String,
        unit: String = "szt.",
        quantity: Double = 1,
        unitNetPrice: Double = 0,
        netAmount: Double = 0,
        vatRate: String = "23",
        vatAmount: Double = 0,
        cnPkwiu: String = "",
        gtu: String = "",
        procedure: String = "",
        ossRate: Double? = nil
    ) {
        self.index = index
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitNetPrice = unitNetPrice
        self.netAmount = netAmount
        self.vatRate = vatRate
        self.vatAmount = vatAmount
        self.cnPkwiu = cnPkwiu
        self.gtu = gtu
        self.procedure = procedure
        self.ossRate = ossRate
    }
}

/// Dane faktury korygowanej — wspólne dla szkicu (generowanie KOR)
/// i dokumentów sparsowanych z KSeF.
public struct InvoiceCorrectionInfo: Equatable, Sendable {
    /// Numer własny faktury korygowanej.
    public var originalNumber: String
    /// Data wystawienia faktury korygowanej.
    public var originalIssueDate: Date
    /// Numer KSeF faktury korygowanej (nil, gdy faktura nie miała numeru KSeF).
    public var originalKsefNumber: String?
    /// Przyczyna korekty.
    public var reason: String?

    public init(
        originalNumber: String,
        originalIssueDate: Date,
        originalKsefNumber: String? = nil,
        reason: String? = nil
    ) {
        self.originalNumber = originalNumber
        self.originalIssueDate = originalIssueDate
        self.originalKsefNumber = originalKsefNumber
        self.reason = reason
    }
}

/// Dane faktury sparsowane z dokumentu XML w strukturze FA(2)
/// lub przygotowane do wygenerowania takiego dokumentu.
public struct FA2InvoiceData: Equatable, Sendable {
    /// Numer referencyjny KSeF (uzupełniany po pobraniu/wysyłce).
    public var ksefId: String?
    public var invoiceNumber: String
    public var issueDate: Date
    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    public var netAmount: Double
    public var vatAmount: Double
    public var grossAmount: Double
    public var paymentDueDate: Date?
    /// Kod formy płatności (słownik FA(2): 1-gotówka … 6-przelew).
    public var paymentForm: String?
    /// Numer rachunku bankowego do płatności (NrRB).
    public var paymentBankAccount: String?
    /// Data zapłaty (DataZaplaty), jeśli wskazano na fakturze.
    public var paymentDate: Date?
    /// Znacznik „Zaplacono” — faktura opłacona przy wystawieniu (np. gotówką/kartą).
    public var isPaidMarker: Bool
    /// Rodzaj dokumentu wg FA(2): "VAT" lub "KOR".
    public var documentType: String
    /// Dane faktury korygowanej (dla dokumentów KOR).
    public var correction: InvoiceCorrectionInfo?
    /// Pozycje faktury.
    public var lines: [FA2InvoiceLine]
    /// Uwagi z faktury (Stopka/Informacje/StopkaFaktury).
    public var notes: String
    /// Waluta faktury (KodWaluty).
    public var currency: String
    /// Mechanizm podzielonej płatności (Adnotacje P_18A = 1).
    public var splitPayment: Bool
    /// Data dokonania dostawy / otrzymania zapłaty (P_6).
    public var saleDate: Date?
    /// Załącznik do faktury (element Zalacznik FA(3)) — bloki danych.
    public var attachments: [FA3AttachmentBlock]
    /// Oryginalna treść dokumentu XML.
    public var rawXML: String

    public init(
        ksefId: String? = nil,
        invoiceNumber: String,
        issueDate: Date,
        sellerName: String,
        sellerNIP: String,
        sellerAddress: String = "",
        buyerName: String,
        buyerNIP: String,
        buyerAddress: String = "",
        netAmount: Double,
        vatAmount: Double,
        grossAmount: Double,
        paymentDueDate: Date? = nil,
        paymentForm: String? = nil,
        paymentBankAccount: String? = nil,
        paymentDate: Date? = nil,
        isPaidMarker: Bool = false,
        documentType: String = "VAT",
        correction: InvoiceCorrectionInfo? = nil,
        lines: [FA2InvoiceLine] = [],
        notes: String = "",
        currency: String = "PLN",
        splitPayment: Bool = false,
        saleDate: Date? = nil,
        attachments: [FA3AttachmentBlock] = [],
        rawXML: String = ""
    ) {
        self.ksefId = ksefId
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.sellerName = sellerName
        self.sellerNIP = sellerNIP
        self.sellerAddress = sellerAddress
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.buyerAddress = buyerAddress
        self.netAmount = netAmount
        self.vatAmount = vatAmount
        self.grossAmount = grossAmount
        self.paymentDueDate = paymentDueDate
        self.paymentForm = paymentForm
        self.paymentBankAccount = paymentBankAccount
        self.paymentDate = paymentDate
        self.isPaidMarker = isPaidMarker
        self.documentType = documentType
        self.correction = correction
        self.lines = lines
        self.notes = notes
        self.currency = currency
        self.splitPayment = splitPayment
        self.saleDate = saleDate
        self.attachments = attachments
        self.rawXML = rawXML
    }
}

/// Wspólne formatery dat używane w dokumentach FA(2).
public enum FA2Format {
    /// Format daty pól P_1, Termin itd. — "yyyy-MM-dd".
    public static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Format znacznika czasu wytworzenia dokumentu (ISO 8601).
    public static let timestampFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

    /// Formatowanie kwot — zawsze z kropką dziesiętną i dwoma miejscami po przecinku.
    public static func amount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Formatowanie ilości — do 4 miejsc po przecinku, bez zbędnych zer.
    public static func quantity(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Formatowanie wartości procentowej (TProcentowy — do 6 miejsc po
    /// przecinku), bez zbędnych zer. Używane dla stawki OSS (P_12_XII).
    public static func percent(_ value: Double) -> String {
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

// MARK: - Generator XML FA(2)

/// Generator dokumentu XML zgodnego ze schemą FA(2) (wymagane elementy:
/// adresy stron, blok Adnotacje, RodzajFaktury, pozycje FaWiersz,
/// sumy wartości per stawka VAT oraz dane płatności).
public enum FA2XMLGenerator {

    /// Przestrzeń nazw schemy FA(2).
    /// Przestrzeń nazw schemy FA(3) — bieżąca wersja generowanych dokumentów.
    public static let namespace = "http://crd.gov.pl/wzor/2025/06/25/13775/"

    /// Generuje dokument XML dla podanego szkicu faktury.
    /// - Parameters:
    ///   - draft: zwalidowane dane faktury,
    ///   - generatedAt: znacznik czasu wytworzenia dokumentu (parametr ułatwia testowanie).
    public static func generateXML(for draft: InvoiceDraft, generatedAt: Date = .now) -> String {
        let issueDate = FA2Format.dateFormatter.string(from: draft.issueDate)
        let createdAt = FA2Format.timestampFormatter.string(from: generatedAt)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Faktura xmlns="\(namespace)">
          <Naglowek>
            <KodFormularza kodSystemowy="FA (3)" wersjaSchemy="1-0E">FA</KodFormularza>
            <WariantFormularza>3</WariantFormularza>
            <DataWytworzeniaFa>\(createdAt)</DataWytworzeniaFa>
            <SystemInfo>Ksefiarz macOS</SystemInfo>
          </Naglowek>
          <Podmiot1>
            <DaneIdentyfikacyjne>
              <NIP>\(escape(draft.sellerNIP))</NIP>
              <Nazwa>\(escape(draft.sellerName))</Nazwa>
            </DaneIdentyfikacyjne>
            <Adres>
              <KodKraju>PL</KodKraju>
              <AdresL1>\(escape(draft.sellerAddress))</AdresL1>
            </Adres>
          </Podmiot1>
          <Podmiot2>
            <DaneIdentyfikacyjne>
              <NIP>\(escape(draft.buyerNIP))</NIP>
              <Nazwa>\(escape(draft.buyerName))</Nazwa>
            </DaneIdentyfikacyjne>\(buyerAddressBlock(draft))
            <JST>2</JST>
            <GV>2</GV>
          </Podmiot2>
          <Fa>
            <KodWaluty>\(escape(draft.currency))</KodWaluty>
            <P_1>\(issueDate)</P_1>
            <P_2>\(escape(draft.invoiceNumber))</P_2>
        \(saleDateElement(draft))\(vatSummaryBlock(draft))    <P_15>\(FA2Format.amount(draft.grossAmount))</P_15>
            <Adnotacje>
              <P_16>2</P_16>
              <P_17>2</P_17>
              <P_18>2</P_18>
              <P_18A>\(draft.splitPayment ? 1 : 2)</P_18A>
              <Zwolnienie>
                <P_19N>1</P_19N>
              </Zwolnienie>
              <NoweSrodkiTransportu>
                <P_22N>1</P_22N>
              </NoweSrodkiTransportu>
              <P_23>2</P_23>
        \(marginBlock(draft))    </Adnotacje>
            <RodzajFaktury>\(escape(draft.documentType))</RodzajFaktury>
        \(correctionBlock(draft))\(advanceInvoicesBlock(draft))\(linesBlock(draft))\(paymentBlock(draft))  </Fa>
        \(stopkaBlock(draft))\(attachmentBlock(draft))</Faktura>
        """
    }

    /// Procedury marży (Adnotacje/PMarzy): wybór jednego znacznika
    /// (P_PMarzy_2 — biura podróży, P_PMarzy_3_1/2/3 — towary używane /
    /// dzieła sztuki / antyki) albo P_PMarzyN=1 (nie dotyczy).
    private static func marginBlock(_ draft: InvoiceDraft) -> String {
        let allowed = ["2", "3_1", "3_2", "3_3"]
        guard allowed.contains(draft.marginProcedure) else {
            return """
                  <PMarzy>
                    <P_PMarzyN>1</P_PMarzyN>
                  </PMarzy>

            """
        }
        return """
              <PMarzy>
                <P_PMarzy>1</P_PMarzy>
                <P_PMarzy_\(draft.marginProcedure)>1</P_PMarzy_\(draft.marginProcedure)>
              </PMarzy>

        """
    }

    /// Data dokonania dostawy / otrzymania zapłaty (P_6) — po P_2, przed sumami.
    private static func saleDateElement(_ draft: InvoiceDraft) -> String {
        guard let saleDate = draft.saleDate else { return "" }
        return "    <P_6>\(FA2Format.dateFormatter.string(from: saleDate))</P_6>\n"
    }

    /// Odwołania do faktur zaliczkowych (dokumenty ROZ) — przed FaWiersz.
    private static func advanceInvoicesBlock(_ draft: InvoiceDraft) -> String {
        guard draft.documentType == "ROZ" else { return "" }
        return draft.advanceInvoiceRefs
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ref in
                """
                    <FakturaZaliczkowa>
                      <NrKSeFFaZaliczkowej>\(escape(ref.trimmingCharacters(in: .whitespaces)))</NrKSeFFaZaliczkowej>
                    </FakturaZaliczkowa>

                """
            }
            .joined()
    }

    /// Stopka z uwagami (dopiskiem) — opcjonalna, po elemencie Fa.
    private static func stopkaBlock(_ draft: InvoiceDraft) -> String {
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return "" }
        return """
          <Stopka>
            <Informacje>
              <StopkaFaktury>\(escape(notes))</StopkaFaktury>
            </Informacje>
          </Stopka>

        """
    }

    /// Załącznik do faktury (element Zalacznik) — ostatni element dokumentu,
    /// po Stopce. Struktura wg XSD FA(3): BlokDanych → ZNaglowek?,
    /// MetaDane+ (ZKlucz/ZWartosc), Tekst? (Akapit×10), Tabela*
    /// (Opis?, TNaglowek/Kol/NKom, Wiersz/WKom, Suma?/SKom).
    private static func attachmentBlock(_ draft: InvoiceDraft) -> String {
        guard !draft.attachments.isEmpty else { return "" }
        var xml = "  <Zalacznik>\n"
        for block in draft.attachments {
            xml += "    <BlokDanych>\n"
            let header = block.header.trimmingCharacters(in: .whitespacesAndNewlines)
            if !header.isEmpty {
                xml += "      <ZNaglowek>\(escape(header))</ZNaglowek>\n"
            }
            // Puste pary (np. niewypełnione wiersze formularza) pomijamy —
            // XSD wymaga niepustych ZKlucz/ZWartosc.
            let metadata = block.metadata.filter {
                !$0.key.trimmingCharacters(in: .whitespaces).isEmpty
                    && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
            }
            for meta in metadata {
                xml += "      <MetaDane>\n"
                xml += "        <ZKlucz>\(escape(meta.key))</ZKlucz>\n"
                xml += "        <ZWartosc>\(escape(meta.value))</ZWartosc>\n"
                xml += "      </MetaDane>\n"
            }
            let paragraphs = block.paragraphs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !paragraphs.isEmpty {
                xml += "      <Tekst>\n"
                for paragraph in paragraphs {
                    xml += "        <Akapit>\(escape(paragraph))</Akapit>\n"
                }
                xml += "      </Tekst>\n"
            }
            for table in block.tables where !table.columns.isEmpty && !table.rows.isEmpty {
                xml += "      <Tabela>\n"
                let description = table.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty {
                    xml += "        <Opis>\(escape(description))</Opis>\n"
                }
                xml += "        <TNaglowek>\n"
                for column in table.columns {
                    xml += "          <Kol Typ=\"txt\">\n"
                    xml += "            <NKom>\(escape(column))</NKom>\n"
                    xml += "          </Kol>\n"
                }
                xml += "        </TNaglowek>\n"
                for row in table.rows {
                    xml += "        <Wiersz>\n"
                    for cell in row.prefix(table.columns.count) {
                        xml += "          <WKom>\(escape(cell))</WKom>\n"
                    }
                    xml += "        </Wiersz>\n"
                }
                if !table.summary.isEmpty {
                    xml += "        <Suma>\n"
                    for cell in table.summary.prefix(table.columns.count) {
                        xml += "          <SKom>\(escape(cell))</SKom>\n"
                    }
                    xml += "        </Suma>\n"
                }
                xml += "      </Tabela>\n"
            }
            xml += "    </BlokDanych>\n"
        }
        xml += "  </Zalacznik>\n"
        return xml
    }

    /// Blok danych faktury korygowanej (dokumenty KOR).
    /// Kolejność elementów zgodna z XSD: PrzyczynaKorekty, TypKorekty, DaneFaKorygowanej.
    private static func correctionBlock(_ draft: InvoiceDraft) -> String {
        guard let correction = draft.correction else { return "" }

        var xml = ""
        if let reason = correction.reason, !reason.isEmpty {
            xml += "    <PrzyczynaKorekty>\(escape(reason))</PrzyczynaKorekty>\n"
        }
        // TypKorekty 2 — korekta ujmowana zgodnie z datą wystawienia korekty.
        xml += "    <TypKorekty>2</TypKorekty>\n"

        let originalDate = FA2Format.dateFormatter.string(from: correction.originalIssueDate)
        // Wybór (choice): faktura korygowana miała numer KSeF albo nie.
        let ksefPart: String
        if let ksefNumber = correction.originalKsefNumber, !ksefNumber.isEmpty {
            ksefPart = """
                  <NrKSeF>1</NrKSeF>
                  <NrKSeFFaKorygowanej>\(escape(ksefNumber))</NrKSeFFaKorygowanej>
            """
        } else {
            ksefPart = "      <NrKSeFN>1</NrKSeFN>"
        }
        xml += """
            <DaneFaKorygowanej>
              <DataWystFaKorygowanej>\(originalDate)</DataWystFaKorygowanej>
              <NrFaKorygowanej>\(escape(correction.originalNumber))</NrFaKorygowanej>
        \(ksefPart)
            </DaneFaKorygowanej>

        """
        return xml
    }

    // MARK: Bloki dokumentu

    /// Adres nabywcy — opcjonalny w FA(2).
    private static func buyerAddressBlock(_ draft: InvoiceDraft) -> String {
        let address = draft.buyerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return "" }
        return """

            <Adres>
              <KodKraju>PL</KodKraju>
              <AdresL1>\(escape(address))</AdresL1>
            </Adres>
        """
    }

    /// Sumy wartości sprzedaży netto i kwot VAT per stawka (P_13_x / P_14_x).
    /// Przy walucie obcej z podanym kursem dodatkowo kwota VAT w PLN
    /// (P_14_xW — obowiązek z art. 106e ust. 11 ustawy o VAT).
    /// Kolejność pól musi odpowiadać sekwencji w XSD.
    private static func vatSummaryBlock(_ draft: InvoiceDraft) -> String {
        let foreignRate = draft.currency == "PLN" || draft.exchangeRate <= 0
            ? nil : draft.exchangeRate

        func vatInPLN(_ vat: Double, field: String) -> String {
            guard let rate = foreignRate, vat != 0 else { return "" }
            let converted = ((vat * rate) * 100).rounded() / 100
            return "    <\(field)>\(FA2Format.amount(converted))</\(field)>\n"
        }

        // Tryb uproszczony bez pozycji: całość traktujemy jako stawkę podstawową.
        guard !draft.lines.isEmpty else {
            return """
                <P_13_1>\(FA2Format.amount(draft.netAmount))</P_13_1>
                <P_14_1>\(FA2Format.amount(draft.vatAmount))</P_14_1>
            \(vatInPLN(draft.vatAmount, field: "P_14_1W"))
            """
        }

        // Pozycje OSS (P_12_XII) mają własne sumy P_13_5/P_14_5 —
        // nie wchodzą do sum polskich stawek.
        func sums(for rate: VATRate) -> (net: Double, vat: Double)? {
            let matching = draft.lines.filter { $0.ossRate == nil && $0.vatRate == rate }
            guard !matching.isEmpty else { return nil }
            let net = matching.reduce(0) { $0 + $1.netAmount }
            let vat = matching.reduce(0) { $0 + $1.vatAmount }
            return (net, vat)
        }

        var xml = ""
        if let s = sums(for: .standard) {
            xml += "    <P_13_1>\(FA2Format.amount(s.net))</P_13_1>\n"
            xml += "    <P_14_1>\(FA2Format.amount(s.vat))</P_14_1>\n"
            xml += vatInPLN(s.vat, field: "P_14_1W")
        }
        if let s = sums(for: .reducedFirst) {
            xml += "    <P_13_2>\(FA2Format.amount(s.net))</P_13_2>\n"
            xml += "    <P_14_2>\(FA2Format.amount(s.vat))</P_14_2>\n"
            xml += vatInPLN(s.vat, field: "P_14_2W")
        }
        if let s = sums(for: .reducedSecond) {
            xml += "    <P_13_3>\(FA2Format.amount(s.net))</P_13_3>\n"
            xml += "    <P_14_3>\(FA2Format.amount(s.vat))</P_14_3>\n"
            xml += vatInPLN(s.vat, field: "P_14_3W")
        }
        // Procedura OSS (dział XII rozdz. 6a): suma netto i podatek od
        // wartości dodanej — sekwencja przed P_13_6_1 zgodnie z XSD.
        let ossLines = draft.lines.filter { $0.ossRate != nil }
        if !ossLines.isEmpty {
            let net = ossLines.reduce(0) { $0 + $1.netAmount }
            let vat = ossLines.reduce(0) { $0 + $1.vatAmount }
            xml += "    <P_13_5>\(FA2Format.amount(net))</P_13_5>\n"
            xml += "    <P_14_5>\(FA2Format.amount(vat))</P_14_5>\n"
        }
        if let s = sums(for: .zero) {
            xml += "    <P_13_6_1>\(FA2Format.amount(s.net))</P_13_6_1>\n"
        }
        if let s = sums(for: .exempt) {
            xml += "    <P_13_7>\(FA2Format.amount(s.net))</P_13_7>\n"
        }
        return xml
    }

    /// Pozycje faktury (FaWiersz). Kolejność elementów wg XSD:
    /// NrWierszaFa, P_7, [PKWiU|CN], P_8A, P_8B, P_9A, P_11,
    /// P_12 albo P_12_XII (OSS), [GTU], [Procedura].
    private static func linesBlock(_ draft: InvoiceDraft) -> String {
        guard !draft.lines.isEmpty else { return "" }
        var xml = ""
        for (offset, line) in draft.lines.enumerated() {
            // Pozycja OSS ma stawkę podatku od wartości dodanej państwa
            // konsumpcji (P_12_XII) zamiast polskiej stawki (P_12).
            let rateElement = line.ossRate.map {
                "<P_12_XII>\(FA2Format.percent($0))</P_12_XII>"
            } ?? "<P_12>\(line.vatRate.rawValue)</P_12>"
            xml += """
                <FaWiersz>
                  <NrWierszaFa>\(offset + 1)</NrWierszaFa>
                  <P_7>\(escape(line.name))</P_7>
            \(classificationElement(line.cnPkwiu))      <P_8A>\(escape(line.unit))</P_8A>
                  <P_8B>\(FA2Format.quantity(line.quantity))</P_8B>
                  <P_9A>\(FA2Format.amount(line.unitNetPrice))</P_9A>
                  <P_11>\(FA2Format.amount(line.netAmount))</P_11>
                  \(rateElement)
            \(gtuElement(line.gtu))\(procedureElement(line.procedure))    </FaWiersz>

            """
        }
        return xml
    }

    /// Element klasyfikacji pozycji. XSD rozróżnia PKWiU i CN — kody PKWiU
    /// mają format z kropkami (np. "62.01.11.0"), kody CN są ciągiem cyfr
    /// (np. "85234910"); po tym rozpoznajemy właściwy element.
    private static func classificationElement(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let element = trimmed.contains(".") ? "PKWiU" : "CN"
        return "      <\(element)>\(escape(trimmed))</\(element)>\n"
    }

    /// Element GTU pozycji (opcjonalny).
    private static func gtuElement(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "      <GTU>\(escape(trimmed))</GTU>\n"
    }

    /// Element Procedura pozycji (opcjonalny) — po GTU, zgodnie z XSD.
    private static func procedureElement(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "      <Procedura>\(escape(trimmed))</Procedura>\n"
    }

    /// Dane płatności: termin, forma, numer rachunku.
    private static func paymentBlock(_ draft: InvoiceDraft) -> String {
        var inner = ""
        if let due = draft.paymentDueDate {
            inner += """
                  <TerminPlatnosci>
                    <Termin>\(FA2Format.dateFormatter.string(from: due))</Termin>
                  </TerminPlatnosci>

            """
        }
        if let form = draft.paymentForm {
            inner += "          <FormaPlatnosci>\(form.rawValue)</FormaPlatnosci>\n"
        }
        let account = draft.paymentBankAccount.replacingOccurrences(of: " ", with: "")
        if !account.isEmpty {
            inner += """
                  <RachunekBankowy>
                    <NrRB>\(escape(account))</NrRB>
                  </RachunekBankowy>

            """
        }
        guard !inner.isEmpty else { return "" }
        return "    <Platnosc>\n\(inner)    </Platnosc>\n"
    }

    /// Ucieczka znaków specjalnych XML.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Parser XML FA(2)

/// Parser struktury FA(2) → `FA2InvoiceData`.
/// Oparty o `XMLDocument` (Foundation, macOS) — odporny na przestrzenie nazw
/// dzięki wyszukiwaniu elementów po nazwie lokalnej.
public enum FA2XMLParser {

    /// Parsuje dokument XML e-Faktury.
    public static func parse(data: Data) throws -> FA2InvoiceData {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw KSeFError.xmlParsingFailed("Dokument nie jest poprawnym XML: \(error.localizedDescription)")
        }
        guard let root = document.rootElement(), localName(of: root) == "Faktura" else {
            throw KSeFError.xmlParsingFailed("Brak elementu głównego <Faktura>.")
        }

        guard let podmiot1 = firstDescendant(named: "Podmiot1", in: root) else {
            throw KSeFError.xmlParsingFailed("Brak elementu <Podmiot1> (sprzedawca).")
        }
        guard let podmiot2 = firstDescendant(named: "Podmiot2", in: root) else {
            throw KSeFError.xmlParsingFailed("Brak elementu <Podmiot2> (nabywca).")
        }
        guard let fa = firstDescendant(named: "Fa", in: root) else {
            throw KSeFError.xmlParsingFailed("Brak elementu <Fa> z danymi faktury.")
        }

        guard let invoiceNumber = text(of: "P_2", in: fa), !invoiceNumber.isEmpty else {
            throw KSeFError.xmlParsingFailed("Brak numeru faktury (P_2).")
        }
        guard let issueDateString = text(of: "P_1", in: fa),
              let issueDate = FA2Format.dateFormatter.date(from: issueDateString) else {
            throw KSeFError.xmlParsingFailed("Brak lub nieprawidłowa data wystawienia (P_1).")
        }
        guard let grossString = text(of: "P_15", in: fa), let gross = Double(grossString) else {
            throw KSeFError.xmlParsingFailed("Brak lub nieprawidłowa kwota brutto (P_15).")
        }

        // Pozycje faktury.
        let lines = parseLines(in: fa)

        // Sumy netto/VAT ze wszystkich pól per stawka; gdy brak — z pozycji.
        let netFields = ["P_13_1", "P_13_2", "P_13_3", "P_13_4", "P_13_5",
                         "P_13_6_1", "P_13_6_2", "P_13_6_3", "P_13_7", "P_13_8",
                         "P_13_9", "P_13_10", "P_13_11"]
        let vatFields = ["P_14_1", "P_14_2", "P_14_3", "P_14_4", "P_14_5"]
        var net = sum(of: netFields, in: fa)
        var vat = sum(of: vatFields, in: fa)
        if net == 0, vat == 0, !lines.isEmpty {
            net = lines.reduce(0) { $0 + $1.netAmount }
            vat = lines.reduce(0) { $0 + $1.vatAmount }
        }

        // Dane płatności.
        let payment = firstDescendant(named: "Platnosc", in: fa)
        var dueDate: Date?
        if let dueString = text(of: "Termin", in: fa) {
            dueDate = FA2Format.dateFormatter.date(from: dueString)
        }
        let isPaidMarker = payment.flatMap { text(of: "Zaplacono", in: $0) } == "1"
        let paymentDate = payment
            .flatMap { text(of: "DataZaplaty", in: $0) }
            .flatMap { FA2Format.dateFormatter.date(from: $0) }
        let paymentForm = payment.flatMap { text(of: "FormaPlatnosci", in: $0) }
        let bankAccount = payment.flatMap { text(of: "NrRB", in: $0) }

        // Rodzaj dokumentu i dane faktury korygowanej (KOR).
        let documentType = text(of: "RodzajFaktury", in: fa) ?? "VAT"
        var correction: InvoiceCorrectionInfo?
        if documentType == "KOR", let corrected = firstDescendant(named: "DaneFaKorygowanej", in: fa) {
            let originalDate = text(of: "DataWystFaKorygowanej", in: corrected)
                .flatMap { FA2Format.dateFormatter.date(from: $0) }
            correction = InvoiceCorrectionInfo(
                originalNumber: text(of: "NrFaKorygowanej", in: corrected) ?? "",
                originalIssueDate: originalDate ?? issueDate,
                originalKsefNumber: text(of: "NrKSeFFaKorygowanej", in: corrected),
                reason: text(of: "PrzyczynaKorekty", in: fa)
            )
        }

        // Uwagi (Stopka jest elementem równorzędnym do Fa — szukamy od korzenia).
        let notes = text(of: "StopkaFaktury", in: root) ?? ""

        let currency = text(of: "KodWaluty", in: fa) ?? "PLN"
        let splitPayment = text(of: "P_18A", in: fa) == "1"
        let saleDate = text(of: "P_6", in: fa)
            .flatMap { FA2Format.dateFormatter.date(from: $0) }

        // Załącznik (element równorzędny do Fa — szukamy od korzenia).
        let attachments = parseAttachments(in: root)

        return FA2InvoiceData(
            invoiceNumber: invoiceNumber,
            issueDate: issueDate,
            sellerName: text(of: "Nazwa", in: podmiot1) ?? "",
            sellerNIP: text(of: "NIP", in: podmiot1) ?? "",
            sellerAddress: parseAddress(in: podmiot1),
            buyerName: text(of: "Nazwa", in: podmiot2) ?? "",
            buyerNIP: text(of: "NIP", in: podmiot2) ?? "",
            buyerAddress: parseAddress(in: podmiot2),
            netAmount: net,
            vatAmount: vat,
            grossAmount: gross,
            paymentDueDate: dueDate,
            paymentForm: paymentForm,
            paymentBankAccount: bankAccount,
            paymentDate: paymentDate,
            isPaidMarker: isPaidMarker,
            documentType: documentType,
            correction: correction,
            lines: lines,
            notes: notes,
            currency: currency,
            splitPayment: splitPayment,
            saleDate: saleDate,
            attachments: attachments,
            rawXML: String(data: data, encoding: .utf8) ?? ""
        )
    }

    /// Parsuje dokument XML przekazany jako String.
    public static func parse(xml: String) throws -> FA2InvoiceData {
        try parse(data: Data(xml.utf8))
    }

    // MARK: Bloki dokumentu

    /// Adres podmiotu: AdresL1 + AdresL2 połączone przecinkiem.
    private static func parseAddress(in podmiot: XMLElement) -> String {
        guard let adres = firstDescendant(named: "Adres", in: podmiot) else { return "" }
        let parts = [text(of: "AdresL1", in: adres), text(of: "AdresL2", in: adres)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    /// Pozycje FaWiersz.
    private static func parseLines(in fa: XMLElement) -> [FA2InvoiceLine] {
        descendants(named: "FaWiersz", in: fa).enumerated().compactMap { offset, wiersz in
            guard let name = text(of: "P_7", in: wiersz) else { return nil }
            let index = text(of: "NrWierszaFa", in: wiersz).flatMap(Int.init) ?? (offset + 1)
            let quantity = text(of: "P_8B", in: wiersz).flatMap(Double.init) ?? 1
            let unitPrice = text(of: "P_9A", in: wiersz).flatMap(Double.init) ?? 0
            let netAmount = text(of: "P_11", in: wiersz).flatMap(Double.init)
                ?? ((quantity * unitPrice * 100).rounded() / 100)
            let rate = text(of: "P_12", in: wiersz) ?? ""
            // Pozycja OSS: stawka podatku od wartości dodanej w P_12_XII.
            let ossRate = text(of: "P_12_XII", in: wiersz).flatMap(Double.init)
            let multiplier = ossRate.map { $0 / 100 }
                ?? VATRate(rawValue: rate)?.multiplier ?? 0
            let vatAmount = ((netAmount * multiplier) * 100).rounded() / 100

            return FA2InvoiceLine(
                index: index,
                name: name,
                unit: text(of: "P_8A", in: wiersz) ?? "szt.",
                quantity: quantity,
                unitNetPrice: unitPrice,
                netAmount: netAmount,
                vatRate: rate,
                vatAmount: vatAmount,
                cnPkwiu: text(of: "PKWiU", in: wiersz) ?? text(of: "CN", in: wiersz) ?? "",
                gtu: text(of: "GTU", in: wiersz) ?? "",
                procedure: text(of: "Procedura", in: wiersz) ?? "",
                ossRate: ossRate
            )
        }
    }

    /// Załącznik FA(3): bloki danych z metadanymi, akapitami i tabelami.
    private static func parseAttachments(in root: XMLElement) -> [FA3AttachmentBlock] {
        guard let zalacznik = firstDescendant(named: "Zalacznik", in: root) else { return [] }
        return descendants(named: "BlokDanych", in: zalacznik).map { blok in
            let metadata = descendants(named: "MetaDane", in: blok).map { meta in
                FA3AttachmentBlock.Meta(
                    key: text(of: "ZKlucz", in: meta) ?? "",
                    value: text(of: "ZWartosc", in: meta) ?? ""
                )
            }
            let paragraphs = firstDescendant(named: "Tekst", in: blok).map { tekst in
                descendants(named: "Akapit", in: tekst).compactMap {
                    $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } ?? []
            let tables = descendants(named: "Tabela", in: blok).map { tabela in
                FA3AttachmentBlock.Table(
                    description: text(of: "Opis", in: tabela) ?? "",
                    columns: firstDescendant(named: "TNaglowek", in: tabela).map {
                        descendants(named: "NKom", in: $0).compactMap { $0.stringValue }
                    } ?? [],
                    rows: descendants(named: "Wiersz", in: tabela).map { wiersz in
                        descendants(named: "WKom", in: wiersz).compactMap { $0.stringValue }
                    },
                    summary: firstDescendant(named: "Suma", in: tabela).map {
                        descendants(named: "SKom", in: $0).compactMap { $0.stringValue }
                    } ?? []
                )
            }
            return FA3AttachmentBlock(
                header: text(of: "ZNaglowek", in: blok) ?? "",
                metadata: metadata,
                paragraphs: paragraphs,
                tables: tables
            )
        }
    }

    /// Suma wartości liczbowych z listy elementów (pomija nieobecne).
    private static func sum(of names: [String], in element: XMLElement) -> Double {
        names.reduce(0) { total, name in
            total + (text(of: name, in: element).flatMap(Double.init) ?? 0)
        }
    }

    // MARK: Pomocnicze przeszukiwanie drzewa XML

    private static func localName(of element: XMLElement) -> String {
        element.localName ?? element.name ?? ""
    }

    /// Rekurencyjnie wyszukuje pierwszy element potomny o podanej nazwie lokalnej.
    private static func firstDescendant(named name: String, in element: XMLElement) -> XMLElement? {
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if localName(of: childElement) == name { return childElement }
            if let found = firstDescendant(named: name, in: childElement) { return found }
        }
        return nil
    }

    /// Rekurencyjnie zbiera wszystkie elementy potomne o podanej nazwie lokalnej.
    private static func descendants(named name: String, in element: XMLElement) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if localName(of: childElement) == name {
                result.append(childElement)
            } else {
                result.append(contentsOf: descendants(named: name, in: childElement))
            }
        }
        return result
    }

    /// Zwraca przyciętą zawartość tekstową pierwszego potomka o podanej nazwie.
    private static func text(of name: String, in element: XMLElement) -> String? {
        firstDescendant(named: name, in: element)?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
