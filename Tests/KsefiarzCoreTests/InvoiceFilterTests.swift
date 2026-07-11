import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Filtrowanie listy faktur")
struct InvoiceFilterTests {

    private func makeInvoices() -> [Invoice] {
        [
            makeTestInvoice(number: "FV/1", isPaid: true, sellerName: "Alfa Sp. z o.o.", sellerNIP: "5260250274"),
            makeTestInvoice(number: "FV/2", isPaid: false, sellerName: "Beta S.A.", sellerNIP: "1111111111"),
            makeTestInvoice(number: "FV/3", isPaid: false, sellerName: "Gamma sp.j.", sellerNIP: "5260250274"),
        ]
    }

    @Test("Filtr „Wszystkie” nie zmienia listy")
    func allFilter() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .all, searchText: "")
        #expect(result.count == 3)
    }

    @Test("Filtr „Opłacone” zostawia tylko opłacone")
    func paidFilter() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .paid, searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.invoiceNumber == "FV/1")
    }

    @Test("Filtr „Nieopłacone” zostawia tylko nieopłacone")
    func unpaidFilter() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .unpaid, searchText: "")
        #expect(result.count == 2)
        #expect(result.allSatisfy { !$0.isPaid })
    }

    @Test("Wyszukiwanie po nazwie kontrahenta ignoruje wielkość liter")
    func searchByName() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .all, searchText: "beta")
        #expect(result.count == 1)
        #expect(result.first?.sellerName == "Beta S.A.")
    }

    @Test("Wyszukiwanie po NIP")
    func searchByNIP() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .all, searchText: "5260250274")
        #expect(result.count == 2)
    }

    @Test("Wyszukiwanie po numerze faktury")
    func searchByInvoiceNumber() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .all, searchText: "fv/2")
        #expect(result.count == 1)
        #expect(result.first?.invoiceNumber == "FV/2")
    }

    @Test("Filtr statusu i wyszukiwanie działają łącznie")
    func combinedFilters() {
        // Nieopłacone + NIP 5260250274 → tylko Gamma (Alfa jest opłacona).
        let result = InvoiceFilter.apply(makeInvoices(), status: .unpaid, searchText: "5260250274")
        #expect(result.count == 1)
        #expect(result.first?.sellerName == "Gamma sp.j.")
    }

    @Test("Białe znaki w zapytaniu są ignorowane")
    func whitespaceQuery() {
        let result = InvoiceFilter.apply(makeInvoices(), status: .all, searchText: "   ")
        #expect(result.count == 3)
    }
}

@Suite("Filtr statusu wysyłki do KSeF")
struct KSeFSyncFilterTests {

    private func makeInvoices() -> [Invoice] {
        let invoices = [
            makeTestInvoice(number: "WYSLANA", kind: .sales, ksefId: "KSEF-1"),
            makeTestInvoice(number: "LOKALNA-1", kind: .sales),
            makeTestInvoice(number: "LOKALNA-2", kind: .sales),
        ]
        let processing = makeTestInvoice(number: "W-TOKU", kind: .sales)
        processing.ksefInvoiceReference = "INV-P"
        processing.ksefSubmissionStatus = .processing
        let rejected = makeTestInvoice(number: "ODRZUCONA", kind: .sales)
        rejected.ksefInvoiceReference = "INV-R"
        rejected.ksefSubmissionStatus = .rejected
        return invoices + [processing, rejected]
    }

    @Test("isLocalOnly rozpoznaje faktury bez numeru KSeF")
    func localOnlyFlag() {
        #expect(makeTestInvoice(number: "L").isLocalOnly)
        #expect(!makeTestInvoice(number: "W", ksefId: "KSEF-9").isLocalOnly)
    }

    @Test("Filtry rozróżniają pełny stan wysyłki")
    func filters() {
        let invoices = makeInvoices()
        #expect(KSeFSyncFilter.all.apply(to: invoices).count == 5)
        #expect(KSeFSyncFilter.sent.apply(to: invoices).count == 3)
        #expect(KSeFSyncFilter.accepted.apply(to: invoices).map(\.invoiceNumber) == ["WYSLANA"])
        #expect(KSeFSyncFilter.processing.apply(to: invoices).map(\.invoiceNumber) == ["W-TOKU"])
        #expect(KSeFSyncFilter.rejected.apply(to: invoices).map(\.invoiceNumber) == ["ODRZUCONA"])
        let localOnly = KSeFSyncFilter.localOnly.apply(to: invoices)
        #expect(localOnly.count == 2)
        #expect(localOnly.allSatisfy { $0.isLocalOnly })
    }
}

@Suite("Odtwarzanie szkicu z zapisanej faktury")
struct InvoiceDraftFromInvoiceTests {

    @Test("Szkic z faktury lokalnej zachowuje pozycje i dane płatności")
    func reconstructsDraft() {
        let invoice = makeTestInvoice(number: "FV/LOK/1", kind: .sales)
        invoice.sellerAddress = "ul. Testowa 1"
        invoice.buyerAddress = "ul. Odbiorcza 2"
        invoice.paymentFormRaw = PaymentForm.cash.rawValue
        invoice.paymentBankAccount = "11222233334444555566667777"
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa", unit: "godz.", quantity: 2, unitNetPrice: 100, netAmount: 200, vatRate: "23", vatAmount: 46),
        ]

        let draft = InvoiceDraft(from: invoice)

        #expect(draft.invoiceNumber == "FV/LOK/1")
        #expect(draft.sellerAddress == "ul. Testowa 1")
        #expect(draft.buyerAddress == "ul. Odbiorcza 2")
        #expect(draft.paymentForm == .cash)
        #expect(draft.paymentBankAccount == "11222233334444555566667777")
        #expect(draft.lines.count == 1)
        #expect(draft.lines.first?.name == "Usługa")
        // Kwoty wyliczone z pozycji.
        #expect(abs(draft.netAmount - 200) < 0.001)
        #expect(abs(draft.vatAmount - 46) < 0.001)
        #expect(draft.correction == nil)
        // Szkic z poprawnymi danymi przechodzi walidację — można wysłać do KSeF.
        #expect(InvoiceValidator.validate(draft).isEmpty)
    }

    @Test("Szkic z lokalnej korekty odtwarza dane faktury korygowanej")
    func reconstructsCorrectionDraft() throws {
        let invoice = makeTestInvoice(number: "KOR/1", kind: .sales)
        invoice.documentTypeRaw = "KOR"
        invoice.correctionReason = "Zwrot"
        invoice.correctedInvoiceNumber = "FV/7"
        invoice.correctedInvoiceKsefId = "KSEF-7"
        invoice.correctedInvoiceIssueDate = FA2Format.dateFormatter.date(from: "2026-05-01")!

        let draft = InvoiceDraft(from: invoice)
        let correction = try #require(draft.correction)
        #expect(correction.originalNumber == "FV/7")
        #expect(correction.originalKsefNumber == "KSEF-7")
        #expect(correction.reason == "Zwrot")
        #expect(FA2Format.dateFormatter.string(from: correction.originalIssueDate) == "2026-05-01")
    }
}
