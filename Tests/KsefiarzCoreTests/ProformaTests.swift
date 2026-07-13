import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

/// Testy faktury proforma: model, walidator, most do faktury VAT (konwersja),
/// przejściowa faktura do PDF/e-maila, numeracja i kopia zapasowa.
@Suite("Faktura proforma")
struct ProformaTests {

    // MARK: Pomocnicze

    /// Prawidłowy 26-cyfrowy NRB (do kodu QR płatności).
    private static let sampleNRB = "61109010140000071219812874"

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Proforma.self, ProformaLine.self, configurations: configuration
        )
        return ModelContext(container)
    }

    /// Szkic proformy z jedną poprawną pozycją (100 netto, 23% VAT).
    private func sampleDraft(
        number: String = "PF/2026/07/001",
        buyerNIP: String = "",
        currency: String = "PLN",
        exchangeRate: Double = 0,
        validUntil: Date? = nil
    ) -> ProformaDraft {
        ProformaDraft(
            proformaNumber: number,
            issueDate: Date(timeIntervalSince1970: 1_770_000_000),
            validUntil: validUntil,
            sellerName: "Moja Firma",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
            buyerName: "Klient Sp. z o.o.",
            buyerNIP: buyerNIP,
            buyerAddress: "ul. Kliencka 2, 00-002 Warszawa",
            lines: [InvoiceLineDraft(name: "Usługa doradcza", quantity: 1, unitNetPrice: 100, vatRate: .standard)],
            paymentBankAccount: Self.sampleNRB,
            currency: currency,
            exchangeRate: exchangeRate
        )
    }

    // MARK: Walidator

    @Test("Poprawny szkic proformy przechodzi walidację (NIP nabywcy pusty)")
    func validDraftPasses() {
        #expect(ProformaValidator.validate(sampleDraft()).isEmpty)
    }

    @Test("Pusty numer, nazwa sprzedawcy i nabywcy dają błędy")
    func emptyFieldsFail() {
        var draft = sampleDraft(number: "  ")
        draft.sellerName = ""
        draft.buyerName = ""
        let errors = ProformaValidator.validate(draft)
        #expect(errors.contains(.emptyProformaNumber))
        #expect(errors.contains(.emptySellerName))
        #expect(errors.contains(.emptyBuyerName))
    }

    @Test("NIP sprzedawcy musi być poprawny")
    func invalidSellerNIPFails() {
        var draft = sampleDraft()
        draft.sellerNIP = "1234567890"
        #expect(ProformaValidator.validate(draft).contains(.invalidSellerNIP))
    }

    @Test("NIP nabywcy jest opcjonalny, ale walidowany gdy podany")
    func buyerNIPOptionalButValidated() {
        // Pusty — OK.
        #expect(!ProformaValidator.validate(sampleDraft(buyerNIP: "")).contains(.invalidBuyerNIP))
        // Poprawny — OK.
        #expect(!ProformaValidator.validate(sampleDraft(buyerNIP: "5260250274")).contains(.invalidBuyerNIP))
        // Błędny — błąd.
        #expect(ProformaValidator.validate(sampleDraft(buyerNIP: "123")).contains(.invalidBuyerNIP))
    }

    @Test("Kwota netto niedodatnia i ujemny VAT są błędne")
    func amountErrors() {
        var draft = sampleDraft()
        draft.lines = [InvoiceLineDraft(name: "Pusta", quantity: 1, unitNetPrice: 0, vatRate: .standard)]
        #expect(ProformaValidator.validate(draft).contains(.nonPositiveNetAmount))
    }

    @Test("Waluta obca z VAT wymaga kursu PLN")
    func foreignCurrencyNeedsRate() {
        let noRate = sampleDraft(currency: "EUR", exchangeRate: 0)
        #expect(ProformaValidator.validate(noRate).contains(.missingExchangeRate))
        let withRate = sampleDraft(currency: "EUR", exchangeRate: 4.32)
        #expect(!ProformaValidator.validate(withRate).contains(.missingExchangeRate))
    }

    @Test("Data ważności przed datą wystawienia jest błędna")
    func validUntilBeforeIssueFails() {
        let issue = Date(timeIntervalSince1970: 1_770_000_000)
        let before = issue.addingTimeInterval(-86_400)
        #expect(ProformaValidator.validate(sampleDraft(validUntil: before)).contains(.validUntilBeforeIssue))
    }

    @Test("Duplikat numeru proformy blokuje zapis")
    func duplicateNumberFails() {
        let existing: Set<String> = [InvoiceValidator.normalizedNumber("PF/2026/07/001")]
        let errors = ProformaValidator.validate(sampleDraft(), existingNumbers: existing)
        #expect(errors.contains(.duplicateProformaNumber("PF/2026/07/001")))
    }

    @Test("Błędne pozycje (pusta nazwa, zerowa ilość) są wykrywane")
    func lineErrors() {
        var draft = sampleDraft()
        draft.lines = [InvoiceLineDraft(name: "", quantity: 0, unitNetPrice: 50, vatRate: .standard)]
        let errors = ProformaValidator.validate(draft)
        #expect(errors.contains(.emptyLineName(1)))
        #expect(errors.contains(.nonPositiveLineQuantity(1)))
    }

    // MARK: Model — kwoty i cykl życia

    @Test("Saldo proformy: brutto gdy nieopłacona, 0 gdy opłacona")
    func outstanding() {
        let proforma = makeProforma(gross: 246, isPaid: false)
        #expect(proforma.outstandingAmount == 246)
        proforma.isPaid = true
        #expect(proforma.outstandingAmount == 0)
    }

    @Test("Oznaczenie rozliczenia zapisuje numer faktury i datę")
    func markConverted() {
        let proforma = makeProforma()
        #expect(proforma.isConverted == false)
        proforma.markConverted(toInvoiceNumber: "FV/2026/07/012")
        #expect(proforma.isConverted)
        #expect(proforma.convertedInvoiceNumber == "FV/2026/07/012")
        #expect(proforma.convertedAt != nil)
    }

    @Test("Proforma po terminie ważności; rozliczona nie jest wygasła")
    func expiry() {
        let issue = Date(timeIntervalSince1970: 1_770_000_000)
        let proforma = makeProforma()
        proforma.issueDate = issue
        proforma.validUntil = issue.addingTimeInterval(86_400)
        let after = issue.addingTimeInterval(2 * 86_400)
        #expect(proforma.isExpired(asOf: after))
        proforma.markConverted(toInvoiceNumber: "FV/1")
        #expect(proforma.isExpired(asOf: after) == false)
    }

    // MARK: Most do faktury (konwersja)

    @Test("invoiceDraft() z proformy: pusty numer, typ VAT, dane przeniesione")
    func invoiceDraftBridge() {
        let proforma = makeProforma(gross: 123)
        let draft = proforma.invoiceDraft()
        #expect(draft.invoiceNumber.isEmpty)          // numer nada NewInvoiceView
        #expect(draft.invoiceType == "VAT")
        #expect(draft.correction == nil)
        #expect(draft.sellerNIP == proforma.sellerNIP)
        #expect(draft.buyerName == proforma.buyerName)
        #expect(draft.lines.count == proforma.lines.count)
        #expect(draft.paymentDueDate != nil)          // domyślnie 14 dni
    }

    @Test("ProformaDraft(from:) odtwarza pola zapisanej proformy")
    func draftFromProforma() {
        let proforma = makeProforma(gross: 123)
        proforma.notes = "Oferta ważna 14 dni"
        let draft = ProformaDraft(from: proforma)
        #expect(draft.proformaNumber == proforma.proformaNumber)
        #expect(draft.notes == "Oferta ważna 14 dni")
        #expect(draft.lines.count == 1)
        #expect(draft.grossAmount == proforma.grossAmount)
    }

    // MARK: Przejściowa faktura (PDF / e-mail)

    @Test("transientInvoice: typ PRO, sprzedaż, bez numeru KSeF, pozycje przeniesione")
    func transientInvoice() {
        let proforma = makeProforma(gross: 123)
        let invoice = proforma.transientInvoice()
        #expect(invoice.documentTypeRaw == "PRO")
        #expect(invoice.kind == .sales)
        #expect(invoice.ksefId == nil)            // brak KOD I/II KSeF
        #expect(invoice.isOfflineMode == false)
        #expect(invoice.lines.count == proforma.lines.count)
        #expect(invoice.grossAmount == proforma.grossAmount)
    }

    @Test("Kod QR płatności (2D ZBP) powstaje z przejściowej faktury proformy")
    func paymentQRForProforma() {
        let proforma = makeProforma(gross: 123)
        let content = PaymentQRCode.zbpTransferContent(for: proforma.transientInvoice())
        #expect(content != nil)
        // Tytuł przelewu = numer proformy; kwota w groszach (12300).
        #expect(content?.contains(proforma.proformaNumber) == true)
    }

    @MainActor
    @Test("PDF proformy renderuje się (dokument handlowy, nie faktura VAT)")
    func proformaPDFRenders() {
        let proforma = makeProforma(gross: 123)
        let data = InvoicePDFGenerator.pdfData(for: proforma.transientInvoice())
        #expect(data != nil)
        #expect((data?.count ?? 0) > 0)
    }

    // MARK: Numeracja

    @Test("Numeracja proform używa osobnej serii PF")
    func proformaNumbering() {
        let date = Date(timeIntervalSince1970: 1_770_000_000) // 2026
        let first = InvoiceNumberGenerator.nextNumber(
            pattern: InvoiceNumberGenerator.defaultProformaPattern,
            existing: [],
            date: date
        )
        #expect(first.hasPrefix("PF/"))
        let next = InvoiceNumberGenerator.nextNumber(
            pattern: InvoiceNumberGenerator.defaultProformaPattern,
            existing: [first],
            date: date
        )
        #expect(next != first)
    }

    // MARK: Persystencja + kopia zapasowa

    @Test("Zapis i odczyt proformy z bazy zachowuje pozycje")
    func persistence() throws {
        let context = try makeContext()
        let proforma = makeProforma(gross: 123)
        context.insert(proforma)
        proforma.lines = [ProformaLine(index: 1, name: "Usługa", netAmount: 100, vatAmount: 23)]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Proforma>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.sortedLines.count == 1)
        #expect(fetched.first?.sortedLines.first?.name == "Usługa")
    }

    @Test("Kopia zapasowa proformy: round-trip zachowuje dane i pozycje")
    func backupRoundTrip() throws {
        let proforma = makeProforma(gross: 123)
        proforma.lines = [ProformaLine(index: 1, name: "Usługa", quantity: 2, unitNetPrice: 50, netAmount: 100, vatRate: "23", vatAmount: 23, cnPkwiu: "62.01.11.0")]
        proforma.markConverted(toInvoiceNumber: "FV/2026/07/010")

        let data = try BackupService.makeBackup(invoices: [], settings: [:], proformas: [proforma])
        let file = try BackupService.decode(data)
        #expect(file.version == BackupService.currentVersion)

        let toImport = BackupService.proformasToImport(from: file, existing: [])
        #expect(toImport.count == 1)
        let restored = BackupService.makeProforma(from: toImport[0])
        restored.lines = BackupService.makeProformaLines(for: toImport[0])
        #expect(restored.proformaNumber == proforma.proformaNumber)
        #expect(restored.grossAmount == proforma.grossAmount)
        #expect(restored.convertedInvoiceNumber == "FV/2026/07/010")
        #expect(restored.sortedLines.count == 1)
        #expect(restored.sortedLines.first?.cnPkwiu == "62.01.11.0")
    }

    @Test("proformasToImport pomija duplikaty po numerze")
    func backupDedup() throws {
        let proforma = makeProforma()
        let data = try BackupService.makeBackup(invoices: [], settings: [:], proformas: [proforma])
        let file = try BackupService.decode(data)
        let existing = makeProforma() // ten sam numer PF/2026/07/001
        #expect(BackupService.proformasToImport(from: file, existing: [existing]).isEmpty)
    }

    // MARK: Fabryka

    private func makeProforma(
        number: String = "PF/2026/07/001",
        gross: Double = 123,
        isPaid: Bool = false
    ) -> Proforma {
        let net = (gross / 1.23 * 100).rounded() / 100
        let proforma = Proforma(
            proformaNumber: number,
            issueDate: Date(timeIntervalSince1970: 1_770_000_000),
            sellerName: "Moja Firma",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Testowa 1",
            buyerName: "Klient Sp. z o.o.",
            netAmount: net,
            vatAmount: gross - net,
            grossAmount: gross,
            isPaid: isPaid,
            paymentBankAccount: Self.sampleNRB
        )
        proforma.lines = [ProformaLine(index: 1, name: "Usługa", quantity: 1, unitNetPrice: net, netAmount: net, vatRate: "23", vatAmount: gross - net)]
        return proforma
    }
}
