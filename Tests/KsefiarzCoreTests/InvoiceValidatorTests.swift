import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Walidator — blokada duplikatów numerów")
struct DuplicateNumberValidationTests {

    private func makeDraft(number: String) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: number,
            issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            sellerAddress: "Adres 1",
            buyerName: "N", buyerNIP: "1111111111",
            lines: [InvoiceLineDraft(name: "Pozycja", quantity: 1, unitNetPrice: 100)]
        )
    }

    private func hasDuplicateError(_ errors: [InvoiceValidationError]) -> Bool {
        errors.contains { if case .duplicateInvoiceNumber = $0 { return true } else { return false } }
    }

    @Test("Numer istniejący w bazie blokuje zapis — niezależnie od wielkości liter i spacji")
    func duplikatBlokuje() {
        let existing: Set<String> = [InvoiceValidator.normalizedNumber("FV/01/06/2026")]

        let duplicate = InvoiceValidator.validate(
            makeDraft(number: " fv/01/06/2026 "), existingNumbers: existing
        )
        #expect(hasDuplicateError(duplicate))

        let fresh = InvoiceValidator.validate(
            makeDraft(number: "FV/02/06/2026"), existingNumbers: existing
        )
        #expect(!hasDuplicateError(fresh))
    }

    @Test("Edycja: numer edytowanej faktury nie jest duplikatem (wyłączony ze zbioru)")
    func edycjaWlasnegoNumeru() {
        // Zbiór numerów buduje wywołujący BEZ edytowanego dokumentu —
        // walidator nie zgłasza wtedy duplikatu dla własnego numeru.
        let othersOnly: Set<String> = [InvoiceValidator.normalizedNumber("FV/99/06/2026")]
        let errors = InvoiceValidator.validate(
            makeDraft(number: "FV/01/06/2026"), existingNumbers: othersOnly
        )
        #expect(!hasDuplicateError(errors))
    }

    @Test("Brak zbioru numerów (np. walidacja samych pól) nie zgłasza duplikatu")
    func brakZbioruNumerow() {
        #expect(!hasDuplicateError(InvoiceValidator.validate(makeDraft(number: "FV/01/06/2026"))))
    }
}

@Suite("Walidacja NIP")
struct NIPValidationTests {

    @Test("Poprawne numery NIP przechodzą walidację")
    func validNIPs() {
        #expect(InvoiceValidator.isValidNIP("5260250274"))
        #expect(InvoiceValidator.isValidNIP("1111111111"))
        // NIP z separatorami również jest akceptowany.
        #expect(InvoiceValidator.isValidNIP("526-025-02-74"))
        #expect(InvoiceValidator.isValidNIP("526 025 02 74"))
    }

    @Test("Niepoprawne numery NIP są odrzucane")
    func invalidNIPs() {
        // Błędna cyfra kontrolna.
        #expect(!InvoiceValidator.isValidNIP("5260250275"))
        // Suma kontrolna równa 10 — zawsze nieprawidłowa.
        #expect(!InvoiceValidator.isValidNIP("1234567890"))
        // Zła długość.
        #expect(!InvoiceValidator.isValidNIP("123"))
        #expect(!InvoiceValidator.isValidNIP("52602502741"))
        // Znaki niedozwolone.
        #expect(!InvoiceValidator.isValidNIP("52602502a4"))
        #expect(!InvoiceValidator.isValidNIP(""))
    }
}

@Suite("Walidacja szkicu faktury")
struct InvoiceDraftValidationTests {

    /// Poprawny szkic bazowy używany w testach.
    private func makeValidDraft() -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "FV/2026/06/001",
            issueDate: .now,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100.0,
            vatAmount: 23.0
        )
    }

    @Test("Poprawny szkic nie zgłasza błędów")
    func validDraft() {
        #expect(InvoiceValidator.validate(makeValidDraft()).isEmpty)
    }

    @Test("Brutto jest domyślnie wyliczane jako netto + VAT")
    func grossComputed() {
        #expect(abs(makeValidDraft().grossAmount - 123.0) < 0.001)
    }

    @Test("Pusty numer faktury jest wykrywany")
    func emptyInvoiceNumber() {
        var draft = makeValidDraft()
        draft.invoiceNumber = "   "
        #expect(InvoiceValidator.validate(draft).contains(.emptyInvoiceNumber))
    }

    @Test("Nieprawidłowe NIP-y stron są wykrywane")
    func invalidNIPs() {
        var draft = makeValidDraft()
        draft.sellerNIP = "0000000001"
        draft.buyerNIP = "abc"
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.invalidSellerNIP))
        #expect(errors.contains(.invalidBuyerNIP))
    }

    @Test("Kwoty: netto <= 0 i ujemny VAT są wykrywane")
    func invalidAmounts() {
        var draft = makeValidDraft()
        draft.netAmount = 0
        draft.vatAmount = -1
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.nonPositiveNetAmount))
        #expect(errors.contains(.negativeVatAmount))
    }

    @Test("Niezgodność brutto z sumą netto + VAT jest wykrywana")
    func amountsMismatch() {
        var draft = makeValidDraft()
        draft.grossAmount = 999.99
        #expect(InvoiceValidator.validate(draft).contains(.amountsMismatch))
    }

    @Test("Puste nazwy stron są wykrywane")
    func emptyNames() {
        var draft = makeValidDraft()
        draft.sellerName = ""
        draft.buyerName = " "
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.emptySellerName))
        #expect(errors.contains(.emptyBuyerName))
    }

    @Test("Brak adresu sprzedawcy jest wykrywany (wymóg FA(2))")
    func emptySellerAddress() {
        var draft = makeValidDraft()
        draft.sellerAddress = "  "
        #expect(InvoiceValidator.validate(draft).contains(.emptySellerAddress))
    }

    @Test("Błędy pozycji są wykrywane z numerem wiersza")
    func lineErrors() {
        var draft = makeValidDraft()
        draft.lines = [
            InvoiceLineDraft(name: "OK", quantity: 1, unitNetPrice: 100, vatRate: .standard),
            InvoiceLineDraft(name: "", quantity: 0, unitNetPrice: -5, vatRate: .standard),
        ]
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.emptyLineName(2)))
        #expect(errors.contains(.nonPositiveLineQuantity(2)))
        #expect(errors.contains(.negativeLinePrice(2)))
        #expect(!errors.contains(.emptyLineName(1)))
    }
}

@Suite("Pozycje i kwoty szkicu faktury")
struct InvoiceLineDraftTests {

    @Test("Kwoty pozycji: netto, VAT i brutto liczone ze stawki")
    func lineAmounts() {
        let line = InvoiceLineDraft(name: "Usługa", quantity: 3, unitNetPrice: 99.99, vatRate: .standard)
        #expect(abs(line.netAmount - 299.97) < 0.001)
        #expect(abs(line.vatAmount - 68.99) < 0.001) // 299.97 × 0.23 = 68.9931 → 68.99
        #expect(abs(line.grossAmount - 368.96) < 0.001)
    }

    @Test("Stawki 0% i zw. nie naliczają VAT")
    func zeroRates() {
        let zero = InvoiceLineDraft(name: "Eksport", quantity: 1, unitNetPrice: 100, vatRate: .zero)
        let exempt = InvoiceLineDraft(name: "Szkolenie", quantity: 1, unitNetPrice: 100, vatRate: .exempt)
        #expect(zero.vatAmount == 0)
        #expect(exempt.vatAmount == 0)
    }

    @Test("Kwoty szkicu wyliczane z pozycji o różnych stawkach")
    func draftTotalsFromLines() {
        let draft = InvoiceDraft(
            invoiceNumber: "FV/1",
            issueDate: .now,
            sellerName: "A",
            sellerNIP: "5260250274",
            sellerAddress: "Adres 1",
            buyerName: "B",
            buyerNIP: "1111111111",
            lines: [
                InvoiceLineDraft(name: "X", quantity: 10, unitNetPrice: 150, vatRate: .standard), // 1500 + 345
                InvoiceLineDraft(name: "Y", quantity: 2, unitNetPrice: 50, vatRate: .reducedFirst), // 100 + 8
                InvoiceLineDraft(name: "Z", quantity: 1, unitNetPrice: 200, vatRate: .exempt), // 200 + 0
            ]
        )
        #expect(abs(draft.netAmount - 1800) < 0.001)
        #expect(abs(draft.vatAmount - 353) < 0.001)
        #expect(abs(draft.grossAmount - 2153) < 0.001)
        // Szkic z pozycjami przechodzi pełną walidację.
        #expect(InvoiceValidator.validate(draft).isEmpty)
    }
}
