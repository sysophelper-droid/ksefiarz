import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Import wsadowy CSV/Excel")
struct BulkImportParserTests {

    @Test("CSV rozpoznaje średnik, CRLF, cytowane separatory i wieloliniowe pola")
    func csvQuotedAndCRLF() throws {
        let csv = "Nazwa;NIP;Uwagi\r\n\"ACME; Polska\";5260250274;\"linia 1\nlinia 2\"\r\n"
        let sheet = try TabularFileReader.parseCSV(csv)

        #expect(sheet.headers == ["Nazwa", "NIP", "Uwagi"])
        #expect(sheet.dataRows.count == 1)
        #expect(sheet.dataRows[0][0] == "ACME; Polska")
        #expect(sheet.dataRows[0][2] == "linia 1\nlinia 2")
    }

    @Test("CSV rozpoznaje przecinek i podwójny cudzysłów")
    func csvCommaAndEscapedQuote() throws {
        let csv = "name,nip\n\"Firma \"\"A\"\"\",1234567890\n"
        let sheet = try TabularFileReader.parseCSV(csv)
        #expect(sheet.dataRows[0] == ["Firma \"A\"", "1234567890"])
    }

    @Test("Przecinki dziesiętne nie mylą autodetekcji separatora średnikowego")
    func decimalCommasDoNotChangeDelimiter() throws {
        let csv = "Numer;Netto\nFV/1;1,20\nFV/2;2,40\n"
        let sheet = try TabularFileReader.parseCSV(csv)
        #expect(sheet.headers == ["Numer", "Netto"])
        #expect(sheet.dataRows[1] == ["FV/2", "2,40"])
    }

    @Test("BOM UTF-8 nie psuje cudzysłowu pierwszego pola")
    func bomWithQuotedFirstField() throws {
        let csv = "\u{FEFF}\"Nazwa firmy\";NIP\n\"ACME; Polska\";5260250274\n"
        let sheet = try TabularFileReader.parseCSV(csv)
        #expect(sheet.headers == ["Nazwa firmy", "NIP"])
        #expect(sheet.dataRows[0] == ["ACME; Polska", "5260250274"])

        let mapping = BulkImportEngine.automaticMapping(entity: .contractors, headers: sheet.headers)
        #expect(mapping[.contractorName] == 0)
        #expect(mapping[.contractorNIP] == 1)
    }

    @Test("Kwoty z dopiskiem zł są parsowane")
    func amountsWithZlotySuffix() throws {
        let sheet = TabularSheet(name: "Cennik", rows: [
            ["Nazwa", "Cena netto"],
            ["Abonament", "1 234,56 zł"],
        ])
        let mapping = BulkImportEngine.automaticMapping(entity: .products, headers: sheet.headers)
        let plan = BulkImportEngine.plan(sheet: sheet, entity: .products, mapping: mapping)
        let product = try #require(plan.products.first)
        #expect(product.basePriceNet == 1234.56)
    }

    @Test("Typ dokumentu jest normalizowany do słownika aplikacji")
    func documentTypeNormalization() {
        let sheet = TabularSheet(name: "Faktury", rows: [
            ["Numer", "Data", "Kontrahent", "Netto", "Typ dokumentu"],
            ["FV/1", "2026-07-01", "Klient", "100", "Faktura VAT"],
            ["FV/2", "2026-07-02", "Klient", "100", "Faktura zaliczkowa"],
            ["FV/3", "2026-07-03", "Klient", "100", "pro-forma"],
            ["FV/4", "2026-07-04", "Klient", "100", "Paragon"],
        ])
        let plan = BulkImportEngine.plan(
            sheet: sheet, entity: .invoices,
            mapping: [.invoiceNumber: 0, .invoiceIssueDate: 1, .invoiceContractorName: 2,
                      .invoiceNet: 3, .invoiceDocumentType: 4],
            options: .init(company: .init(name: "Moja Firma", nip: "1111111111"))
        )
        #expect(plan.invoices.map(\.documentType) == ["VAT", "ZAL", "PRO", "VAT"])
        #expect(plan.issues.contains { $0.severity == .warning && $0.message.contains("Paragon") })
    }

    @Test("Plik CSV Windows-1250 zachowuje polskie znaki")
    func windows1250() throws {
        let text = "Nazwa;NIP\r\nZażółć;5260250274\r\n"
        let data = try #require(text.data(using: .windowsCP1250))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bulk-import-\(UUID().uuidString).csv")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sheet = try TabularFileReader.read(url: url)
        #expect(sheet.dataRows[0][0] == "Zażółć")
    }

    @Test("Automatyczne mapowanie rozpoznaje nagłówki migracyjne i nie używa kolumny dwa razy")
    func automaticMapping() {
        let headers = ["Numer faktury", "Data wystawienia", "Kontrahent", "NIP", "Netto", "VAT", "Brutto"]
        let mapping = BulkImportEngine.automaticMapping(entity: .invoices, headers: headers)

        #expect(mapping[.invoiceNumber] == 0)
        #expect(mapping[.invoiceIssueDate] == 1)
        #expect(mapping[.invoiceContractorName] == 2)
        #expect(mapping[.invoiceContractorNIP] == 3)
        #expect(mapping[.invoiceNet] == 4)
        #expect(mapping[.invoiceVAT] == 5)
        #expect(mapping[.invoiceGross] == 6)
        #expect(Set(mapping.values).count == mapping.count)
    }

    @Test("Brak wymaganego mapowania jest błędem blokującym bez numeru wiersza")
    func missingRequiredMapping() {
        let sheet = TabularSheet(name: "x", rows: [["Nazwa"], ["ACME"]])
        let plan = BulkImportEngine.plan(sheet: sheet, entity: .contractors, mapping: [.contractorName: 0])
        #expect(plan.importCount == 0)
        #expect(plan.issues.contains { $0.severity == .error && $0.row == nil && $0.message.contains("NIP") })
    }

    @Test("Kontrahenci: pola są mapowane, wartości logiczne parsowane, duplikat NIP pomijany")
    func contractorPlanAndDuplicate() {
        let sheet = TabularSheet(name: "Kontrahenci", rows: [
            ["Nazwa", "NIP", "Miasto", "Dostawca", "Odbiorca", "PL/EN"],
            ["ACME", "526-025-02-74", "Kraków", "nie", "tak", "tak"],
            ["Duplikat", "5260250274", "Warszawa", "tak", "tak", "nie"],
        ])
        let mapping: [BulkImportField: Int] = [
            .contractorName: 0, .contractorNIP: 1, .contractorCity: 2,
            .contractorSupplier: 3, .contractorRecipient: 4, .contractorBilingual: 5,
        ]
        let plan = BulkImportEngine.plan(sheet: sheet, entity: .contractors, mapping: mapping)

        #expect(plan.contractors.count == 1)
        #expect(plan.duplicateCount == 1)
        #expect(plan.contractors[0].city == "Kraków")
        #expect(!plan.contractors[0].isSupplier)
        #expect(plan.contractors[0].isRecipient)
        #expect(plan.contractors[0].prefersBilingualDocuments)
    }

    @Test("Towary: polskie kwoty, stawki VAT, GTU i identyfikatory tekstowe")
    func productParsing() throws {
        let sheet = TabularSheet(name: "Towary", rows: [
            ["Nazwa", "Typ", "SKU", "EAN", "Cena", "VAT", "GTU", "Zał. 15"],
            ["Audyt", "usługa", "0007", "05901234567890", "1 234,56 PLN", "8%", "12", "1"],
        ])
        let mapping: [BulkImportField: Int] = [
            .productName: 0, .productType: 1, .productSKU: 2, .productEAN: 3,
            .productSalePriceNet: 4, .productSaleVAT: 5, .productGTU: 6,
            .productAttachment15: 7,
        ]
        let plan = BulkImportEngine.plan(sheet: sheet, entity: .products, mapping: mapping)

        let product = try #require(plan.products.first)
        #expect(product.type == .service)
        #expect(product.sku == "0007")
        #expect(product.ean == "05901234567890")
        #expect(product.basePriceNet == 1234.56)
        #expect(product.basePriceVAT == .reducedFirst)
        #expect(product.gtu == "GTU_12")
        #expect(product.isAttachment15)
    }

    @Test("Towary są deduplikowane po każdym dostępnym kluczu, także nazwie")
    func productDuplicateByName() {
        let sheet = TabularSheet(name: "Towary", rows: [
            ["Nazwa", "SKU"],
            ["Licencja", "ABC"],
            ["licencja", "XYZ"],
        ])
        let plan = BulkImportEngine.plan(
            sheet: sheet, entity: .products,
            mapping: [.productName: 0, .productSKU: 1]
        )
        #expect(plan.products.count == 1)
        #expect(plan.duplicateCount == 1)
    }

    @Test("Układ katalogu wFirmy mapuje cenę zakupu brutto i przelicza ją na netto")
    func wFirmaProductLayout() throws {
        let headers = ["Nazwa", "PKWiU", "Jednostka", "Ilość", "Cena", "Stawka",
                       "Szczegółowy opis", "Rodzaj ceny", "Kod produktu", "Typ"]
        let sheet = TabularSheet(name: "wFirma", rows: [
            headers,
            ["Serwis", "62.01.11.0", "godz.", "0", "123,00", "23%", "", "brutto", "WF-01", "usługa"],
        ])
        let mapping = BulkImportEngine.automaticMapping(entity: .products, headers: headers)
        #expect(mapping[.productName] == 0)
        #expect(mapping[.productCNPkwiu] == 1)
        #expect(mapping[.productPurchasePriceNet] == 4)
        #expect(mapping[.productPurchaseVAT] == 5)
        #expect(mapping[.productPurchasePriceKind] == 7)
        #expect(mapping[.productSKU] == 8)

        let plan = BulkImportEngine.plan(sheet: sheet, entity: .products, mapping: mapping)
        let product = try #require(plan.products.first)
        #expect(product.type == .service)
        #expect(product.purchasePriceNet == 100)
        #expect(product.purchasePriceVAT == .standard)
    }

    @Test("Cena brutto produktu z eksportu jest przeliczana według stawki VAT")
    func grossSalePrice() throws {
        let sheet = TabularSheet(name: "Cennik", rows: [
            ["Nazwa", "Cena brutto", "VAT"],
            ["Abonament", "108,00", "8%"],
        ])
        let mapping = BulkImportEngine.automaticMapping(entity: .products, headers: sheet.headers)
        let plan = BulkImportEngine.plan(sheet: sheet, entity: .products, mapping: mapping)
        let product = try #require(plan.products.first)
        #expect(product.basePriceNet == 100)
        #expect(product.basePriceVAT == .reducedFirst)
    }

    @Test("Faktury: powtarzane wiersze tworzą jedną fakturę z dwiema pozycjami")
    func invoiceGroupingAndLines() throws {
        let sheet = TabularSheet(name: "Faktury", rows: [
            ["Numer", "Data", "Kontrahent", "NIP", "Netto", "VAT", "Brutto", "Opłacona", "Forma", "Pozycja", "Ilość", "Cena", "Stawka"],
            ["FV/7/2026", "13.07.2026", "Klient SA", "5260250274", "300,00", "69,00", "369,00", "tak", "przelew", "Analiza", "2", "100", "23%"],
            ["FV/7/2026", "13.07.2026", "Klient SA", "5260250274", "300,00", "69,00", "369,00", "tak", "przelew", "Raport", "1", "100", "23%"],
        ])
        let mapping: [BulkImportField: Int] = [
            .invoiceNumber: 0, .invoiceIssueDate: 1, .invoiceContractorName: 2,
            .invoiceContractorNIP: 3, .invoiceNet: 4, .invoiceVAT: 5,
            .invoiceGross: 6, .invoicePaid: 7, .invoicePaymentForm: 8,
            .lineName: 9, .lineQuantity: 10, .lineUnitNetPrice: 11, .lineVATRate: 12,
        ]
        let options = BulkImportOptions(
            defaultInvoiceKind: .sales,
            company: .init(name: "Moja Firma", nip: "1111111111", address: "Rynek 1")
        )
        let plan = BulkImportEngine.plan(
            sheet: sheet, entity: .invoices, mapping: mapping, options: options
        )

        let invoice = try #require(plan.invoices.first)
        #expect(plan.invoices.count == 1)
        #expect(invoice.kind == .sales)
        #expect(invoice.sellerName == "Moja Firma")
        #expect(invoice.buyerName == "Klient SA")
        #expect(invoice.grossAmount == 369)
        #expect(invoice.isPaid)
        #expect(invoice.paymentForm == .transfer)
        #expect(invoice.lines.count == 2)
        #expect(invoice.lines[0].netAmount == 200)
        #expect(invoice.lines[0].vatAmount == 46)
        #expect(invoice.lines[1].name == "Raport")
    }

    @Test("Faktury: błędny wiersz jest raportowany, poprawny nadal trafia do planu")
    func invalidRowDoesNotHideValidRows() {
        let sheet = TabularSheet(name: "Faktury", rows: [
            ["Numer", "Data", "Kontrahent", "Netto"],
            ["FV/1", "2026-07-13", "Klient", "100"],
            ["FV/2", "nie-data", "Klient", "100"],
        ])
        let plan = BulkImportEngine.plan(
            sheet: sheet,
            entity: .invoices,
            mapping: [.invoiceNumber: 0, .invoiceIssueDate: 1, .invoiceContractorName: 2, .invoiceNet: 3],
            options: .init(company: .init(name: "Moja Firma", nip: "1111111111"))
        )
        #expect(plan.invoices.count == 1)
        #expect(plan.errorCount == 1)
        #expect(plan.issues.contains { $0.severity == .error && $0.row == 3 })
    }

    @Test("XLSX czyta tekst współdzielony, inline string, liczbę i datę Excela")
    func xlsxTypes() throws {
        var writer = ZipWriter()
        writer.addFile(path: "xl/workbook.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="Dane" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """.utf8))
        writer.addFile(path: "xl/_rels/workbook.xml.rels", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """.utf8))
        writer.addFile(path: "xl/sharedStrings.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">
          <si><t>Numer faktury</t></si><si><t>Data wystawienia</t></si><si><t>NIP</t></si><si><t>EAN</t></si>
        </sst>
        """.utf8))
        writer.addFile(path: "xl/styles.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <numFmts count="1"><numFmt numFmtId="164" formatCode="00000000000000"/></numFmts>
          <cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs>
        </styleSheet>
        """.utf8))
        writer.addFile(path: "xl/worksheets/sheet1.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
          <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>3</v></c></row>
          <row r="2"><c r="A2" t="inlineStr"><is><t>FV/1</t></is></c><c r="B2" s="1"><v>1</v></c><c r="C2"><v>5260250274</v></c><c r="D2" s="2"><v>590123456789</v></c></row>
        </sheetData></worksheet>
        """.utf8))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bulk-import-\(UUID().uuidString).xlsx")
        try writer.finalized().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let sheet = try TabularFileReader.read(url: url)
        #expect(sheet.name == "Dane")
        #expect(sheet.headers == ["Numer faktury", "Data wystawienia", "NIP", "EAN"])
        #expect(sheet.dataRows[0] == ["FV/1", "1900-01-01", "5260250274", "00590123456789"])
    }

    @Test("XLSX z prefiksami przestrzeni nazw (x:) jest czytany jak bez prefiksów")
    func xlsxNamespacePrefixes() throws {
        var writer = ZipWriter()
        writer.addFile(path: "xl/workbook.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <x:sheets><x:sheet name="Arkusz1" sheetId="1" r:id="rId1"/></x:sheets>
        </x:workbook>
        """.utf8))
        writer.addFile(path: "xl/_rels/workbook.xml.rels", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """.utf8))
        writer.addFile(path: "xl/sharedStrings.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <x:sst xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
          <x:si><x:t>Nazwa</x:t></x:si><x:si><x:t>NIP</x:t></x:si>
        </x:sst>
        """.utf8))
        writer.addFile(path: "xl/worksheets/sheet1.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheetData>
          <x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c><x:c r="B1" t="s"><x:v>1</x:v></x:c></x:row>
          <x:row r="2"><x:c r="A2" t="inlineStr"><x:is><x:t>ACME</x:t></x:is></x:c><x:c r="B2"><x:v>5260250274</x:v></x:c></x:row>
        </x:sheetData></x:worksheet>
        """.utf8))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bulk-import-\(UUID().uuidString).xlsx")
        try writer.finalized().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let sheet = try TabularFileReader.read(url: url)
        #expect(sheet.headers == ["Nazwa", "NIP"])
        #expect(sheet.dataRows[0] == ["ACME", "5260250274"])
    }
}

@Suite("Import wsadowy — zapis SwiftData")
@MainActor
struct BulkImportPersistenceTests {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, Contractor.self, Product.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @Test("Istniejąca ukryta faktura jest widziana przez deduplikację")
    func hiddenInvoiceIsDuplicate() throws {
        let context = try makeContext()
        let hidden = makeTestInvoice(
            number: "FV/UKRYTA", kind: .purchase, isHidden: true,
            sellerName: "Dostawca", sellerNIP: "5260250274",
            buyerName: "Moja Firma", buyerNIP: "1111111111"
        )
        context.insert(hidden)
        try context.save()
        let keys = BulkImportService.existingKeys(
            contractors: [], products: [], invoices: try context.fetch(FetchDescriptor<Invoice>())
        )
        let sheet = TabularSheet(name: "Faktury", rows: [
            ["Numer", "Data", "Sprzedawca", "NIP sprzedawcy", "Nabywca", "NIP nabywcy", "Brutto"],
            ["fv/ukryta", "2026-07-13", "Dostawca", "526-025-02-74", "Moja Firma", "1111111111", "123"],
        ])
        let plan = BulkImportEngine.plan(
            sheet: sheet, entity: .invoices,
            mapping: [.invoiceNumber: 0, .invoiceIssueDate: 1, .invoiceSellerName: 2,
                      .invoiceSellerNIP: 3, .invoiceBuyerName: 4, .invoiceBuyerNIP: 5,
                      .invoiceGross: 6],
            options: .init(defaultInvoiceKind: .purchase), existing: keys
        )
        #expect(plan.invoices.isEmpty)
        #expect(plan.duplicateCount == 1)
    }

    @Test("Faktura z numerem KSeF jest deduplikowana także po kluczu lokalnym")
    func ksefInvoiceAlsoHasLocalKey() throws {
        let context = try makeContext()
        let existing = makeTestInvoice(
            number: "FV/10", kind: .sales,
            sellerName: "Moja Firma", sellerNIP: "1111111111",
            buyerName: "Klient", buyerNIP: "5260250274", ksefId: "KSEF-10"
        )
        context.insert(existing)
        try context.save()
        let keys = BulkImportService.existingKeys(contractors: [], products: [], invoices: [existing])
        #expect(keys.invoices.contains("ksef:ksef10"))
        #expect(keys.invoices.contains("sprzedaz|fv/10|1111111111|5260250274"))
    }

    @Test("Serwis zapisuje słowniki i fakturę, a pozycje przypisuje po insert")
    func servicePersistsAllEntities() throws {
        let context = try makeContext()
        var contractor = ImportedContractor()
        contractor.name = "Klient"
        contractor.nip = "5260250274"
        var product = ImportedProduct()
        product.name = "Usługa"
        product.type = .service
        let invoice = ImportedInvoice(
            ksefId: "KSEF-1", invoiceNumber: "FV/1",
            issueDate: Date(timeIntervalSince1970: 1_783_900_800),
            sellerName: "Moja Firma", sellerNIP: "1111111111", sellerAddress: "Rynek 1",
            buyerName: "Klient", buyerNIP: "5260250274", buyerAddress: "Długa 1",
            netAmount: 100, vatAmount: 23, grossAmount: 123, isPaid: true,
            paymentDueDate: nil, paymentDate: nil, paymentForm: .transfer,
            paymentBankAccount: nil, currency: "PLN", exchangeRate: 0,
            splitPayment: false, documentType: "VAT", notes: "Import",
            costCategory: "", kind: .sales,
            lines: [.init(name: "Usługa", unit: "godz.", quantity: 2,
                          unitNetPrice: 50, netAmount: 100, vatRate: "23",
                          vatAmount: 23, cnPkwiu: "62.01.11.0", gtu: "GTU_12")]
        )
        var plan = BulkImportPlan()
        plan.contractors = [contractor]
        plan.products = [product]
        plan.invoices = [invoice]

        let count = try BulkImportService.apply(plan, to: context)
        #expect(count == 3)
        #expect(try context.fetchCount(FetchDescriptor<Contractor>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        let saved = try #require(context.fetch(FetchDescriptor<Invoice>()).first)
        #expect(saved.ksefSubmissionStatus == .accepted)
        #expect(saved.isPaid)
        #expect(saved.lines.count == 1)
        #expect(saved.lines[0].invoice === saved)
        #expect(saved.lines[0].cnPkwiu == "62.01.11.0")
    }
}
