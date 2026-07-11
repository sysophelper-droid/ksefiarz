import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Wysyłka e-mail — dobór adresata, temat i treść")
struct InvoiceEmailComposerTests {

    private func makeInvoice(buyerNIP: String = "1111111111") -> Invoice {
        Invoice(
            ksefId: "1111111111-20260711-AAAAAAAAAAAA-AA",
            invoiceNumber: "FV/7/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: buyerNIP,
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            paymentDueDate: FA2Format.dateFormatter.date(from: "2026-07-15")!,
            paymentBankAccount: "11222233334444555566667777",
            kind: .sales
        )
    }

    private func makeContractor(
        nip: String,
        email: String = "",
        invoiceEmail: String = ""
    ) -> Contractor {
        let contractor = Contractor()
        contractor.name = "Kontrahent S.A."
        contractor.nip = nip
        contractor.email = email
        contractor.invoiceEmail = invoiceEmail
        return contractor
    }

    @Test("Adres fakturowy ze słownika ma pierwszeństwo przed ogólnym")
    func invoiceEmailPreferred() {
        let contractor = makeContractor(
            nip: "1111111111",
            email: "biuro@kontrahent.pl",
            invoiceEmail: "faktury@kontrahent.pl"
        )
        let recipient = InvoiceEmailComposer.recipient(
            for: makeInvoice(), contractors: [contractor]
        )
        #expect(recipient == "faktury@kontrahent.pl")
    }

    @Test("Bez adresu fakturowego używany jest adres ogólny; NIP dopasowany mimo myślników")
    func fallbackToGeneralEmail() {
        let contractor = makeContractor(nip: "111-111-11-11", email: "biuro@kontrahent.pl")
        let recipient = InvoiceEmailComposer.recipient(
            for: makeInvoice(), contractors: [contractor]
        )
        #expect(recipient == "biuro@kontrahent.pl")
    }

    @Test("Brak kontrahenta w słowniku daje pusty adres (do ręcznego wpisania)")
    func noMatch() {
        let other = makeContractor(nip: "9999999999", email: "inny@firma.pl")
        let recipient = InvoiceEmailComposer.recipient(
            for: makeInvoice(), contractors: [other]
        )
        #expect(recipient.isEmpty)
    }

    @Test("Temat zawiera numer faktury i sprzedawcę")
    func subject() {
        let subject = InvoiceEmailComposer.defaultSubject(for: makeInvoice())
        #expect(subject == "Faktura FV/7/2026 — ACME Sp. z o.o.")
    }

    @Test("Treść zawiera kwotę, termin, rachunek i numer KSeF")
    func body() {
        let body = InvoiceEmailComposer.defaultBody(for: makeInvoice())
        #expect(body.contains("FV/7/2026"))
        #expect(body.contains("123.00 PLN"))
        #expect(body.contains("Termin płatności"))
        #expect(body.contains("11222233334444555566667777"))
        #expect(body.contains("1111111111-20260711-AAAAAAAAAAAA-AA"))
        #expect(body.contains("ACME Sp. z o.o."))
    }

    @Test("Nazwa załącznika nie zawiera znaków niedozwolonych w plikach")
    func attachmentName() {
        #expect(InvoiceEmailComposer.attachmentBaseName(for: makeInvoice()) == "Faktura-FV_7_2026")
    }
}
