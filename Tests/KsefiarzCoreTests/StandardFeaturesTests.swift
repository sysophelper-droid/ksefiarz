import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Filtr wyświetlania (Kokpit i listy)")
struct DisplayDateFilterTests {

    private let now = FA2Format.dateFormatter.date(from: "2026-06-11")!
    private func day(_ string: String) -> Date {
        FA2Format.dateFormatter.date(from: string)!
    }

    private func invoice(issued: String) -> Invoice {
        let invoice = makeTestInvoice(number: "FV/\(issued)")
        invoice.issueDate = day(issued)
        return invoice
    }

    @Test("Filtr „Wszystkie” nie ogranicza listy")
    func allFilter() {
        let invoices = [invoice(issued: "2020-01-01"), invoice(issued: "2026-06-10")]
        #expect(DisplayDateFilter.all.apply(to: invoices, now: now).count == 2)
        #expect(DisplayDateFilter.all.range(now: now) == nil)
    }

    @Test("Bieżący miesiąc, poprzedni miesiąc i bieżący rok")
    func monthAndYearFilters() {
        let invoices = [
            invoice(issued: "2026-06-05"),  // bieżący miesiąc
            invoice(issued: "2026-05-20"),  // poprzedni miesiąc
            invoice(issued: "2026-01-15"),  // bieżący rok
            invoice(issued: "2025-12-31"),  // poprzedni rok
        ]
        #expect(DisplayDateFilter.currentMonth.apply(to: invoices, now: now).map(\.invoiceNumber) == ["FV/2026-06-05"])
        #expect(DisplayDateFilter.lastMonth.apply(to: invoices, now: now).map(\.invoiceNumber) == ["FV/2026-05-20"])
        #expect(DisplayDateFilter.currentYear.apply(to: invoices, now: now).count == 3)
        #expect(DisplayDateFilter.last3Months.apply(to: invoices, now: now).count == 2)
    }
}

@Suite("Automatyczna numeracja faktur")
struct InvoiceNumberGeneratorTests {

    private let june = FA2Format.dateFormatter.date(from: "2026-06-11")!

    @Test("Pierwsza faktura w miesiącu dostaje numer 001 (wzorzec domyślny)")
    func firstInMonth() {
        #expect(InvoiceNumberGenerator.nextNumber(existing: [], date: june) == "FV/2026/06/001")
        // Numery z innych miesięcy nie wpływają na licznik.
        #expect(InvoiceNumberGenerator.nextNumber(existing: ["FV/2026/05/009"], date: june) == "FV/2026/06/001")
    }

    @Test("Kolejny numer to najwyższy istniejący + 1")
    func incrementsHighest() {
        let existing = ["FV/2026/06/001", "FV/2026/06/007", "FV/2026/06/003", "inny-format"]
        #expect(InvoiceNumberGenerator.nextNumber(existing: existing, date: june) == "FV/2026/06/008")
    }

    @Test("Własne wzorce: różne symbole dat i pozycja licznika")
    func customPatterns() {
        // Licznik na początku, rok dwucyfrowy.
        #expect(InvoiceNumberGenerator.nextNumber(pattern: "{NN}/{MM}/{RR}", existing: ["03/06/26"], date: june) == "04/06/26")
        // Numeracja roczna (bez miesiąca) — czerwiec kontynuuje licznik z maja.
        #expect(
            InvoiceNumberGenerator.nextNumber(pattern: "F/{NNNN}/{RRRR}", existing: ["F/0041/2026"], date: june)
                == "F/0042/2026"
        )
        // Własny prefiks tekstowy.
        #expect(InvoiceNumberGenerator.nextNumber(pattern: "ACME-{RRRR}{MM}-{N}", existing: ["ACME-202606-9"], date: june) == "ACME-202606-10")
    }

    @Test("Licznik szerszy niż wzorzec nie jest obcinany")
    func widthOverflow() {
        #expect(
            InvoiceNumberGenerator.nextNumber(pattern: "FV/{MM}/{N}", existing: ["FV/06/99"], date: june)
                == "FV/06/100"
        )
    }

    @Test("Wzorzec bez licznika i wzorzec pusty są normalizowane")
    func normalization() {
        // Bez {N…} — licznik dopisany na końcu.
        #expect(InvoiceNumberGenerator.nextNumber(pattern: "FV/{RRRR}", existing: [], date: june) == "FV/2026/001")
        // Pusty wzorzec — domyślny.
        #expect(InvoiceNumberGenerator.nextNumber(pattern: "  ", existing: [], date: june) == "FV/2026/06/001")
        #expect(!InvoiceNumberGenerator.hasSequenceToken("FV/{RRRR}"))
        #expect(InvoiceNumberGenerator.hasSequenceToken("FV/{NNN}"))
    }

    @Test("Podgląd wzorca w Ustawieniach")
    func preview() {
        #expect(InvoiceNumberGenerator.preview(pattern: "RACH/{RR}/{NN}", date: june) == "RACH/26/01")
    }
}

@Suite("Kwota słownie")
struct AmountInWordsTests {

    @Test("Podstawowe liczby")
    func basicNumbers() {
        #expect(AmountInWords.numberInWords(0) == "zero")
        #expect(AmountInWords.numberInWords(7) == "siedem")
        #expect(AmountInWords.numberInWords(15) == "piętnaście")
        #expect(AmountInWords.numberInWords(42) == "czterdzieści dwa")
        #expect(AmountInWords.numberInWords(123) == "sto dwadzieścia trzy")
        #expect(AmountInWords.numberInWords(999) == "dziewięćset dziewięćdziesiąt dziewięć")
    }

    @Test("Tysiące i miliony z polską odmianą")
    func thousandsAndMillions() {
        #expect(AmountInWords.numberInWords(1000) == "tysiąc")
        #expect(AmountInWords.numberInWords(2000) == "dwa tysiące")
        #expect(AmountInWords.numberInWords(5000) == "pięć tysięcy")
        #expect(AmountInWords.numberInWords(12000) == "dwanaście tysięcy")
        #expect(AmountInWords.numberInWords(22000) == "dwadzieścia dwa tysiące")
        #expect(AmountInWords.numberInWords(1_000_000) == "milion")
        #expect(AmountInWords.numberInWords(3_000_000) == "trzy miliony")
        #expect(AmountInWords.numberInWords(1_234_567)
            == "milion dwieście trzydzieści cztery tysiące pięćset sześćdziesiąt siedem")
    }

    @Test("Kwoty walutowe z odmianą „złoty” i groszami")
    func currencyAmounts() {
        #expect(AmountInWords.polishCurrency(1.00) == "jeden złoty 00/100")
        #expect(AmountInWords.polishCurrency(2.50) == "dwa złote 50/100")
        #expect(AmountInWords.polishCurrency(5.05) == "pięć złotych 05/100")
        #expect(AmountInWords.polishCurrency(123.45) == "sto dwadzieścia trzy złote 45/100")
        #expect(AmountInWords.polishCurrency(0.99) == "zero złotych 99/100")
        #expect(AmountInWords.polishCurrency(1953.00) == "tysiąc dziewięćset pięćdziesiąt trzy złote 00/100")
    }

    @Test("Zaokrąglanie groszy")
    func roundsGrosze() {
        // 171.2 → 171 zł 20 gr (bez błędu zmiennoprzecinkowego).
        #expect(AmountInWords.polishCurrency(171.2) == "sto siedemdziesiąt jeden złotych 20/100")
    }
}

@Suite("Polityka form płatności")
struct PaymentFormPolicyTests {

    @Test("Domyślnie gotówka, karta, bon i mobilna są opłacone z góry")
    func defaults() {
        let prepaid = PaymentFormPolicy.defaultPrepaidForms
        #expect(PaymentFormPolicy.isPrepaid(.cash, prepaidForms: prepaid))
        #expect(PaymentFormPolicy.isPrepaid(.card, prepaidForms: prepaid))
        #expect(PaymentFormPolicy.isPrepaid(.mobile, prepaidForms: prepaid))
        // Przelew, czek i kredyt — odroczone.
        #expect(!PaymentFormPolicy.isPrepaid(.transfer, prepaidForms: prepaid))
        #expect(!PaymentFormPolicy.isPrepaid(.cheque, prepaidForms: prepaid))
        #expect(!PaymentFormPolicy.isPrepaid(nil, prepaidForms: prepaid))
    }

    @Test("Serializacja zestawu form do @AppStorage i z powrotem")
    func encodeDecode() {
        let forms: Set<String> = [PaymentForm.cash.rawValue, PaymentForm.transfer.rawValue]
        let encoded = PaymentFormPolicy.encode(forms)
        #expect(PaymentFormPolicy.decode(encoded) == forms)
        // Pusty zestaw (świadomie nic nie jest opłacone z góry).
        #expect(PaymentFormPolicy.decode(PaymentFormPolicy.encode([])).isEmpty)
    }

    @Test("Polityka ustawia status opłacenia, ale nigdy go nie cofa")
    func applyPolicy() {
        let prepaid = PaymentFormPolicy.defaultPrepaidForms

        // Gotówka → oznaczona jako opłacona.
        let cashInvoice = makeTestInvoice(number: "GOTOWKA")
        cashInvoice.paymentFormRaw = PaymentForm.cash.rawValue
        PaymentFormPolicy.apply(to: cashInvoice, prepaidForms: prepaid)
        #expect(cashInvoice.isPaid)

        // Przelew → pozostaje do opłacenia.
        let transferInvoice = makeTestInvoice(number: "PRZELEW")
        transferInvoice.paymentFormRaw = PaymentForm.transfer.rawValue
        PaymentFormPolicy.apply(to: transferInvoice, prepaidForms: prepaid)
        #expect(!transferInvoice.isPaid)

        // Ręcznie opłacona faktura przelewowa nie jest cofana.
        let manuallyPaid = makeTestInvoice(number: "RECZNA", isPaid: true)
        manuallyPaid.paymentFormRaw = PaymentForm.transfer.rawValue
        PaymentFormPolicy.apply(to: manuallyPaid, prepaidForms: prepaid)
        #expect(manuallyPaid.isPaid)

        // Konfiguracja użytkownika ma pierwszeństwo: gotówka wyłączona z „z góry”.
        let custom: Set<String> = []
        let cashDeferred = makeTestInvoice(number: "GOTOWKA-ODROCZONA")
        cashDeferred.paymentFormRaw = PaymentForm.cash.rawValue
        PaymentFormPolicy.apply(to: cashDeferred, prepaidForms: custom)
        #expect(!cashDeferred.isPaid)
    }
}

@Suite("Eksport CSV")
struct InvoiceCSVExporterTests {

    @Test("CSV zawiera nagłówek i wiersze z polskim formatem kwot")
    func generatesCSV() {
        let invoice = makeTestInvoice(number: "FV/1", isPaid: true, gross: 123.0, ksefId: "KSEF-1")
        let csv = InvoiceCSVExporter.csv(for: [invoice])
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Numer;Numer KSeF;Rodzaj"))
        #expect(lines[1].contains("FV/1;KSEF-1;Zakup"))
        // Kwoty z przecinkiem dziesiętnym.
        #expect(lines[1].contains("123,00"))
        #expect(lines[1].contains("opłacona"))
    }

    @Test("Wartości ze średnikiem są ujmowane w cudzysłowy")
    func escapesSeparator() {
        let invoice = makeTestInvoice(number: "FV/2", sellerName: "Firma; z średnikiem")
        let csv = InvoiceCSVExporter.csv(for: [invoice])
        #expect(csv.contains("\"Firma; z średnikiem\""))
    }
}
