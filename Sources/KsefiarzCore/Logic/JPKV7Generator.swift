import Foundation

/// Parametry generowania pliku JPK_V7M.
public struct JPKV7Options: Sendable {
    public var year: Int
    public var month: Int
    /// Dane podatnika (Podmiot1/OsobaNiefizyczna).
    public var sellerNIP: String
    public var sellerName: String
    public var email: String
    /// Czterocyfrowy kod urzędu skarbowego (KodUrzedu).
    public var taxOfficeCode: String
    /// Cel złożenia: 1 = złożenie, 2 = korekta.
    public var purpose: Int = 1
    /// Nadwyżka podatku naliczonego z poprzedniej deklaracji (P_39, całe zł).
    public var previousExcess: Int = 0
    /// Czy dołączyć część deklaracyjną (VAT-7) — korekta samej ewidencji
    /// składana jest bez deklaracji.
    public var includeDeclaration: Bool = true

    public init(
        year: Int,
        month: Int,
        sellerNIP: String,
        sellerName: String,
        email: String,
        taxOfficeCode: String,
        purpose: Int = 1,
        previousExcess: Int = 0,
        includeDeclaration: Bool = true
    ) {
        self.year = year
        self.month = month
        self.sellerNIP = sellerNIP
        self.sellerName = sellerName
        self.email = email
        self.taxOfficeCode = taxOfficeCode
        self.purpose = purpose
        self.previousExcess = previousExcess
        self.includeDeclaration = includeDeclaration
    }
}

/// Wynik generowania: dokument XML + podsumowanie i ostrzeżenia
/// (uproszczenia wymagające weryfikacji przed wysyłką do MF).
public struct JPKV7Result: Sendable {
    public var xml: String
    public var salesCount: Int
    public var purchaseCount: Int
    /// Podstawa opodatkowania łącznie (sprzedaż, PLN).
    public var salesNetTotal: Double
    /// Podatek należny (SprzedazCtrl/PodatekNalezny).
    public var outputVAT: Double
    /// Podatek naliczony (ZakupCtrl/PodatekNaliczony).
    public var inputVAT: Double
    /// Kwota do wpłaty (P_51) / nadwyżka do przeniesienia (P_62) — po zaokrągleniach.
    public var amountDue: Int
    public var excessCarried: Int
    public var warnings: [String]
}

/// Generator pliku JPK_V7M(2) — ewidencja VAT (sprzedaż + zakup)
/// z oznaczeniami GTU i procedur oraz częścią deklaracyjną VAT-7(22).
/// Struktura zgodna z oficjalną XSD `http://crd.gov.pl/wzor/2021/12/27/11148/`.
///
/// Przyjęte uproszczenia (raportowane w `warnings`):
/// - przypisanie do okresu po dacie sprzedaży (P_6) lub wystawienia,
/// - zakupy w całości jako „pozostałe nabycia” (K_42/K_43),
/// - pozycje OSS (P_12_XII) pominięte — rozliczane w procedurze unijnej OSS,
/// - faktury bez pozycji traktowane jak sprzedaż ze stawką podstawową.
public enum JPKV7Generator {

    public static let namespace = "http://crd.gov.pl/wzor/2021/12/27/11148/"

    /// Sumy sprzedaży jednej faktury per pole ewidencji (w PLN).
    struct SalesBuckets {
        var k10 = 0.0   // zwolnione
        var k13 = 0.0   // stawka 0%
        var k15 = 0.0; var k16 = 0.0   // 5% netto / VAT
        var k17 = 0.0; var k18 = 0.0   // 8%
        var k19 = 0.0; var k20 = 0.0   // 23%
        var gtu: Set<String> = []
        var procedures: Set<String> = []
        var skippedOSS = false

        var net: Double { k10 + k13 + k15 + k17 + k19 }
        var vat: Double { k16 + k18 + k20 }
        var isEmpty: Bool { net == 0 && vat == 0 }
    }

    /// Kolejność znaczników GTU i procedur zgodna z sekwencją XSD.
    static let gtuCodes = (1...13).map { String(format: "GTU_%02d", $0) }
    static let procedureCodes = [
        "WSTO_EE", "IED", "TP", "TT_WNT", "TT_D", "MR_T", "MR_UZ",
        "I_42", "I_63", "B_SPV", "B_SPV_DOSTAWA", "B_MPV_PROWIZJA",
    ]

    /// Generuje plik JPK_V7M dla wskazanego miesiąca.
    /// Faktury ukryte są pomijane; korekty wchodzą kwotami różnicy (ujemne
    /// wartości dozwolone w ewidencji).
    public static func generate(
        invoices: [Invoice],
        options: JPKV7Options,
        generatedAt: Date = .now
    ) -> JPKV7Result {
        var warnings: [String] = []
        let visible = invoices.filter { !$0.isArchivedOrHidden }
        let sales = visible
            .filter { $0.kind == .sales && inPeriod($0, options: options) }
            .sorted { periodDate($0) < periodDate($1) }
        let purchases = visible
            .filter { $0.kind == .purchase && inPeriod($0, options: options) }
            .sorted { periodDate($0) < periodDate($1) }

        // Ewidencja sprzedaży.
        var salesRows = ""
        var salesVATTotal = 0.0
        var salesNetTotal = 0.0
        for (offset, invoice) in sales.enumerated() {
            let buckets = salesBuckets(for: invoice, warnings: &warnings)
            if buckets.skippedOSS {
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): pozycje OSS pominięte w JPK (podatek rozliczany w procedurze unijnej OSS)."
                )
            }
            salesVATTotal += buckets.vat
            salesNetTotal += buckets.net
            salesRows += salesRow(invoice: invoice, buckets: buckets, index: offset + 1, warnings: &warnings)
        }

        // Ewidencja zakupów — całość jako pozostałe nabycia (K_42/K_43).
        var purchaseRows = ""
        var purchasesNetTotal = 0.0
        var purchasesVATTotal = 0.0
        for (offset, invoice) in purchases.enumerated() {
            let net = amountInPLN(invoice.netAmount, invoice: invoice, warnings: &warnings)
            let vat = amountInPLN(invoice.vatAmount, invoice: invoice, warnings: &warnings)
            purchasesNetTotal += net
            purchasesVATTotal += vat
            purchaseRows += purchaseRow(
                invoice: invoice, net: net, vat: vat, index: offset + 1, warnings: &warnings
            )
        }

        // Część deklaracyjna (VAT-7) — kwoty w pełnych złotych.
        let declaration = options.includeDeclaration
            ? declarationBlock(
                sales: sales,
                purchasesNet: purchasesNetTotal,
                purchasesVAT: purchasesVATTotal,
                options: options,
                warnings: &warnings
            )
            : (xml: "", due: 0, carried: 0)

        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <JPK xmlns="\(namespace)">
          <Naglowek>
            <KodFormularza kodSystemowy="JPK_V7M (2)" wersjaSchemy="1-0E">JPK_VAT</KodFormularza>
            <WariantFormularza>2</WariantFormularza>
            <DataWytworzeniaJPK>\(timestamp)</DataWytworzeniaJPK>
            <NazwaSystemu>Ksefiarz macOS</NazwaSystemu>
            <CelZlozenia poz="P_7">\(options.purpose)</CelZlozenia>
            <KodUrzedu>\(escape(options.taxOfficeCode))</KodUrzedu>
            <Rok>\(options.year)</Rok>
            <Miesiac>\(options.month)</Miesiac>
          </Naglowek>
          <Podmiot1 rola="Podatnik">
            <OsobaNiefizyczna>
              <NIP>\(escape(options.sellerNIP.filter(\.isNumber)))</NIP>
              <PelnaNazwa>\(escape(options.sellerName))</PelnaNazwa>
              <Email>\(escape(options.email))</Email>
            </OsobaNiefizyczna>
          </Podmiot1>
        \(declaration.xml)  <Ewidencja>
        \(salesRows)    <SprzedazCtrl>
              <LiczbaWierszySprzedazy>\(sales.count)</LiczbaWierszySprzedazy>
              <PodatekNalezny>\(amount(salesVATTotal))</PodatekNalezny>
            </SprzedazCtrl>
        \(purchaseRows)    <ZakupCtrl>
              <LiczbaWierszyZakupow>\(purchases.count)</LiczbaWierszyZakupow>
              <PodatekNaliczony>\(amount(purchasesVATTotal))</PodatekNaliczony>
            </ZakupCtrl>
          </Ewidencja>
        </JPK>
        """
        return JPKV7Result(
            xml: xml,
            salesCount: sales.count,
            purchaseCount: purchases.count,
            salesNetTotal: rounded(salesNetTotal),
            outputVAT: rounded(salesVATTotal),
            inputVAT: rounded(purchasesVATTotal),
            amountDue: declaration.due,
            excessCarried: declaration.carried,
            warnings: warnings
        )
    }

    // MARK: Przypisanie do okresu

    /// Data decydująca o okresie: data sprzedaży (P_6), a bez niej data
    /// wystawienia — uproszczenie względem pełnych reguł obowiązku
    /// podatkowego i prawa do odliczenia.
    static func periodDate(_ invoice: Invoice) -> Date {
        invoice.saleDate ?? invoice.issueDate
    }

    static func inPeriod(_ invoice: Invoice, options: JPKV7Options) -> Bool {
        let components = Calendar.current.dateComponents([.year, .month], from: periodDate(invoice))
        return components.year == options.year && components.month == options.month
    }

    // MARK: Sprzedaż

    /// Rozkłada fakturę sprzedażową na pola K per stawka; zbiera GTU
    /// i oznaczenia procedur z pozycji.
    static func salesBuckets(for invoice: Invoice, warnings: inout [String]) -> SalesBuckets {
        var buckets = SalesBuckets()

        if invoice.sortedLines.isEmpty {
            // Tryb uproszczony bez pozycji — całość jak stawka podstawowa.
            buckets.k19 = amountInPLN(invoice.netAmount, invoice: invoice, warnings: &warnings)
            buckets.k20 = amountInPLN(invoice.vatAmount, invoice: invoice, warnings: &warnings)
            warnings.append(
                "Faktura \(invoice.invoiceNumber): brak pozycji — całość wykazana jako stawka podstawowa (K_19/K_20)."
            )
        }

        for line in invoice.sortedLines {
            if line.ossRate != nil {
                buckets.skippedOSS = true
                continue
            }
            let net = amountInPLN(line.netAmount, invoice: invoice, warnings: &warnings)
            let vat = amountInPLN(line.vatAmount, invoice: invoice, warnings: &warnings)
            switch VATRate(rawValue: line.vatRate) {
            case .exempt: buckets.k10 += net
            case .zero: buckets.k13 += net
            case .reducedSecond: buckets.k15 += net; buckets.k16 += vat
            case .reducedFirst: buckets.k17 += net; buckets.k18 += vat
            case .standard: buckets.k19 += net; buckets.k20 += vat
            case nil:
                buckets.k19 += net; buckets.k20 += vat
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): nieznana stawka „\(line.vatRate)” wykazana jako podstawowa."
                )
            }
            let gtu = line.gtu.trimmingCharacters(in: .whitespaces).uppercased()
            if !gtu.isEmpty {
                let normalized = gtu.hasPrefix("GTU_") ? gtu : "GTU_" + gtu
                if gtuCodes.contains(normalized) { buckets.gtu.insert(normalized) }
            }
            let procedure = line.procedure.trimmingCharacters(in: .whitespaces).uppercased()
            if procedureCodes.contains(procedure) { buckets.procedures.insert(procedure) }
        }

        // Procedura marży → znacznik MR_T / MR_UZ.
        switch invoice.marginProcedureRaw {
        case "2": buckets.procedures.insert("MR_T")
        case "3_1", "3_2", "3_3": buckets.procedures.insert("MR_UZ")
        default: break
        }
        return buckets
    }

    static func salesRow(
        invoice: Invoice,
        buckets: SalesBuckets,
        index: Int,
        warnings: inout [String]
    ) -> String {
        var xml = "    <SprzedazWiersz>\n"
        xml += "      <LpSprzedazy>\(index)</LpSprzedazy>\n"
        xml += "      <NrKontrahenta>\(escape(contractorNIP(invoice.buyerNIP, invoice: invoice, warnings: &warnings)))</NrKontrahenta>\n"
        xml += "      <NazwaKontrahenta>\(escape(invoice.buyerName))</NazwaKontrahenta>\n"
        xml += "      <DowodSprzedazy>\(escape(invoice.invoiceNumber))</DowodSprzedazy>\n"
        xml += "      <DataWystawienia>\(day(invoice.issueDate))</DataWystawienia>\n"
        if let saleDate = invoice.saleDate,
           !Calendar.current.isDate(saleDate, inSameDayAs: invoice.issueDate) {
            xml += "      <DataSprzedazy>\(day(saleDate))</DataSprzedazy>\n"
        }
        // Znaczniki GTU i procedur — kolejność sekwencji XSD.
        for code in gtuCodes where buckets.gtu.contains(code) {
            xml += "      <\(code)>1</\(code)>\n"
        }
        for code in procedureCodes where buckets.procedures.contains(code) {
            xml += "      <\(code)>1</\(code)>\n"
        }
        if buckets.k10 != 0 { xml += "      <K_10>\(amount(buckets.k10))</K_10>\n" }
        if buckets.k13 != 0 { xml += "      <K_13>\(amount(buckets.k13))</K_13>\n" }
        if buckets.k15 != 0 || buckets.k16 != 0 {
            xml += "      <K_15>\(amount(buckets.k15))</K_15>\n"
            xml += "      <K_16>\(amount(buckets.k16))</K_16>\n"
        }
        if buckets.k17 != 0 || buckets.k18 != 0 {
            xml += "      <K_17>\(amount(buckets.k17))</K_17>\n"
            xml += "      <K_18>\(amount(buckets.k18))</K_18>\n"
        }
        if buckets.k19 != 0 || buckets.k20 != 0 {
            xml += "      <K_19>\(amount(buckets.k19))</K_19>\n"
            xml += "      <K_20>\(amount(buckets.k20))</K_20>\n"
        }
        // Procedura marży: dodatkowo wartość sprzedaży brutto.
        if !invoice.marginProcedureRaw.isEmpty {
            let gross = amountInPLN(invoice.grossAmount, invoice: invoice, warnings: &warnings)
            xml += "      <SprzedazVAT_Marza>\(amount(gross))</SprzedazVAT_Marza>\n"
            warnings.append(
                "Faktura \(invoice.invoiceNumber): procedura marży — zweryfikuj podstawę opodatkowania (marżę) przed wysyłką."
            )
        }
        xml += "    </SprzedazWiersz>\n"
        return xml
    }

    // MARK: Zakup

    static func purchaseRow(
        invoice: Invoice,
        net: Double,
        vat: Double,
        index: Int,
        warnings: inout [String]
    ) -> String {
        var xml = "    <ZakupWiersz>\n"
        xml += "      <LpZakupu>\(index)</LpZakupu>\n"
        xml += "      <NrDostawcy>\(escape(contractorNIP(invoice.sellerNIP, invoice: invoice, warnings: &warnings)))</NrDostawcy>\n"
        xml += "      <NazwaDostawcy>\(escape(invoice.sellerName))</NazwaDostawcy>\n"
        xml += "      <DowodZakupu>\(escape(invoice.invoiceNumber))</DowodZakupu>\n"
        xml += "      <DataZakupu>\(day(invoice.issueDate))</DataZakupu>\n"
        xml += "      <K_42>\(amount(net))</K_42>\n"
        xml += "      <K_43>\(amount(vat))</K_43>\n"
        xml += "    </ZakupWiersz>\n"
        return xml
    }

    // MARK: Deklaracja VAT-7

    /// Część deklaracyjna: kwoty w pełnych złotych (TKwotaC), P_51 nieujemna.
    static func declarationBlock(
        sales: [Invoice],
        purchasesNet: Double,
        purchasesVAT: Double,
        options: JPKV7Options,
        warnings: inout [String]
    ) -> (xml: String, due: Int, carried: Int) {
        // Sumy pól K całej ewidencji (przed zaokrągleniem do złotych).
        var total = SalesBuckets()
        for invoice in sales {
            var scratch: [String] = [] // ostrzeżenia już zebrane przy wierszach
            let buckets = salesBuckets(for: invoice, warnings: &scratch)
            total.k10 += buckets.k10; total.k13 += buckets.k13
            total.k15 += buckets.k15; total.k16 += buckets.k16
            total.k17 += buckets.k17; total.k18 += buckets.k18
            total.k19 += buckets.k19; total.k20 += buckets.k20
        }
        let p10 = zl(total.k10)
        let p13 = zl(total.k13)
        let p15 = zl(total.k15); let p16 = zl(total.k16)
        let p17 = zl(total.k17); let p18 = zl(total.k18)
        let p19 = zl(total.k19); let p20 = zl(total.k20)
        let p37 = p10 + p13 + p15 + p17 + p19
        let p38 = p16 + p18 + p20
        let p42 = zl(purchasesNet); let p43 = zl(purchasesVAT)
        let p48 = options.previousExcess + p43
        let due = max(0, p38 - p48)
        let carried = max(0, p48 - p38)

        var positions = ""
        if p10 != 0 { positions += "        <P_10>\(p10)</P_10>\n" }
        // Sekwencja P_11–P_20: elementy wymagane razem (zera dozwolone).
        if p13 != 0 || p15 != 0 || p16 != 0 || p17 != 0 || p18 != 0 || p19 != 0 || p20 != 0 {
            positions += "        <P_11>0</P_11>\n"
            positions += "        <P_13>\(p13)</P_13>\n"
            positions += "        <P_15>\(p15)</P_15>\n"
            positions += "        <P_16>\(p16)</P_16>\n"
            positions += "        <P_17>\(p17)</P_17>\n"
            positions += "        <P_18>\(p18)</P_18>\n"
            positions += "        <P_19>\(p19)</P_19>\n"
            positions += "        <P_20>\(p20)</P_20>\n"
        }
        positions += "        <P_37>\(p37)</P_37>\n"
        positions += "        <P_38>\(p38)</P_38>\n"
        if options.previousExcess != 0 {
            positions += "        <P_39>\(options.previousExcess)</P_39>\n"
        }
        if p42 != 0 || p43 != 0 {
            positions += "        <P_40>0</P_40>\n"
            positions += "        <P_41>0</P_41>\n"
            positions += "        <P_42>\(p42)</P_42>\n"
            positions += "        <P_43>\(p43)</P_43>\n"
        }
        positions += "        <P_48>\(p48)</P_48>\n"
        positions += "        <P_51>\(due)</P_51>\n"
        if carried > 0 {
            positions += "        <P_53>\(carried)</P_53>\n"
            positions += "        <P_62>\(carried)</P_62>\n"
        }

        let xml = """
          <Deklaracja>
            <Naglowek>
              <KodFormularzaDekl kodSystemowy="VAT-7 (22)" kodPodatku="VAT" rodzajZobowiazania="Z" wersjaSchemy="1-0E">VAT-7</KodFormularzaDekl>
              <WariantFormularzaDekl>22</WariantFormularzaDekl>
            </Naglowek>
            <PozycjeSzczegolowe>
        \(positions)    </PozycjeSzczegolowe>
            <Pouczenia>1</Pouczenia>
          </Deklaracja>

        """
        return (xml, due, carried)
    }

    // MARK: Pomocnicze

    /// Kwota w PLN — faktury walutowe po kursie z faktury.
    static func amountInPLN(_ value: Double, invoice: Invoice, warnings: inout [String]) -> Double {
        guard invoice.currency != "PLN" else { return value }
        guard invoice.exchangeRate > 0 else {
            let warning = "Faktura \(invoice.invoiceNumber): waluta \(invoice.currency) bez kursu — kwoty przyjęte nominalnie."
            if !warnings.contains(warning) { warnings.append(warning) }
            return value
        }
        return rounded(value * invoice.exchangeRate)
    }

    /// NIP kontrahenta (same cyfry); brak numeru → "BRAK" (praktyka MF
    /// dla podmiotów bez identyfikatora) z ostrzeżeniem.
    static func contractorNIP(_ nip: String, invoice: Invoice, warnings: inout [String]) -> String {
        let cleaned = nip.filter(\.isNumber)
        guard cleaned.isEmpty else { return cleaned }
        warnings.append("Faktura \(invoice.invoiceNumber): brak NIP kontrahenta — wpisano „BRAK”.")
        return "BRAK"
    }

    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Kwota ewidencji (TKwotowy) — dwa miejsca po przecinku.
    static func amount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Kwota deklaracji (TKwotaC) — pełne złote.
    static func zl(_ value: Double) -> Int {
        Int(value.rounded())
    }

    static func day(_ date: Date) -> String {
        FA2Format.dateFormatter.string(from: date)
    }

    static func escape(_ value: String) -> String {
        FA2XMLGenerator.escape(value)
    }
}
