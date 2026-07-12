import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Dokumenty dwujęzyczne — etykiety PDF i angielski e-mail")
struct BilingualDocumentsTests {

    private func makeInvoice() -> Invoice {
        Invoice(
            ksefId: "1111111111-20260711-AAAAAAAAAAAA-AA",
            invoiceNumber: "FV/7/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Foreign Ltd.",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            paymentDueDate: FA2Format.dateFormatter.date(from: "2026-07-15")!,
            paymentBankAccount: "11222233334444555566667777",
            kind: .sales
        )
    }

    // MARK: Etykiety PDF

    @Test("Etykiety polskie pozostają bez zmian, dwujęzyczne łączą oba języki")
    func labels() {
        let polish = InvoicePDFLabels(bilingual: false)
        let bilingual = InvoicePDFLabels(bilingual: true)

        #expect(polish.text("Sprzedawca", "Seller") == "Sprzedawca")
        #expect(bilingual.text("Sprzedawca", "Seller") == "Sprzedawca / Seller")
        #expect(bilingual.text("Faktura VAT", "VAT Invoice") == "Faktura VAT / VAT Invoice")
    }

    @Test("Formy płatności mają angielskie nazwy")
    func paymentFormEnglishNames() {
        #expect(PaymentForm.transfer.englishName == "Bank transfer")
        #expect(PaymentForm.cash.englishName == "Cash")
        // Każda forma ma niepustą nazwę angielską.
        for form in PaymentForm.allCases {
            #expect(!form.englishName.isEmpty)
        }
    }

    // MARK: Angielski szablon e-mail

    @Test("Angielski temat i treść zawierają numer, kwotę, rachunek i numer KSeF")
    func englishTemplate() {
        let invoice = makeInvoice()
        let subject = InvoiceEmailComposer.defaultSubject(for: invoice, language: .english)
        let body = InvoiceEmailComposer.defaultBody(for: invoice, language: .english)

        #expect(subject == "Invoice FV/7/2026 — ACME Sp. z o.o.")
        #expect(body.contains("please find attached invoice FV/7/2026"))
        #expect(body.contains("123"))
        #expect(body.contains("Payment due date:"))
        #expect(body.contains("11222233334444555566667777"))
        #expect(body.contains("1111111111-20260711-AAAAAAAAAAAA-AA"))
        #expect(body.contains("Kind regards"))
    }

    @Test("Domyślny język szablonu pozostaje polski")
    func polishByDefault() {
        let invoice = makeInvoice()
        #expect(InvoiceEmailComposer.defaultSubject(for: invoice)
            == "Faktura FV/7/2026 — ACME Sp. z o.o.")
        #expect(InvoiceEmailComposer.defaultBody(for: invoice).contains("Dzień dobry"))
    }

    @Test("Język podpowiadany z flagi kontrahenta (dopasowanie po NIP)")
    func preferredLanguage() {
        let invoice = makeInvoice()

        let foreign = Contractor()
        foreign.name = "Foreign Ltd."
        foreign.nip = "111-111-11-11"
        foreign.prefersBilingualDocuments = true

        let domestic = Contractor()
        domestic.name = "Krajowy"
        domestic.nip = "2222222222"
        domestic.prefersBilingualDocuments = true

        #expect(InvoiceEmailComposer.preferredLanguage(for: invoice, contractors: [foreign]) == .english)
        #expect(InvoiceEmailComposer.preferredLanguage(for: invoice, contractors: [domestic]) == .polish)
        #expect(InvoiceEmailComposer.preferredLanguage(for: invoice, contractors: []) == .polish)
    }
}
