import Foundation

/// Parametry generowania informacji podsumowującej VAT-UE.
public struct VATUEOptions: Sendable {
    public var year: Int
    public var month: Int
    /// Dane podatnika (Podmiot1/OsobaNiefizyczna).
    public var sellerNIP: String
    public var sellerName: String
    /// Czterocyfrowy kod urzędu skarbowego (KodUrzedu).
    public var taxOfficeCode: String

    public init(
        year: Int,
        month: Int,
        sellerNIP: String,
        sellerName: String,
        taxOfficeCode: String
    ) {
        self.year = year
        self.month = month
        self.sellerNIP = sellerNIP
        self.sellerName = sellerName
        self.taxOfficeCode = taxOfficeCode
    }
}

/// Pojedynczy wiersz informacji podsumowującej: kontrahent UE i wartość
/// transakcji w pełnych złotych.
public struct VATUEEntry: Sendable, Equatable {
    /// Dwuliterowy kod kraju UE (prefiks VAT; Grecja = "EL", Irlandia Płn. = "XI").
    public var countryCode: String
    /// Numer identyfikacyjny VAT-UE kontrahenta bez prefiksu kraju.
    public var vatNumber: String
    /// Wartość transakcji w pełnych złotych.
    public var amountPLN: Int

    public init(countryCode: String, vatNumber: String, amountPLN: Int) {
        self.countryCode = countryCode
        self.vatNumber = vatNumber
        self.amountPLN = amountPLN
    }
}

/// Wynik generowania VAT-UE: dokument XML, zestawienia per część
/// oraz ostrzeżenia (uproszczenia wymagające weryfikacji przed wysyłką).
public struct VATUEResult: Sendable {
    public var xml: String
    /// Część C — wewnątrzwspólnotowe dostawy towarów (WDT).
    public var wdt: [VATUEEntry]
    /// Część D — wewnątrzwspólnotowe nabycia towarów (WNT).
    public var wnt: [VATUEEntry]
    /// Część E — wewnątrzwspólnotowe świadczenie usług.
    public var services: [VATUEEntry]
    public var warnings: [String]

    /// Brak jakichkolwiek transakcji UE w okresie.
    public var isEmpty: Bool { wdt.isEmpty && wnt.isEmpty && services.isEmpty }

    public var totalWDT: Int { wdt.reduce(0) { $0 + $1.amountPLN } }
    public var totalWNT: Int { wnt.reduce(0) { $0 + $1.amountPLN } }
    public var totalServices: Int { services.reduce(0) { $0 + $1.amountPLN } }
}

/// Generator informacji podsumowującej **VAT-UE(5)** — zestawienie transakcji
/// wewnątrzwspólnotowych z danych faktur: WDT (część C), WNT (część D)
/// i świadczenie usług (część E). Struktura zgodna z oficjalną XSD
/// `http://crd.gov.pl/wzor/2021/01/12/10293/`.
///
/// Kwalifikacja transakcji z danych faktury:
/// - kontrahent UE rozpoznawany po prefiksie kraju w numerze VAT (buyerNIP
///   dla sprzedaży, sellerNIP dla zakupu); numery bez prefiksu = krajowe,
///   spoza UE = pomijane;
/// - towar vs usługa z kodu pozycji (CN — same cyfry → towar; PKWiU
///   z kropkami → usługa; brak kodu → domyślnie towar z ostrzeżeniem);
/// - kwoty w pełnych złotych (TKwotaC), sumowane per kontrahent.
///
/// Świadome uproszczenia i wyłączenia (raportowane w `warnings`):
/// - import usług (zakup usług od kontrahenta UE) NIE jest wykazywany
///   w VAT-UE — trafia tylko do JPK_V7;
/// - sprzedaż w procedurze OSS nie jest wykazywana w VAT-UE;
/// - część F (przemieszczenia w procedurze magazynu call-off stock) oraz
///   oznaczenie transakcji trójstronnych nie są wyprowadzane z danych
///   (P_Dd/P_Nd = 1);
/// - przypisanie do okresu po dacie sprzedaży (P_6), inaczej dacie wystawienia.
public enum VATUEGenerator {

    public static let namespace = "http://crd.gov.pl/wzor/2021/01/12/10293/"
    public static let etdNamespace =
        "http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2020/03/11/eD/DefinicjeTypy/"

    /// Kody krajów UE dla wymiany TOWARÓW (TKodKrajuUE). Zawiera XI (Irlandia
    /// Płn., wyłącznie towary) oraz — zgodnie z wciąż obowiązującym słownikiem
    /// MF — GB. Bez PL (podatnik nie wykazuje transakcji z samym sobą).
    static let goodsCountries: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DK", "DE", "EE", "EL", "ES", "FI", "FR",
        "GB", "HR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PT", "RO",
        "SE", "SI", "SK", "XI",
    ]

    /// Kody krajów UE dla USŁUG (TKodKrajuUEUslugi) — jak dla towarów, ale bez
    /// XI (Irlandia Płn. tylko przy wymianie towarów).
    static let serviceCountries: Set<String> = goodsCountries.subtracting(["XI"])

    /// Kwalifikacja pozycji faktury: towar, usługa albo nierozstrzygnięta.
    enum LineKind: Equatable { case goods, service, unknown }

    /// Generuje informację VAT-UE dla wskazanego miesiąca. Faktury ukryte są
    /// pomijane; korekty wchodzą kwotami różnicy (z ostrzeżeniem).
    public static func generate(invoices: [Invoice], options: VATUEOptions) -> VATUEResult {
        var warnings: [String] = []
        let visible = invoices.filter { !$0.isArchivedOrHidden }
        let sales = visible
            .filter { $0.kind == .sales && inPeriod($0, options: options) }
            .sorted { JPKV7Generator.periodDate($0) < JPKV7Generator.periodDate($1) }
        let purchases = visible
            .filter { $0.kind == .purchase && inPeriod($0, options: options) }
            .sorted { JPKV7Generator.periodDate($0) < JPKV7Generator.periodDate($1) }

        // Sumy wartości (w PLN) per kontrahent (klucz "kraj|numer").
        var wdtSums: [String: Double] = [:]
        var wntSums: [String: Double] = [:]
        var serviceSums: [String: Double] = [:]
        var meta: [String: (country: String, vat: String)] = [:]
        var hasCorrection = false

        // Sprzedaż: towary → WDT (część C), usługi → część E.
        for invoice in sales {
            guard let cp = parseCounterparty(invoice.buyerNIP) else { continue }
            guard isEUCountry(cp.country) else { continue }
            if invoice.isCorrection { hasCorrection = true }
            let key = cp.country + "|" + cp.vat
            meta[key] = cp
            let split = splitNet(invoice, warnings: &warnings)
            if split.goods != 0 {
                wdtSums[key, default: 0] += split.goods
            }
            if split.services != 0 {
                if serviceCountries.contains(cp.country) {
                    serviceSums[key, default: 0] += split.services
                } else {
                    warnings.append(
                        "Faktura \(invoice.invoiceNumber): usługi dla kraju \(cp.country) (Irlandia Płn.) nie są wykazywane w VAT-UE — kod kraju obowiązuje wyłącznie dla towarów; pominięto."
                    )
                }
            }
        }

        // Zakupy: towary → WNT (część D); usługi (import usług) poza VAT-UE.
        for invoice in purchases {
            guard let cp = parseCounterparty(invoice.sellerNIP) else { continue }
            guard isEUCountry(cp.country) else { continue }
            if invoice.isCorrection { hasCorrection = true }
            let key = cp.country + "|" + cp.vat
            meta[key] = cp
            let split = splitNet(invoice, warnings: &warnings)
            if split.goods != 0 {
                wntSums[key, default: 0] += split.goods
            }
            if split.services != 0 {
                warnings.append(
                    "Faktura \(invoice.invoiceNumber): import usług od kontrahenta UE nie jest wykazywany w VAT-UE (tylko w JPK_V7) — pominięto."
                )
            }
        }

        let wdt = entries(from: wdtSums, meta: meta, section: "WDT (część C)", warnings: &warnings)
        let wnt = entries(from: wntSums, meta: meta, section: "WNT (część D)", warnings: &warnings)
        let services = entries(from: serviceSums, meta: meta, section: "usługi (część E)", warnings: &warnings)

        if hasCorrection {
            warnings.append(
                "Okres zawiera faktury korygujące — VAT-UE koryguje się przez ponowne złożenie całej informacji za okres; zweryfikuj wartości."
            )
        }

        let xml = buildXML(options: options, wdt: wdt, wnt: wnt, services: services)
        return VATUEResult(xml: xml, wdt: wdt, wnt: wnt, services: services, warnings: warnings)
    }

    // MARK: Kwalifikacja kontrahenta i pozycji

    /// Rozbija numer VAT kontrahenta na prefiks kraju i część numeryczną.
    /// Zwraca `nil` dla numerów krajowych (same cyfry / prefiks „PL”) i zbyt
    /// krótkich. Grecki prefiks „GR” jest normalizowany do „EL”.
    static func parseCounterparty(_ raw: String) -> (country: String, vat: String)? {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count >= 3 else { return nil }
        let prefix = String(cleaned.prefix(2))
        guard prefix.allSatisfy(\.isLetter) else { return nil }
        let country = prefix == "GR" ? "EL" : prefix
        let vat = String(cleaned.dropFirst(2))
        guard !vat.isEmpty else { return nil }
        return (country, vat)
    }

    /// Czy kod kraju kwalifikuje kontrahenta jako unijnego (towary lub usługi).
    static func isEUCountry(_ code: String) -> Bool {
        goodsCountries.contains(code) || serviceCountries.contains(code)
    }

    /// Kwalifikuje pozycję po kodzie: PKWiU (z kropkami) → usługa,
    /// CN (same cyfry) → towar, brak/nieczytelny → nierozstrzygnięta.
    static func classify(_ code: String) -> LineKind {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .unknown }
        if trimmed.contains(".") { return .service }
        if trimmed.contains(where: \.isNumber) { return .goods }
        return .unknown
    }

    /// Rozkłada wartość netto faktury (w PLN) na towary i usługi. Pozycje OSS
    /// są pomijane (procedura OSS poza VAT-UE); brak pozycji lub brak kodu
    /// CN/PKWiU → wartość jako towary z ostrzeżeniem.
    static func splitNet(_ invoice: Invoice, warnings: inout [String]) -> (goods: Double, services: Double) {
        let lines = invoice.sortedLines
        if lines.isEmpty {
            let net = JPKV7Generator.amountInPLN(invoice.netAmount, invoice: invoice, warnings: &warnings)
            warnings.append(
                "Faktura \(invoice.invoiceNumber): brak pozycji — całość wykazana jako towary; zweryfikuj, czy nie są to usługi (część E)."
            )
            return (net, 0)
        }
        var goods = 0.0
        var services = 0.0
        var sawUnknown = false
        var sawOSS = false
        for line in lines {
            if line.ossRate != nil {
                sawOSS = true
                continue
            }
            let net = JPKV7Generator.amountInPLN(line.netAmount, invoice: invoice, warnings: &warnings)
            switch classify(line.cnPkwiu) {
            case .goods: goods += net
            case .service: services += net
            case .unknown:
                goods += net
                sawUnknown = true
            }
        }
        if sawOSS {
            warnings.append(
                "Faktura \(invoice.invoiceNumber): pozycje OSS pominięte — sprzedaż w procedurze OSS nie jest wykazywana w VAT-UE."
            )
        }
        if sawUnknown {
            warnings.append(
                "Faktura \(invoice.invoiceNumber): pozycja bez kodu CN/PKWiU — zakwalifikowana jako towary; zweryfikuj, czy nie jest to usługa (część E)."
            )
        }
        return (goods, services)
    }

    // MARK: Agregacja

    /// Zamienia sumy per kontrahent na posortowane wiersze w pełnych złotych;
    /// pomija zerowe, ostrzega o ujemnych i zbyt długich numerach VAT.
    static func entries(
        from sums: [String: Double],
        meta: [String: (country: String, vat: String)],
        section: String,
        warnings: inout [String]
    ) -> [VATUEEntry] {
        var result: [VATUEEntry] = []
        for (key, value) in sums {
            guard let cp = meta[key] else { continue }
            let zl = Int(value.rounded())
            if zl == 0 { continue }
            if zl < 0 {
                warnings.append(
                    "\(section): kontrahent \(cp.country)\(cp.vat) ma ujemną wartość (\(zl) zł) — VAT-UE nie przyjmuje kwot ujemnych; skoryguj ręcznie."
                )
            }
            if cp.vat.count > 12 {
                warnings.append(
                    "\(section): numer VAT \(cp.country)\(cp.vat) przekracza 12 znaków — zweryfikuj poprawność."
                )
            }
            result.append(VATUEEntry(countryCode: cp.country, vatNumber: cp.vat, amountPLN: zl))
        }
        return result.sorted { ($0.countryCode, $0.vatNumber) < ($1.countryCode, $1.vatNumber) }
    }

    // MARK: Okres

    static func inPeriod(_ invoice: Invoice, options: VATUEOptions) -> Bool {
        let components = Calendar.current.dateComponents(
            [.year, .month], from: JPKV7Generator.periodDate(invoice)
        )
        return components.year == options.year && components.month == options.month
    }

    // MARK: XML

    static func buildXML(
        options: VATUEOptions,
        wdt: [VATUEEntry],
        wnt: [VATUEEntry],
        services: [VATUEEntry]
    ) -> String {
        var groups = ""
        // Część C — WDT (Grupa1); P_Dd = 1 (brak danych o transakcji trójstronnej).
        for entry in wdt {
            groups += "    <Grupa1>\n"
            groups += "      <P_Da>\(escape(entry.countryCode))</P_Da>\n"
            groups += "      <P_Db>\(escape(entry.vatNumber))</P_Db>\n"
            groups += "      <P_Dc>\(entry.amountPLN)</P_Dc>\n"
            groups += "      <P_Dd>1</P_Dd>\n"
            groups += "    </Grupa1>\n"
        }
        // Część D — WNT (Grupa2); P_Nd = 1.
        for entry in wnt {
            groups += "    <Grupa2>\n"
            groups += "      <P_Na>\(escape(entry.countryCode))</P_Na>\n"
            groups += "      <P_Nb>\(escape(entry.vatNumber))</P_Nb>\n"
            groups += "      <P_Nc>\(entry.amountPLN)</P_Nc>\n"
            groups += "      <P_Nd>1</P_Nd>\n"
            groups += "    </Grupa2>\n"
        }
        // Część E — usługi (Grupa3).
        for entry in services {
            groups += "    <Grupa3>\n"
            groups += "      <P_Ua>\(escape(entry.countryCode))</P_Ua>\n"
            groups += "      <P_Ub>\(escape(entry.vatNumber))</P_Ub>\n"
            groups += "      <P_Uc>\(entry.amountPLN)</P_Uc>\n"
            groups += "    </Grupa3>\n"
        }

        let nip = options.sellerNIP.filter(\.isNumber)
        let taxOffice = options.taxOfficeCode.filter(\.isNumber)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Deklaracja xmlns="\(namespace)" xmlns:etd="\(etdNamespace)">
          <Naglowek>
            <KodFormularza kodSystemowy="VAT-UE (5)" wersjaSchemy="2-0E">VAT-UE</KodFormularza>
            <WariantFormularza>5</WariantFormularza>
            <Rok>\(options.year)</Rok>
            <Miesiac>\(options.month)</Miesiac>
            <CelZlozenia>1</CelZlozenia>
            <KodUrzedu>\(escape(taxOffice))</KodUrzedu>
          </Naglowek>
          <Podmiot1 rola="Podatnik">
            <etd:OsobaNiefizyczna>
              <etd:NIP>\(escape(nip))</etd:NIP>
              <etd:PelnaNazwa>\(escape(options.sellerName))</etd:PelnaNazwa>
            </etd:OsobaNiefizyczna>
          </Podmiot1>
          <PozycjeSzczegolowe>
        \(groups)  </PozycjeSzczegolowe>
          <Pouczenie>1</Pouczenie>
        </Deklaracja>
        """
    }

    static func escape(_ value: String) -> String {
        FA2XMLGenerator.escape(value)
    }
}
