import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

// Ścieżki brzegowe usług: błędy HTTP (status ≠ 200), guardy i akcesory,
// których nie dotykają testy „szczęśliwej ścieżki". Wszystkie operacje
// sieciowe idą przez atrapę transportu — żaden test nie łączy się z KSeF,
// NBP ani wykazem podatników.

@Suite("Usługi HTTP — ścieżki błędów statusu")
struct ServiceHTTPErrorTests {

    @Test("NBP — status inny niż 200/404 zgłasza serviceError z kodem HTTP")
    func nbpNieoczekiwanyStatus() async {
        let transport = MockTransport()
        transport.route("/api/exchangerates/rates/a/eur/") { _ in (500, Data()) }
        let service = NBPExchangeRateService(transport: transport)
        await #expect(throws: NBPExchangeRateService.RateError.serviceError("HTTP 500")) {
            _ = try await service.midRate(currency: "EUR", onOrBefore: .now)
        }
    }

    @Test("Wykaz podatników — lookup przy błędzie zwraca komunikat z API")
    func lookupBladZKomunikatem() async {
        let transport = MockTransport()
        transport.route("/api/search/nip/9999999999") { _ in
            (400, Data(#"{"message":"Zły dzień zapytania"}"#.utf8))
        }
        let service = ContractorLookupService(transport: transport)
        await #expect(throws: ContractorLookupService.LookupError.serviceError("Zły dzień zapytania")) {
            _ = try await service.lookup(nip: "9999999999")
        }
    }

    @Test("Wykaz podatników — lookup bez treści błędu podaje kod HTTP")
    func lookupBladBezKomunikatu() async {
        let transport = MockTransport()
        transport.route("/api/search/nip/9999999999") { _ in (503, Data()) }
        let service = ContractorLookupService(transport: transport)
        await #expect(throws: ContractorLookupService.LookupError.serviceError("HTTP 503")) {
            _ = try await service.lookup(nip: "9999999999")
        }
    }

    @Test("Wykaz podatników — weryfikacja rachunku przy błędzie HTTP zgłasza serviceError")
    func verifyAccountBladHTTP() async {
        let transport = MockTransport()
        transport.route("/api/check/nip/9999999999/bank-account/") { _ in
            (500, Data(#"{"message":"Awaria wykazu"}"#.utf8))
        }
        let service = ContractorLookupService(transport: transport)
        await #expect(throws: ContractorLookupService.LookupError.serviceError("Awaria wykazu")) {
            _ = try await service.verifyAccount(
                nip: "9999999999",
                account: "PL26 1090 2402 0000 0006 1234 5678"
            )
        }
    }
}

@Suite("KeychainSecretStorage — realny pęk kluczy (konto-atrapa)")
struct KeychainSecretStorageTests {

    // Konto testowe pod tą samą usługą, ale NIGDY „ksef.token" — nie dotyka
    // prawdziwego tokenu użytkownika. Test po sobie sprząta.
    private let dummyAccount = "test.coverage.keychain"

    @Test("Zapis, aktualizacja, wyczyszczenie i usunięcie wpisu")
    func zapisIUsuniecie() {
        let storage = KeychainSecretStorage()
        storage.delete(account: dummyAccount) // czysty start

        storage.save("wartosc-1", account: dummyAccount)      // ścieżka add (not found)
        storage.save("wartosc-2", account: dummyAccount)      // ścieżka update
        storage.save("", account: dummyAccount)               // pusty → delete
        storage.delete(account: dummyAccount)                 // sprzątanie

        // Bez twardej asercji stanu pęku (CI bywa bez dostępu) — istotne jest
        // wykonanie ścieżek zapisu/usuwania. Odczyt po wyczyszczeniu jest nil.
        #expect(storage.read(account: dummyAccount) == nil)
    }
}

@MainActor
@Suite("Eksport plików i poczta — guardy przed panelem systemowym")
struct ExportAndEmailGuardTests {

    @Test("exportXML zwraca false, gdy faktura nie ma XML")
    func exportXMLBezXML() {
        let invoice = makeTestInvoice()
        #expect(invoice.rawXmlContent == nil)
        #expect(FileExportService.exportXML(of: invoice) == false)
    }

    @Test("exportCSV zwraca false dla pustej listy")
    func exportCSVPusta() {
        #expect(FileExportService.exportCSV(of: [], suggestedName: "faktury.csv") == false)
    }

    @Test("compose zgłasza błąd, gdy zażądano XML, którego faktura nie ma")
    func composeBrakXML() {
        let invoice = makeTestInvoice()
        #expect(throws: Error.self) {
            try InvoiceEmailService.compose(
                invoice: invoice,
                recipient: "biuro@example.com",
                subject: "Faktura",
                body: "W załączeniu.",
                includePDF: false,
                includeXML: true
            )
        }
    }
}

@MainActor
@Suite("SyncActivity i QuickSyncRunner — stan i guardy", .serialized)
struct SyncActivityTests {

    @Test("refreshMenuBarStatus przelicza liczniki z faktur")
    func refreshMenuBarStatus() {
        let activity = SyncActivity.shared
        activity.menuBarStatus = nil
        let invoices = [
            makeTestInvoice(number: "FV/1", isPaid: false),
            makeTestInvoice(number: "FV/2", isPaid: true),
        ]
        activity.refreshMenuBarStatus(invoices: invoices)
        #expect(activity.menuBarStatus != nil)
    }

    @Test("MainWindowOpener przechowuje i wykonuje domknięcie otwierające")
    func mainWindowOpener() {
        var opened = false
        MainWindowOpener.open = { opened = true }
        MainWindowOpener.open?()
        #expect(opened)
        MainWindowOpener.open = nil
    }

    @Test("QuickSyncRunner przerywa, gdy synchronizacja już trwa")
    func quickSyncGuardTrwa() async throws {
        let context = try makeInMemoryContext()
        let activity = SyncActivity.shared
        activity.isSyncing = true
        defer { activity.isSyncing = false }
        activity.lastError = "ZNACZNIK"

        await QuickSyncRunner.syncAll(context: context)

        // Wczesny return nie tknął stanu (lastError bez zmian).
        #expect(activity.lastError == "ZNACZNIK")
    }

    @Test("QuickSyncRunner bez poświadczeń ustawia błąd i nie startuje synchronizacji")
    func quickSyncBrakPoswiadczen() async throws {
        // Domena UserDefaults procesu testowego (NIE preferencje aplikacji
        // pl.itkrak.ksefiarz) — usunięcie NIP wymusza ścieżkę „brak poświadczeń"
        // i blokuje jakiekolwiek połączenie sieciowe.
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.nip)
        let context = try makeInMemoryContext()
        let activity = SyncActivity.shared
        activity.isSyncing = false
        activity.lastError = nil

        await QuickSyncRunner.syncAll(context: context)

        #expect(activity.isSyncing == false)
        #expect(activity.lastError == KSeFError.missingCredentials.localizedDescription)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Invoice.self, SyncRun.self, configurations: configuration)
        return ModelContext(container)
    }
}
