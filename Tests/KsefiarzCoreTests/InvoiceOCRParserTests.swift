import Foundation
import Testing
@testable import KsefiarzCore

@Suite("OCR faktur kosztowych — parser pól z tekstu skanu")
struct InvoiceOCRParserTests {

    private func day(_ iso: String) -> Date {
        FA2Format.dateFormatter.date(from: iso)!
    }

    // MARK: - Pełna faktura

    @Test("Typowa polska faktura: komplet pól z etykiet")
    func typicalInvoice() {
        let lines = [
            "FAKTURA VAT nr FV/123/07/2026",
            "Data wystawienia: 10.07.2026",
            "Data sprzedaży: 08.07.2026",
            "Sprzedawca:",
            "ACME Sp. z o.o.",
            "ul. Przemysłowa 7",
            "31-123 Kraków",
            "NIP: 526-104-08-28",
            "Nabywca:",
            "Moja Firma",
            "NIP: 1111111111",
            "Wartość netto Kwota VAT Wartość brutto",
            "Razem 1 000,00 230,00 1 230,00",
            "Do zapłaty: 1 230,00 PLN",
            "Forma płatności: przelew",
            "Termin płatności: 24.07.2026",
            "Nr konta: PL61 1090 1014 0000 0712 1981 2874",
        ]
        let result = InvoiceOCRParser.parse(lines: lines, ownNIP: "1111111111")
        #expect(result.documentNumber == "FV/123/07/2026")
        #expect(result.issueDate == day("2026-07-10"))
        #expect(result.saleDate == day("2026-07-08"))
        #expect(result.sellerName == "ACME Sp. z o.o.")
        #expect(result.sellerTaxID == "5261040828")
        #expect(result.sellerAddress == "ul. Przemysłowa 7, 31-123 Kraków")
        #expect(result.netAmount == 1000.00)
        #expect(result.vatAmount == 230.00)
        #expect(result.grossAmount == 1230.00)
        #expect(result.currency == "PLN")
        #expect(result.bankAccount == "61109010140000071219812874")
        #expect(result.paymentDueDate == day("2026-07-24"))
        #expect(result.paymentForm == .transfer)
    }

    @Test("OCR bez polskich znaków (zgubione diakrytyki) — etykiety nadal rozpoznawane")
    func missingDiacritics() {
        let lines = [
            "Faktura nr 15/2026",
            "Data wystawienia: 2026-07-01",
            "Data sprzedazy: 2026-06-30",
            "Termin platnosci: 2026-07-15",
            "Do zaplaty: 615,00 zl",
            "Forma platnosci: gotowka",
        ]
        let result = InvoiceOCRParser.parse(lines: lines)
        #expect(result.documentNumber == "15/2026")
        #expect(result.issueDate == day("2026-07-01"))
        #expect(result.saleDate == day("2026-06-30"))
        #expect(result.paymentDueDate == day("2026-07-15"))
        #expect(result.grossAmount == 615.00)
        #expect(result.currency == "PLN")
        #expect(result.paymentForm == .cash)
    }

    @Test("Pusty i bezwartościowy tekst — puste rozpoznanie")
    func garbageInput() {
        #expect(InvoiceOCRParser.parse(lines: []).isEmpty)
        #expect(InvoiceOCRParser.parse(lines: ["   ", ""]).isEmpty)
        let noise = InvoiceOCRParser.parse(lines: ["lorem ipsum", "dolor sit amet"])
        #expect(noise.isEmpty)
    }

    // MARK: - Numer dokumentu

    @Test("Numer po „nr” ucinany przed datą („z dnia …”)")
    func numberStopsBeforeDate() {
        let result = InvoiceOCRParser.parse(lines: ["FAKTURA NR 15/2026 z dnia 12.03.2026"])
        #expect(result.documentNumber == "15/2026")
        // Jedyna data w dokumencie służy za datę wystawienia.
        #expect(result.issueDate == day("2026-03-12"))
    }

    @Test("Nagłówek bez „nr”: Faktura VAT FV/07/2026")
    func numberWithoutNrKeyword() {
        let result = InvoiceOCRParser.parse(lines: ["Faktura VAT FV/07/2026"])
        #expect(result.documentNumber == "FV/07/2026")
    }

    @Test("Etykieta „Numer faktury” z wartością w następnej linii")
    func numberOnNextLine() {
        let result = InvoiceOCRParser.parse(lines: ["Numer faktury", "F/00123/26"])
        #expect(result.documentNumber == "F/00123/26")
    }

    @Test("Sam nagłówek „Faktura VAT” bez cyfr nie daje numeru")
    func headerWithoutDigitsIsNotANumber() {
        let result = InvoiceOCRParser.parse(lines: ["Faktura VAT", "Oryginał"])
        #expect(result.documentNumber == nil)
    }

    @Test("Numer n/miesiąc/rok (1/07/2026) nie jest odrzucany jako data")
    func slashDateLikeNumberAccepted() {
        #expect(InvoiceOCRParser.parse(lines: ["Faktura nr 1/07/2026"]).documentNumber == "1/07/2026")
    }

    @Test("„Rachunek bankowy nr …” nie jest brany za numer dokumentu")
    func bankAccountLineNotDocumentNumber() {
        let result = InvoiceOCRParser.parse(lines: [
            "Faktura VAT FV/1/2026",
            "Rachunek bankowy nr: 61 1090 1014 0000 0712 1981 2874",
        ])
        #expect(result.documentNumber == "FV/1/2026")
        #expect(result.bankAccount == "61109010140000071219812874")
    }

    // MARK: - Daty

    @Test("Formaty dat: kropki, myślniki, ISO i słownie")
    func dateFormats() {
        #expect(InvoiceOCRParser.date(in: "10.07.2026") == day("2026-07-10"))
        #expect(InvoiceOCRParser.date(in: "10-07-2026") == day("2026-07-10"))
        #expect(InvoiceOCRParser.date(in: "10/07/2026") == day("2026-07-10"))
        #expect(InvoiceOCRParser.date(in: "2026-07-10") == day("2026-07-10"))
        #expect(InvoiceOCRParser.date(in: "1.7.2026") == day("2026-07-01"))
        #expect(InvoiceOCRParser.date(in: "12 czerwca 2026") == day("2026-06-12"))
        #expect(InvoiceOCRParser.date(in: "3 maja 2026 r.") == day("2026-05-03"))
        #expect(InvoiceOCRParser.date(in: "12 września 2026") == day("2026-09-12"))
    }

    @Test("Zapis amerykański (miesiąc > 12 na drugiej pozycji) — zamiana dnia z miesiącem")
    func americanDateOrder() {
        #expect(InvoiceOCRParser.date(in: "07/25/2026") == day("2026-07-25"))
    }

    @Test("Nieistniejące daty i liczby niebędące datami są odrzucane")
    func invalidDates() {
        #expect(InvoiceOCRParser.date(in: "31.02.2026") == nil)
        #expect(InvoiceOCRParser.date(in: "99.99.2026") == nil)
        #expect(InvoiceOCRParser.date(in: "1 230,00") == nil)
        #expect(InvoiceOCRParser.date(in: "FV/123/2026") == nil)
        #expect(InvoiceOCRParser.date(in: "tekst bez daty") == nil)
    }

    @Test("Etykieta daty i wartość w osobnych liniach (układ kolumnowy)")
    func dateOnNextLine() {
        let result = InvoiceOCRParser.parse(lines: ["Data wystawienia", "10.07.2026"])
        #expect(result.issueDate == day("2026-07-10"))
    }

    @Test("Wiele różnych dat bez etykiet — brak zgadywania daty wystawienia")
    func multipleUnlabeledDates() {
        let result = InvoiceOCRParser.parse(lines: ["10.07.2026", "24.07.2026"])
        #expect(result.issueDate == nil)
    }

    @Test("Jedyna data będąca terminem płatności nie staje się datą wystawienia")
    func dueDateNotStolenAsIssueDate() {
        let labeled = InvoiceOCRParser.parse(lines: ["Rachunek nr 7/2026", "Zapłata do: 24.07.2026"])
        #expect(labeled.paymentDueDate == day("2026-07-24"))
        #expect(labeled.issueDate == nil)
        // Etykieta spoza słownika, ale kontekst terminu/zapłaty w linii.
        let hinted = InvoiceOCRParser.parse(lines: ["Płatność do dnia 20.07.2026"])
        #expect(hinted.issueDate == nil)
    }

    // MARK: - Kwoty

    @Test("Formaty kwot: spacje, kropki tysięcy, przecinek i kropka dziesiętna")
    func amountFormats() {
        #expect(InvoiceOCRParser.amounts(in: "1 234,56") == [1234.56])
        #expect(InvoiceOCRParser.amounts(in: "1.234,56") == [1234.56])
        #expect(InvoiceOCRParser.amounts(in: "1234,56") == [1234.56])
        #expect(InvoiceOCRParser.amounts(in: "1234.56") == [1234.56])
        #expect(InvoiceOCRParser.amounts(in: "12 345 678,90 zł") == [12345678.90])
        #expect(InvoiceOCRParser.amounts(in: "Do zapłaty: 615,00 PLN") == [615.00])
    }

    @Test("Kwoty nie łapią dat ani stawek procentowych")
    func amountsIgnoreDatesAndRates() {
        #expect(InvoiceOCRParser.amounts(in: "12.03.2026").isEmpty)
        #expect(InvoiceOCRParser.amounts(in: "VAT 23,00 %").isEmpty)
        #expect(InvoiceOCRParser.amounts(in: "VAT 23,00%").isEmpty)
        #expect(InvoiceOCRParser.amounts(in: "Razem 1 000,00 230,00 1 230,00") == [1000.00, 230.00, 1230.00])
    }

    @Test("Wiersz podsumowania ze stawką: netto+VAT=brutto wybiera właściwe kwoty")
    func summaryRowWithRate() {
        let result = InvoiceOCRParser.parse(lines: ["Razem 23,00 1 000,00 230,00 1 230,00"])
        #expect(result.netAmount == 1000.00)
        #expect(result.vatAmount == 230.00)
        #expect(result.grossAmount == 1230.00)
    }

    @Test("Wiersz podsumowania: para tuż przed brutto wygrywa z przypadkową kombinacją")
    func summaryRowTrailingPairWins() {
        // 23,00 + 1 207,00 też daje 1 230,00, ale klasyczny układ kolumn
        // to „… netto VAT brutto” — decyduje para bezpośrednio przed brutto.
        let result = InvoiceOCRParser.parse(lines: ["Razem 23,00 1 207,00 1 000,00 230,00 1 230,00"])
        #expect(result.netAmount == 1000.00)
        #expect(result.vatAmount == 230.00)
        #expect(result.grossAmount == 1230.00)
    }

    @Test("Stawka VAT (też z podwójną spacją przed %) nie jest kwotą VAT")
    func vatRateNotAmount() {
        #expect(InvoiceOCRParser.amounts(in: "VAT 23,00  %").isEmpty)
        let result = InvoiceOCRParser.parse(lines: ["Stawka VAT: 23,00", "Do zapłaty: 1 230,00 zł"])
        #expect(result.vatAmount == nil)
        #expect(result.grossAmount == 1230.00)
    }

    @Test("Wiersz podsumowania bez spełnionego równania jest pomijany")
    func summaryRowInconsistent() {
        let result = InvoiceOCRParser.parse(lines: ["Razem 111,11 222,22 999,99"])
        #expect(result.netAmount == nil)
        #expect(result.grossAmount == nil)
    }

    @Test("Kwoty z etykiet w osobnych liniach")
    func labeledAmounts() {
        let result = InvoiceOCRParser.parse(lines: [
            "Suma netto: 500,00",
            "Kwota VAT: 115,00",
            "Do zapłaty: 615,00",
        ])
        #expect(result.netAmount == 500.00)
        #expect(result.vatAmount == 115.00)
        #expect(result.grossAmount == 615.00)
    }

    @Test("Etykieta kwoty i wartość w następnej linii")
    func amountOnNextLine() {
        let result = InvoiceOCRParser.parse(lines: ["Do zapłaty", "1 230,00 PLN"])
        #expect(result.grossAmount == 1230.00)
    }

    // MARK: - Wyprowadzanie kwot

    @Test("resolvedAmounts: brakująca kwota wynika z netto + VAT = brutto")
    func resolvedAmountCombinations() {
        #expect(InvoiceOCRExtraction(netAmount: 100, vatAmount: 23)
            .resolvedAmounts()! == (net: 100, vat: 23))
        #expect(InvoiceOCRExtraction(netAmount: 100, grossAmount: 123)
            .resolvedAmounts()! == (net: 100, vat: 23))
        #expect(InvoiceOCRExtraction(vatAmount: 23, grossAmount: 123)
            .resolvedAmounts()! == (net: 100, vat: 23))
        #expect(InvoiceOCRExtraction(grossAmount: 123)
            .resolvedAmounts()! == (net: 123, vat: 0))
        #expect(InvoiceOCRExtraction(netAmount: 100)
            .resolvedAmounts()! == (net: 100, vat: 0))
        #expect(InvoiceOCRExtraction().resolvedAmounts() == nil)
    }

    @Test("resolvedAmounts: para netto+VAT ma pierwszeństwo przed brutto (brutto bywa saldem)")
    func resolvedAmountsInconsistentTriple() {
        let extraction = InvoiceOCRExtraction(netAmount: 100, vatAmount: 8, grossAmount: 123)
        #expect(extraction.resolvedAmounts()! == (net: 100, vat: 8))
    }

    @Test("Opłacona faktura z „Do zapłaty: 0,00” nie daje ujemnego VAT")
    func paidInvoiceZeroDue() {
        let result = InvoiceOCRParser.parse(lines: [
            "Suma netto: 1000,00",
            "Kwota VAT: 230,00",
            "Do zapłaty: 0,00",
        ])
        #expect(result.resolvedAmounts()! == (net: 1000, vat: 230))
        // Samo netto + zerowe „do zapłaty” — ujemna różnica nie jest VAT-em.
        let netOnly = InvoiceOCRParser.parse(lines: ["Suma netto: 1000,00", "Do zapłaty: 0,00"])
        #expect(netOnly.resolvedAmounts()! == (net: 1000, vat: 0))
    }

    @Test("Jawna suma brutto wygrywa z zerowym saldem do zapłaty")
    func explicitGrossBeatsZeroDueBalance() {
        let result = InvoiceOCRParser.parse(lines: [
            "Suma brutto: 1 230,00 PLN",
            "Do zapłaty: 0,00 PLN",
        ])
        #expect(result.grossAmount == 1230)
        #expect(result.resolvedAmounts()! == (net: 1230, vat: 0))

        let itemPrice = InvoiceOCRParser.parse(lines: [
            "Cena brutto: 10,00 PLN",
            "Do zapłaty: 100,00 PLN",
        ])
        #expect(itemPrice.grossAmount == 100)
    }

    @Test("Samo brutto zgodne z istniejącym podziałem netto/VAT nie zeruje VAT (edycja)")
    func grossOnlyKeepsExistingSplit() {
        var draft = ManualPurchaseDraft()
        draft.netAmount = 100
        draft.vatAmount = 23
        let merged = InvoiceOCRExtraction(grossAmount: 123).applied(to: draft)
        #expect(merged.netAmount == 100)
        #expect(merged.vatAmount == 23)
        // Inne brutto = inny dokument — nadpisuje.
        let other = InvoiceOCRExtraction(grossAmount: 200).applied(to: draft)
        #expect(other.netAmount == 200)
        #expect(other.vatAmount == 0)
    }

    // MARK: - Sprzedawca

    @Test("NIP własnej firmy (nabywcy) nie jest brany za NIP sprzedawcy")
    func ownNIPExcluded() {
        let lines = [
            "Nabywca: Moja Firma, NIP: 1111111111",
            "Sprzedawca: ACME, NIP: 1234563218",
        ]
        let result = InvoiceOCRParser.parse(lines: lines, ownNIP: "1111111111")
        #expect(result.sellerTaxID == "1234563218")
        // Bez własnego NIP decyduje etykieta „Sprzedawca” — najbliższy NIP od niej.
        let anonymous = InvoiceOCRParser.parse(lines: lines)
        #expect(anonymous.sellerTaxID == "1234563218")
        // Bez etykiety i bez własnego NIP pierwszy poprawny NIP wygrywa.
        let unlabeled = InvoiceOCRParser.parse(lines: ["NIP: 1111111111", "NIP: 1234563218"])
        #expect(unlabeled.sellerTaxID == "1111111111")
    }

    @Test("NIP z separatorami i prefiksem PL oraz odrzucenie błędnej sumy kontrolnej")
    func nipFormats() {
        #expect(InvoiceOCRParser.parse(lines: ["NIP: PL 526-104-08-28"]).sellerTaxID == "5261040828")
        #expect(InvoiceOCRParser.parse(lines: ["NIP: 526 104 08 28"]).sellerTaxID == "5261040828")
        // 5261040820 ma błędną sumę kontrolną — nie jest NIP-em.
        #expect(InvoiceOCRParser.parse(lines: ["NIP: 5261040820"]).sellerTaxID == nil)
    }

    @Test("Zagraniczny VAT ID z prefiksem kraju UE w linii z „VAT”")
    func foreignVATID() {
        let result = InvoiceOCRParser.parse(lines: ["USt-IdNr / VAT ID: DE123456789"])
        #expect(result.sellerTaxID == "DE123456789")
        // Prefiks spoza UE (albo zwykłe słowo) nie jest identyfikatorem.
        #expect(InvoiceOCRParser.parse(lines: ["VAT ID: XX123456789"]).sellerTaxID == nil)
        // Bez kontekstu VAT/NIP w linii — brak rozpoznania.
        #expect(InvoiceOCRParser.parse(lines: ["DE123456789"]).sellerTaxID == nil)
    }

    @Test("Prefiks IBAN „PL61…” w linii „Rachunek VAT” nie jest identyfikatorem VAT")
    func ibanPrefixNotVATID() {
        let result = InvoiceOCRParser.parse(lines: ["Rachunek VAT: PL61 1090 1014 0000 0712 1981 2874"])
        #expect(result.sellerTaxID == nil)
        #expect(result.bankAccount == "61109010140000071219812874")
    }

    @Test("NIP z nagłówka papieru firmowego wygrywa z NIP nabywcy")
    func headerNIPBeatsBuyerNIP() {
        let result = InvoiceOCRParser.parse(lines: [
            "ACME Sp. z o.o. NIP 5261040828",
            "Sprzedawca: ACME Sp. z o.o.",
            "Nabywca:",
            "Klient Sp. k.",
            "NIP: 1234563218",
        ])
        #expect(result.sellerTaxID == "5261040828")
    }

    @Test("Nazwa sprzedawcy z linii etykiety albo spod niej; adres z kodem pocztowym")
    func sellerNameAndAddress() {
        let inline = InvoiceOCRParser.parse(lines: ["Sprzedawca: ACME Sp. z o.o."])
        #expect(inline.sellerName == "ACME Sp. z o.o.")

        let below = InvoiceOCRParser.parse(lines: [
            "Sprzedawca",
            "Hurtownia Papiernicza S.A.",
            "al. Pokoju 12",
            "00-001 Warszawa",
            "NIP 1234563218",
        ])
        #expect(below.sellerName == "Hurtownia Papiernicza S.A.")
        #expect(below.sellerAddress == "al. Pokoju 12, 00-001 Warszawa")
        #expect(below.sellerTaxID == "1234563218")
    }

    @Test("NIP w linii sprzedawcy nie staje się częścią nazwy")
    func inlineSellerMetadataExcludedFromName() {
        let result = InvoiceOCRParser.parse(lines: [
            "Sprzedawca: ACME Sp. z o.o., NIP: 526-104-08-28",
        ])
        #expect(result.sellerName == "ACME Sp. z o.o.")
        #expect(result.sellerTaxID == "5261040828")
    }

    @Test("Bez etykiety „Sprzedawca” nazwa nie jest zgadywana")
    func noSellerLabelNoGuess() {
        let result = InvoiceOCRParser.parse(lines: ["Jakaś Firma", "NIP: 1234563218"])
        #expect(result.sellerName == nil)
        #expect(result.sellerTaxID == "1234563218")
    }

    // MARK: - Waluta, rachunek, forma płatności

    @Test("Waluta: najczęstszy kod wygrywa; „zł” liczy się jako PLN")
    func currencyDetection() {
        #expect(InvoiceOCRParser.parse(lines: ["Do zapłaty: 100,00 EUR", "Razem EUR"]).currency == "EUR")
        #expect(InvoiceOCRParser.parse(lines: ["Do zapłaty: 100,00 zł"]).currency == "PLN")
        #expect(InvoiceOCRParser.parse(lines: ["bez waluty 100,00"]).currency == nil)
        // Kod wewnątrz słowa nie jest walutą.
        #expect(InvoiceOCRParser.parse(lines: ["SUPLNET dostawa"]).currency == nil)
    }

    @Test("Kody waluty, VAT ID i prefiks IBAN są niewrażliwe na wielkość liter")
    func identifiersAreCaseInsensitive() {
        let result = InvoiceOCRParser.parse(lines: [
            "VAT ID: de123456789",
            "Do zapłaty: 100,00 eur",
            "Konto: pl61 1090 1014 0000 0712 1981 2874",
        ])
        #expect(result.sellerTaxID == "DE123456789")
        #expect(result.currency == "EUR")
        #expect(result.bankAccount == "61109010140000071219812874")
    }

    @Test("Rachunek NRB: grupowany, z prefiksem PL i walidacją sumy kontrolnej")
    func bankAccountDetection() {
        let grouped = InvoiceOCRParser.parse(lines: ["Konto: 61 1090 1014 0000 0712 1981 2874"])
        #expect(grouped.bankAccount == "61109010140000071219812874")
        let compact = InvoiceOCRParser.parse(lines: ["PL61109010140000071219812874"])
        #expect(compact.bankAccount == "61109010140000071219812874")
        // Błędna suma kontrolna IBAN — brak rachunku.
        let invalid = InvoiceOCRParser.parse(lines: ["62 1090 1014 0000 0712 1981 2874"])
        #expect(invalid.bankAccount == nil)
    }

    @Test("Rachunek w kontekście nabywcy ustępuje rachunkowi do wpłaty")
    func buyerAccountDeprioritized() {
        let result = InvoiceOCRParser.parse(lines: [
            "Zaliczka z rachunku nabywcy 14 1020 1026 0000 0000 0000 1234",
            "Wpłata na konto: 61 1090 1014 0000 0712 1981 2874",
        ])
        #expect(result.bankAccount == "61109010140000071219812874")
        // Gdy jest tylko rachunek nabywcy — lepszy niż nic.
        let onlyBuyer = InvoiceOCRParser.parse(lines: [
            "Zaliczka z rachunku nabywcy 14 1020 1026 0000 0000 0000 1234",
        ])
        #expect(onlyBuyer.bankAccount == "14102010260000000000001234")
    }

    @Test("Forma płatności z etykiety oraz domyślny przelew ze wzmianki")
    func paymentFormDetection() {
        #expect(InvoiceOCRParser.parse(lines: ["Sposób zapłaty: karta"]).paymentForm == .card)
        #expect(InvoiceOCRParser.parse(lines: ["Forma płatności:", "gotówka"]).paymentForm == .cash)
        #expect(InvoiceOCRParser.parse(lines: ["płatne przelewem na konto"]).paymentForm == .transfer)
        #expect(InvoiceOCRParser.parse(lines: ["Faktura VAT"]).paymentForm == nil)
    }

    // MARK: - Nanoszenie na szkic

    @Test("applied(to:) nadpisuje tylko rozpoznane pola; nabywca, status i uwagi nietknięte")
    func appliedToDraft() {
        var draft = ManualPurchaseDraft()
        draft.buyerName = "Moja Firma"
        draft.buyerNIP = "1111111111"
        draft.notes = "notatka"
        draft.costCategory = "Paliwo i transport"
        draft.isPaid = true
        draft.sellerName = "Stara nazwa"

        let extraction = InvoiceOCRExtraction(
            documentNumber: "FV/1/2026",
            issueDate: day("2026-07-10"),
            sellerName: "ACME Sp. z o.o.",
            sellerTaxID: "5261040828",
            netAmount: 100,
            vatAmount: 23,
            currency: "PLN",
            bankAccount: "61109010140000071219812874",
            paymentDueDate: day("2026-07-24"),
            paymentForm: .transfer
        )
        let merged = extraction.applied(to: draft)
        #expect(merged.documentNumber == "FV/1/2026")
        #expect(merged.issueDate == day("2026-07-10"))
        #expect(merged.sellerName == "ACME Sp. z o.o.")
        #expect(merged.sellerTaxID == "5261040828")
        #expect(merged.netAmount == 100)
        #expect(merged.vatAmount == 23)
        #expect(merged.grossAmount == 123)
        #expect(merged.paymentBankAccount == "61109010140000071219812874")
        #expect(merged.paymentDueDate == day("2026-07-24"))
        #expect(merged.paymentForm == .transfer)
        // Pola nierozpoznane / niedotykane przez OCR:
        #expect(merged.buyerName == "Moja Firma")
        #expect(merged.buyerNIP == "1111111111")
        #expect(merged.notes == "notatka")
        #expect(merged.costCategory == "Paliwo i transport")
        #expect(merged.isPaid == true)
        #expect(merged.saleDate == nil)
    }

    @Test("Puste rozpoznanie zostawia szkic bez zmian")
    func emptyExtractionKeepsDraft() {
        var draft = ManualPurchaseDraft()
        draft.documentNumber = "FZ/9/2026"
        draft.sellerName = "Dostawca"
        draft.netAmount = 50
        let merged = InvoiceOCRExtraction().applied(to: draft)
        #expect(merged == draft)
    }

    @Test("Samo brutto trafia do netto z VAT = 0 (paragon)")
    func grossOnlyGoesToNet() {
        let merged = InvoiceOCRExtraction(grossAmount: 615).applied(to: ManualPurchaseDraft())
        #expect(merged.netAmount == 615)
        #expect(merged.vatAmount == 0)
        #expect(merged.grossAmount == 615)
    }

    @Test("recognizedFieldNames wymienia po polsku rozpoznane pola")
    func recognizedFieldNames() {
        let extraction = InvoiceOCRExtraction(
            documentNumber: "FV/1/2026",
            issueDate: .now,
            grossAmount: 123,
            currency: "PLN"
        )
        #expect(extraction.recognizedFieldNames == ["numer dokumentu", "data wystawienia", "kwoty", "waluta"])
        #expect(InvoiceOCRExtraction().recognizedFieldNames.isEmpty)
    }

    // MARK: - Normalizacja

    @Test("Normalizacja etykiet usuwa polskie znaki, w tym „ł”")
    func normalization() {
        #expect(InvoiceOCRParser.normalized("Termin PŁATNOŚCI") == "termin platnosci")
        #expect(InvoiceOCRParser.normalized("Data sprzedaży") == "data sprzedazy")
        #expect(InvoiceOCRParser.normalized("źdźbło ĄĘĆŃÓŚŻŹŁ") == "zdzblo aecnoszzl")
    }
}
