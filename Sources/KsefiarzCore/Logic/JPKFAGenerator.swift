import Foundation

/// Parametry generowania pliku JPK_FA(4) — JPK faktur VAT na żądanie
/// (kontrola US, czynności sprawdzające, postępowanie podatkowe).
///
/// Okres pliku wyznacza zakres dat WYSTAWIENIA faktur (organ żąda pliku
/// wg kryteriów kontroli — najczęściej po dacie wystawienia). Adres
/// podmiotu jest wymagany przez XSD w postaci strukturalnej
/// (etd:TAdresPolski1), dlatego nie da się go wyprowadzić z jednolinijkowego
/// adresu z Ustawień.
public struct JPKFAOptions: Sendable {
    /// Początek okresu (data wystawienia, włącznie).
    public var dateFrom: Date
    /// Koniec okresu (data wystawienia, włącznie).
    public var dateTo: Date
    /// Dane podatnika (Podmiot1/IdentyfikatorPodmiotu).
    public var sellerNIP: String
    public var sellerName: String
    /// Czterocyfrowy kod urzędu skarbowego (KodUrzedu).
    public var taxOfficeCode: String
    /// Adres polski podmiotu (etd:TAdresPolski1) — pola wymagane przez XSD
    /// poza ulicą i numerem lokalu.
    public var wojewodztwo: String
    public var powiat: String
    public var gmina: String
    public var ulica: String
    public var nrDomu: String
    public var nrLokalu: String
    public var miejscowosc: String
    public var kodPocztowy: String

    public init(
        dateFrom: Date,
        dateTo: Date,
        sellerNIP: String,
        sellerName: String,
        taxOfficeCode: String,
        wojewodztwo: String,
        powiat: String,
        gmina: String,
        ulica: String = "",
        nrDomu: String,
        nrLokalu: String = "",
        miejscowosc: String,
        kodPocztowy: String
    ) {
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.sellerNIP = sellerNIP
        self.sellerName = sellerName
        self.taxOfficeCode = taxOfficeCode
        self.wojewodztwo = wojewodztwo
        self.powiat = powiat
        self.gmina = gmina
        self.ulica = ulica
        self.nrDomu = nrDomu
        self.nrLokalu = nrLokalu
        self.miejscowosc = miejscowosc
        self.kodPocztowy = kodPocztowy
    }
}

/// Wynik generowania: dokument XML + sumy kontrolne i ostrzeżenia
/// (uproszczenia wymagające weryfikacji przed przekazaniem organowi).
public struct JPKFAResult: Sendable {
    public var xml: String
    /// Liczba faktur (FakturaCtrl/LiczbaFaktur).
    public var invoiceCount: Int
    /// Suma kolumny P_15 (FakturaCtrl/WartoscFaktur) — suma nominalna,
    /// przy fakturach walutowych mieszająca waluty (tak definiuje ją XSD).
    public var invoiceTotal: Double
    /// Liczba wierszy faktur (FakturaWierszCtrl/LiczbaWierszyFaktur).
    public var lineCount: Int
    /// Suma kolumny P_11 (FakturaWierszCtrl/WartoscWierszyFaktur).
    public var lineTotal: Double
    /// Liczba zamówień faktur zaliczkowych (ZamowienieCtrl/LiczbaZamowien).
    public var orderCount: Int
    /// Suma kolumny WartoscZamowienia (ZamowienieCtrl/WartoscZamowien).
    public var orderTotal: Double
    /// Waluty występujące w pliku (informacyjnie dla UI).
    public var currencies: [String]
    public var warnings: [String]
}

/// Generator pliku JPK_FA(4) — jednolity plik kontrolny faktur VAT
/// przekazywany NA ŻĄDANIE organu podatkowego (art. 193a Ordynacji
/// podatkowej). To pełny wykaz WYSTAWIONYCH faktur sprzedaży z pozycjami,
/// nie ewidencja VAT (JPK_V7M/V7K pozostaje osobną strukturą).
///
/// Fakty zweryfikowane u źródła (oficjalny XSD `Schemat_JPK_FA(4)_v1-0.xsd`,
/// gov.pl/web/kas/struktury-jpk, oraz broszura informacyjna MF JPK_FA(4)):
/// - struktura obejmuje WYŁĄCZNIE faktury sprzedaży podatnika; faktury
///   VAT RR mają osobną strukturę (JPK_FA_RR) i są pomijane,
/// - samofaktury wystawione przez nas w imieniu dostawcy trafiają do
///   JPK_FA DOSTAWCY (to jego sprzedaż) — pomijane; nasza sprzedaż
///   z adnotacją samofakturowania (P_17) wchodzi normalnie,
/// - kwoty w walucie faktury; jedynie kwoty podatku przeliczone na PLN
///   (art. 31a) idą do pól P_14_1W/P_14_2W/P_14_3W,
/// - eksport towarów i WDT → P_13_6 (stawka 0%), transakcje poza
///   terytorium kraju i OSS → P_13_5 (+P_14_5, w wierszu P_12_XII),
/// - faktury zaliczkowe (ZAL) i korekty zaliczkowych: kwoty sekcji Faktura
///   dotyczą zaliczki, pozycje idą do węzła Zamowienie (bez FakturaWiersz),
/// - faktury rozliczające (ROZ, art. 106f ust. 3) prezentuje się jak VAT,
///   z numerami wcześniejszych faktur zaliczkowych w NrFaZaliczkowej,
/// - JPK na żądanie nie podlega korekcie — CelZlozenia zawsze 1.
public enum JPKFAGenerator {

    /// Namespace oficjalnej schemy JPK_FA(4) (obowiązuje od 1.04.2022).
    public static let namespace = "http://jpk.mf.gov.pl/wzor/2022/02/17/02171/"

    /// Stawki dopuszczone w polu P_12 wiersza (enum XSD).
    static let allowedP12 = ["23", "22", "8", "7", "5", "4", "3", "0", "zw", "oo", "np"]

    /// Kody krajów UE dopuszczone w P_4A/P_5A (enum TKodyKrajowUE z XSD —
    /// zawiera też GB oraz XI; Grecja występuje wyłącznie jako EL).
    static let euPrefixes: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "EL",
        "HR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT",
        "RO", "SK", "SI", "ES", "SE", "GB", "XI",
    ]

    /// Sumy jednej faktury per pola P_13_x/P_14_x (w walucie faktury).
    struct RateBuckets {
        var net23 = 0.0; var vat23 = 0.0      // P_13_1 / P_14_1
        var net8 = 0.0; var vat8 = 0.0        // P_13_2 / P_14_2
        var net5 = 0.0; var vat5 = 0.0        // P_13_3 / P_14_3
        var netOSS = 0.0; var vatOSS = 0.0    // P_13_5 / P_14_5
        var net0 = 0.0                        // P_13_6
        var netExempt = 0.0                   // P_13_7
    }

    /// Generuje plik JPK_FA(4) dla faktur sprzedaży wystawionych we
    /// wskazanym zakresie dat. Faktury ukryte, zakupy (w tym samofaktury
    /// i VAT RR wystawione przez nas jako nabywcę) są pomijane.
    public static func generate(
        invoices: [Invoice],
        options: JPKFAOptions,
        generatedAt: Date = .now
    ) -> JPKFAResult {
        var warnings: [String] = []

        let selected = invoices
            .filter { qualifies($0, options: options) }
            .sorted {
                $0.issueDate != $1.issueDate
                    ? $0.issueDate < $1.issueDate
                    : $0.invoiceNumber < $1.invoiceNumber
            }

        var invoiceRows = ""
        var lineRows = ""
        var orderRows = ""
        var invoiceTotal = 0.0
        var lineCount = 0
        var lineTotal = 0.0
        var orderCount = 0
        var orderTotal = 0.0
        var currencies: Set<String> = []

        for invoice in selected {
            currencies.insert(invoice.currency)
            invoiceTotal += invoice.grossAmount
            invoiceRows += invoiceElement(invoice, warnings: &warnings)
            if isAdvanceLike(invoice) {
                // Pozycje faktury zaliczkowej (i korekty zaliczkowej) idą
                // do węzła Zamowienie — bez wierszy FakturaWiersz (broszura
                // MF, pyt. 12 i 14).
                orderRows += orderElement(invoice, warnings: &warnings)
                orderCount += 1
                orderTotal += invoice.grossAmount
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): wartość zamówienia przyjęta z kwot dokumentu zaliczkowego — zweryfikuj, jeśli zamówienie lub umowa opiewa na kwotę wyższą niż zaliczka."
                )
            } else {
                for line in invoice.sortedLines {
                    lineRows += lineElement(line, invoice: invoice, warnings: &warnings)
                    lineCount += 1
                    lineTotal += line.netAmount
                }
                if invoice.sortedLines.isEmpty {
                    warnings.append(
                        "Faktura \(invoice.invoiceNumber): brak pozycji — sekcja FakturaWiersz nie zawiera wierszy tej faktury."
                    )
                }
            }
        }

        if selected.isEmpty {
            warnings.append(
                "Brak faktur sprzedaży wystawionych we wskazanym okresie — plik JPK_FA wymaga co najmniej jednej faktury (XSD)."
            )
        } else if lineCount == 0 {
            warnings.append(
                "Plik nie zawiera żadnego wiersza FakturaWiersz — schema JPK_FA(4) wymaga co najmniej jednego wiersza; plik w tej postaci nie przejdzie walidacji XSD."
            )
        }
        if currencies.count > 1 {
            warnings.append(
                "Plik zawiera faktury w walutach: \(currencies.sorted().joined(separator: ", ")) — sumy kontrolne są sumami nominalnymi kwot w walutach dokumentów (tak definiuje je struktura)."
            )
        }

        var ordersBlock = ""
        if orderCount > 0 {
            ordersBlock = orderRows + """
              <ZamowienieCtrl>
                <LiczbaZamowien>\(orderCount)</LiczbaZamowien>
                <WartoscZamowien>\(amount(orderTotal))</WartoscZamowien>
              </ZamowienieCtrl>

            """
        }

        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <JPK xmlns="\(namespace)" xmlns:etd="http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2018/08/24/eD/DefinicjeTypy/">
          <Naglowek>
            <KodFormularza kodSystemowy="JPK_FA (4)" wersjaSchemy="1-0">JPK_FA</KodFormularza>
            <WariantFormularza>4</WariantFormularza>
            <CelZlozenia>1</CelZlozenia>
            <DataWytworzeniaJPK>\(timestamp)</DataWytworzeniaJPK>
            <DataOd>\(day(options.dateFrom))</DataOd>
            <DataDo>\(day(options.dateTo))</DataDo>
            <KodUrzedu>\(escape(options.taxOfficeCode.filter(\.isNumber)))</KodUrzedu>
          </Naglowek>
          <Podmiot1>
            <IdentyfikatorPodmiotu>
              <NIP>\(escape(options.sellerNIP.filter(\.isNumber)))</NIP>
              <PelnaNazwa>\(escape(clip(options.sellerName, max: 240)))</PelnaNazwa>
            </IdentyfikatorPodmiotu>
            <AdresPodmiotu>
              <etd:KodKraju>PL</etd:KodKraju>
              <etd:Wojewodztwo>\(escape(clip(options.wojewodztwo, max: 36)))</etd:Wojewodztwo>
              <etd:Powiat>\(escape(clip(options.powiat, max: 36)))</etd:Powiat>
              <etd:Gmina>\(escape(clip(options.gmina, max: 36)))</etd:Gmina>
        \(optionalElement("etd:Ulica", options.ulica, max: 65, indent: "      "))      <etd:NrDomu>\(escape(clip(options.nrDomu, max: 9)))</etd:NrDomu>
        \(optionalElement("etd:NrLokalu", options.nrLokalu, max: 10, indent: "      "))      <etd:Miejscowosc>\(escape(clip(options.miejscowosc, max: 56)))</etd:Miejscowosc>
              <etd:KodPocztowy>\(escape(clip(options.kodPocztowy, max: 8)))</etd:KodPocztowy>
            </AdresPodmiotu>
          </Podmiot1>
        \(invoiceRows)  <FakturaCtrl>
            <LiczbaFaktur>\(selected.count)</LiczbaFaktur>
            <WartoscFaktur>\(amount(invoiceTotal))</WartoscFaktur>
          </FakturaCtrl>
        \(lineRows)  <FakturaWierszCtrl>
            <LiczbaWierszyFaktur>\(lineCount)</LiczbaWierszyFaktur>
            <WartoscWierszyFaktur>\(amount(lineTotal))</WartoscWierszyFaktur>
          </FakturaWierszCtrl>
        \(ordersBlock)</JPK>
        """

        return JPKFAResult(
            xml: xml,
            invoiceCount: selected.count,
            invoiceTotal: rounded(invoiceTotal),
            lineCount: lineCount,
            lineTotal: rounded(lineTotal),
            orderCount: orderCount,
            orderTotal: rounded(orderTotal),
            currencies: currencies.sorted(),
            warnings: warnings
        )
    }

    // MARK: Kwalifikacja dokumentów

    /// JPK_FA obejmuje wyłącznie widoczne faktury SPRZEDAŻY wystawione
    /// w okresie (po dacie wystawienia). Zakupy — w tym samofaktury
    /// i VAT RR wystawione przez nas jako nabywcę — należą do JPK_FA
    /// (lub JPK_FA_RR) dostawcy, nie naszego.
    static func qualifies(_ invoice: Invoice, options: JPKFAOptions) -> Bool {
        guard invoice.kind == .sales, !invoice.isArchivedOrHidden, !invoice.isRR else {
            return false
        }
        return inRange(invoice.issueDate, from: options.dateFrom, to: options.dateTo)
    }

    /// Porównanie po dniach kalendarzowych — obie granice włącznie.
    static func inRange(_ date: Date, from: Date, to: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: from) && day <= calendar.startOfDay(for: to)
    }

    /// Dokumenty, których pozycje prezentuje się w węźle Zamowienie
    /// zamiast FakturaWiersz: faktura zaliczkowa i korekta zaliczkowej.
    static func isAdvanceLike(_ invoice: Invoice) -> Bool {
        invoice.documentTypeRaw == "ZAL" || invoice.documentTypeRaw == "KOR_ZAL"
    }

    /// Mapowanie rodzaju dokumentu aplikacji na RodzajFaktury (VAT/KOREKTA/ZAL).
    /// ROZ (art. 106f ust. 3) i UPR prezentuje się jako "VAT" (broszura MF).
    static func documentKind(_ invoice: Invoice) -> String {
        if invoice.isCorrection { return "KOREKTA" }
        if invoice.documentTypeRaw == "ZAL" { return "ZAL" }
        return "VAT"
    }

    // MARK: Sekcja Faktura

    /// Rozkłada pozycje na pola P_13_x/P_14_x w walucie faktury.
    static func rateBuckets(for invoice: Invoice, warnings: inout [String]) -> RateBuckets {
        var buckets = RateBuckets()
        if invoice.sortedLines.isEmpty {
            buckets.net23 = invoice.netAmount
            buckets.vat23 = invoice.vatAmount
            warnings.append(
                "Faktura \(invoice.invoiceNumber): brak pozycji — kwoty wykazane w całości jako stawka podstawowa (P_13_1/P_14_1)."
            )
            return buckets
        }
        for line in invoice.sortedLines {
            if line.ossRate != nil {
                buckets.netOSS += line.netAmount
                buckets.vatOSS += line.vatAmount
                continue
            }
            switch VATRate(rawValue: line.vatRate) {
            case .standard:
                buckets.net23 += line.netAmount; buckets.vat23 += line.vatAmount
            case .reducedFirst:
                buckets.net8 += line.netAmount; buckets.vat8 += line.vatAmount
            case .reducedSecond:
                buckets.net5 += line.netAmount; buckets.vat5 += line.vatAmount
            case .zero:
                buckets.net0 += line.netAmount
            case .exempt:
                buckets.netExempt += line.netAmount
            case .rr, .rrHistorical:
                // Stawki zryczałtowanego zwrotu nie występują na fakturze
                // sprzedażowej FA(3) — defensywnie jako stawka obniżona
                // pierwsza (7% to historyczna stawka obniżona w schemie).
                buckets.net8 += line.netAmount; buckets.vat8 += line.vatAmount
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): stawka VAT RR (\(line.vatRate)%) na dokumencie sprzedażowym wykazana jako stawka obniżona pierwsza."
                )
            case nil:
                buckets.net23 += line.netAmount; buckets.vat23 += line.vatAmount
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): nieznana stawka „\(line.vatRate)” wykazana jako podstawowa."
                )
            }
        }
        return buckets
    }

    static func invoiceElement(_ invoice: Invoice, warnings: inout [String]) -> String {
        let buckets = rateBuckets(for: invoice, warnings: &warnings)
        // Kwoty podatku przeliczone na PLN (art. 31a) — tylko waluta obca
        // ze znanym kursem.
        let foreign = invoice.currency != "PLN"
        let hasRate = invoice.exchangeRate > 0
        if foreign && !hasRate {
            warnings.append(
                "Faktura \(invoice.invoiceNumber): waluta \(invoice.currency) bez kursu — pominięto pola podatku przeliczonego na złote (P_14_xW)."
            )
        }
        let emitW = foreign && hasRate

        var xml = "  <Faktura>\n"
        xml += "    <KodWaluty>\(escape(invoice.currency))</KodWaluty>\n"
        xml += "    <P_1>\(day(invoice.issueDate))</P_1>\n"
        xml += "    <P_2A>\(escape(clip(invoice.invoiceNumber, max: 256)))</P_2A>\n"
        if !invoice.buyerName.isEmpty {
            xml += "    <P_3A>\(escape(clip(invoice.buyerName, max: 256)))</P_3A>\n"
        }
        if !invoice.buyerAddress.isEmpty {
            xml += "    <P_3B>\(escape(clip(invoice.buyerAddress, max: 256)))</P_3B>\n"
        }
        xml += "    <P_3C>\(escape(clip(sellerName(invoice, warnings: &warnings), max: 256)))</P_3C>\n"
        xml += "    <P_3D>\(escape(clip(sellerAddress(invoice, warnings: &warnings), max: 256)))</P_3D>\n"
        let seller = taxIdentifier(invoice.sellerNIP)
        if let prefix = seller.prefix {
            xml += "    <P_4A>\(prefix)</P_4A>\n"
        }
        if let number = seller.number {
            xml += "    <P_4B>\(escape(number))</P_4B>\n"
        }
        let buyer = taxIdentifier(invoice.buyerNIP)
        if let prefix = buyer.prefix {
            xml += "    <P_5A>\(prefix)</P_5A>\n"
        }
        if let number = buyer.number {
            xml += "    <P_5B>\(escape(number))</P_5B>\n"
        }
        if let saleDate = invoice.saleDate,
           !Calendar.current.isDate(saleDate, inSameDayAs: invoice.issueDate) {
            xml += "    <P_6>\(day(saleDate))</P_6>\n"
        }
        if buckets.net23 != 0 || buckets.vat23 != 0 {
            xml += "    <P_13_1>\(amount(buckets.net23))</P_13_1>\n"
            xml += "    <P_14_1>\(amount(buckets.vat23))</P_14_1>\n"
            if emitW {
                xml += "    <P_14_1W>\(amount(buckets.vat23 * invoice.exchangeRate))</P_14_1W>\n"
            }
        }
        if buckets.net8 != 0 || buckets.vat8 != 0 {
            xml += "    <P_13_2>\(amount(buckets.net8))</P_13_2>\n"
            xml += "    <P_14_2>\(amount(buckets.vat8))</P_14_2>\n"
            if emitW {
                xml += "    <P_14_2W>\(amount(buckets.vat8 * invoice.exchangeRate))</P_14_2W>\n"
            }
        }
        if buckets.net5 != 0 || buckets.vat5 != 0 {
            xml += "    <P_13_3>\(amount(buckets.net5))</P_13_3>\n"
            xml += "    <P_14_3>\(amount(buckets.vat5))</P_14_3>\n"
            if emitW {
                xml += "    <P_14_3W>\(amount(buckets.vat5 * invoice.exchangeRate))</P_14_3W>\n"
            }
        }
        if buckets.netOSS != 0 || buckets.vatOSS != 0 {
            xml += "    <P_13_5>\(amount(buckets.netOSS))</P_13_5>\n"
            xml += "    <P_14_5>\(amount(buckets.vatOSS))</P_14_5>\n"
        }
        if buckets.net0 != 0 {
            xml += "    <P_13_6>\(amount(buckets.net0))</P_13_6>\n"
        }
        if buckets.netExempt != 0 {
            xml += "    <P_13_7>\(amount(buckets.netExempt))</P_13_7>\n"
        }
        xml += "    <P_15>\(amount(invoice.grossAmount))</P_15>\n"
        // Znaczniki: metoda kasowa (P_16) i odwrotne obciążenie (P_18) nie
        // są modelowane w aplikacji — zawsze false, jak w generatorze FA(3).
        xml += "    <P_16>false</P_16>\n"
        xml += "    <P_17>\(invoice.isSelfInvoicing ? "true" : "false")</P_17>\n"
        xml += "    <P_18>false</P_18>\n"
        xml += "    <P_18A>\(invoice.splitPayment ? "true" : "false")</P_18A>\n"
        let exempt = buckets.netExempt != 0
        xml += "    <P_19>\(exempt ? "true" : "false")</P_19>\n"
        if exempt {
            warnings.append(
                "Faktura \(invoice.invoiceNumber): sprzedaż zwolniona — aplikacja nie przechowuje podstawy zwolnienia, pola P_19A–P_19C pozostały puste (uzupełnij na wezwanie organu, jeśli wymagane)."
            )
        }
        xml += "    <P_20>false</P_20>\n"
        xml += "    <P_21>false</P_21>\n"
        xml += "    <P_22>false</P_22>\n"
        xml += "    <P_23>false</P_23>\n"
        // Procedury marży: "2" — biura podróży, "3_1/3_2/3_3" — towary
        // używane / dzieła sztuki / antyki (te same kody co FA(3)/JPK_V7).
        let travelMargin = invoice.marginProcedureRaw == "2"
        let usedGoodsMargin = ["3_1", "3_2", "3_3"].contains(invoice.marginProcedureRaw)
        xml += "    <P_106E_2>\(travelMargin ? "true" : "false")</P_106E_2>\n"
        xml += "    <P_106E_3>\(usedGoodsMargin ? "true" : "false")</P_106E_3>\n"
        if usedGoodsMargin {
            xml += "    <P_106E_3A>\(marginLabel(invoice.marginProcedureRaw))</P_106E_3A>\n"
        }
        xml += "    <RodzajFaktury>\(documentKind(invoice))</RodzajFaktury>\n"
        if invoice.isCorrection {
            if let corrected = invoice.correctedInvoiceNumber, !corrected.isEmpty {
                if let reason = invoice.correctionReason, !reason.isEmpty {
                    xml += "    <PrzyczynaKorekty>\(escape(clip(reason, max: 256)))</PrzyczynaKorekty>\n"
                }
                xml += "    <NrFaKorygowanej>\(escape(clip(corrected, max: 256)))</NrFaKorygowanej>\n"
            } else {
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): korekta bez numeru faktury korygowanej — pominięto pola korekty (NrFaKorygowanej)."
                )
            }
        }
        // Numery wcześniejszych faktur zaliczkowych (ROZ i korekta ROZ).
        let advanceRefs = invoice.advanceInvoiceRefs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !advanceRefs.isEmpty {
            let joined = advanceRefs.joined(separator: ", ")
            if joined.count > 256 {
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): lista faktur zaliczkowych przekracza 256 znaków — obcięta w polu NrFaZaliczkowej."
                )
            }
            xml += "    <NrFaZaliczkowej>\(escape(clip(joined, max: 256)))</NrFaZaliczkowej>\n"
        }
        xml += "  </Faktura>\n"
        return xml
    }

    /// Nazwa sprzedawcy — pole wymagane (P_3C); pusta wartość zastępowana
    /// znacznikiem BRAK z ostrzeżeniem (praktyka jak w JPK_V7).
    static func sellerName(_ invoice: Invoice, warnings: inout [String]) -> String {
        guard invoice.sellerName.isEmpty else { return invoice.sellerName }
        warnings.append("Faktura \(invoice.invoiceNumber): brak nazwy sprzedawcy — wpisano „BRAK”.")
        return "BRAK"
    }

    /// Adres sprzedawcy — pole wymagane (P_3D); pusta wartość zastępowana
    /// znacznikiem BRAK z ostrzeżeniem.
    static func sellerAddress(_ invoice: Invoice, warnings: inout [String]) -> String {
        guard invoice.sellerAddress.isEmpty else { return invoice.sellerAddress }
        warnings.append(
            "Faktura \(invoice.invoiceNumber): brak adresu sprzedawcy — wpisano „BRAK” (uzupełnij adres w dokumencie lub Ustawieniach)."
        )
        return "BRAK"
    }

    /// Rozbiór identyfikatora podatkowego: prefiks UE (P_4A/P_5A) +
    /// numer (P_4B/P_5B). Polski NIP zostaje samymi cyframi bez prefiksu;
    /// pusty identyfikator pomija oba pola (dozwolone przez XSD).
    static func taxIdentifier(_ raw: String) -> (prefix: String?, number: String?) {
        let cleaned = raw.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard !cleaned.isEmpty else { return (nil, nil) }
        let upper = cleaned.uppercased()
        var prefix = String(upper.prefix(2))
        if prefix == "GR" { prefix = "EL" }
        if prefix.allSatisfy(\.isLetter), euPrefixes.contains(prefix) {
            let number = String(upper.dropFirst(2))
            guard !number.isEmpty else { return (nil, nil) }
            // Polski numer prezentujemy bez prefiksu (jak krajowy NIP).
            return prefix == "PL" ? (nil, number) : (prefix, number)
        }
        return (nil, cleaned)
    }

    /// Adnotacja procedury marży dla P_106E_3A (art. 120 ust. 4 i 5).
    static func marginLabel(_ raw: String) -> String {
        switch raw {
        case "3_1": return "procedura marży - towary używane"
        case "3_2": return "procedura marży - dzieła sztuki"
        case "3_3": return "procedura marży - przedmioty kolekcjonerskie i antyki"
        default: return ""
        }
    }

    // MARK: Sekcja FakturaWiersz

    static func lineElement(
        _ line: InvoiceLine,
        invoice: Invoice,
        warnings: inout [String]
    ) -> String {
        var xml = "  <FakturaWiersz>\n"
        xml += "    <P_2B>\(escape(clip(invoice.invoiceNumber, max: 256)))</P_2B>\n"
        if !line.name.isEmpty {
            xml += "    <P_7>\(escape(clip(line.name, max: 256)))</P_7>\n"
        }
        if !line.unit.isEmpty {
            xml += "    <P_8A>\(escape(clip(line.unit, max: 256)))</P_8A>\n"
        }
        xml += "    <P_8B>\(quantity(line.quantity))</P_8B>\n"
        xml += "    <P_9A>\(amount(line.unitNetPrice))</P_9A>\n"
        xml += "    <P_11>\(amount(line.netAmount))</P_11>\n"
        if let ossRate = line.ossRate {
            // Pozycja OSS: stawka państwa konsumpcji w P_12_XII zamiast P_12.
            xml += "    <P_12_XII>\(percent(ossRate))</P_12_XII>\n"
        } else if allowedP12.contains(line.vatRate) {
            xml += "    <P_12>\(line.vatRate)</P_12>\n"
        } else {
            warnings.append(
                "Faktura \(invoice.invoiceNumber), pozycja „\(line.name)”: stawka „\(line.vatRate)” spoza słownika P_12 — pole stawki w wierszu pominięto."
            )
        }
        xml += "  </FakturaWiersz>\n"
        return xml
    }

    // MARK: Sekcja Zamowienie (faktury zaliczkowe)

    static func orderElement(_ invoice: Invoice, warnings: inout [String]) -> String {
        var xml = "  <Zamowienie>\n"
        xml += "    <P_2AZ>\(escape(clip(invoice.invoiceNumber, max: 256)))</P_2AZ>\n"
        xml += "    <WartoscZamowienia>\(amount(invoice.grossAmount))</WartoscZamowienia>\n"
        if invoice.sortedLines.isEmpty {
            // XSD wymaga co najmniej jednego wiersza zamówienia — dokument
            // bez pozycji dostaje wiersz z samymi kwotami.
            xml += "    <ZamowienieWiersz>\n"
            xml += "      <P_11NettoZ>\(amount(invoice.netAmount))</P_11NettoZ>\n"
            xml += "      <P_11VatZ>\(amount(invoice.vatAmount))</P_11VatZ>\n"
            xml += "    </ZamowienieWiersz>\n"
            warnings.append(
                "Faktura \(invoice.invoiceNumber): dokument zaliczkowy bez pozycji — zamówienie zawiera wyłącznie kwoty łączne."
            )
        }
        for line in invoice.sortedLines {
            xml += "    <ZamowienieWiersz>\n"
            if !line.name.isEmpty {
                xml += "      <P_7Z>\(escape(clip(line.name, max: 256)))</P_7Z>\n"
            }
            if !line.unit.isEmpty {
                xml += "      <P_8AZ>\(escape(clip(line.unit, max: 256)))</P_8AZ>\n"
            }
            xml += "      <P_8BZ>\(quantity(line.quantity))</P_8BZ>\n"
            xml += "      <P_9AZ>\(amount(line.unitNetPrice))</P_9AZ>\n"
            xml += "      <P_11NettoZ>\(amount(line.netAmount))</P_11NettoZ>\n"
            xml += "      <P_11VatZ>\(amount(line.vatAmount))</P_11VatZ>\n"
            if let ossRate = line.ossRate {
                xml += "      <P_12Z_XII>\(percent(ossRate))</P_12Z_XII>\n"
            } else if allowedP12.contains(line.vatRate) {
                xml += "      <P_12Z>\(line.vatRate)</P_12Z>\n"
            } else {
                warnings.append(
                    "Faktura \(invoice.invoiceNumber), pozycja „\(line.name)”: stawka „\(line.vatRate)” spoza słownika P_12Z — pole stawki w zamówieniu pominięto."
                )
            }
            xml += "    </ZamowienieWiersz>\n"
        }
        xml += "  </Zamowienie>\n"
        return xml
    }

    // MARK: Pomocnicze

    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Kwota (TKwotowy) — dwa miejsca po przecinku, znak zachowany (korekty).
    static func amount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Ilość (TIlosciJPK) — do 6 miejsc po przecinku, bez zbędnych zer.
    static func quantity(_ value: Double) -> String {
        trimmedDecimal(String(format: "%.6f", value))
    }

    /// Stawka procentowa (TProcentowy) — do 6 miejsc po przecinku.
    static func percent(_ value: Double) -> String {
        trimmedDecimal(String(format: "%.6f", value))
    }

    static func trimmedDecimal(_ formatted: String) -> String {
        var result = formatted
        while result.contains("."), result.hasSuffix("0") {
            result.removeLast()
        }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    /// Przycięcie do limitu typu znakowego XSD (TZnakowyJPK i pokrewne).
    static func clip(_ value: String, max: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > max ? String(trimmed.prefix(max)) : trimmed
    }

    /// Element opcjonalny emitowany tylko dla niepustej wartości.
    static func optionalElement(_ name: String, _ value: String, max: Int, indent: String) -> String {
        let clipped = clip(value, max: max)
        guard !clipped.isEmpty else { return "" }
        return "\(indent)<\(name)>\(escape(clipped))</\(name)>\n"
    }

    static func day(_ date: Date) -> String {
        FA2Format.dateFormatter.string(from: date)
    }

    static func escape(_ value: String) -> String {
        FA2XMLGenerator.escape(value)
    }
}
