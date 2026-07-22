import Foundation

/// Eksport dokumentów do publicznego formatu wymiany WAPRO XML, importowanego
/// przez WAPRO Kaper i WAPRO Fakir. Struktura odpowiada specyfikacji MAGIK_EKSPORT
/// 4.3.2 (WAPRO Fakir 8.51+).
public enum WaproXMLExporter {

    public enum ExportError: LocalizedError, Equatable {
        case noDocuments
        case tooManyDocuments(Int)

        public var errorDescription: String? {
            switch self {
            case .noDocuments:
                return "Wybierz co najmniej jedną fakturę do eksportu WAPRO XML."
            case .tooManyDocuments(let count):
                return "Format WAPRO XML mieści maksymalnie 999 dokumentów w jednym pliku (wybrano \(count))."
            }
        }
    }

    /// Wynik eksportu wraz z ostrzeżeniami wymagającymi weryfikacji po imporcie.
    public struct Result: Sendable {
        public let data: Data
        public let documentCount: Int
        public let warnings: [String]
    }

    private struct Contractor {
        let id: Int
        var name: String
        var nip: String
        var country: String
        var address: String
        var isCustomer: Bool
        var isSupplier: Bool
    }

    private struct VATBucket {
        var net: Double = 0
        var vat: Double = 0
    }

    /// Buduje kompletny plik WAPRO XML. Kolejność dokumentów jest zachowana.
    public static func export(invoices: [Invoice], generatedAt: Date = .now) throws -> Result {
        guard !invoices.isEmpty else { throw ExportError.noDocuments }
        guard invoices.count <= 999 else { throw ExportError.tooManyDocuments(invoices.count) }

        let catalog = contractorCatalog(for: invoices)
        let root = XMLElement(name: "MAGIK_EKSPORT")
        root.addChild(infoElement(documentCount: invoices.count, generatedAt: generatedAt))

        let documents = XMLElement(name: "DOKUMENTY")
        var warnings: [String] = []
        for (index, invoice) in invoices.enumerated() {
            let key = contractorKey(for: invoice)
            let contractorID = catalog.idsByKey[key] ?? index + 1
            documents.addChild(documentElement(invoice, contractorID: contractorID, documentID: index + 1))

            if !CurrencyCode.isPLN(invoice.currency), invoice.exchangeRate <= 0 {
                warnings.append("\(invoice.invoiceNumber): brak kursu PLN — wartości bazowe zapisano w walucie faktury.")
            }
            if invoice.sortedLines.isEmpty {
                warnings.append("\(invoice.invoiceNumber): brak pozycji — wyeksportowano nagłówek i podsumowanie VAT.")
            }
        }
        root.addChild(documents)

        let contractors = XMLElement(name: "KARTOTEKA_KONTRAHENTOW")
        for contractor in catalog.contractors.sorted(by: { $0.id < $1.id }) {
            contractors.addChild(contractorElement(contractor))
        }
        root.addChild(contractors)
        root.addChild(XMLElement(name: "KARTOTEKA_PRACOWNIKOW"))
        root.addChild(XMLElement(name: "KARTOTEKA_ARTYKULOW"))

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return Result(
            data: document.xmlData(options: [.nodePrettyPrint]),
            documentCount: invoices.count,
            warnings: warnings
        )
    }

    /// Data Clarion wg wzoru WAPRO: liczba dni SQL od 1900-01-01 + 36163.
    /// Liczona zawsze w kalendarzu gregoriańskim — kalendarz systemowy inny
    /// niż gregoriański (np. buddyjski) przesunąłby rok 1900 o setki lat;
    /// z przekazanego kalendarza brana jest wyłącznie strefa czasowa.
    static func clarionDate(_ date: Date, calendar source: Calendar = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = calendar.date(from: components) ?? date
        let reference = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        return calendar.dateComponents([.day], from: reference, to: day).day! + 36_163
    }

    /// Czas Clarion: liczba setnych sekundy od północy + 1.
    static func clarionTime(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = (parts.hour ?? 0) * 3_600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        return seconds * 100 + (parts.nanosecond ?? 0) / 10_000_000 + 1
    }

    // MARK: - Sekcje dokumentu

    private static func infoElement(documentCount: Int, generatedAt: Date) -> XMLElement {
        let info = XMLElement(name: "INFO_EKSPORTU")
        add("WERSJA_MAGIKA", "4.3.2", to: info)
        add("NAZWA_PROGRAMU", "Ksefiarz", to: info)
        add("WERSJA_PROGRAMU", "1.0", to: info)
        add("DATA_EKSPORTU", dateText(generatedAt), to: info)
        add("GODZINA_EKSPORTU", clarionTime(generatedAt), to: info)
        add("LICZBA_DOKUMENTOW", documentCount, to: info)
        return info
    }

    private static func documentElement(
        _ invoice: Invoice,
        contractorID: Int,
        documentID: Int
    ) -> XMLElement {
        let document = XMLElement(name: "DOKUMENT")
        let header = XMLElement(name: "NAGLOWEK_DOKUMENTU")
        let isSales = invoice.kind == .sales
        let isForeign = !CurrencyCode.isPLN(invoice.currency)
        let factor = isForeign && invoice.exchangeRate > 0 ? invoice.exchangeRate : 1

        add("RODZAJ_DOKUMENTU", "H", to: header)
        add("NUMER", limited(invoice.invoiceNumber, to: 30), to: header)
        if let original = invoice.correctedInvoiceNumber, !original.isEmpty {
            add("NR_DOK_ORYG", limited(original, to: 30), to: header)
        }
        // Mimo historycznej nazwy pole jest w specyfikacji opisane jako
        // wymagany identyfikator dokumentu. Stabilność obowiązuje w pliku.
        add("ID_DOKUMENTU_ORYG", documentID, to: header)
        add("DOK_ZBIOR", 0, to: header)
        add("ID_KONTRAHENTA", contractorID, to: header)
        add("ID_PLATNIKA", contractorID, to: header)
        add("ZAKUP_SPRZEDAZ", isSales ? "S" : "Z", to: header)
        add("OBLICZANIE_WG_CEN", "Netto", to: header)
        add("TYP_DOKUMENTU", invoice.isCorrection ? "KF" : (isSales ? "FS" : "FZ"), to: header)
        add("OPIS", limited(invoice.notes, to: 50), to: header, unlessEmpty: true)
        add("SYM_WAL", limited(CurrencyCode.normalizedOrPLN(invoice.currency), to: 3), to: header)
        add("NUMER_RACHUNKU", normalizedAccount(invoice.paymentBankAccount), to: header, unlessEmpty: true)
        add("TYP_PLATNIKA", "K", to: header)
        add("CZY_DOKUMENT_KOREKTY", invoice.isCorrection ? 1 : 0, to: header)
        add("WYROZNIK", limited(invoice.ksefId ?? invoice.id.uuidString, to: 30), to: header)
        add("POZ_WAL_BAZOWE", isForeign ? 0 : 1, to: header)
        if let paymentForm = invoice.paymentForm {
            add("FORMA_PLATNOSCI", limited(paymentForm.displayName, to: 50), to: header)
            if let waproID = waproPaymentFormID(paymentForm) {
                add("ID_FORMY_PLAT", waproID, to: header)
            }
        }
        let transactionCodes = transactionCodes(for: invoice)
        add("RODZAJ_TRANSAKCJI_HANDLOWEJ", limited(transactionCodes.joined(separator: " "), to: 255), to: header, unlessEmpty: true)
        add("PODLEGA_PP", invoice.splitPayment ? 1 : 0, to: header)

        if let ksefID = invoice.ksefId, !ksefID.isEmpty {
            let ksef = XMLElement(name: "KSEF")
            add("KSEF_ID", limited(ksefID, to: 36), to: ksef)
            if let acceptedAt = invoice.ksefAcceptedAt {
                add("DATA_POTW_KSEF", clarionDate(acceptedAt), to: ksef)
                add("GODZINA_POTW_KSEF", clarionTime(acceptedAt), to: ksef)
            }
            header.addChild(ksef)
        }

        if invoice.splitPayment {
            let split = XMLElement(name: "PODZIELONA_PLATNOSC")
            add("PP", 1, to: split)
            add("PP_NR_FAKTURY", limited(invoice.invoiceNumber, to: 30), to: split)
            let payerIdentity = taxIdentity(isSales ? invoice.buyerNIP : invoice.sellerNIP)
            add("PP_NIP", limited(payerIdentity.number, to: 30), to: split)
            // MPP rozlicza się w złotych — kwota VAT po kursie dokumentu.
            add("PP_KW_VAT_R", decimal(invoice.vatAmount * factor), to: split)
            header.addChild(split)
        }

        let dates = XMLElement(name: "DATY")
        add("DATA_WYSTAWIENIA", clarionDate(invoice.issueDate), to: dates)
        add("DATA_SPRZEDAZY", clarionDate(invoice.saleDate ?? invoice.issueDate), to: dates)
        add("DATA_WPLYWU", clarionDate(invoice.issueDate), to: dates)
        add("TERMIN_PLATNOSCI", clarionDate(invoice.paymentDueDate ?? invoice.issueDate), to: dates)
        header.addChild(dates)

        let values = XMLElement(name: "WARTOSCI_NAGLOWKA")
        add("NETTO_SPRZEDAZY", decimal(isSales ? invoice.netAmount * factor : 0), to: values)
        add("BRUTTO_SPRZEDAZY", decimal(isSales ? invoice.grossAmount * factor : 0), to: values)
        add("NETTO_ZAKUPU", decimal(isSales ? 0 : invoice.netAmount * factor), to: values)
        add("BRUTTO_ZAKUPU", decimal(isSales ? 0 : invoice.grossAmount * factor), to: values)
        if isForeign {
            add("NETTO_SPRZEDAZY_WALUTA", decimal(isSales ? invoice.netAmount : 0), to: values)
            add("BRUTTO_SPRZEDAZY_WALUTA", decimal(isSales ? invoice.grossAmount : 0), to: values)
            add("KURS_WALUTY", decimal(invoice.exchangeRate > 0 ? invoice.exchangeRate : 1, places: 4), to: values)
        }
        add("KW_ROZRACH", decimal(invoice.grossAmount * factor), to: values)
        add("KW_ROZRACH_W", decimal(invoice.grossAmount), to: values)
        header.addChild(values)
        document.addChild(header)

        if !invoice.sortedLines.isEmpty {
            let positions = XMLElement(name: "POZYCJE_DOKUMENTU")
            for line in invoice.sortedLines {
                positions.addChild(positionElement(line, invoice: invoice, contractorID: contractorID))
            }
            document.addChild(positions)
        }

        let vat = XMLElement(name: "VAT")
        for (rate, bucket) in vatBuckets(for: invoice).sorted(by: { $0.key < $1.key }) {
            let rateElement = XMLElement(name: "STAWKA")
            add("KOD_VAT", limited(rate, to: 3), to: rateElement)
            add("NETTO", decimal(bucket.net * factor), to: rateElement)
            add("VAT", decimal(bucket.vat * factor), to: rateElement)
            add("NETTO_WALUTA", decimal(bucket.net), to: rateElement)
            add("VAT_WALUTA", decimal(bucket.vat), to: rateElement)
            add("DATA_VAT", clarionDate(invoice.saleDate ?? invoice.issueDate), to: rateElement)
            vat.addChild(rateElement)
        }
        document.addChild(vat)
        return document
    }

    private static func positionElement(
        _ line: InvoiceLine,
        invoice: Invoice,
        contractorID: Int
    ) -> XMLElement {
        let position = XMLElement(name: "POZYCJA_DOKUMENTU")
        let isSales = invoice.kind == .sales
        let factor = !CurrencyCode.isPLN(invoice.currency) && invoice.exchangeRate > 0
            ? invoice.exchangeRate : 1
        let gross = line.netAmount + line.vatAmount

        add("RODZAJ_POZYCJI", isSales ? "P" : "R", to: position)
        add("KOD_VAT", limited(normalizedVATRate(line.vatRate), to: 3), to: position)
        add("OPIS_POZYCJI", limited(line.name, to: 250), to: position)
        add("TYP_PLATNIKA", "K", to: position)
        add("ID_PLATNIKA", contractorID, to: position)
        add("SYM_WAL", limited(CurrencyCode.normalizedOrPLN(invoice.currency), to: 3), to: position)
        add("POZ_WAL_BAZOWE", CurrencyCode.isPLN(invoice.currency) ? 1 : 0, to: position)
        add("KOD_CN", limited(line.cnPkwiu, to: 10), to: position, unlessEmpty: true)
        add("DATA_VAT", clarionDate(invoice.saleDate ?? invoice.issueDate), to: position)

        let values = XMLElement(name: "WARTOSCI_POZYCJI")
        add("WARTOSC_ZAKUPU_NETTO", decimal(isSales ? 0 : line.netAmount * factor), to: values)
        add("WARTOSC_ZAKUPU_BRUTTO", decimal(isSales ? 0 : gross * factor), to: values)
        add("WARTOSC_NETTO", decimal(isSales ? line.netAmount * factor : 0), to: values)
        add("WARTOSC_BRUTTO", decimal(isSales ? gross * factor : 0), to: values)
        add("WARTOSC_NETTO_WALUTA", decimal(isSales ? line.netAmount : 0), to: values)
        add("WARTOSC_BRUTTO_WALUTA", decimal(isSales ? gross : 0), to: values)
        add("WARTOSC_ZAKUPU_NETTO_WALUTA", decimal(isSales ? 0 : line.netAmount), to: values)
        add("WARTOSC_ZAKUPU_BRUTTO_WALUTA", decimal(isSales ? 0 : gross), to: values)
        position.addChild(values)
        return position
    }

    private static func contractorElement(_ contractor: Contractor) -> XMLElement {
        let element = XMLElement(name: "KONTRAHENT")
        add("ID_KONTRAHENTA", contractor.id, to: element)
        add("KOD_KONTRAHENTA", contractor.id, to: element)
        add("NAZWA", limited(contractor.name, to: 50), to: element)
        add("NAZWA_PELNA", limited(contractor.name, to: 200), to: element)
        add("ADRES", limited(contractor.address, to: 50), to: element, unlessEmpty: true)
        add("NIP", limited(contractor.nip, to: 30), to: element, unlessEmpty: true)
        add("SYMBOL_KRAJU_KONTRAHENTA", contractor.country, to: element)
        // PDF specyfikacji używa ODBIORCA; wersja HTML ma literówkę DBIORCA.
        add("ODBIORCA", contractor.isCustomer ? 1 : 0, to: element)
        add("DOSTAWCA", contractor.isSupplier ? 1 : 0, to: element)
        add("CZY_KONTRAHENT_UE", isEU(contractor.country) ? 1 : 0, to: element)
        add("RODZAJ_EWIDENCJI", contractor.nip.isEmpty ? 0 : 1, to: element)
        return element
    }

    // MARK: - Normalizacja danych

    private static func contractorCatalog(for invoices: [Invoice]) -> (
        contractors: [Contractor], idsByKey: [String: Int]
    ) {
        var contractors: [Contractor] = []
        var indicesByKey: [String: Int] = [:]

        for invoice in invoices {
            let key = contractorKey(for: invoice)
            let isSales = invoice.kind == .sales
            let name = isSales ? invoice.buyerName : invoice.sellerName
            let nip = isSales ? invoice.buyerNIP : invoice.sellerNIP
            let identity = taxIdentity(nip)
            let address = isSales ? invoice.buyerAddress : invoice.sellerAddress
            if let index = indicesByKey[key] {
                contractors[index].isCustomer = contractors[index].isCustomer || isSales
                contractors[index].isSupplier = contractors[index].isSupplier || !isSales
            } else {
                indicesByKey[key] = contractors.count
                contractors.append(Contractor(
                    id: contractors.count + 1,
                    name: name.isEmpty ? "Kontrahent bez nazwy" : name,
                    nip: identity.number,
                    country: identity.country,
                    address: address,
                    isCustomer: isSales,
                    isSupplier: !isSales
                ))
            }
        }
        let ids = Dictionary(uniqueKeysWithValues: indicesByKey.map { ($0.key, contractors[$0.value].id) })
        return (contractors, ids)
    }

    private static func contractorKey(for invoice: Invoice) -> String {
        let isSales = invoice.kind == .sales
        let identity = taxIdentity(isSales ? invoice.buyerNIP : invoice.sellerNIP)
        if !identity.number.isEmpty { return "nip:\(identity.country):\(identity.number)" }
        let name = (isSales ? invoice.buyerName : invoice.sellerName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "name:\(name)"
    }

    private static func vatBuckets(for invoice: Invoice) -> [String: VATBucket] {
        guard !invoice.sortedLines.isEmpty else {
            return [inferredVATRate(net: invoice.netAmount, vat: invoice.vatAmount): VATBucket(
                net: invoice.netAmount,
                vat: invoice.vatAmount
            )]
        }
        return invoice.sortedLines.reduce(into: [:]) { result, line in
            let rate = normalizedVATRate(line.vatRate)
            result[rate, default: VATBucket()].net += line.netAmount
            result[rate, default: VATBucket()].vat += line.vatAmount
        }
    }

    private static func inferredVATRate(net: Double, vat: Double) -> String {
        guard abs(net) > 0.005, abs(vat) > 0.005 else { return "0" }
        let percentage = abs(vat / net * 100)
        return [23.0, 8.0, 7.0, 5.0, 0.0]
            .min(by: { abs($0 - percentage) < abs($1 - percentage) })
            .map { String(format: "%.0f", $0) } ?? "NP"
    }

    private static func normalizedVATRate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "zw", "zw.": return "ZW"
        case "np", "np.": return "NP"
        default:
            // Obcinana jest wyłącznie zbędna część ułamkowa ("8.0", "23,00"),
            // nigdy cyfry samej stawki.
            var rate = trimmed.replacingOccurrences(of: ",", with: ".")
            if rate.contains(".") {
                while rate.hasSuffix("0") { rate.removeLast() }
                if rate.hasSuffix(".") { rate.removeLast() }
            }
            return rate
        }
    }

    private static func transactionCodes(for invoice: Invoice) -> [String] {
        var codes: [String] = []
        func append(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty, !codes.contains(normalized) { codes.append(normalized) }
        }
        for line in invoice.sortedLines {
            append(line.gtu)
            append(line.procedure)
        }
        if invoice.splitPayment { append("MPP") }
        if invoice.isRR { append("VAT_RR") }
        return codes
    }

    private static func waproPaymentFormID(_ paymentForm: PaymentForm) -> Int? {
        switch paymentForm {
        case .cash: return 1
        case .card: return 2
        case .transfer: return 3
        case .cheque: return 7
        case .credit: return 8
        case .voucher, .mobile: return nil
        }
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// NUMER_RACHUNKU to wg specyfikacji STR(26) — mieści wyłącznie polski
    /// NRB (bez prefiksu PL). Rachunek innego kształtu, np. zagraniczny IBAN,
    /// jest pomijany zamiast zapisu w postaci obciętej i przekłamanej.
    private static func normalizedAccount(_ value: String?) -> String {
        let compact = normalizedIdentifier(value ?? "")
        let digits = compact.hasPrefix("PL") ? String(compact.dropFirst(2)) : compact
        guard digits.count == 26, digits.allSatisfy(\.isNumber) else { return "" }
        return digits
    }

    private static func taxIdentity(_ identifier: String) -> (country: String, number: String) {
        let normalized = normalizedIdentifier(identifier)
        let prefix = String(normalized.prefix(2))
        guard prefix.count == 2, prefix.allSatisfy(\.isLetter) else {
            return ("PL", normalized)
        }
        let country = prefix == "EL" ? "GR" : prefix
        return (country, String(normalized.dropFirst(2)))
    }

    private static func isEU(_ country: String) -> Bool {
        Set(["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "GR", "ES", "NL", "IE", "LT", "LU", "LV", "MT", "DE", "PL", "PT", "RO", "SK", "SI", "SE", "HU", "IT"]).contains(country)
            && country != "PL"
    }

    private static func limited(_ value: String, to maximum: Int) -> String {
        String(value.prefix(maximum))
    }

    private static func decimal(_ value: Double, places: Int = 2) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }

    private static func add<T>(
        _ name: String,
        _ value: T,
        to parent: XMLElement,
        unlessEmpty: Bool = false
    ) {
        let text = String(describing: value)
        if unlessEmpty && text.isEmpty { return }
        let child = XMLElement(name: name)
        child.stringValue = text
        parent.addChild(child)
    }
}
