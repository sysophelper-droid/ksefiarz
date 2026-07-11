import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze szkice

private func makeBaseDraft(
    lines: [InvoiceLineDraft],
    attachments: [FA3AttachmentBlock] = []
) -> InvoiceDraft {
    InvoiceDraft(
        invoiceNumber: "FV/OSS/1",
        issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
        sellerName: "ACME Sp. z o.o.",
        sellerNIP: "5260250274",
        sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
        buyerName: "Verbraucher GmbH",
        buyerNIP: "1111111111",
        lines: lines,
        attachments: attachments
    )
}

private func makeAttachmentBlock() -> FA3AttachmentBlock {
    FA3AttachmentBlock(
        header: "Specyfikacja dostawy",
        metadata: [
            .init(key: "Numer zamówienia", value: "ZAM/77/2026"),
            .init(key: "", value: ""), // pusta para — ma zostać pominięta
        ],
        paragraphs: ["Dostawa zrealizowana w dwóch partiach.", "Odbiór potwierdzony."],
        tables: [
            .init(
                description: "Partie dostawy",
                columns: ["Partia", "Ilość"],
                rows: [["I", "10"], ["II", "5"]],
                summary: ["Razem", "15"]
            )
        ]
    )
}

// MARK: - OSS (dział XII rozdz. 6a)

@Suite("FA(3) — procedura OSS (P_12_XII, P_13_5/P_14_5)")
struct FA3OSSTests {

    @Test("Pozycja OSS dostaje P_12_XII zamiast P_12, a sumy trafiają do P_13_5/P_14_5")
    func ossLineAndSums() {
        let draft = makeBaseDraft(lines: [
            InvoiceLineDraft(name: "Sprzedaż wysyłkowa DE", quantity: 1, unitNetPrice: 100,
                             procedure: "WSTO_EE", ossRate: 19),
            InvoiceLineDraft(name: "Usługa krajowa", quantity: 1, unitNetPrice: 200,
                             vatRate: .standard),
        ])
        let xml = FA2XMLGenerator.generateXML(for: draft)

        // Pozycja OSS: stawka państwa konsumpcji, bez polskiej stawki.
        #expect(xml.contains("<P_12_XII>19</P_12_XII>"))
        #expect(!xml.contains("<P_12>19</P_12>"))
        // Pozycja krajowa nadal z polską stawką.
        #expect(xml.contains("<P_12>23</P_12>"))
        // Sumy OSS: 100 netto, 19 podatku od wartości dodanej.
        #expect(xml.contains("<P_13_5>100.00</P_13_5>"))
        #expect(xml.contains("<P_14_5>19.00</P_14_5>"))
        // Pozycja OSS nie zawyża sum polskiej stawki podstawowej.
        #expect(xml.contains("<P_13_1>200.00</P_13_1>"))
        #expect(xml.contains("<P_14_1>46.00</P_14_1>"))
        // Kwoty faktury obejmują podatek OSS.
        #expect(draft.vatAmount == 65.00)
        #expect(draft.grossAmount == 365.00)
    }

    @Test("Sekwencja sum: P_13_5 przed P_13_6_1 (kolejność XSD)")
    func ossSumsOrder() {
        let draft = makeBaseDraft(lines: [
            InvoiceLineDraft(name: "OSS", quantity: 1, unitNetPrice: 100, ossRate: 21),
            InvoiceLineDraft(name: "Stawka 0%", quantity: 1, unitNetPrice: 50, vatRate: .zero),
        ])
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let p135 = xml.range(of: "<P_13_5>")
        let p1361 = xml.range(of: "<P_13_6_1>")
        #expect(p135 != nil && p1361 != nil)
        if let p135, let p1361 {
            #expect(p135.lowerBound < p1361.lowerBound)
        }
    }

    @Test("Stawka OSS z ułamkiem formatuje się bez zbędnych zer (TProcentowy)")
    func ossRateFormatting() {
        #expect(FA2Format.percent(19) == "19")
        #expect(FA2Format.percent(8.5) == "8.5")
        #expect(FA2Format.percent(21.375) == "21.375")
    }

    @Test("Parser odczytuje P_12_XII i wylicza podatek pozycji ze stawki OSS")
    func parserReadsOSS() throws {
        let draft = makeBaseDraft(lines: [
            InvoiceLineDraft(name: "Sprzedaż OSS", quantity: 2, unitNetPrice: 50,
                             procedure: "WSTO_EE", ossRate: 19),
        ])
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let parsed = try FA2XMLParser.parse(xml: xml)

        #expect(parsed.lines.count == 1)
        #expect(parsed.lines[0].ossRate == 19)
        #expect(parsed.lines[0].vatAmount == 19.00)
        #expect(parsed.lines[0].procedure == "WSTO_EE")
    }

    @Test("Walidator odrzuca stawkę OSS spoza zakresu 0–100")
    func validatorRejectsBadOSSRate() {
        let draft = makeBaseDraft(lines: [
            InvoiceLineDraft(name: "Zła stawka", quantity: 1, unitNetPrice: 100, ossRate: 123),
        ])
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.invalidLineOSSRate(1)))
    }
}

// MARK: - Załącznik (element Zalacznik)

@Suite("FA(3) — załącznik do faktury (Zalacznik)")
struct FA3AttachmentTests {

    @Test("Generator emituje Zalacznik z metadanymi, akapitami i tabelą; puste pary pomija")
    func generatesAttachment() {
        let draft = makeBaseDraft(
            lines: [InvoiceLineDraft(name: "Towar", quantity: 1, unitNetPrice: 100)],
            attachments: [makeAttachmentBlock()]
        )
        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<Zalacznik>"))
        #expect(xml.contains("<ZNaglowek>Specyfikacja dostawy</ZNaglowek>"))
        #expect(xml.contains("<ZKlucz>Numer zamówienia</ZKlucz>"))
        #expect(xml.contains("<ZWartosc>ZAM/77/2026</ZWartosc>"))
        // Pusta para metadanych nie zostawia pustych elementów.
        #expect(!xml.contains("<ZKlucz></ZKlucz>"))
        #expect(xml.contains("<Akapit>Dostawa zrealizowana w dwóch partiach.</Akapit>"))
        #expect(xml.contains("<Opis>Partie dostawy</Opis>"))
        #expect(xml.contains("<Kol Typ=\"txt\">"))
        #expect(xml.contains("<NKom>Partia</NKom>"))
        #expect(xml.contains("<WKom>10</WKom>"))
        #expect(xml.contains("<SKom>Razem</SKom>"))
        // Zalacznik po zamknięciu Fa (ostatni element dokumentu).
        if let faEnd = xml.range(of: "</Fa>"), let attachment = xml.range(of: "<Zalacznik>") {
            #expect(faEnd.lowerBound < attachment.lowerBound)
        }
        // Dokument pozostaje poprawnym XML.
        #expect((try? XMLDocument(data: Data(xml.utf8), options: [])) != nil)
    }

    @Test("Parser odtwarza załącznik z wygenerowanego dokumentu (round-trip)")
    func parserRoundTrip() throws {
        let block = makeAttachmentBlock()
        let draft = makeBaseDraft(
            lines: [InvoiceLineDraft(name: "Towar", quantity: 1, unitNetPrice: 100)],
            attachments: [block]
        )
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let parsed = try FA2XMLParser.parse(xml: xml)

        #expect(parsed.attachments.count == 1)
        let roundTripped = parsed.attachments[0]
        #expect(roundTripped.header == "Specyfikacja dostawy")
        // Pusta para została odfiltrowana przy generowaniu.
        #expect(roundTripped.metadata == [.init(key: "Numer zamówienia", value: "ZAM/77/2026")])
        #expect(roundTripped.paragraphs == block.paragraphs)
        #expect(roundTripped.tables == block.tables)
    }

    @Test("Serializacja JSON załącznika na fakturze (attachmentJSON) jest odwracalna")
    func jsonRoundTrip() {
        let blocks = [makeAttachmentBlock()]
        let json = blocks.encodedJSON()
        #expect(!json.isEmpty)
        #expect([FA3AttachmentBlock].decoded(from: json) == blocks)
        #expect([FA3AttachmentBlock].decoded(from: "") == [])
        #expect([FA3AttachmentBlock]().encodedJSON() == "")
    }

    @Test("Walidator wymaga metadanych i poprawnej tabeli w bloku załącznika")
    func validatorChecksAttachment() {
        var noMeta = makeAttachmentBlock()
        noMeta.metadata = [.init(key: "", value: "")]
        var badTable = makeAttachmentBlock()
        badTable.tables = [.init(columns: [], rows: [])]

        let draft = makeBaseDraft(
            lines: [InvoiceLineDraft(name: "Towar", quantity: 1, unitNetPrice: 100)],
            attachments: [noMeta, badTable]
        )
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.attachmentMissingMetadata(1)))
        #expect(errors.contains(.attachmentInvalidTable(2)))
    }

    @Test("Więcej niż 10 akapitów w bloku jest odrzucane")
    func validatorChecksParagraphLimit() {
        var block = makeAttachmentBlock()
        block.paragraphs = (1...11).map { "Akapit \($0)" }
        let draft = makeBaseDraft(
            lines: [InvoiceLineDraft(name: "Towar", quantity: 1, unitNetPrice: 100)],
            attachments: [block]
        )
        #expect(InvoiceValidator.validate(draft).contains(.attachmentTooManyParagraphs(1)))
    }
}
