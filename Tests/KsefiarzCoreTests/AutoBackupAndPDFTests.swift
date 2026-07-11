import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Automatyczna kopia zapasowa

@Suite("Automatyczna kopia zapasowa — zapis dzienny i rotacja")
struct AutoBackupServiceTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ksefiarz-backup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func day(_ string: String) -> Date {
        FA2Format.dateFormatter.date(from: string)!
    }

    private func writeBackup(_ dayString: String, in directory: URL) throws {
        let name = "ksefiarz-auto-\(dayString).json"
        try Data("{}".utf8).write(to: directory.appending(path: name))
    }

    @Test("Pierwsze uruchomienie dnia zapisuje kopię, kolejne już nie")
    func jednaKopiaDziennie() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var dataCalls = 0
        let provider: () throws -> Data = { dataCalls += 1; return Data("{}".utf8) }

        let first = try AutoBackupService.performIfNeeded(
            directory: directory, mode: .keepCount, keepCount: 7, keepDays: 30,
            now: day("2026-06-12"), data: provider
        )
        let second = try AutoBackupService.performIfNeeded(
            directory: directory, mode: .keepCount, keepCount: 7, keepDays: 30,
            now: day("2026-06-12"), data: provider
        )

        #expect(first == true)
        #expect(second == false)
        #expect(dataCalls == 1) // dane budowane tylko przy faktycznym zapisie
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["ksefiarz-auto-2026-06-12.json"])
    }

    @Test("Rotacja po liczbie kopii zostawia N najnowszych")
    func rotacjaPoLiczbie() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for dayString in ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04"] {
            try writeBackup(dayString, in: directory)
        }

        try AutoBackupService.rotate(
            in: directory, mode: .keepCount, keepCount: 2, keepDays: 30, now: day("2026-06-12")
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == ["ksefiarz-auto-2026-06-03.json", "ksefiarz-auto-2026-06-04.json"])
    }

    @Test("Rotacja po dniach usuwa kopie starsze niż N dni")
    func rotacjaPoDniach() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for dayString in ["2026-05-01", "2026-06-08", "2026-06-12"] {
            try writeBackup(dayString, in: directory)
        }

        try AutoBackupService.rotate(
            in: directory, mode: .keepDays, keepCount: 7, keepDays: 7, now: day("2026-06-12")
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == ["ksefiarz-auto-2026-06-08.json", "ksefiarz-auto-2026-06-12.json"])
    }

    @Test("Rotacja nie dotyka plików spoza schematu automatycznego")
    func rotacjaOmijaInnePliki() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appending(path: "ksefiarz-kopia-reczna.json"))
        for dayString in ["2026-06-01", "2026-06-02"] {
            try writeBackup(dayString, in: directory)
        }

        try AutoBackupService.rotate(
            in: directory, mode: .keepCount, keepCount: 1, keepDays: 30, now: day("2026-06-12")
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == ["ksefiarz-auto-2026-06-02.json", "ksefiarz-kopia-reczna.json"])
    }
}

// MARK: - Paginacja PDF

@Suite("PDF — podział pozycji na strony")
@MainActor
struct PDFPaginationTests {

    private func makeLines(_ count: Int) -> [InvoiceLine] {
        (1...count).map { InvoiceLine(index: $0, name: "Pozycja \($0)") }
    }

    @Test("Krótka faktura mieści się na jednej stronie")
    func jednaStrona() {
        #expect(InvoicePDFGenerator.paginate([]).count == 1)
        #expect(InvoicePDFGenerator.paginate(makeLines(10)).count == 1)
    }

    @Test("Pozycje niemieszczące się z podsumowaniem przechodzą na kolejne strony")
    func wieleStron() {
        // 12 pozycji wypełnia pierwszą stronę — podsumowanie dostaje własną.
        let chunks12 = InvoicePDFGenerator.paginate(makeLines(12))
        #expect(chunks12.map(\.count) == [12, 0])

        // 40 pozycji: 12 + 22 + 6; ostatnia strona mieści podsumowanie.
        let chunks40 = InvoicePDFGenerator.paginate(makeLines(40))
        #expect(chunks40.map(\.count) == [12, 22, 6])
    }

    @Test("Kolejność pozycji jest zachowana między stronami")
    func kolejnoscZachowana() {
        let chunks = InvoicePDFGenerator.paginate(makeLines(30))
        let indices = chunks.flatMap { $0.map(\.index) }
        #expect(indices == Array(1...30))
    }
}
