import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Analityka Kokpitu — przepływy, VAT, wiekowanie, porównania")
@MainActor
struct DashboardAnalyticsTests {

    /// Stały punkt odniesienia: 15 lipca 2026, południe.
    private let now = FA2Format.dateFormatter.date(from: "2026-07-15")!.addingTimeInterval(12 * 3600)

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, PaymentRecord.self, configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeInvoice(
        number: String,
        issue: String,
        kind: Invoice.Kind,
        net: Double,
        vat: Double,
        due: String? = nil,
        isPaid: Bool = false,
        currency: String = "PLN",
        exchangeRate: Double = 0
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: issue)!,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: net, vatAmount: vat, grossAmount: net + vat,
            isPaid: isPaid,
            paymentDueDate: due.flatMap { FA2Format.dateFormatter.date(from: $0) },
            currency: currency,
            exchangeRate: exchangeRate,
            kind: kind
        )
    }

    @Test("VAT należny i naliczony liczone z okresu, waluty po kursie faktury")
    func vatSums() {
        let sale = makeInvoice(number: "S/1", issue: "2026-07-01", kind: .sales, net: 100, vat: 23)
        let saleEUR = makeInvoice(
            number: "S/2", issue: "2026-07-02", kind: .sales, net: 100, vat: 19,
            currency: "EUR", exchangeRate: 4.0
        )
        let purchase = makeInvoice(number: "Z/1", issue: "2026-07-03", kind: .purchase, net: 200, vat: 46)

        let analytics = DashboardAnalytics(
            invoices: [sale, saleEUR, purchase],
            periodInvoices: [sale, saleEUR, purchase],
            now: now
        )
        #expect(analytics.vatDue == 23 + 19 * 4.0)
        #expect(analytics.vatInput == 46)
        #expect(analytics.vatBalance == 23 + 76 - 46)
    }

    @Test("Przepływy: wpłaty sprzedaży to wpływy, zakupów wydatki, per miesiąc")
    func cashFlowBuckets() throws {
        let context = try makeContext()
        let sale = makeInvoice(number: "S/1", issue: "2026-06-01", kind: .sales, net: 100, vat: 23)
        let purchase = makeInvoice(number: "Z/1", issue: "2026-06-05", kind: .purchase, net: 50, vat: 11.5)
        context.insert(sale)
        context.insert(purchase)
        // Wpłaty PO wstawieniu do kontekstu (relacja SwiftData).
        sale.payments = [
            PaymentRecord(amount: 60, date: FA2Format.dateFormatter.date(from: "2026-06-10")!),
            PaymentRecord(amount: 63, date: FA2Format.dateFormatter.date(from: "2026-07-01")!),
        ]
        purchase.payments = [
            PaymentRecord(amount: 61.5, date: FA2Format.dateFormatter.date(from: "2026-07-03")!),
            // Wpłata sprzed okna 6 miesięcy — pomijana.
            PaymentRecord(amount: 999, date: FA2Format.dateFormatter.date(from: "2025-01-01")!),
        ]
        try context.save()

        let analytics = DashboardAnalytics(
            invoices: [sale, purchase], periodInvoices: [], now: now, months: 6
        )
        #expect(analytics.cashFlow.count == 6)
        let june = analytics.cashFlow[4]
        let july = analytics.cashFlow[5]
        #expect(june.inflow == 60)
        #expect(june.outflow == 0)
        #expect(july.inflow == 63)
        #expect(july.outflow == 61.5)
        #expect(july.balance == 1.5)
        // Wpłata z 2025 nie powiększa żadnego słupka.
        #expect(analytics.cashFlow.reduce(0) { $0 + $1.outflow } == 61.5)
    }

    @Test("Wiekowanie: salda trafiają do przedziałów wg dni po terminie")
    func agingBuckets() throws {
        let context = try makeContext()
        let beforeDue = makeInvoice(number: "S/1", issue: "2026-07-01", kind: .sales,
                                    net: 100, vat: 0, due: "2026-08-01")
        let overdue10 = makeInvoice(number: "S/2", issue: "2026-06-01", kind: .sales,
                                    net: 200, vat: 0, due: "2026-07-05")
        let overdue45 = makeInvoice(number: "Z/1", issue: "2026-05-01", kind: .purchase,
                                    net: 300, vat: 0, due: "2026-05-31")
        let overdue100 = makeInvoice(number: "Z/2", issue: "2026-03-01", kind: .purchase,
                                     net: 400, vat: 0, due: "2026-04-06")
        let paid = makeInvoice(number: "S/3", issue: "2026-06-01", kind: .sales,
                               net: 999, vat: 0, due: "2026-06-10", isPaid: true)
        [beforeDue, overdue10, overdue45, overdue100, paid].forEach { context.insert($0) }
        // Wpłata częściowa zmniejsza saldo w wiekowaniu.
        overdue10.payments = [PaymentRecord(amount: 50, date: now)]
        try context.save()

        let analytics = DashboardAnalytics(
            invoices: [beforeDue, overdue10, overdue45, overdue100, paid],
            periodInvoices: [], now: now
        )
        #expect(analytics.aging[0].receivables == 100)   // przed terminem
        #expect(analytics.aging[1].receivables == 150)   // 1–30 dni (200 − 50)
        #expect(analytics.aging[2].payables == 300)      // 31–60 dni
        #expect(analytics.aging[4].payables == 400)      // ponad 90 dni
        // Opłacona faktura nie występuje w wiekowaniu.
        #expect(analytics.aging.reduce(0) { $0 + $1.receivables } == 250)
    }

    @Test("Porównanie miesięczne: sumy bieżącego i poprzedniego miesiąca oraz zmiana %")
    func monthComparison() {
        let currentSale = makeInvoice(number: "S/7", issue: "2026-07-10", kind: .sales, net: 200, vat: 46)
        let previousSale = makeInvoice(number: "S/6", issue: "2026-06-10", kind: .sales, net: 100, vat: 23)
        let previousPurchase = makeInvoice(number: "Z/6", issue: "2026-06-20", kind: .purchase, net: 50, vat: 11.5)

        let analytics = DashboardAnalytics(
            invoices: [currentSale, previousSale, previousPurchase],
            periodInvoices: [], now: now
        )
        #expect(analytics.currentMonth.salesGross == 246)
        #expect(analytics.previousMonth.salesGross == 123)
        #expect(analytics.currentMonth.purchasesGross == 0)
        #expect(analytics.previousMonth.purchasesGross == 61.5)
        #expect(DashboardAnalytics.MonthSummary.change(from: 123, to: 246) == 100)
        #expect(DashboardAnalytics.MonthSummary.change(from: 0, to: 10) == nil)
    }
}
