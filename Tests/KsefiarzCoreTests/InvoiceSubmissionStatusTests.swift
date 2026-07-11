import Foundation
import Testing
@testable import KsefiarzCore

private final class StubSubmissionStatusService: KSeFSubmissionStatusProviding {
    var results: [Result<KSeFInvoiceProcessingResult, Error>]
    var upoData: Data?
    private(set) var statusRequests: [(String, String)] = []
    private(set) var upoRequests: [(String, String)] = []

    init(
        results: [Result<KSeFInvoiceProcessingResult, Error>] = [],
        upoData: Data? = nil
    ) {
        self.results = results
        self.upoData = upoData
    }

    func fetchInvoiceStatus(
        sessionReference: String,
        invoiceReference: String
    ) async throws -> KSeFInvoiceProcessingResult {
        statusRequests.append((sessionReference, invoiceReference))
        guard !results.isEmpty else { throw KSeFError.invalidResponse }
        return try results.removeFirst().get()
    }

    func downloadUPO(sessionReference: String, ksefNumber: String) async throws -> Data {
        upoRequests.append((sessionReference, ksefNumber))
        guard let upoData else { throw KSeFError.invalidResponse }
        return upoData
    }
}

private func makeSubmittedInvoice(
    status: KSeFSubmissionStatus = .processing,
    environment: String = KSeFEnvironment.test.rawValue
) -> Invoice {
    let invoice = makeTestInvoice(number: "FV/STATUS/1", kind: .sales)
    invoice.ksefSessionReference = "SESS-STATUS-1"
    invoice.ksefInvoiceReference = "INV-STATUS-1"
    invoice.ksefSubmissionStatus = status
    invoice.ksefEnvironmentRaw = environment
    return invoice
}

@Suite("Pełny cykl statusu wysyłki KSeF")
struct InvoiceSubmissionStatusTests {

    @Test("Starsze rekordy wyprowadzają stan z numeru KSeF, a lokalne pozostają edytowalne")
    func legacyFallback() {
        let local = makeTestInvoice(kind: .sales)
        #expect(local.ksefSubmissionStatus == .local)
        #expect(local.isLocalOnly)

        let legacyAccepted = makeTestInvoice(kind: .sales, ksefId: "KSEF-LEGACY")
        #expect(legacyAccepted.ksefSubmissionStatus == .accepted)
        #expect(!legacyAccepted.isLocalOnly)

        let processing = makeSubmittedInvoice()
        #expect(processing.ksefSubmissionStatus == .processing)
        #expect(processing.needsKSeFFollowUp)
        #expect(!processing.isLocalOnly)
    }

    @Test("Status w toku zapisuje kod i opis, ale nie udaje numeru KSeF")
    @MainActor
    func processingStatus() async throws {
        let invoice = makeSubmittedInvoice()
        let result = KSeFInvoiceProcessingResult(
            status: .processing,
            statusCode: 150,
            description: "Trwa przetwarzanie"
        )
        let service = StubSubmissionStatusService(results: [.success(result)])
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try await InvoiceSubmissionStatusEngine.refresh(
            invoice,
            using: service,
            now: checkedAt
        )

        #expect(invoice.ksefSubmissionStatus == .processing)
        #expect(invoice.ksefId == nil)
        #expect(invoice.ksefStatusCode == 150)
        #expect(invoice.ksefStatusDescription == "Trwa przetwarzanie")
        #expect(invoice.ksefLastCheckedAt == checkedAt)
        #expect(service.statusRequests.count == 1)
        #expect(service.upoRequests.isEmpty)
    }

    @Test("Przyjęcie zapisuje numer KSeF, datę i automatycznie pobrane UPO")
    @MainActor
    func acceptedStatusAndUPO() async throws {
        let invoice = makeSubmittedInvoice()
        let acceptedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let result = KSeFInvoiceProcessingResult(
            status: .accepted,
            statusCode: 200,
            description: "Faktura przyjęta",
            ksefNumber: "KSEF-FINAL-1",
            acquisitionDate: acceptedAt
        )
        let service = StubSubmissionStatusService(
            results: [.success(result)],
            upoData: Data("<UPO>ok</UPO>".utf8)
        )

        _ = try await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)

        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefId == "KSEF-FINAL-1")
        #expect(invoice.ksefAcceptedAt == acceptedAt)
        #expect(invoice.upoXmlContent == "<UPO>ok</UPO>")
        #expect(!invoice.needsKSeFFollowUp)
        #expect(service.upoRequests.count == 1)
    }

    @Test("Brak gotowego UPO nie cofa przyjęcia i pozostawia zadanie do ponowienia")
    @MainActor
    func acceptedWithoutReadyUPO() async throws {
        let invoice = makeSubmittedInvoice()
        let result = KSeFInvoiceProcessingResult(
            status: .accepted,
            statusCode: 200,
            description: "Przyjęta",
            ksefNumber: "KSEF-FINAL-2"
        )
        let service = StubSubmissionStatusService(results: [.success(result)])

        _ = try await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)

        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefId == "KSEF-FINAL-2")
        #expect(invoice.upoXmlContent == nil)
        #expect(invoice.needsKSeFFollowUp)
    }

    @Test("Odrzucenie jest trwałym stanem z komunikatem KSeF")
    @MainActor
    func rejectedStatus() async throws {
        let invoice = makeSubmittedInvoice()
        let result = KSeFInvoiceProcessingResult(
            status: .rejected,
            statusCode: 440,
            description: "Sesja anulowana"
        )
        let service = StubSubmissionStatusService(results: [.success(result)])

        _ = try await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)

        #expect(invoice.ksefSubmissionStatus == .rejected)
        #expect(invoice.ksefStatusCode == 440)
        #expect(invoice.ksefStatusDescription == "Sesja anulowana")
        #expect(invoice.ksefId == nil)
        #expect(!invoice.needsKSeFFollowUp)
    }

    @Test("Automat sprawdza tylko właściwe środowisko i izoluje błędy dokumentów")
    @MainActor
    func outstandingSummaryAndEnvironment() async {
        let matching = makeSubmittedInvoice(environment: KSeFEnvironment.test.rawValue)
        let otherEnvironment = makeSubmittedInvoice(environment: KSeFEnvironment.production.rawValue)
        otherEnvironment.invoiceNumber = "FV/STATUS/2"
        let service = StubSubmissionStatusService(
            results: [.failure(KSeFError.invalidResponse)]
        )

        let summary = await InvoiceSubmissionStatusEngine.refreshOutstanding(
            [matching, otherEnvironment],
            environmentRaw: KSeFEnvironment.test.rawValue,
            using: service
        )

        #expect(summary.checked == 0)
        #expect(summary.failures == 1)
        #expect(service.statusRequests.count == 1)
        #expect(otherEnvironment.ksefLastCheckedAt == nil)
    }
}
