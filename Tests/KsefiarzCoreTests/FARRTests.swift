import Foundation
import Testing
@testable import KsefiarzCore

private func szkicRR(
    rate: VATRate = .rr,
    quality: String = "klasa I",
    buyerAddress: String = "ul. Firmowa 1, 00-001 Warszawa"
) -> InvoiceDraft {
    InvoiceDraft(
        invoiceNumber: "RR/2026/04/001",
        issueDate: FA2Format.dateFormatter.date(from: "2026-04-15")!,
        sellerName: "Jan Rolnik",
        sellerNIP: "1111111111",
        sellerAddress: "Wiejska 2, 00-950 Warszawa",
        buyerName: "ACME Sp. z o.o.",
        buyerNIP: "5260250274",
        buyerAddress: buyerAddress,
        lines: [InvoiceLineDraft(
            name: "Pszenica konsumpcyjna",
            unit: "kg",
            quantity: 2,
            unitNetPrice: 100,
            vatRate: rate,
            cnPkwiu: "01.11.11.0",
            rrQuality: quality
        )],
        paymentDueDate: FA2Format.dateFormatter.date(from: "2026-04-29"),
        paymentForm: .transfer,
        paymentBankAccount: "61109010140000071219812874",
        notes: "Nabycie od rolnika ryczałtowego",
        invoiceType: "VAT_RR",
        saleDate: FA2Format.dateFormatter.date(from: "2026-04-14")
    )
}

@Suite("FA_RR(1) — faktury VAT RR")
struct FARRTests {
    @Test("Generator tworzy nagłówek FA_RR(1), role stron i wymagane sumy")
    func generatorRR() throws {
        let generated = ISO8601DateFormatter().date(from: "2026-04-15T10:00:00Z")!
        let xml = FARRXMLGenerator.generateXML(for: szkicRR(), generatedAt: generated)

        #expect(xml.contains(#"xmlns="http://crd.gov.pl/wzor/2026/03/06/14189/""#))
        #expect(xml.contains(#"kodSystemowy="FA_RR (1)" wersjaSchemy="1-1E">FA_RR"#))
        #expect(xml.contains("<WariantFormularza>1</WariantFormularza>"))
        #expect(xml.contains("<P_4A>2026-04-14</P_4A>"))
        #expect(xml.contains("<P_4B>2026-04-15</P_4B>"))
        #expect(xml.contains("<P_4C>RR/2026/04/001</P_4C>"))
        #expect(xml.contains("<P_11_1>200.00</P_11_1>"))
        #expect(xml.contains("<P_11_2>14.00</P_11_2>"))
        #expect(xml.contains("<P_12_1>214.00</P_12_1>"))
        #expect(xml.contains("<P_12_2>dwieście czternaście złotych 00/100</P_12_2>"))
        #expect(xml.contains("<RodzajFaktury>VAT_RR</RodzajFaktury>"))
        #expect(xml.contains("<P_6C>klasa I</P_6C>"))
        #expect(xml.contains("<P_9>7</P_9>"))
        #expect(xml.contains("<P_10>14.00</P_10>"))
        #expect(xml.contains("<RachunekBankowy1>"))

        let supplierRange = try #require(xml.range(of: "<Podmiot1>"))
        let buyerRange = try #require(xml.range(of: "<Podmiot2>"))
        #expect(supplierRange.lowerBound < buyerRange.lowerBound)
        let supplierBlock = String(xml[supplierRange.lowerBound..<buyerRange.lowerBound])
        #expect(supplierBlock.contains("<Nazwa>Jan Rolnik</Nazwa>"))
        #expect(xml[buyerRange.lowerBound...].contains("<Nazwa>ACME Sp. z o.o.</Nazwa>"))
    }

    @Test("Wspólny generator przełącza się z FA(3) na FA_RR(1)")
    func dispatchGeneratora() {
        let xml = FA2XMLGenerator.generateXML(for: szkicRR())
        #expect(xml.contains("FA_RR (1)"))
        #expect(!xml.contains("FA (3)"))
    }

    @Test("Parser odczytuje VAT RR wraz z pozycją, jakością i płatnością")
    func parserRoundTrip() throws {
        let parsed = try FA2XMLParser.parse(xml: FARRXMLGenerator.generateXML(for: szkicRR()))

        #expect(parsed.documentType == "VAT_RR")
        #expect(parsed.invoiceNumber == "RR/2026/04/001")
        #expect(parsed.sellerName == "Jan Rolnik")
        #expect(parsed.buyerName == "ACME Sp. z o.o.")
        #expect(parsed.netAmount == 200)
        #expect(parsed.vatAmount == 14)
        #expect(parsed.grossAmount == 214)
        #expect(parsed.paymentForm == PaymentForm.transfer.rawValue)
        #expect(parsed.paymentBankAccount == "61109010140000071219812874")
        let line = try #require(parsed.lines.first)
        #expect(line.name == "Pszenica konsumpcyjna")
        #expect(line.vatRate == "7")
        #expect(line.rrQuality == "klasa I")
    }

    @Test("Korekta VAT RR generuje KOR_VAT_RR i przechodzi round-trip parsera")
    func korektaRR() throws {
        var draft = szkicRR()
        draft.invoiceNumber = "KOR/RR/2026/04/001"
        draft.lines[0].unitNetPrice = -10
        draft.netAmount = -20
        draft.vatAmount = -1.40
        draft.grossAmount = -21.40
        draft.correction = InvoiceCorrectionInfo(
            originalNumber: "RR/2026/04/001",
            originalIssueDate: FA2Format.dateFormatter.date(from: "2026-04-15")!,
            originalKsefNumber: nil,
            reason: "Korekta ceny"
        )

        #expect(InvoiceValidator.validate(draft).isEmpty)
        let xml = FARRXMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<RodzajFaktury>KOR_VAT_RR</RodzajFaktury>"))
        #expect(xml.contains("<PrzyczynaKorekty>Korekta ceny</PrzyczynaKorekty>"))
        #expect(xml.contains("<TypKorekty>2</TypKorekty>"))
        #expect(xml.contains("<NrKSeFN>1</NrKSeFN>"))
        #expect(xml.contains("<P_11_1>-20.00</P_11_1>"))

        let parsed = try FA2XMLParser.parse(xml: xml)
        #expect(parsed.documentType == "KOR_VAT_RR")
        #expect(parsed.correction?.originalNumber == "RR/2026/04/001")
        #expect(parsed.correction?.reason == "Korekta ceny")
        #expect(parsed.netAmount == -20)
    }

    @Test("Walidator wymaga stawek RR, klasy jakości i adresu nabywcy")
    func walidacjaRR() {
        #expect(InvoiceValidator.validate(szkicRR()).isEmpty)
        #expect(InvoiceValidator.validate(szkicRR(rate: .standard)).contains(.invalidRRRate(1)))
        #expect(InvoiceValidator.validate(szkicRR(quality: "")).contains(.emptyRRQuality(1)))
        #expect(InvoiceValidator.validate(szkicRR(buyerAddress: "")).contains(.emptyRRBuyerAddress))
    }

    @Test("Stawki zwrotu RR nie są dozwolone na zwykłej fakturze")
    func stawkaRRTylkoDlaRR() {
        var draft = szkicRR()
        draft.invoiceType = "VAT"
        #expect(InvoiceValidator.validate(draft).contains(.invalidStandardInvoiceRate(1)))
    }

    @Test("Schemat sesji jest rozpoznawany także z zapisanego XML offline")
    func detekcjaSchemy() {
        let rr = Data(FARRXMLGenerator.generateXML(for: szkicRR()).utf8)
        #expect(KSeFInvoiceSchema.detect(in: rr) == .faRR)
        #expect(KSeFInvoiceSchema.detect(in: Data("<Faktura><KodFormularza>FA</KodFormularza></Faktura>".utf8)) == .fa3)
    }

    @Test("Model rozpoznaje podstawową i korygującą fakturę VAT RR")
    func modelRR() {
        let invoice = Invoice(
            invoiceNumber: "RR/1", issueDate: .now,
            sellerName: "Rolnik", sellerNIP: "1111111111",
            buyerName: "Nabywca", buyerNIP: "5260250274",
            netAmount: 100, vatAmount: 7, grossAmount: 107,
            documentType: "VAT_RR", kind: .purchase
        )
        #expect(invoice.isRR)
        #expect(!invoice.isCorrection)
        invoice.documentTypeRaw = "KOR_VAT_RR"
        #expect(invoice.isRR)
        #expect(invoice.isCorrection)
        #expect(InvoiceDraft.baseType(for: invoice.documentTypeRaw) == "VAT_RR")
        #expect(DocumentTypeFilter.rr.matches("VAT_RR"))
        #expect(!DocumentTypeFilter.rr.matches("VAT"))
    }
}
