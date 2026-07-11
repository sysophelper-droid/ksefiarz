import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze: rozpakowanie systemowym unzip

/// Zapisuje archiwum do pliku tymczasowego i uruchamia /usr/bin/unzip —
/// niezależna weryfikacja zgodności naszego ZIP z formatem.
private func withTemporaryZip<T>(_ data: Data, _ body: (URL) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ksefiarz-test-\(UUID().uuidString).zip")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

private func runUnzip(_ arguments: [String]) throws -> (status: Int32, output: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, output)
}

/// Zawartość pojedynczego pliku z archiwum — rozpakowanie całości do
/// katalogu tymczasowego i odczyt z dysku (dopasowanie nazw UTF-8
/// w argumencie `unzip -p` bywa zawodne, samo archiwum jest poprawne).
private func extractFile(_ zip: Data, path: String) throws -> Data {
    try withTemporaryZip(zip) { url in
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ksefiarz-unzip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try runUnzip(["-o", "-q", url.path, "-d", directory.path])
        return try Data(contentsOf: directory.appendingPathComponent(path))
    }
}

// MARK: - ZipWriter

@Suite("ZipWriter — archiwum ZIP bez zależności")
struct ZipWriterTests {

    @Test("CRC-32 zgodny z wektorem referencyjnym")
    func crc32Vector() {
        // Standardowy wektor: crc32("123456789") = 0xCBF43926.
        #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF43926)
        #expect(ZipWriter.crc32(Data()) == 0)
    }

    @Test("Archiwum przechodzi test integralności systemowego unzip")
    func unzipIntegrity() throws {
        var writer = ZipWriter()
        writer.addFile(path: "raport.txt", data: Data("treść raportu".utf8))
        writer.addFile(path: "XML/sprzedaz/Faktura_FV-1.xml", data: Data("<Faktura/>".utf8))
        let archive = writer.finalized()

        let result = try withTemporaryZip(archive) { url in
            try runUnzip(["-t", url.path])
        }
        #expect(result.status == 0, "unzip -t zgłosił błąd integralności")
        let listing = String(decoding: result.output, as: UTF8.self)
        #expect(listing.contains("raport.txt"))
        #expect(listing.contains("XML/sprzedaz/Faktura_FV-1.xml"))
    }

    @Test("Zawartość plików wychodzi bajt w bajt (w tym polskie znaki w nazwach)")
    func contentRoundTrip() throws {
        let payload = Data("Zażółć gęślą jaźń — treść pliku".utf8)
        var writer = ZipWriter()
        writer.addFile(path: "zestawienie_sprzedaż.csv", data: payload)
        let archive = writer.finalized()

        let extracted = try extractFile(archive, path: "zestawienie_sprzedaż.csv")
        #expect(extracted == payload)
    }
}

// MARK: - Paczka dla księgowości

@Suite("AccountingPackageBuilder — paczka dla księgowości")
@MainActor
struct AccountingPackageTests {

    private func makeInvoice(
        number: String,
        kind: Invoice.Kind,
        xml: String? = "<Faktura>dok</Faktura>",
        status: KSeFSubmissionStatus = .accepted,
        upo: String? = "<UPO/>",
        buyerNIP: String = "2222222222",
        gross: Double = 123,
        currency: String = "PLN"
    ) -> Invoice {
        Invoice(
            ksefId: status == .accepted ? "1111111111-20260711-AAAAAAAAAAAA-AA" : nil,
            invoiceNumber: number,
            issueDate: .now,
            sellerName: "Sprzedawca", sellerNIP: "1111111111",
            buyerName: "Nabywca", buyerNIP: buyerNIP,
            netAmount: gross / 1.23, vatAmount: gross - gross / 1.23, grossAmount: gross,
            rawXmlContent: xml,
            ksefSubmissionStatus: status,
            upoXmlContent: upo,
            currency: currency,
            kind: kind
        )
    }

    @Test("Raport braków: komplet dokumentów nie zgłasza problemów")
    func noIssuesForCompleteInvoice() {
        let complete = makeInvoice(number: "FV/1", kind: .sales)
        #expect(AccountingPackageBuilder.documentIssues(for: complete).isEmpty)
    }

    @Test("Raport braków wykrywa: brak XML, brak UPO, lokalną, odrzuconą, offline i brak NIP")
    func detectsIssues() {
        let noXML = makeInvoice(number: "Z/1", kind: .purchase, xml: nil)
        #expect(AccountingPackageBuilder.documentIssues(for: noXML)
            .contains { $0.contains("brak oryginalnego dokumentu XML") })

        let noUPO = makeInvoice(number: "FV/2", kind: .sales, upo: nil)
        #expect(AccountingPackageBuilder.documentIssues(for: noUPO)
            .contains { $0.contains("brak pobranego UPO") })

        let localOnly = makeInvoice(number: "FV/3", kind: .sales, status: .local, upo: nil)
        #expect(AccountingPackageBuilder.documentIssues(for: localOnly)
            .contains { $0.contains("nie przekazana do KSeF") })

        let rejected = makeInvoice(number: "FV/4", kind: .sales, status: .rejected, upo: nil)
        #expect(AccountingPackageBuilder.documentIssues(for: rejected)
            .contains { $0.contains("ODRZUCONA") })

        let offline = makeInvoice(number: "FV/5", kind: .sales, status: .offlinePending, upo: nil)
        #expect(AccountingPackageBuilder.documentIssues(for: offline)
            .contains { $0.contains("offline24") })

        let noNIP = makeInvoice(number: "FV/6", kind: .sales, buyerNIP: "")
        #expect(AccountingPackageBuilder.documentIssues(for: noNIP)
            .contains { $0.contains("brak NIP nabywcy") })

        // Faktura zakupowa lokalna (pobrana bez XML) nie jest „niewysłana".
        let purchaseLocal = makeInvoice(number: "Z/2", kind: .purchase, status: .local, upo: nil)
        #expect(!AccountingPackageBuilder.documentIssues(for: purchaseLocal)
            .contains { $0.contains("nie przekazana") })
    }

    @Test("Paczka zawiera CSV, XML, PDF i raport; braki trafiają do raportu")
    func fullPackage() throws {
        let invoices = [
            makeInvoice(number: "FV/2026/06/001", kind: .sales),
            makeInvoice(number: "FV/2026/06/002", kind: .sales, xml: nil, status: .local, upo: nil),
            makeInvoice(number: "FZ/44", kind: .purchase, gross: 246, currency: "EUR"),
        ]
        // Pozycje potrzebne do sensownego PDF.
        invoices[0].lines = [
            InvoiceLine(index: 1, name: "Usługa", unit: "szt.", quantity: 1,
                        unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23),
        ]

        let result = AccountingPackageBuilder.makePackage(
            invoices: invoices,
            periodLabel: "czerwiec 2026"
        )
        #expect(result.invoiceCount == 3)
        #expect(result.issueCount >= 2) // brak XML + niewysłana (FV/002)

        // Struktura archiwum potwierdzona systemowym unzip.
        let listing = try withTemporaryZip(result.zipData) { url in
            String(decoding: try runUnzip(["-l", url.path]).output, as: UTF8.self)
        }
        #expect(listing.contains("zestawienie_sprzedaz.csv"))
        #expect(listing.contains("zestawienie_zakup.csv"))
        #expect(listing.contains("XML/sprzedaz/Faktura_FV-2026-06-001.xml"))
        #expect(listing.contains("PDF/sprzedaz/Faktura_FV-2026-06-001.pdf"))
        #expect(listing.contains("PDF/zakup/Faktura_FZ-44.pdf"))
        #expect(listing.contains("raport.txt"))
        // Faktura bez XML nie tworzy pustego pliku XML.
        #expect(!listing.contains("XML/sprzedaz/Faktura_FV-2026-06-002.xml"))

        // Raport: okres, sumy per waluta i wykryte braki.
        let report = String(
            decoding: try extractFile(result.zipData, path: "raport.txt"),
            as: UTF8.self
        )
        #expect(report.contains("czerwiec 2026"))
        #expect(report.contains("Sprzedaż: 2 faktur"))
        #expect(report.contains("Zakup: 1 faktur"))
        #expect(report.contains("EUR"))
        #expect(report.contains("FV/2026/06/002"))
        #expect(report.contains("brak oryginalnego dokumentu XML"))
        #expect(report.contains("nie przekazana do KSeF"))

        // CSV sprzedaży zawiera numery faktur.
        let csv = String(
            decoding: try extractFile(result.zipData, path: "zestawienie_sprzedaz.csv"),
            as: UTF8.self
        )
        #expect(csv.contains("FV/2026/06/001"))
        #expect(csv.contains("FV/2026/06/002"))

        // XML wychodzi bajt w bajt.
        let xml = try extractFile(result.zipData, path: "XML/sprzedaz/Faktura_FV-2026-06-001.xml")
        #expect(xml == Data("<Faktura>dok</Faktura>".utf8))
    }

    @Test("Opcje pozwalają pominąć XML i PDF (samo zestawienie z raportem)")
    func optionsSkipComponents() throws {
        let result = AccountingPackageBuilder.makePackage(
            invoices: [makeInvoice(number: "FV/1", kind: .sales)],
            periodLabel: "lipiec 2026",
            options: .init(includeXML: false, includePDF: false)
        )
        let listing = try withTemporaryZip(result.zipData) { url in
            String(decoding: try runUnzip(["-l", url.path]).output, as: UTF8.self)
        }
        #expect(listing.contains("zestawienie_sprzedaz.csv"))
        #expect(listing.contains("raport.txt"))
        #expect(!listing.contains("XML/"))
        #expect(!listing.contains("PDF/"))
    }

    @Test("Pusta paczka zawiera sam raport z informacją o braku dokumentów")
    func emptyPackage() throws {
        let result = AccountingPackageBuilder.makePackage(invoices: [], periodLabel: "maj 2026")
        #expect(result.invoiceCount == 0)
        let report = String(
            decoding: try extractFile(result.zipData, path: "raport.txt"),
            as: UTF8.self
        )
        #expect(report.contains("maj 2026"))
        #expect(report.contains("nie wykryto"))
    }
}
