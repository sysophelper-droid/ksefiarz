import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Statystyki Kokpitu")
struct DashboardMetricsTests {

    private let now = FA2Format.dateFormatter.date(from: "2026-06-11")!

    private func days(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: now)!
    }

    @Test("Sumy zobowiązań i należności liczone tylko z nieopłaconych faktur")
    func sums() {
        let invoices = [
            makeTestInvoice(kind: .purchase, isPaid: false, gross: 100),
            makeTestInvoice(kind: .purchase, isPaid: false, gross: 50),
            makeTestInvoice(kind: .purchase, isPaid: true, gross: 999),   // opłacona — pominięta
            makeTestInvoice(kind: .sales, isPaid: false, gross: 300),
            makeTestInvoice(kind: .sales, isPaid: true, gross: 777),      // opłacona — pominięta
        ]
        let metrics = DashboardMetrics(invoices: invoices, now: now)

        #expect(abs(metrics.purchasesToPayGross - 150) < 0.001)
        #expect(abs(metrics.salesAwaitingGross - 300) < 0.001)
        #expect(metrics.unpaidCount == 3)
    }

    @Test("Faktury ukryte nie fałszują statystyk")
    func hiddenExcluded() {
        let invoices = [
            makeTestInvoice(kind: .purchase, isPaid: false, gross: 100),
            // Nieuprawniona faktura na dużą kwotę — ukryta, nie może wpływać na wyniki.
            makeTestInvoice(kind: .purchase, isPaid: false, isHidden: true, gross: 100_000, dueDate: days(-5)),
        ]
        let metrics = DashboardMetrics(invoices: invoices, now: now)

        #expect(abs(metrics.purchasesToPayGross - 100) < 0.001)
        #expect(metrics.overdueCount == 0)
        #expect(metrics.unpaidCount == 1)
    }

    @Test("Liczenie faktur zaległych")
    func overdueCount() {
        let invoices = [
            makeTestInvoice(isPaid: false, dueDate: days(-1)),  // zaległa
            makeTestInvoice(isPaid: false, dueDate: days(-10)), // zaległa
            makeTestInvoice(isPaid: false, dueDate: days(3)),   // jeszcze nie
            makeTestInvoice(isPaid: true, dueDate: days(-5)),   // opłacona
        ]
        let metrics = DashboardMetrics(invoices: invoices, now: now)
        #expect(metrics.overdueCount == 2)
    }

    @Test("Płatności w ciągu 7 dni — tylko nieopłacone, posortowane po terminie")
    func dueSoon() {
        let inTwoDays = makeTestInvoice(number: "ZA-2-DNI", isPaid: false, dueDate: days(2))
        let inFiveDays = makeTestInvoice(number: "ZA-5-DNI", isPaid: false, dueDate: days(5))
        let invoices = [
            inFiveDays,
            inTwoDays,
            makeTestInvoice(number: "ZA-30-DNI", isPaid: false, dueDate: days(30)),  // poza horyzontem
            makeTestInvoice(number: "WCZORAJ", isPaid: false, dueDate: days(-1)),    // już zaległa
            makeTestInvoice(number: "OPLACONA", isPaid: true, dueDate: days(3)),     // opłacona
        ]
        let metrics = DashboardMetrics(invoices: invoices, now: now)

        #expect(metrics.dueSoonInvoices.map(\.invoiceNumber) == ["ZA-2-DNI", "ZA-5-DNI"])
        #expect(metrics.dueSoonDays == 7)
    }

    @Test("Konfigurowalny horyzont najbliższych płatności")
    func configurableDueSoonHorizon() {
        let invoices = [
            makeTestInvoice(number: "ZA-2-DNI", isPaid: false, dueDate: days(2)),
            makeTestInvoice(number: "ZA-5-DNI", isPaid: false, dueDate: days(5)),
            makeTestInvoice(number: "ZA-20-DNI", isPaid: false, dueDate: days(20)),
        ]
        // Horyzont 3 dni — tylko najbliższa faktura.
        let short = DashboardMetrics(invoices: invoices, now: now, dueSoonDays: 3)
        #expect(short.dueSoonInvoices.map(\.invoiceNumber) == ["ZA-2-DNI"])

        // Horyzont 30 dni — wszystkie trzy.
        let long = DashboardMetrics(invoices: invoices, now: now, dueSoonDays: 30)
        #expect(long.dueSoonInvoices.count == 3)
    }

    @Test("Brak faktur daje zerowe statystyki")
    func emptyInput() {
        let metrics = DashboardMetrics(invoices: [], now: now)
        #expect(metrics.purchasesToPayGross == 0)
        #expect(metrics.salesAwaitingGross == 0)
        #expect(metrics.overdueCount == 0)
        #expect(metrics.unpaidCount == 0)
        #expect(metrics.dueSoonInvoices.isEmpty)
    }
}
