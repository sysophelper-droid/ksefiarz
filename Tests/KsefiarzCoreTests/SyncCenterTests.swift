import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

// MARK: - Atrapa usługi (wysyłka + statusy + UPO)

/// Atrapa łącząca kontrakty potrzebne do domykania wysyłek
/// (kolejka offline + sesje wsadowe + statusy/UPO).
private final class MockSubmissionService: KSeFInvoiceSending, KSeFSubmissionStatusProviding,
    KSeFBatchStatusProviding {
    var sendError: Error?
    var statusError: Error?
    /// Stan sesji wsadowych — domyślnie brak (odpytanie jest błędem).
    var batchStatusBySession: [String: KSeFBatchSessionStatus] = [:]
    var batchOutcomesBySession: [String: [KSeFBatchInvoiceOutcome]] = [:]

    func fetchBatchSessionStatus(
        referenceNumber: String
    ) async throws -> KSeFBatchSessionStatus {
        guard let status = batchStatusBySession[referenceNumber] else {
            throw KSeFError.invalidResponse
        }
        return status
    }

    func fetchBatchSessionInvoices(
        referenceNumber: String
    ) async throws -> [KSeFBatchInvoiceOutcome] {
        batchOutcomesBySession[referenceNumber] ?? []
    }

    func sendInvoiceXML(_ xmlData: Data, offlineMode: Bool) async throws -> KSeFSendResult {
        if let sendError { throw sendError }
        return KSeFSendResult(
            invoiceReferenceNumber: "INV-REF-1",
            ksefNumber: "1111111111-20260711-BBBBBBBBBBBB-BB",
            sessionReferenceNumber: "SESS-1",
            xml: String(decoding: xmlData, as: UTF8.self),
            processingResult: KSeFInvoiceProcessingResult(
                status: .accepted,
                statusCode: 200,
                description: "Przyjęta",
                ksefNumber: "1111111111-20260711-BBBBBBBBBBBB-BB",
                acquisitionDate: Date(timeIntervalSince1970: 1_790_000_000)
            )
        )
    }

    func fetchInvoiceStatus(
        sessionReference: String,
        invoiceReference: String
    ) async throws -> KSeFInvoiceProcessingResult {
        if let statusError { throw statusError }
        return KSeFInvoiceProcessingResult(
            status: .accepted,
            statusCode: 200,
            description: "Przyjęta",
            ksefNumber: "1111111111-20260711-BBBBBBBBBBBB-BB",
            acquisitionDate: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    func downloadUPO(sessionReference: String, ksefNumber: String) async throws -> Data {
        Data("<UPO/>".utf8)
    }
}

private func makeOfflinePendingInvoice(environment: String = "production") -> Invoice {
    let xml = "<Faktura>offline</Faktura>"
    let invoice = Invoice(
        invoiceNumber: "FV/OFF/1", issueDate: .now,
        sellerName: "A", sellerNIP: "1111111111",
        buyerName: "B", buyerNIP: "2222222222",
        netAmount: 100, vatAmount: 23, grossAmount: 123,
        rawXmlContent: xml,
        ksefSubmissionStatus: .offlinePending,
        ksefEnvironmentRaw: environment,
        kind: .sales
    )
    invoice.isOfflineMode = true
    return invoice
}

// MARK: - Testy

@Suite("Centrum synchronizacji — historia i stany przebiegów")
@MainActor
struct SyncCenterTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, SyncRun.self, configurations: configuration
        )
        return ModelContext(container)
    }

    @Test("Zapis przebiegu trafia do historii z licznikami i bez błędu")
    func zapisPrzebiegu() throws {
        let context = try makeContext()

        let run = try SyncCenter.record(
            operation: .purchases,
            trigger: .manual,
            environmentRaw: "production",
            startedAt: .now,
            fetched: 12,
            inserted: 3,
            context: context
        )

        let saved = try context.fetch(FetchDescriptor<SyncRun>())
        #expect(saved.count == 1)
        #expect(run.operation == .purchases)
        #expect(run.trigger == .manual)
        #expect(run.fetchedCount == 12)
        #expect(run.insertedCount == 3)
        #expect(run.succeeded)
        #expect(context.hasChanges == false) // jawny zapis wykonany
    }

    @Test("Przebieg z błędem lub niepowodzeniami dokumentów nie jest udany")
    func nieudanyPrzebieg() throws {
        let context = try makeContext()

        let failed = try SyncCenter.record(
            operation: .sales,
            trigger: .automatic,
            environmentRaw: "production",
            startedAt: .now,
            error: "Brak sieci",
            context: context
        )
        let partial = try SyncCenter.record(
            operation: .submissions,
            trigger: .automatic,
            environmentRaw: "production",
            startedAt: .now,
            fetched: 3,
            failures: 1,
            context: context
        )

        #expect(!failed.succeeded)
        #expect(failed.errorMessage == "Brak sieci")
        #expect(!partial.succeeded)
        #expect(partial.failureCount == 1)
    }

    @Test("Historia jest przycinana do limitu — zostają najnowsze wpisy")
    func przycinanieHistorii() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        for index in 0..<10 {
            context.insert(SyncRun(
                operation: .purchases,
                trigger: .automatic,
                startedAt: base.addingTimeInterval(Double(index) * 60)
            ))
        }

        try SyncCenter.prune(context: context, keep: 4)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<SyncRun>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        #expect(remaining.count == 4)
        #expect(remaining.first?.startedAt == base.addingTimeInterval(9 * 60))
        #expect(remaining.last?.startedAt == base.addingTimeInterval(6 * 60))
    }

    @Test("Stany operacji: najnowszy przebieg per operacja, tylko bieżące środowisko")
    func stanyOperacji() {
        let old = SyncRun(
            operation: .purchases, trigger: .manual, environmentRaw: "production",
            startedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = SyncRun(
            operation: .purchases, trigger: .automatic, environmentRaw: "production",
            startedAt: Date(timeIntervalSince1970: 200)
        )
        let otherEnvironment = SyncRun(
            operation: .sales, trigger: .manual, environmentRaw: "test",
            startedAt: Date(timeIntervalSince1970: 300)
        )

        let latest = SyncCenter.latestRuns(
            in: [old, newer, otherEnvironment], environmentRaw: "production"
        )
        #expect(latest[.purchases] === newer)
        #expect(latest[.sales] == nil)
        #expect(latest[.submissions] == nil)
    }

    @Test("Pusta kolejka wysyłek nie zaśmieca historii (automat co 60 s)")
    func pustaKolejkaBezWpisu() async throws {
        let context = try makeContext()
        let service = MockSubmissionService()

        let outcome = await SyncCenter.reconcileSubmissions(
            invoices: [],
            environmentRaw: "production",
            trigger: .automatic,
            using: service,
            context: context
        )

        #expect(outcome.hadWork == false)
        #expect(try context.fetch(FetchDescriptor<SyncRun>()).isEmpty)
    }

    @Test("Dosłanie dokumentu offline zapisuje przebieg wysyłek z licznikami")
    func doslanieZapisujePrzebieg() async throws {
        let context = try makeContext()
        let invoice = makeOfflinePendingInvoice()
        context.insert(invoice)
        let service = MockSubmissionService()

        let outcome = await SyncCenter.reconcileSubmissions(
            invoices: [invoice],
            environmentRaw: "production",
            trigger: .manual,
            using: service,
            context: context
        )

        #expect(outcome.hadWork)
        #expect(outcome.failures == 0)
        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefId == "1111111111-20260711-BBBBBBBBBBBB-BB")

        let runs = try context.fetch(FetchDescriptor<SyncRun>())
        #expect(runs.count == 1)
        #expect(runs.first?.operation == .submissions)
        #expect(runs.first?.trigger == .manual)
        #expect(runs.first?.succeeded == true)
        // Dosłanie + pobranie UPO — dokument obsłużony w dwóch krokach.
        #expect((runs.first?.fetchedCount ?? 0) >= 1)
        #expect((runs.first?.insertedCount ?? 0) >= 1)
    }

    @Test("Domknięcie sesji wsadowej nadaje numer KSeF i pobiera UPO w jednym przebiegu")
    func domkniecieSesjiWsadowej() async throws {
        let context = try makeContext()
        // Dokument przekazany wsadowo: „w toku” z sesją, bez referencji faktury.
        let xml = "<Faktura>wsadowa</Faktura>"
        let invoice = Invoice(
            invoiceNumber: "FV/BATCH/1", issueDate: .now,
            sellerName: "A", sellerNIP: "1111111111",
            buyerName: "B", buyerNIP: "2222222222",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            rawXmlContent: xml,
            ksefSessionReference: "SB-1",
            ksefSubmissionStatus: .processing,
            ksefEnvironmentRaw: "production",
            kind: .sales
        )
        context.insert(invoice)

        let service = MockSubmissionService()
        service.batchStatusBySession["SB-1"] = KSeFBatchSessionStatus(
            code: 200, description: "Sesja wsadowa przetworzona pomyślnie",
            invoiceCount: 1, successfulInvoiceCount: 1, failedInvoiceCount: 0
        )
        service.batchOutcomesBySession["SB-1"] = [
            KSeFBatchInvoiceOutcome(
                referenceNumber: "REF-1",
                invoiceNumber: "FV/BATCH/1",
                invoiceHash: KSeFCrypto.sha256Base64(Data(xml.utf8)),
                invoiceFileName: "faktura_00001.xml",
                result: KSeFInvoiceProcessingResult(
                    status: .accepted,
                    statusCode: 200,
                    description: "Sukces",
                    ksefNumber: "1111111111-20260711-BBBBBBBBBBBB-BB",
                    acquisitionDate: Date(timeIntervalSince1970: 1_790_000_000)
                )
            ),
        ]

        let outcome = await SyncCenter.reconcileSubmissions(
            invoices: [invoice],
            environmentRaw: "production",
            trigger: .automatic,
            using: service,
            context: context
        )

        #expect(outcome.hadWork)
        #expect(outcome.accepted >= 1)
        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefId == "1111111111-20260711-BBBBBBBBBBBB-BB")
        #expect(invoice.ksefInvoiceReference == "REF-1")
        // UPO pobrane w tym samym przebiegu (wspólna ścieżka domykania).
        #expect(invoice.upoXmlContent == "<UPO/>")

        let runs = try context.fetch(FetchDescriptor<SyncRun>())
        #expect(runs.first?.operation == .submissions)
    }

    @Test("Błąd sieci przy dosłaniu trafia do historii jako niepowodzenie")
    func bladDoslaniaWHistorii() async throws {
        let context = try makeContext()
        let invoice = makeOfflinePendingInvoice()
        context.insert(invoice)
        let service = MockSubmissionService()
        service.sendError = URLError(.notConnectedToInternet)

        let outcome = await SyncCenter.reconcileSubmissions(
            invoices: [invoice],
            environmentRaw: "production",
            trigger: .automatic,
            using: service,
            context: context
        )

        #expect(outcome.failures == 1)
        #expect(invoice.ksefSubmissionStatus == .offlinePending) // zostaje w kolejce

        let runs = try context.fetch(FetchDescriptor<SyncRun>())
        #expect(runs.count == 1)
        #expect(runs.first?.succeeded == false)
        #expect(runs.first?.failureCount == 1)
    }

    @Test("Nieudany import zapisuje przebieg z komunikatem błędu i rzuca dalej")
    func nieudanyImportWHistorii() async throws {
        let context = try makeContext()
        // Puste poświadczenia — uwierzytelnienie odpada bez ruchu sieciowego.
        let service = KSeFService(environment: .test, nip: "", authToken: "")

        await #expect(throws: KSeFError.missingCredentials) {
            try await InvoiceSyncEngine.sync(
                kind: .purchase,
                service: service,
                from: .now.addingTimeInterval(-86_400),
                to: .now,
                prepaidForms: [],
                context: context,
                trigger: .retry,
                environmentRaw: "test"
            )
        }

        let runs = try context.fetch(FetchDescriptor<SyncRun>())
        #expect(runs.count == 1)
        #expect(runs.first?.operation == .purchases)
        #expect(runs.first?.trigger == .retry)
        #expect(runs.first?.environmentRaw == "test")
        #expect(runs.first?.succeeded == false)
        #expect(runs.first?.errorMessage?.isEmpty == false)
    }
}
