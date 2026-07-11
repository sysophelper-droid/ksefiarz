import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Faktury korygujące (KOR)")
struct CorrectionInvoiceTests {

    /// Szkic korekty: zwrot jednej pozycji (różnica ujemna).
    private func makeCorrectionDraft() -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "KOR/2026/06/001",
            issueDate: FA2Format.dateFormatter.date(from: "2026-06-11")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            lines: [
                InvoiceLineDraft(name: "Zwrot: Licencja", unit: "szt.", quantity: 1, unitNetPrice: -500, vatRate: .standard),
            ],
            correction: InvoiceCorrectionInfo(
                originalNumber: "FV/2026/05/007",
                originalIssueDate: FA2Format.dateFormatter.date(from: "2026-05-10")!,
                originalKsefNumber: "5260250274-20260510-ABCDEF-ABCDEF-AB",
                reason: "Zwrot towaru"
            )
        )
    }

    @Test("Korekta przechodzi walidację mimo ujemnych kwot")
    func validatesNegativeAmounts() {
        let draft = makeCorrectionDraft()
        #expect(draft.netAmount == -500)
        #expect(InvoiceValidator.validate(draft).isEmpty)
    }

    @Test("Zwykła faktura z ujemnymi kwotami jest odrzucana")
    func regularInvoiceRejectsNegative() {
        var draft = makeCorrectionDraft()
        draft.correction = nil
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.nonPositiveNetAmount))
        #expect(errors.contains(.negativeLinePrice(1)))
    }

    @Test("Korekta bez numeru faktury korygowanej jest odrzucana")
    func requiresOriginalNumber() {
        var draft = makeCorrectionDraft()
        draft.correction?.originalNumber = " "
        #expect(InvoiceValidator.validate(draft).contains(.emptyCorrectedInvoiceNumber))
    }

    @Test("Generator tworzy blok KOR z danymi faktury korygowanej")
    func generatesCorrectionBlock() {
        let xml = FA2XMLGenerator.generateXML(for: makeCorrectionDraft())

        #expect(xml.contains("<RodzajFaktury>KOR</RodzajFaktury>"))
        #expect(xml.contains("<PrzyczynaKorekty>Zwrot towaru</PrzyczynaKorekty>"))
        #expect(xml.contains("<TypKorekty>2</TypKorekty>"))
        #expect(xml.contains("<DataWystFaKorygowanej>2026-05-10</DataWystFaKorygowanej>"))
        #expect(xml.contains("<NrFaKorygowanej>FV/2026/05/007</NrFaKorygowanej>"))
        #expect(xml.contains("<NrKSeF>1</NrKSeF>"))
        #expect(xml.contains("<NrKSeFFaKorygowanej>5260250274-20260510-ABCDEF-ABCDEF-AB</NrKSeFFaKorygowanej>"))
        // Kwoty różnicy (ujemne).
        #expect(xml.contains("<P_13_1>-500.00</P_13_1>"))
        #expect(xml.contains("<P_15>-615.00</P_15>"))
    }

    @Test("Korekta faktury bez numeru KSeF generuje znacznik NrKSeFN")
    func generatesNoKsefMarker() {
        var draft = makeCorrectionDraft()
        draft.correction?.originalKsefNumber = nil
        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<NrKSeFN>1</NrKSeFN>"))
        #expect(!xml.contains("<NrKSeFFaKorygowanej>"))
    }

    @Test("Zwykła faktura nie zawiera bloku korekty")
    func regularInvoiceHasNoCorrectionBlock() {
        var draft = makeCorrectionDraft()
        draft.correction = nil
        draft.lines = [InvoiceLineDraft(name: "Usługa", quantity: 1, unitNetPrice: 100, vatRate: .standard)]
        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<RodzajFaktury>VAT</RodzajFaktury>"))
        #expect(!xml.contains("<DaneFaKorygowanej>"))
        #expect(!xml.contains("<TypKorekty>"))
    }

    @Test("Round-trip: generator → parser zachowuje dane korekty")
    func roundTrip() throws {
        let draft = makeCorrectionDraft()
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let parsed = try FA2XMLParser.parse(xml: xml)

        #expect(parsed.documentType == "KOR")
        let correction = try #require(parsed.correction)
        #expect(correction.originalNumber == "FV/2026/05/007")
        #expect(FA2Format.dateFormatter.string(from: correction.originalIssueDate) == "2026-05-10")
        #expect(correction.originalKsefNumber == "5260250274-20260510-ABCDEF-ABCDEF-AB")
        #expect(correction.reason == "Zwrot towaru")
        #expect(abs(parsed.netAmount - (-500)) < 0.001)
    }

    @Test("Mapowanie korekty na model Invoice")
    func mappingToModel() throws {
        let xml = FA2XMLGenerator.generateXML(for: makeCorrectionDraft())
        let parsed = try FA2XMLParser.parse(xml: xml)
        let invoice = Invoice(from: parsed, kind: .sales)

        #expect(invoice.isCorrection)
        #expect(invoice.documentTypeRaw == "KOR")
        #expect(invoice.correctedInvoiceNumber == "FV/2026/05/007")
        #expect(invoice.correctedInvoiceKsefId == "5260250274-20260510-ABCDEF-ABCDEF-AB")
        #expect(invoice.correctionReason == "Zwrot towaru")
    }
}