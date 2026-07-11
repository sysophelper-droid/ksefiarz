import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Zakres dat importu i analiz")
struct DateRangeResolverTests {

    private let now = FA2Format.dateFormatter.date(from: "2026-06-11")!
    private func day(_ string: String) -> Date {
        FA2Format.dateFormatter.date(from: string)!
    }

    @Test("Bieżący miesiąc: od pierwszego dnia miesiąca do teraz")
    func currentMonth() {
        let range = DateRangeResolver.range(mode: .currentMonth, customFrom: .now, customTo: .now, now: now)
        #expect(FA2Format.dateFormatter.string(from: range.from) == "2026-06-01")
        #expect(range.to == now)
    }

    @Test("Poprzedni miesiąc: pełny miesiąc kalendarzowy")
    func lastMonth() {
        let range = DateRangeResolver.range(mode: .lastMonth, customFrom: .now, customTo: .now, now: now)
        #expect(FA2Format.dateFormatter.string(from: range.from) == "2026-05-01")
        #expect(FA2Format.dateFormatter.string(from: range.to) == "2026-05-31")
    }

    @Test("Ostatnie 3 miesiące")
    func last3Months() {
        let range = DateRangeResolver.range(mode: .last3Months, customFrom: .now, customTo: .now, now: now)
        #expect(FA2Format.dateFormatter.string(from: range.from) == "2026-03-11")
        #expect(range.to == now)
    }

    @Test("Własny zakres: cały dzień końcowy, odporność na odwrócone granice")
    func customRange() {
        let from = day("2026-01-15")
        let to = day("2026-02-20")

        let range = DateRangeResolver.range(mode: .custom, customFrom: from, customTo: to, now: now)
        #expect(FA2Format.dateFormatter.string(from: range.from) == "2026-01-15")
        // Koniec dnia 20 lutego — godzina 23:59:59.
        #expect(FA2Format.dateFormatter.string(from: range.to) == "2026-02-20")
        #expect(DateRangeResolver.contains(day("2026-02-20").addingTimeInterval(12 * 3600), in: range))

        // Odwrócone granice nie psują zakresu.
        let reversed = DateRangeResolver.range(mode: .custom, customFrom: to, customTo: from, now: now)
        #expect(reversed.from <= reversed.to)
        #expect(FA2Format.dateFormatter.string(from: reversed.from) == "2026-01-15")
    }

    @Test("Przynależność daty do zakresu (włącznie)")
    func containment() {
        let range = (from: day("2026-06-01"), to: day("2026-06-30"))
        #expect(DateRangeResolver.contains(day("2026-06-01"), in: range))
        #expect(DateRangeResolver.contains(day("2026-06-15"), in: range))
        #expect(DateRangeResolver.contains(day("2026-06-30"), in: range))
        #expect(!DateRangeResolver.contains(day("2026-05-31"), in: range))
        #expect(!DateRangeResolver.contains(day("2026-07-01"), in: range))
    }
}

@Suite("Generowanie PDF faktury")
@MainActor
struct InvoicePDFGeneratorTests {

    @Test("Wygenerowany dokument jest poprawnym plikiem PDF")
    func generatesPDF() throws {
        let invoice = makeTestInvoice(number: "FV/PDF/1")
        invoice.sellerAddress = "ul. Testowa 1, 00-001 Warszawa"
        invoice.paymentBankAccount = "11222233334444555566667777"

        let data = try #require(InvoicePDFGenerator.pdfData(for: invoice))
        // Nagłówek formatu PDF.
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
        #expect(data.count > 1000)
    }
}