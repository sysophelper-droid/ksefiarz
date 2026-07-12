import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Faktury kosztowe spoza KSeF — walidacja i zapis")
struct ManualPurchaseTests {

    private func makeDraft(
        number: String = "FZ/1/2026",
        sellerName: String = "Lieferant GmbH",
        sellerTaxID: String = "DE123456789",
        net: Double = 100,
        vat: Double = 0,
        currency: String = "PLN",
        exchangeRate: Double = 0,
        category: String = "Oprogramowanie i licencje",
        isPaid: Bool = false
    ) -> ManualPurchaseDraft {
        ManualPurchaseDraft(
            documentNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-10")!,
            sellerName: sellerName,
            sellerTaxID: sellerTaxID,
            buyerName: "Moja Firma",
            buyerNIP: "9999999999",
            netAmount: net,
            vatAmount: vat,
            currency: currency,
            exchangeRate: exchangeRate,
            costCategory: category,
            isPaid: isPaid
        )
    }

    @Test("Poprawny szkic przechodzi walidację; brutto = netto + VAT")
    func validDraft() {
        let draft = makeDraft(net: 100, vat: 23)
        #expect(draft.validate().isEmpty)
        #expect(draft.grossAmount == 123)
    }

    @Test("Walidacja wymaga numeru, sprzedawcy i niezerowej kwoty")
    func requiredFields() {
        let errors = makeDraft(number: "  ", sellerName: "", net: 0, vat: 0).validate()
        #expect(errors.contains(.emptyDocumentNumber))
        #expect(errors.contains(.emptySellerName))
        #expect(errors.contains(.zeroAmount))
    }

    @Test("Waluta obca bez kursu PLN jest zatrzymywana walidacją")
    func foreignCurrencyNeedsRate() {
        #expect(makeDraft(currency: "EUR").validate() == [.missingExchangeRate])
        #expect(makeDraft(currency: "EUR", exchangeRate: 4.25).validate().isEmpty)
    }

    @Test("Zapis tworzy zakup tylko lokalny (spoza KSeF) z kategorią kosztu")
    func makeInvoice() {
        let invoice = makeDraft(net: 100, vat: 23, isPaid: true).makeInvoice()

        #expect(invoice.kind == .purchase)
        #expect(invoice.ksefId == nil)
        #expect(invoice.isManualPurchase)
        #expect(invoice.isLocalOnly)
        #expect(invoice.grossAmount == 123)
        #expect(invoice.sellerNIP == "DE123456789")
        #expect(invoice.costCategory == "Oprogramowanie i licencje")
        #expect(invoice.isPaid)
        // Brak jawnej daty zapłaty → data wystawienia.
        #expect(invoice.paymentDate == invoice.issueDate)
    }

    @Test("Zakup pobrany z KSeF (z numerem) nie jest ręczny")
    func ksefPurchaseIsNotManual() {
        let invoice = makeDraft().makeInvoice()
        invoice.ksefId = "9999999999-20260710-AAAAAAAAAAAA-AA"
        #expect(!invoice.isManualPurchase)
    }

    @Test("Edycja nanosi zmiany, ale nie cofa znacznika „opłacona” (niezmiennik)")
    func applyDoesNotUnsetPaid() {
        let invoice = makeDraft(isPaid: true).makeInvoice()

        var updated = ManualPurchaseDraft(from: invoice)
        updated.netAmount = 200
        updated.isPaid = false // szkic „nieopłacony” nie może cofnąć decyzji
        updated.apply(to: invoice)

        #expect(invoice.netAmount == 200)
        #expect(invoice.grossAmount == 200)
        #expect(invoice.isPaid) // ręczna decyzja użytkownika nadrzędna
    }

    @Test("Szkic odtworzony z faktury zachowuje wszystkie pola (round-trip)")
    func roundTrip() {
        let original = makeDraft(net: 150, vat: 34.5, currency: "EUR", exchangeRate: 4.3)
        let invoice = original.makeInvoice()
        let restored = ManualPurchaseDraft(from: invoice)

        #expect(restored.documentNumber == original.documentNumber)
        #expect(restored.sellerName == original.sellerName)
        #expect(restored.sellerTaxID == original.sellerTaxID)
        #expect(restored.netAmount == original.netAmount)
        #expect(restored.vatAmount == original.vatAmount)
        #expect(restored.currency == original.currency)
        #expect(restored.exchangeRate == original.exchangeRate)
        #expect(restored.costCategory == original.costCategory)
    }
}
