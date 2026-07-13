import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Karta i historia kontrahenta")
@MainActor
struct ContractorHistoryTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, PaymentRecord.self, configurations: configuration
        )
        return ModelContext(container)
    }

    private func date(_ value: String) -> Date {
        FA2Format.dateFormatter.date(from: value)!
    }

    private func makeInvoice(
        number: String,
        issue: String = "2026-07-01",
        kind: Invoice.Kind = .sales,
        sellerNIP: String = "9999999999",
        buyerNIP: String = "1234567890",
        gross: Double = 100,
        due: String? = nil,
        paidAt: String? = nil,
        isPaid: Bool = false,
        currency: String = "PLN",
        hidden: Bool = false
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: date(issue),
            sellerName: "Sprzedawca",
            sellerNIP: sellerNIP,
            buyerName: "Nabywca",
            buyerNIP: buyerNIP,
            netAmount: gross,
            vatAmount: 0,
            grossAmount: gross,
            isPaid: isPaid,
            paymentDueDate: due.map(date),
            paymentDate: paidAt.map(date),
            isArchivedOrHidden: hidden,
            currency: currency,
            kind: kind
        )
    }

    @Test("NIP łączy sprzedaż i zakup niezależnie od separatorów, a ukryte i obce dokumenty pomija")
    func matchesDocumentsByCounterpartyRole() {
        let sale = makeInvoice(number: "S/1", buyerNIP: "PL 123-456-78-90")
        let purchase = makeInvoice(
            number: "Z/1", issue: "2026-07-02", kind: .purchase,
            sellerNIP: "123 456 78 90", buyerNIP: "9999999999"
        )
        let hidden = makeInvoice(number: "S/2", buyerNIP: "1234567890", hidden: true)
        let wrongPurchaseSide = makeInvoice(
            number: "Z/2", kind: .purchase,
            sellerNIP: "1111111111", buyerNIP: "1234567890"
        )
        let other = makeInvoice(number: "S/3", buyerNIP: "2222222222")

        let history = ContractorHistory(
            invoices: [sale, purchase, hidden, wrongPurchaseSide, other],
            contractorNIP: "pl1234567890"
        )

        #expect(history.invoices.map(\.invoiceNumber) == ["Z/1", "S/1"])
        #expect(history.salesCount == 1)
        #expect(history.purchaseCount == 1)
    }

    @Test("Saldo zachowuje waluty, częściowe wpłaty, kierunek i ujemną korektę")
    func balancesByCurrency() throws {
        let context = try makeContext()
        let sale = makeInvoice(number: "S/1", gross: 100)
        let correction = makeInvoice(number: "K/1", gross: -10)
        let purchase = makeInvoice(
            number: "Z/1", kind: .purchase,
            sellerNIP: "1234567890", buyerNIP: "9999999999", gross: 40
        )
        let euroSale = makeInvoice(number: "S/2", gross: 50, currency: "eur")
        let settled = makeInvoice(number: "S/3", gross: 999, isPaid: true)
        [sale, correction, purchase, euroSale, settled].forEach(context.insert)
        sale.payments = [PaymentRecord(amount: 25, date: date("2026-07-05"))]
        try context.save()

        let history = ContractorHistory(
            invoices: [sale, correction, purchase, euroSale, settled],
            contractorNIP: "1234567890"
        )
        let eur = try #require(history.balances.first { $0.currency == "EUR" })
        let pln = try #require(history.balances.first { $0.currency == "PLN" })

        #expect(eur.receivables == 50)
        #expect(eur.payables == 0)
        #expect(pln.receivables == 65) // 100 − 25 − 10 korekty
        #expect(pln.payables == 40)
        #expect(pln.net == 25)
    }

    @Test("Średnia i scoring używają pełnej zapłaty sprzedaży oraz bieżących zaległości")
    func paymentBehaviorMetrics() throws {
        let context = try makeContext()
        let onTime = makeInvoice(
            number: "S/1", issue: "2026-07-01", due: "2026-07-10",
            paidAt: "2026-07-10", isPaid: true
        )
        let late = makeInvoice(
            number: "S/2", issue: "2026-07-01", due: "2026-07-05", isPaid: true
        )
        let overdue = makeInvoice(
            number: "S/3", issue: "2026-07-01", due: "2026-07-15"
        )
        let future = makeInvoice(
            number: "S/4", issue: "2026-07-01", due: "2026-08-01"
        )
        let manuallyPaidWithoutDate = makeInvoice(
            number: "S/5", issue: "2026-07-01", due: "2026-07-05", isPaid: true
        )
        let purchase = makeInvoice(
            number: "Z/1", issue: "2026-07-01", kind: .purchase,
            sellerNIP: "1234567890", buyerNIP: "9999999999", gross: 100,
            due: "2026-07-05", paidAt: "2026-07-20", isPaid: true
        )
        [onTime, late, overdue, future, manuallyPaidWithoutDate, purchase].forEach(context.insert)
        late.payments = [
            PaymentRecord(amount: 50, date: date("2026-07-03")),
            PaymentRecord(amount: 50, date: date("2026-07-08")),
        ]
        try context.save()

        let history = ContractorHistory(
            invoices: [onTime, late, overdue, future, manuallyPaidWithoutDate, purchase],
            contractorNIP: "1234567890",
            asOf: date("2026-07-20")
        )

        #expect(history.paymentTimeSampleCount == 2)
        #expect(history.averagePaymentDays == 8) // (9 dni + 7 dni) / 2
        #expect(history.onTimeCount == 1)
        #expect(history.timelinessSampleCount == 3)
        #expect(history.onTimeRate == 1.0 / 3.0)
        #expect(history.score == .poor)
    }

    @Test("Scoring ma jawne progi i stan bez danych")
    func scoreBands() {
        #expect(ContractorHistory.paymentScore(for: nil) == .unrated)
        #expect(ContractorHistory.paymentScore(for: 0.90) == .excellent)
        #expect(ContractorHistory.paymentScore(for: 0.75) == .good)
        #expect(ContractorHistory.paymentScore(for: 0.50) == .needsAttention)
        #expect(ContractorHistory.paymentScore(for: 0.49) == .poor)
    }

    @Test("Pusty identyfikator podatkowy nie łączy przypadkowych dokumentów")
    func emptyTaxIDDoesNotMatch() {
        let invoice = makeInvoice(number: "S/1", buyerNIP: "")
        let history = ContractorHistory(invoices: [invoice], contractorNIP: " - ")
        #expect(history.invoices.isEmpty)
        #expect(history.score == .unrated)
    }
}
