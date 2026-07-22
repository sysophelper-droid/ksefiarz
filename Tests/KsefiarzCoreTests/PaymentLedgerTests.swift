import Foundation
import Testing
@testable import KsefiarzCore

private func makeInvoice(
    number: String = "FV/2026/07/001",
    gross: Double = 123,
    kind: Invoice.Kind = .sales,
    isPaid: Bool = false
) -> Invoice {
    Invoice(
        invoiceNumber: number,
        issueDate: .now,
        sellerName: "Sprzedawca", sellerNIP: "1111111111",
        buyerName: "Nabywca", buyerNIP: "2222222222",
        netAmount: gross / 1.23, vatAmount: gross - gross / 1.23, grossAmount: gross,
        isPaid: isPaid,
        kind: kind
    )
}

// MARK: - Księga płatności

@Suite("PaymentLedger — płatności częściowe i saldo")
@MainActor
struct PaymentLedgerTests {

    @Test("Wpłata częściowa zmniejsza saldo, nie oznacza faktury jako opłaconej")
    func partialPayment() {
        let invoice = makeInvoice(gross: 123)
        PaymentLedger.register(amount: 50, note: "zaliczka", on: invoice)

        #expect(invoice.paidAmount == 50)
        #expect(abs(invoice.outstandingAmount - 73) < 0.001)
        #expect(invoice.isPartiallyPaid)
        #expect(!invoice.isPaid)
    }

    @Test("Domknięcie salda oznacza fakturę jako opłaconą (także w dwóch ratach)")
    func fullCoverageMarksPaid() {
        let invoice = makeInvoice(gross: 123)
        PaymentLedger.register(amount: 100, on: invoice)
        #expect(!invoice.isPaid)
        PaymentLedger.register(amount: 23, on: invoice)

        #expect(invoice.isPaid)
        #expect(invoice.outstandingAmount == 0)
        #expect(invoice.payments.count == 2)
    }

    @Test("Grosze: pokrycie w granicach tolerancji domyka fakturę")
    func toleranceHandling() {
        let invoice = makeInvoice(gross: 100)
        PaymentLedger.register(amount: 99.999, on: invoice)
        #expect(invoice.isPaid)
    }

    @Test("Nadpłata nie psuje salda (saldo nie schodzi poniżej zera)")
    func overpayment() {
        let invoice = makeInvoice(gross: 100)
        PaymentLedger.register(amount: 150, on: invoice)
        #expect(invoice.isPaid)
        #expect(invoice.outstandingAmount == 0)
        #expect(invoice.paidAmount == 150)
    }

    @Test("Ręczny znacznik „opłacona” jest nadrzędny — saldo 0 bez wpłat")
    func manualPaidMarker() {
        let invoice = makeInvoice(gross: 123, isPaid: true)
        #expect(invoice.outstandingAmount == 0)
        #expect(!invoice.isPartiallyPaid)
    }

    @Test("Usunięcie wpłaty domykającej saldo cofa znacznik opłacenia")
    func removalRevertsAutoPaid() throws {
        let invoice = makeInvoice(gross: 100)
        PaymentLedger.register(amount: 40, on: invoice)
        let closing = try #require(PaymentLedger.register(amount: 60, on: invoice))
        #expect(invoice.isPaid)

        PaymentLedger.remove(closing, from: invoice)
        #expect(!invoice.isPaid)
        #expect(invoice.paidAmount == 40)
        #expect(invoice.isPartiallyPaid)
    }

    @Test("Usunięcie wpłaty częściowej NIE cofa ręcznego znacznika opłacenia")
    func removalKeepsManualPaid() throws {
        // Faktura „z góry” (np. gotówka) — opłacona bez kompletu wpłat.
        let invoice = makeInvoice(gross: 123, isPaid: true)
        let partial = try #require(PaymentLedger.register(amount: 10, on: invoice))
        #expect(invoice.isPaid)

        PaymentLedger.remove(partial, from: invoice)
        // Wpłaty nie pokrywały kwoty ani przed, ani po — znacznik zostaje.
        #expect(invoice.isPaid)
        #expect(invoice.payments.isEmpty)
    }
}

// MARK: - Parser MT940

@Suite("MT940Parser — wyciągi bankowe")
struct MT940ParserTests {

    private let sample = """
    :20:MT940
    :25:PL26109024020000000612345678
    :28C:00123
    :60F:C260708PLN10000,00
    :61:2607080708C1234,56NTRFNONREF//BR26070800001
    :86:~00VAN~20FV/2026/07/001 zaplata~21za fakture~22~23~24~25~3010901234~310000000000000001~32ACME SPOLKA Z O.O.~33~38PL61109010140000071219812874
    :61:2607090709D200,00NTRFNONREF//BR26070900002
    :86:~00VAN~20Oplata za prad 06/2026~32ZAKLAD ENERGETYCZNY
    :61:2607100710C50,00NTRFNONREF//BR26071000003
    :86:przelew przychodzacy bez podpol
    :62F:C260710PLN11084,56
    """

    @Test("Parsuje operacje: daty, strony C/D, kwoty i opisy z podpól")
    func parsesTransactions() throws {
        let transactions = MT940Parser.parse(sample)
        #expect(transactions.count == 3)

        let credit = try #require(transactions.first)
        #expect(abs(credit.amount - 1234.56) < 0.001)
        #expect(credit.title == "FV/2026/07/001 zaplataza fakture")
        #expect(credit.counterparty == "ACME SPOLKA Z O.O.")
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(identifier: "Europe/Warsaw")!, from: credit.date
        )
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 8)

        let debit = transactions[1]
        #expect(abs(debit.amount + 200) < 0.001) // obciążenie = kwota ujemna
        #expect(debit.title.contains("Oplata za prad"))
        #expect(debit.counterparty == "ZAKLAD ENERGETYCZNY")

        // Opis bez podpól ~ trafia w całości do tytułu.
        #expect(transactions[2].title == "przelew przychodzacy bez podpol")
        #expect(abs(transactions[2].amount - 50) < 0.001)
    }

    @Test("Storno (RC/RD) odwraca stronę operacji")
    func reversals() {
        let text = """
        :61:2607080708RC100,00NTRF
        :86:zwrot uznania
        :61:2607080708RD75,50NTRF
        :86:zwrot obciazenia
        """
        let transactions = MT940Parser.parse(text)
        #expect(transactions.count == 2)
        #expect(abs(transactions[0].amount + 100) < 0.001)  // RC → wypływ
        #expect(abs(transactions[1].amount - 75.5) < 0.001) // RD → wpływ
    }

    @Test("Pole :61: z datą księgowania (MMDD) i bez kodu N jest akceptowane")
    func optionalSegments() {
        let parsed = MT940Parser.parseStatementLine("260708C99,99")
        #expect(parsed != nil)
        #expect(abs((parsed?.1 ?? 0) - 99.99) < 0.001)
    }

    @Test("Dekodowanie: pliki Windows-1250 czytają polskie znaki")
    func encodingFallback() throws {
        let text = ":86:Opłata za usługę"
        let data = try #require(text.data(using: .windowsCP1250))
        #expect(MT940Parser.decode(data).contains("Opłata za usługę"))
    }
}

// MARK: - Dopasowanie przelewów

@Suite("PaymentMatcher — propozycje dopasowań")
@MainActor
struct PaymentMatcherTests {

    @Test("Numer faktury w tytule przelewu daje pewne dopasowanie")
    func matchByInvoiceNumber() {
        let invoice = makeInvoice(number: "FV/2026/07/001", gross: 123)
        let other = makeInvoice(number: "FV/2026/07/002", gross: 999)
        let transaction = BankTransaction(
            date: .now, amount: 123,
            title: "Zaplata za FV 2026 07 001", counterparty: "ACME"
        )

        let proposals = PaymentMatcher.proposals(
            transactions: [transaction], invoices: [other, invoice]
        )
        #expect(proposals.count == 1)
        #expect(proposals[0].invoiceID == invoice.id)
        #expect(proposals[0].confidence == .invoiceNumber)
    }

    @Test("Dłuższy numer wygrywa — FV/07/0012 nie dopasuje się do FV/07/001")
    func longerNumberWins() {
        let short = makeInvoice(number: "FV/07/001", gross: 100)
        let long = makeInvoice(number: "FV/07/0012", gross: 200)
        let transaction = BankTransaction(date: .now, amount: 200, title: "FV/07/0012")

        let proposals = PaymentMatcher.proposals(
            transactions: [transaction], invoices: [short, long]
        )
        #expect(proposals[0].invoiceID == long.id)
    }

    @Test("Zgodna kwota salda daje dopasowanie tylko przy jednoznaczności")
    func matchByAmount() {
        let unique = makeInvoice(number: "A/1", gross: 777)
        let twinA = makeInvoice(number: "B/1", gross: 200)
        let twinB = makeInvoice(number: "B/2", gross: 200)

        let matched = PaymentMatcher.proposals(
            transactions: [BankTransaction(date: .now, amount: 777, title: "przelew")],
            invoices: [unique, twinA, twinB]
        )
        #expect(matched[0].invoiceID == unique.id)
        #expect(matched[0].confidence == .uniqueAmount)

        // Dwie faktury po 200 zł — kwota nie wskazuje jednej: brak propozycji.
        let ambiguous = PaymentMatcher.proposals(
            transactions: [BankTransaction(date: .now, amount: 200, title: "przelew")],
            invoices: [unique, twinA, twinB]
        )
        #expect(ambiguous[0].invoiceID == nil)
        #expect(ambiguous[0].confidence == .none)
    }

    @Test("Kwota porównywana jest z saldem — częściowo opłacona faktura pasuje resztą")
    func amountMatchesOutstanding() {
        let invoice = makeInvoice(number: "C/1", gross: 300)
        PaymentLedger.register(amount: 100, on: invoice)

        let proposals = PaymentMatcher.proposals(
            transactions: [BankTransaction(date: .now, amount: 200, title: "doplata")],
            invoices: [invoice]
        )
        #expect(proposals[0].invoiceID == invoice.id)
    }

    @Test("Wpływy dopasowują sprzedaż, wypływy — zakupy")
    func directionSplitsPools() {
        let sale = makeInvoice(number: "S/1", gross: 100, kind: .sales)
        let purchase = makeInvoice(number: "Z/1", gross: 100, kind: .purchase)

        let proposals = PaymentMatcher.proposals(
            transactions: [
                BankTransaction(date: .now, amount: 100, title: "za S/1"),
                BankTransaction(date: .now, amount: -100, title: "za Z/1"),
            ],
            invoices: [sale, purchase]
        )
        #expect(proposals[0].invoiceID == sale.id)
        #expect(proposals[1].invoiceID == purchase.id)
    }

    @Test("Faktury opłacone i ukryte nie biorą udziału w dopasowaniu")
    func excludesPaidAndHidden() {
        let paid = makeInvoice(number: "P/1", gross: 100, isPaid: true)
        let hidden = makeInvoice(number: "H/1", gross: 100)
        hidden.isArchivedOrHidden = true

        let proposals = PaymentMatcher.proposals(
            transactions: [BankTransaction(date: .now, amount: 100, title: "za P/1 H/1")],
            invoices: [paid, hidden]
        )
        #expect(proposals[0].invoiceID == nil)
    }

    @Test("Zatwierdzenie propozycji księguje wpłaty z opisem i źródłem wyciągu")
    func applyProposals() {
        let invoice = makeInvoice(number: "FV/9", gross: 100)
        let transaction = BankTransaction(
            date: .now, amount: 100, title: "za FV/9", counterparty: "ACME"
        )
        let proposals = PaymentMatcher.proposals(
            transactions: [transaction], invoices: [invoice]
        )
        let applied = PaymentMatcher.apply(proposals, invoices: [invoice])

        #expect(applied == 1)
        #expect(invoice.isPaid)
        #expect(invoice.payments.count == 1)
        #expect(invoice.payments[0].source == .bankImport)
        #expect(invoice.payments[0].note == "za FV/9 — ACME")
    }
}

// MARK: - Kopia zapasowa wpłat

@Suite("Kopia zapasowa — historia wpłat")
@MainActor
struct PaymentBackupTests {

    @Test("Wpłaty przechodzą round-trip przez eksport i import kopii")
    func paymentsRoundTrip() throws {
        let invoice = makeInvoice(gross: 300)
        PaymentLedger.register(
            amount: 100,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            note: "zaliczka",
            on: invoice
        )
        PaymentLedger.register(
            amount: 50,
            date: Date(timeIntervalSince1970: 1_800_100_000),
            note: "przelew — ACME",
            source: .bankImport,
            on: invoice
        )

        let data = try BackupService.makeBackup(invoices: [invoice], settings: [:])
        let decoded = try BackupService.decode(data)
        let entry = try #require(decoded.invoices.first)
        let payments = try #require(entry.payments)
        #expect(payments.count == 2)
        #expect(payments.contains { $0.amount == 100 && $0.note == "zaliczka" })
        #expect(payments.contains { $0.amount == 50 && $0.sourceRaw == PaymentRecord.Source.bankImport.rawValue })

        // Odtworzenie modeli z kopii zachowuje kwoty, daty i źródła.
        let restored = BackupService.makePayments(for: entry)
        #expect(restored.count == 2)
        #expect(restored.reduce(0) { $0 + $1.amount } == 150)
        #expect(restored.contains { $0.source == .bankImport })

        // Starsza kopia bez pola payments odtwarza pustą historię.
        var legacy = entry
        legacy.payments = nil
        #expect(BackupService.makePayments(for: legacy).isEmpty)
    }
}
