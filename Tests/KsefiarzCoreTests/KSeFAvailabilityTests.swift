import Foundation
import Testing
@testable import KsefiarzCore

private let availabilityStatusMaintenance = Data(#"""
{
  "status":"MAINTENANCE",
  "messages":[{
    "id":"K/2026/NI/01","eventId":1000,"category":"MAINTENANCE",
    "type":"MAINTENANCE_ANNOUNCEMENT","title":"Planowana niedostępność",
    "text":"Prace serwisowe KSeF","start":"2026-07-18T20:00:00+02:00",
    "end":"2026-07-19T04:00:00+02:00","version":2,
    "published":"2026-07-13T08:00:00.123+00:00"
  }]
}
"""#.utf8)

private let availabilityMessages = Data(#"""
[
  {
    "id":"K/2026/NI/01","eventId":1000,"category":"MAINTENANCE",
    "type":"MAINTENANCE_ANNOUNCEMENT","title":"Planowana niedostępność",
    "text":"Prace serwisowe KSeF","start":"2026-07-18T20:00:00+02:00",
    "end":"2026-07-19T04:00:00+02:00","version":2,
    "published":"2026-07-13T08:00:00.123+00:00"
  },
  {
    "id":"K/2026/AWR/02","eventId":1001,"category":"FAILURE",
    "type":"FAILURE_END","title":"Zakończenie awarii",
    "text":"Awaria zakończona","start":"2026-07-10T08:00:00Z",
    "end":"2026-07-10T12:30:00Z","version":1,
    "published":"2026-07-10T12:35:00Z"
  }
]
"""#.utf8)

private func availabilityDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

private func availabilityMessage(
    eventId: Int,
    category: KSeFAvailabilityCategory,
    type: KSeFAvailabilityMessageType,
    start: Date,
    end: Date? = nil,
    title: String = "Komunikat MF"
) -> KSeFAvailabilityMessage {
    KSeFAvailabilityMessage(
        id: "K/TEST/\(eventId)/\(type)", eventId: eventId,
        category: category, type: type, title: title, text: "Treść komunikatu",
        start: start, end: end, version: 1, published: start
    )
}

private func availabilityInvoice(
    reason: Invoice.OfflineReason,
    eventId: Int? = nil,
    environment: KSeFEnvironment = .production
) -> Invoice {
    let invoice = Invoice(
        invoiceNumber: "FV/LATARNIA", issueDate: availabilityDate("2026-07-10T10:00:00Z"),
        sellerName: "A", sellerNIP: "5260250274", buyerName: "B", buyerNIP: "1111111111",
        netAmount: 100, vatAmount: 23, grossAmount: 123,
        rawXmlContent: "<Faktura/>", ksefSubmissionStatus: .offlinePending,
        ksefEnvironmentRaw: environment.rawValue, kind: .sales
    )
    invoice.isOfflineMode = true
    invoice.offlineReason = reason
    invoice.offlineEventId = eventId
    return invoice
}

@Suite("Latarnia KSeF — klient publicznego API MF")
struct KSeFAvailabilityServiceTests {

    @Test("Pobiera status i komunikaty, dekodując daty z offsetem i ułamkami sekund")
    func fetchesSnapshot() async throws {
        let transport = MockTransport()
        transport.routeOK("/status", data: availabilityStatusMaintenance)
        transport.routeOK("/messages", data: availabilityMessages)
        let now = availabilityDate("2026-07-13T12:00:00Z")
        let service = KSeFAvailabilityService(
            environment: .production,
            transport: transport,
            baseURL: URL(string: "https://latarnia.example")!
        )

        let snapshot = try await service.fetchSnapshot(now: now)

        #expect(snapshot.environment == .production)
        #expect(snapshot.status == .maintenance)
        #expect(snapshot.activeMessages.count == 1)
        #expect(snapshot.messages.count == 2)
        #expect(snapshot.activeMessages[0].eventId == 1000)
        #expect(snapshot.activeMessages[0].end == availabilityDate("2026-07-19T02:00:00Z"))
        #expect(snapshot.fetchedAt == now)
        #expect(transport.requests.map(\.url?.path) == ["/messages", "/status"])
        #expect(transport.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == nil
                && $0.value(forHTTPHeaderField: "Accept") == "application/json"
        })
    }

    @Test("Odpowiedź AVAILABLE bez pola messages jest poprawna")
    func availableWithoutMessages() async throws {
        let transport = MockTransport()
        transport.routeOK("/status", data: Data(#"{"status":"AVAILABLE"}"#.utf8))
        transport.routeOK("/messages", data: Data("[]".utf8))
        let snapshot = try await KSeFAvailabilityService(
            environment: .test, transport: transport,
            baseURL: URL(string: "https://latarnia.example")!
        ).fetchSnapshot()
        #expect(snapshot.status == .available)
        #expect(snapshot.activeMessages.isEmpty)
        #expect(snapshot.messages.isEmpty)
    }

    @Test("Nieznany przyszły status nie uruchamia automatycznie trybu offline")
    func unknownStatusIsSafe() async throws {
        let transport = MockTransport()
        transport.routeOK("/status", data: Data(#"{"status":"DEGRADED"}"#.utf8))
        transport.routeOK("/messages", data: Data("[]".utf8))
        let snapshot = try await KSeFAvailabilityService(
            environment: .production, transport: transport,
            baseURL: URL(string: "https://latarnia.example")!
        ).fetchSnapshot()
        #expect(snapshot.status == .unknown("DEGRADED"))
        #expect(KSeFAvailabilityPolicy.currentSuggestion(from: snapshot) == nil)
    }

    @Test("Błąd HTTP i niepoprawny JSON są raportowane czytelnie")
    func errors() async {
        let failed = MockTransport()
        failed.route("/messages") { _ in (503, Data()) }
        let failedService = KSeFAvailabilityService(
            environment: .production, transport: failed,
            baseURL: URL(string: "https://latarnia.example")!
        )
        await #expect(throws: KSeFAvailabilityError.badStatus(503)) {
            try await failedService.fetchSnapshot()
        }

        let malformed = MockTransport()
        malformed.routeOK("/status", data: Data(#"{"status":"AVAILABLE"}"#.utf8))
        malformed.routeOK("/messages", data: Data("{}".utf8))
        let malformedService = KSeFAvailabilityService(
            environment: .production, transport: malformed,
            baseURL: URL(string: "https://latarnia.example")!
        )
        await #expect(throws: KSeFAvailabilityError.invalidResponse) {
            try await malformedService.fetchSnapshot()
        }
    }

    @Test("Latarnia ma osobne adresy TEST i produkcja, bez fałszywego mapowania Demo")
    func environmentURLs() {
        #expect(KSeFEnvironment.test.availabilityBaseURL?.host == "api-latarnia-test.ksef.mf.gov.pl")
        #expect(KSeFEnvironment.production.availabilityBaseURL?.host == "api-latarnia.ksef.mf.gov.pl")
        #expect(KSeFEnvironment.demo.availabilityBaseURL == nil)
    }
}

@Suite("Latarnia KSeF — podpowiedzi trybu i automatyczny termin")
struct KSeFAvailabilityPolicyTests {

    @Test("Trwająca przerwa serwisowa proponuje niedostępność i znany termin")
    func maintenanceSuggestion() throws {
        let end = availabilityDate("2026-07-19T02:00:00Z") // niedziela 04:00 w Polsce
        let message = availabilityMessage(
            eventId: 1000, category: .maintenance, type: .maintenanceAnnouncement,
            start: availabilityDate("2026-07-18T18:00:00Z"), end: end
        )
        let snapshot = KSeFAvailabilitySnapshot(
            environment: .production, status: .maintenance,
            activeMessages: [message], messages: [message]
        )

        let suggestion = try #require(KSeFAvailabilityPolicy.currentSuggestion(from: snapshot))
        #expect(suggestion.reason == .unavailability)
        #expect(suggestion.eventId == 1000)
        let deadline = suggestion.deadline.map {
            PolishBusinessCalendar.calendar.dateComponents([.year, .month, .day], from: $0)
        }
        #expect(deadline == DateComponents(year: 2026, month: 7, day: 20))

        let invoice = availabilityInvoice(reason: .unavailability)
        KSeFAvailabilityPolicy.apply(suggestion, to: invoice)
        #expect(invoice.offlineEventId == 1000)
        #expect(invoice.offlineEventEndedAt == end)
    }

    @Test("Trwająca awaria proponuje tryb awaryjny, ale termin czeka na komunikat kończący")
    func failureSuggestion() {
        let start = availabilityDate("2026-07-10T08:00:00Z")
        let message = availabilityMessage(
            eventId: 1001, category: .failure, type: .failureStart, start: start
        )
        let snapshot = KSeFAvailabilitySnapshot(
            environment: .production, status: .failure,
            activeMessages: [message], messages: [message]
        )
        let suggestion = KSeFAvailabilityPolicy.currentSuggestion(from: snapshot)
        #expect(suggestion?.reason == .failure)
        #expect(suggestion?.deadline == nil)
    }

    @Test("Komunikat kończący uzupełnia termin tylko fakturze z tym samym eventId i środowiskiem")
    func reconcilesMatchingInvoice() {
        let end = availabilityDate("2026-07-10T12:30:00Z")
        let endMessage = availabilityMessage(
            eventId: 1001, category: .failure, type: .failureEnd,
            start: availabilityDate("2026-07-10T08:00:00Z"), end: end
        )
        let matching = availabilityInvoice(reason: .failure, eventId: 1001)
        let maintenance = availabilityInvoice(reason: .unavailability, eventId: 2000)
        let otherEvent = availabilityInvoice(reason: .failure, eventId: 9999)
        let demo = availabilityInvoice(reason: .failure, eventId: 1001, environment: .demo)
        let manual = availabilityInvoice(reason: .failure, eventId: nil)

        let maintenanceEnd = availabilityDate("2026-07-12T04:00:00Z")
        let maintenanceMessage = availabilityMessage(
            eventId: 2000, category: .maintenance, type: .maintenanceAnnouncement,
            start: availabilityDate("2026-07-11T22:00:00Z"), end: maintenanceEnd
        )
        let changed = KSeFAvailabilityPolicy.reconcile(
            invoices: [matching, maintenance, otherEvent, demo, manual],
            messages: [endMessage, maintenanceMessage],
            environmentRaw: KSeFEnvironment.production.rawValue
        )

        #expect(changed == 2)
        #expect(matching.offlineEventEndedAt == end)
        #expect(matching.offlineSendDeadline != nil)
        #expect(maintenance.offlineEventEndedAt == maintenanceEnd)
        #expect(otherEvent.offlineEventEndedAt == nil)
        #expect(demo.offlineEventEndedAt == nil)
        #expect(manual.offlineEventEndedAt == nil)
    }

    @Test("Awaria całkowita blokuje mapowanie na zwykły tryb offline")
    func totalFailureIsNotOffline() {
        let message = availabilityMessage(
            eventId: 1002, category: .totalFailure, type: .failureStart,
            start: availabilityDate("2026-07-10T08:00:00Z")
        )
        let snapshot = KSeFAvailabilitySnapshot(
            environment: .production, status: .totalFailure,
            activeMessages: [message], messages: [message]
        )
        #expect(KSeFAvailabilityPolicy.isTotalFailure(snapshot))
        #expect(KSeFAvailabilityPolicy.currentSuggestion(from: snapshot) == nil)
    }

    @Test("Przyszła przerwa jest zapowiadana najwyżej 7 dni wcześniej")
    func upcomingMaintenance() {
        let now = availabilityDate("2026-07-13T10:00:00Z")
        let soon = availabilityMessage(
            eventId: 10, category: .maintenance, type: .maintenanceAnnouncement,
            start: now.addingTimeInterval(2 * 86_400), end: now.addingTimeInterval(2 * 86_400 + 3600)
        )
        let later = availabilityMessage(
            eventId: 11, category: .maintenance, type: .maintenanceAnnouncement,
            start: now.addingTimeInterval(10 * 86_400), end: now.addingTimeInterval(10 * 86_400 + 3600)
        )
        let snapshot = KSeFAvailabilitySnapshot(
            environment: .production, status: .available,
            activeMessages: [], messages: [later, soon]
        )
        #expect(KSeFAvailabilityPolicy.upcomingMaintenance(from: snapshot, now: now)?.eventId == 10)
    }
}

/// Transport, którego żądania wiszą do jawnego zwolnienia — pozwala zbadać
/// zachowanie monitora, gdy odświeżanie wciąż trwa.
private final class WiszacyTransport: HTTPTransport, @unchecked Sendable {
    private let zamek = NSLock()
    private var kontynuacje: [CheckedContinuation<Void, Never>] = []
    private var zwolniony = false

    var czyCosWisi: Bool {
        zamek.lock(); defer { zamek.unlock() }
        return !kontynuacje.isEmpty
    }

    func zwolnij() {
        zamek.lock()
        zwolniony = true
        let wznawiane = kontynuacje
        kontynuacje = []
        zamek.unlock()
        wznawiane.forEach { $0.resume() }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await withCheckedContinuation { kontynuacja in
            zamek.lock()
            if zwolniony {
                zamek.unlock()
                kontynuacja.resume()
            } else {
                kontynuacje.append(kontynuacja)
                zamek.unlock()
            }
        }
        let sciezka = request.url?.path ?? ""
        let dane = sciezka.contains("status")
            ? Data(#"{"status":"AVAILABLE"}"#.utf8)
            : Data("[]".utf8)
        return (dane, HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!)
    }
}

private func availabilityOKTransport() -> MockTransport {
    let transport = MockTransport()
    transport.routeOK("/status", data: Data(#"{"status":"AVAILABLE"}"#.utf8))
    transport.routeOK("/messages", data: Data("[]".utf8))
    return transport
}

@Suite("Latarnia KSeF — monitor współdzielonego stanu")
@MainActor
struct KSeFAvailabilityMonitorTests {

    private static func monitor(
        transport: @escaping () -> HTTPTransport
    ) -> KSeFAvailabilityMonitor {
        KSeFAvailabilityMonitor { environment in
            KSeFAvailabilityService(
                environment: environment,
                transport: transport(),
                baseURL: URL(string: "https://latarnia.example")!
            )
        }
    }

    @Test("Udany odczyt ustawia snapshot; Demo czyści go i zgłasza jawny błąd")
    func demoCzysciSnapshot() async {
        let monitor = Self.monitor { availabilityOKTransport() }

        let pierwszy = await monitor.refresh(environment: .test)
        #expect(pierwszy?.environment == .test)
        #expect(monitor.snapshot?.environment == .test)
        #expect(monitor.lastError == nil)

        let demo = await monitor.refresh(environment: .demo)
        #expect(demo == nil)
        #expect(monitor.snapshot == nil)
        #expect(monitor.lastError == KSeFAvailabilityError.unsupportedEnvironment.localizedDescription)
    }

    @Test("Błąd sieci zachowuje poprzedni odczyt i ustawia czytelny komunikat")
    func bladZachowujePoprzedniOdczyt() async {
        let zepsuty = MockTransport()
        zepsuty.route("/messages") { _ in (503, Data()) }
        var transport: HTTPTransport = availabilityOKTransport()
        let monitor = Self.monitor { transport }

        _ = await monitor.refresh(environment: .production)
        #expect(monitor.snapshot != nil)

        transport = zepsuty
        let wynik = await monitor.refresh(environment: .production)
        #expect(wynik == nil)
        #expect(monitor.lastError == KSeFAvailabilityError.badStatus(503).localizedDescription)
        // Poprzedni snapshot zostaje — formularz sam ocenia jego świeżość.
        #expect(monitor.snapshot?.environment == .production)
    }

    @Test("Trwające odświeżanie nie oddaje snapshotu innego środowiska")
    func trwajaceOdswiezanieNieMieszaSrodowisk() async {
        let wiszacy = WiszacyTransport()
        var transport: HTTPTransport = availabilityOKTransport()
        let monitor = Self.monitor { transport }

        // Udany odczyt TEST, potem drugie odświeżanie TEST zawisa na sieci…
        _ = await monitor.refresh(environment: .test)
        transport = wiszacy
        let wTrakcie = Task { await monitor.refresh(environment: .test) }
        while !wiszacy.czyCosWisi { await Task.yield() }
        #expect(monitor.isRefreshing)

        // …i w tym oknie produkcja NIE może dostać snapshotu z TEST
        // (eventId to niezależne liczniki środowisk), a TEST nadal
        // dostaje swój ostatni znany odczyt.
        let produkcja = await monitor.refresh(environment: .production)
        #expect(produkcja == nil)
        let test = await monitor.refresh(environment: .test)
        #expect(test?.environment == .test)

        wiszacy.zwolnij()
        let dokonczone = await wTrakcie.value
        #expect(dokonczone?.environment == .test)
        #expect(!monitor.isRefreshing)
    }
}
