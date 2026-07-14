import Foundation
import PDFKit
import Testing
@testable import KsefiarzCore

@Suite("WaproXMLExporter — format importu WAPRO Kaper/Fakir")
struct WaproXMLExporterTests {

    private func invoice(
        number: String,
        kind: Invoice.Kind,
        contractorName: String = "Kontrahent & Syn <test>",
        contractorNIP: String = "PL5250001009",
        currency: String = "PLN",
        exchangeRate: Double = 0,
        documentType: String = "VAT"
    ) -> Invoice {
        let invoice = Invoice(
            ksefId: "5250001009-20260714-AAAAAAAAAAAA-AA",
            invoiceNumber: number,
            issueDate: Date(timeIntervalSince1970: 0),
            sellerName: kind == .sales ? "Moja firma" : contractorName,
            sellerNIP: kind == .sales ? "1111111111" : contractorNIP,
            sellerAddress: kind == .sales ? "ul. Własna 1" : "ul. Dostawcy 2",
            buyerName: kind == .sales ? contractorName : "Moja firma",
            buyerNIP: kind == .sales ? contractorNIP : "1111111111",
            buyerAddress: kind == .sales ? "ul. Odbiorcy 3" : "ul. Własna 1",
            netAmount: 150,
            vatAmount: 27,
            grossAmount: 177,
            paymentDueDate: Date(timeIntervalSince1970: 86_400),
            paymentForm: .transfer,
            paymentBankAccount: "PL 49 1140 2004 0000 3302 0011 2177",
            documentType: documentType,
            currency: currency,
            exchangeRate: exchangeRate,
            splitPayment: true,
            saleDate: Date(timeIntervalSince1970: 0),
            kind: kind
        )
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa A & B", quantity: 1,
                        unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23,
                        cnPkwiu: "62.01.11.0", gtu: "GTU_12", procedure: "WSTO_EE"),
            InvoiceLine(index: 2, name: "Towar <specjalny>", quantity: 1,
                        unitNetPrice: 50, netAmount: 50, vatRate: "8.0", vatAmount: 4),
        ]
        return invoice
    }

    private func document(_ data: Data) throws -> XMLDocument {
        try XMLDocument(data: data)
    }

    private func texts(_ xpath: String, in document: XMLDocument) throws -> [String] {
        try document.nodes(forXPath: xpath).compactMap(\.stringValue)
    }

    @Test("Plik ma wymagany korzeń, metrykę, dokumenty i katalogi")
    func requiredStructure() throws {
        let sale = invoice(number: "FV/1&2", kind: .sales)
        let purchase = invoice(number: "FZ/3", kind: .purchase, contractorNIP: "525-000-10-09")
        let result = try WaproXMLExporter.export(
            invoices: [sale, purchase],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let xml = try document(result.data)

        #expect(xml.rootElement()?.name == "MAGIK_EKSPORT")
        #expect(try texts("/MAGIK_EKSPORT/INFO_EKSPORTU/WERSJA_MAGIKA", in: xml) == ["4.3.2"])
        #expect(try texts("/MAGIK_EKSPORT/INFO_EKSPORTU/LICZBA_DOKUMENTOW", in: xml) == ["2"])
        #expect(try xml.nodes(forXPath: "/MAGIK_EKSPORT/DOKUMENTY/DOKUMENT").count == 2)
        #expect(try xml.nodes(forXPath: "/MAGIK_EKSPORT/KARTOTEKA_PRACOWNIKOW").count == 1)
        #expect(try xml.nodes(forXPath: "/MAGIK_EKSPORT/KARTOTEKA_ARTYKULOW").count == 1)

        // Ten sam kontrahent (NIP znormalizowany z prefiksem PL) jest jedną
        // kartą używaną jako odbiorca i dostawca.
        #expect(try xml.nodes(forXPath: "/MAGIK_EKSPORT/KARTOTEKA_KONTRAHENTOW/KONTRAHENT").count == 1)
        #expect(try texts("//KONTRAHENT/NAZWA_PELNA", in: xml) == ["Kontrahent & Syn <test>"])
        #expect(try texts("//KONTRAHENT/NIP", in: xml) == ["5250001009"])
        #expect(try texts("//KONTRAHENT/SYMBOL_KRAJU_KONTRAHENTA", in: xml) == ["PL"])
        #expect(try texts("//KONTRAHENT/ODBIORCA", in: xml) == ["1"])
        #expect(try texts("//KONTRAHENT/DOSTAWCA", in: xml) == ["1"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/NUMER", in: xml) == ["FV/1&2", "FZ/3"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/ZAKUP_SPRZEDAZ", in: xml) == ["S", "Z"])
    }

    @Test("Pozycje, podsumowanie VAT, KSeF i podzielona płatność zachowują dane")
    func documentDetails() throws {
        let invoice = invoice(number: "FV/2026/7", kind: .sales)
        let result = try WaproXMLExporter.export(invoices: [invoice])
        let xml = try document(result.data)

        #expect(try texts("//POZYCJA_DOKUMENTU/OPIS_POZYCJI", in: xml) == ["Usługa A & B", "Towar <specjalny>"])
        #expect(try texts("//POZYCJA_DOKUMENTU/KOD_VAT", in: xml) == ["23", "8"])
        #expect(try texts("//VAT/STAWKA/KOD_VAT", in: xml) == ["23", "8"])
        #expect(try texts("//VAT/STAWKA/NETTO", in: xml) == ["100.00", "50.00"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/KSEF/KSEF_ID", in: xml).first == invoice.ksefId)
        #expect(try texts("//PODZIELONA_PLATNOSC/PP", in: xml) == ["1"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/FORMA_PLATNOSCI", in: xml) == ["Przelew"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/ID_FORMY_PLAT", in: xml) == ["3"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/PODLEGA_PP", in: xml) == ["1"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/RODZAJ_TRANSAKCJI_HANDLOWEJ", in: xml) == ["GTU_12 WSTO_EE MPP"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/NUMER_RACHUNKU", in: xml) == ["49114020040000330200112177"])
    }

    @Test("Korekta wskazuje numer pierwotny i zachowuje własny identyfikator dokumentu")
    func correction() throws {
        let correction = invoice(number: "KOR/1", kind: .sales, documentType: "KOR")
        correction.correctedInvoiceNumber = "FV/ORIG/1"
        let result = try WaproXMLExporter.export(invoices: [correction])
        let xml = try document(result.data)

        #expect(try texts("//NAGLOWEK_DOKUMENTU/TYP_DOKUMENTU", in: xml) == ["KF"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/CZY_DOKUMENT_KOREKTY", in: xml) == ["1"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/NR_DOK_ORYG", in: xml) == ["FV/ORIG/1"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/ID_DOKUMENTU_ORYG", in: xml) == ["1"])
    }

    @Test("Waluta obca zapisuje wartości walutowe i przelicza bazowe po kursie")
    func foreignCurrency() throws {
        let foreign = invoice(number: "EUR/1", kind: .sales, currency: "EUR", exchangeRate: 4.2)
        let result = try WaproXMLExporter.export(invoices: [foreign])
        let xml = try document(result.data)

        #expect(result.warnings.isEmpty)
        #expect(try texts("//WARTOSCI_NAGLOWKA/NETTO_SPRZEDAZY", in: xml) == ["630.00"])
        #expect(try texts("//WARTOSCI_NAGLOWKA/NETTO_SPRZEDAZY_WALUTA", in: xml) == ["150.00"])
        #expect(try texts("//WARTOSCI_NAGLOWKA/KURS_WALUTY", in: xml) == ["4.2000"])
        #expect(try texts("//NAGLOWEK_DOKUMENTU/POZ_WAL_BAZOWE", in: xml) == ["0"])
    }

    @Test("Brak kursu i pozycji jest jawnie raportowany, ale plik pozostaje poprawnym XML")
    func warnings() throws {
        let foreign = invoice(number: "EUR/bez-kursu", kind: .purchase, currency: "EUR")
        foreign.lines = []
        let result = try WaproXMLExporter.export(invoices: [foreign])
        let xml = try document(result.data)

        #expect(result.warnings.count == 2)
        #expect(result.warnings.contains { $0.contains("brak kursu PLN") })
        #expect(result.warnings.contains { $0.contains("brak pozycji") })
        #expect(try xml.nodes(forXPath: "//VAT/STAWKA").count == 1)
        #expect(try xml.nodes(forXPath: "//POZYCJE_DOKUMENTU").isEmpty)
    }

    @Test("Daty i czas używają formatu Clarion ze specyfikacji WAPRO")
    func clarionValues() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(
            year: 1900, month: 1, day: 1, hour: 12, minute: 30, second: 3
        ))!

        #expect(WaproXMLExporter.clarionDate(reference, calendar: calendar) == 36_163)
        #expect(WaproXMLExporter.clarionTime(reference, calendar: calendar) == 4_500_301)
    }

    @Test("Eksporter odrzuca pusty wybór i limit powyżej 999 dokumentów")
    func limits() throws {
        #expect(throws: WaproXMLExporter.ExportError.noDocuments) {
            try WaproXMLExporter.export(invoices: [])
        }
        let one = invoice(number: "FV/1", kind: .sales)
        #expect(throws: WaproXMLExporter.ExportError.tooManyDocuments(1_000)) {
            try WaproXMLExporter.export(invoices: Array(repeating: one, count: 1_000))
        }
    }
}

@Suite("BatchInvoicePDFBuilder — wspólny wydruk wielu faktur")
@MainActor
struct BatchInvoicePDFBuilderTests {

    private func invoice(number: String, lineCount: Int) -> Invoice {
        let invoice = Invoice(
            invoiceNumber: number,
            issueDate: .now,
            sellerName: "Sprzedawca", sellerNIP: "1111111111",
            buyerName: "Nabywca", buyerNIP: "2222222222",
            netAmount: Double(lineCount) * 10,
            vatAmount: Double(lineCount) * 2.3,
            grossAmount: Double(lineCount) * 12.3,
            kind: .sales
        )
        invoice.lines = (1...lineCount).map { index in
            InvoiceLine(index: index, name: "Pozycja \(index) dokumentu \(number)",
                        quantity: 1, unitNetPrice: 10, netAmount: 10,
                        vatRate: "23", vatAmount: 2.3)
        }
        return invoice
    }

    @Test("Pusty wybór nie tworzy pozornie poprawnego PDF")
    func emptySelection() {
        #expect(BatchInvoicePDFBuilder.makePDF(invoices: []) == nil)
    }

    @Test("Jeden PDF zawiera wszystkie strony i zachowuje kolejność faktur")
    func combinesPagesInOrder() throws {
        let first = invoice(number: "BATCH-PIERWSZA", lineCount: 1)
        let second = invoice(number: "BATCH-DRUGA", lineCount: 30)
        let firstPDF = try #require(InvoicePDFGenerator.pdfData(for: first))
        let secondPDF = try #require(InvoicePDFGenerator.pdfData(for: second))
        let expectedPages = try #require(PDFDocument(data: firstPDF)).pageCount
            + (try #require(PDFDocument(data: secondPDF))).pageCount

        let result = try #require(BatchInvoicePDFBuilder.makePDF(invoices: [first, second]))
        let document = try #require(PDFDocument(data: result.data))
        let text = try #require(document.string)

        #expect(result.invoiceCount == 2)
        #expect(result.pageCount == expectedPages)
        #expect(document.pageCount == expectedPages)
        let firstRange = try #require(text.range(of: "BATCH-PIERWSZA"))
        let secondRange = try #require(text.range(of: "BATCH-DRUGA"))
        #expect(firstRange.lowerBound < secondRange.lowerBound)
    }
}
