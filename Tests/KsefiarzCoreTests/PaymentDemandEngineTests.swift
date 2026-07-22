import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Wezwania do zapłaty — odsetki i pozycje dokumentu")
@MainActor
struct PaymentDemandEngineTests {

    /// 15 lipca 2026, południe.
    private let now = FA2Format.dateFormatter.date(from: "2026-07-15")!
        .addingTimeInterval(12 * 3600)

    private func makeInvoice(
        number: String,
        due: String,
        gross: Double = 123,
        isPaid: Bool = false,
        hidden: Bool = false,
        currency: String = "PLN"
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: "2026-05-01")!,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: gross / 1.23, vatAmount: gross - gross / 1.23, grossAmount: gross,
            isPaid: isPaid,
            paymentDueDate: FA2Format.dateFormatter.date(from: due),
            isArchivedOrHidden: hidden,
            currency: currency,
            kind: .sales
        )
    }

    @Test("Odsetki proste: saldo × stopa × dni/365, zaokrąglone do groszy")
    func interestFormula() {
        // 100 zł, 73 dni, 10% rocznie → 100 × 0,10 × 73/365 = 2,00 zł.
        let due = FA2Format.dateFormatter.date(from: "2026-05-03")! // 73 dni przed 15.07
        let interest = PaymentDemandEngine.interest(
            amount: 100, from: due, to: now, annualRatePercent: 10
        )
        #expect(PaymentDemandEngine.daysOverdue(dueDate: due, asOf: now) == 73)
        #expect(interest == 2.00)
        // Przed terminem — zero.
        #expect(PaymentDemandEngine.interest(
            amount: 100, from: now.addingTimeInterval(86_400), to: now, annualRatePercent: 10
        ) == 0)
    }

    @Test("Pozycje: tylko zaległe i nieopłacone; saldo po wpłatach częściowych")
    func itemsFiltering() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, PaymentRecord.self, configurations: configuration
        )
        let context = ModelContext(container)

        let overdue = makeInvoice(number: "FV/1", due: "2026-06-30", gross: 200)
        let partiallyPaid = makeInvoice(number: "FV/2", due: "2026-06-30", gross: 300)
        let notDue = makeInvoice(number: "FV/3", due: "2026-08-01")
        let paid = makeInvoice(number: "FV/4", due: "2026-06-01", isPaid: true)
        let hidden = makeInvoice(number: "FV/5", due: "2026-06-01", hidden: true)
        [overdue, partiallyPaid, notDue, paid, hidden].forEach { context.insert($0) }
        partiallyPaid.payments = [PaymentRecord(amount: 250, date: now)]
        try context.save()

        let items = PaymentDemandEngine.items(
            for: [overdue, partiallyPaid, notDue, paid, hidden],
            annualRatePercent: 10,
            asOf: now
        )
        #expect(items.map(\.invoiceNumber) == ["FV/1", "FV/2"])
        #expect(items[0].outstanding == 200)
        #expect(items[1].outstanding == 50) // 300 − 250 wpłaty
        #expect(items[0].daysOverdue == 15)
        // Odsetki liczone od salda: 50 × 10% × 15/365 ≈ 0,21 zł.
        #expect(items[1].interest == 0.21)
    }

    @Test("Sumy dokumentu grupowane per waluta")
    func totalsByCurrency() {
        let itemPLN = PaymentDemandItem(
            invoiceNumber: "A", issueDate: now, dueDate: now,
            outstanding: 100, daysOverdue: 10, interest: 1, currency: "PLN"
        )
        let itemPLN2 = PaymentDemandItem(
            invoiceNumber: "B", issueDate: now, dueDate: now,
            outstanding: 50, daysOverdue: 5, interest: 0.5, currency: "PLN"
        )
        let itemEUR = PaymentDemandItem(
            invoiceNumber: "C", issueDate: now, dueDate: now,
            outstanding: 10, daysOverdue: 3, interest: 0.1, currency: "EUR"
        )
        let totals = PaymentDemandEngine.totals(of: [itemPLN, itemPLN2, itemEUR])
        #expect(totals.count == 2)
        #expect(totals.first { $0.currency == "PLN" }?.outstanding == 150)
        #expect(totals.first { $0.currency == "PLN" }?.interest == 1.5)
        #expect(totals.first { $0.currency == "EUR" }?.outstanding == 10)
    }

    @Test("Pozycja wezwania normalizuje surowy kod PLN")
    func itemNormalizesRawPLNCurrency() {
        let invoice = makeInvoice(number: "FV/PLN", due: "2026-06-30")
        invoice.currency = " pln\n"

        let items = PaymentDemandEngine.items(
            for: [invoice], annualRatePercent: 10, asOf: now
        )

        #expect(items.map(\.currency) == ["PLN"])
    }

    @Test("PDF wezwania generuje się dla zaległych faktur")
    func pdfGenerates() {
        let items = PaymentDemandEngine.items(
            for: [makeInvoice(number: "FV/1", due: "2026-06-30")],
            annualRatePercent: 13,
            asOf: now
        )
        let document = PaymentDemandDocument(
            kind: .demand,
            number: "WZ/1/2026",
            sellerName: "ACME Sp. z o.o.",
            sellerAddress: "ul. Przykładowa 1, Warszawa",
            sellerNIP: "5260250274",
            bankAccount: "11222233334444555566667777",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            buyerAddress: "",
            items: items,
            annualRatePercent: 13,
            paymentDays: 7
        )
        let pdf = PaymentDemandPDFGenerator.pdfData(for: document)
        #expect(pdf != nil)
        #expect((pdf?.count ?? 0) > 1000)
        // Nagłówek PDF.
        #expect(pdf?.prefix(5) == Data("%PDF-".utf8))
    }
}
