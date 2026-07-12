import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

// Testy domykające drobne luki pokrycia w logice domenowej (pojedyncze
// linie i gałęzie): pełny przebieg `sync`, gałąź „starszy przebieg”
// w `latestRuns`, brak referencji wysyłki, etykiety enumów (`displayName`,
// `id`), operator porównania oraz przeliczenie walutowe brutto.

// MARK: - Atrapy pomocnicze

/// Minimalna atrapa kontraktu statusu wysyłki — w teście luki `refresh`
/// rzuca jeszcze przed sięgnięciem po usługę, więc metody nie są wołane.
private final class NieużywanaUsługaStatusu_lgap: KSeFSubmissionStatusProviding {
    func fetchInvoiceStatus(
        sessionReference: String,
        invoiceReference: String
    ) async throws -> KSeFInvoiceProcessingResult {
        KSeFInvoiceProcessingResult(status: .processing, statusCode: nil, description: "")
    }

    func downloadUPO(sessionReference: String, ksefNumber: String) async throws -> Data {
        Data()
    }
}

/// Rejestruje komplet tras potrzebnych do pomyślnego uwierzytelnienia
/// (odpowiednik prywatnego `routeSuccessfulAuth` z `KSeFServiceTests`).
private func routujUwierzytelnienie_lgap(on transport: MockTransport) {
    transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
    transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
    transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
    transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
    transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
}

// MARK: - InvoiceSyncEngine.sync (linie 29, 30, 37, 38)

@Suite("Luki pokrycia — pełny przebieg InvoiceSyncEngine.sync")
@MainActor
struct SyncEngineGapsTests_lgap {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, SyncRun.self, configurations: configuration
        )
        return ModelContext(container)
    }

    @Test("sync buduje zbiór faktur z kompletem danych i scala pusty wynik z KSeF")
    func pełnyPrzebiegSync() async throws {
        let context = try makeContext()

        // Faktura z kompletem danych (rawXML + numer KSeF) — trafia do
        // zbioru `complete` (gałąź `: invoice.ksefId` z linii 30).
        let kompletna = Invoice(
            ksefId: "KSEF-KOMPLET", invoiceNumber: "F/1/2026", issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            rawXmlContent: "<Faktura/>", kind: .purchase
        )
        context.insert(kompletna)
        // Faktura bez XML — gałąź `nil` z linii 30 (nie trafia do `complete`).
        let bezXML = Invoice(
            ksefId: "KSEF-BEZ-XML", invoiceNumber: "F/2/2026", issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 1, vatAmount: 0, grossAmount: 1, kind: .purchase
        )
        context.insert(bezXML)
        try context.save()

        let transport = MockTransport()
        routujUwierzytelnienie_lgap(on: transport)
        transport.routeOK(
            "invoices/query/metadata",
            data: Data(#"{"hasMore":false,"invoices":[]}"#.utf8)
        )
        let keys = TestRSAKeyPair()
        let service = KSeFService(
            environment: .test,
            nip: "1111111111",
            authToken: "tok-abc",
            transport: transport,
            publicKeyResolver: { _ in keys.publicKey }
        )
        service.pollInterval = 0

        let wstawione = try await InvoiceSyncEngine.sync(
            kind: .purchase,
            service: service,
            from: .distantPast,
            to: .now,
            prepaidForms: [],
            context: context,
            trigger: .manual,
            environmentRaw: KSeFEnvironment.test.rawValue
        )

        // Pusta lista z KSeF — nic nie doszło, ale przebieg trafił do historii.
        #expect(wstawione == 0)
        let runs = try context.fetch(FetchDescriptor<SyncRun>())
        #expect(runs.count == 1)
        #expect(runs.first?.operation == .purchases)
        #expect(runs.first?.succeeded == true)
    }
}

// MARK: - SyncCenter.latestRuns (linia 74)

@Suite("Luki pokrycia — SyncCenter.latestRuns pomija starszy przebieg")
@MainActor
struct SyncCenterGapsTests_lgap {

    @Test("Starszy przebieg po nowszym nie nadpisuje stanu operacji")
    func starszyPoNowszym() {
        // Kolejność w tablicy: najpierw NOWSZY, potem STARSZY tej samej
        // operacji — druga iteracja wchodzi w gałąź `continue` (linia 74/75).
        let nowszy = SyncRun(
            operation: .sales, trigger: .automatic, environmentRaw: "production",
            startedAt: Date(timeIntervalSince1970: 500)
        )
        let starszy = SyncRun(
            operation: .sales, trigger: .manual, environmentRaw: "production",
            startedAt: Date(timeIntervalSince1970: 100)
        )

        let latest = SyncCenter.latestRuns(
            in: [nowszy, starszy], environmentRaw: "production"
        )
        #expect(latest[.sales] === nowszy)
    }
}

// MARK: - InvoiceSubmissionStatusEngine.refresh (linia 39)

@Suite("Luki pokrycia — refresh bez referencji przesyłki rzuca błąd")
@MainActor
struct SubmissionStatusGapsTests_lgap {

    @Test("Faktura z sesją, lecz bez referencji dokumentu, przerywa odświeżanie")
    func brakReferencjiDokumentu() async {
        // Sesja obecna → druga część `guard let` (linia 39) jest wykonywana,
        // a brak `ksefInvoiceReference` wprowadza w gałąź `else` (rzut błędu).
        let invoice = makeTestInvoice(kind: .sales)
        invoice.ksefSessionReference = "SESS-1"
        invoice.ksefInvoiceReference = nil

        let service = NieużywanaUsługaStatusu_lgap()
        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)
        }
    }
}

// MARK: - Etykiety enumów i operatory (luki jednoliniowe)

@Suite("Luki pokrycia — etykiety enumów, id oraz operator porównania")
@MainActor
struct EnumGapsTests_lgap {

    @Test("PaymentMatcher.Confidence — displayName, operator < oraz id propozycji")
    func dopasowaniePłatności() {
        typealias Confidence = PaymentMatchProposal.Confidence

        // displayName wszystkich wariantów (linie 18–22).
        #expect(Confidence.invoiceNumber.displayName == "numer faktury w tytule")
        #expect(Confidence.uniqueAmount.displayName == "zgodna kwota salda")
        #expect(Confidence.none.displayName == "brak dopasowania")

        // Operator < z Comparable (linia 14).
        #expect(Confidence.none < Confidence.uniqueAmount)
        #expect(Confidence.uniqueAmount < Confidence.invoiceNumber)
        #expect(!(Confidence.invoiceNumber < Confidence.none))

        // Konstrukcja propozycji uruchamia domyślny inicjalizator `id` (linia 27).
        let sprzedaz = makeTestInvoice(number: "FV/2026/06/001", kind: .sales, gross: 123)
        let operacja = BankTransaction(
            date: .now, amount: 123, title: "Przelew FV/2026/06/001", counterparty: "Klient"
        )
        // Dwie propozycje uruchamiają domyślny inicjalizator `id` i mają
        // różne, unikalne identyfikatory (linia 27).
        let propozycje = PaymentMatcher.proposals(
            transactions: [operacja, operacja], invoices: [sprzedaz]
        )
        #expect(propozycje.count == 2)
        #expect(propozycje[0].confidence == .invoiceNumber)
        #expect(propozycje[0].id != propozycje[1].id)
    }

    @Test("PaymentDemandKind — identyfikatory wariantów")
    func rodzajWezwania() {
        #expect(PaymentDemandKind.demand.id == "wezwanie")
        #expect(PaymentDemandKind.interestNote.id == "nota")
    }

    @Test("InvoiceEmailComposer.Language — id oraz displayName")
    func jezykWiadomosci() {
        #expect(InvoiceEmailComposer.Language.polish.id == "polish")
        #expect(InvoiceEmailComposer.Language.english.id == "english")
        #expect(InvoiceEmailComposer.Language.polish.displayName == "Polski")
        #expect(InvoiceEmailComposer.Language.english.displayName == "Angielski")
    }

    @Test("ReportsEngine.CategoryCost — id równa się nazwie kategorii")
    func kategoriaKosztuId() {
        let zakup = makeTestInvoice(kind: .purchase, gross: 123)
        zakup.costCategory = "Sprzęt IT"
        let koszty = ReportsEngine.costsByCategory(in: [zakup])
        #expect(koszty.first?.id == "Sprzęt IT")
        #expect(koszty.first?.id == koszty.first?.category)
    }
}

// MARK: - Przeliczenie walutowe (DashboardMetrics linia 28, DashboardAnalytics inPLN)

@Suite("Luki pokrycia — brutto faktur walutowych przeliczane po kursie")
@MainActor
struct CurrencyGapsTests_lgap {

    private let now = FA2Format.dateFormatter.date(from: "2026-06-11")!

    private func makeCurrencyInvoice() -> Invoice {
        Invoice(
            invoiceNumber: "FV/EUR/1", issueDate: now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            currency: "EUR", exchangeRate: 4.5, kind: .sales
        )
    }

    @Test("DashboardMetrics przelicza brutto faktury walutowej po kursie")
    func metrykiWalutowe() {
        let inv = makeCurrencyInvoice()
        let metrics = DashboardMetrics(invoices: [inv], now: now)
        // 123 EUR × 4,5 = 553,5 PLN (gałąź `grossAmount * exchangeRate`).
        #expect(abs(metrics.salesAwaitingGross - 553.5) < 0.001)
    }

    @Test("DashboardAnalytics przelicza VAT należny faktury walutowej po kursie")
    func analitykaWalutowa() {
        let inv = makeCurrencyInvoice()
        let analytics = DashboardAnalytics(
            invoices: [inv], periodInvoices: [inv], now: now, months: 3
        )
        // 23 EUR × 4,5 = 103,5 PLN VAT należnego.
        #expect(abs(analytics.vatDue - 103.5) < 0.001)
        #expect(analytics.cashFlow.count == 3)
    }
}

// MARK: - MT940Parser (przypadki brzegowe parsera)

@Suite("Luki pokrycia — MT940Parser: storno, opis wielolinijkowy, dekodowanie")
struct MT940GapsTests_lgap {

    @Test("Storno odwraca stronę operacji, a opis bez ~ trafia w całości do tytułu")
    func stornoIOpisProsty() {
        // RC = storno uznania → wypływ (kwota ujemna); opis bez podpól „~”.
        let parsed = MT940Parser.parseStatementLine("260708RC50,00")
        #expect((parsed?.1 ?? 0) < 0)
        #expect(abs((parsed?.1 ?? 0) + 50.0) < 0.001)
    }

    @Test("Pełny wyciąg: :61: + wielolinijkowe :86: z podpolami kontrahenta")
    func wyciagZKontrahentem() {
        let text = """
        :20:WYCIAG
        :61:2607080708C1234,56NTRFREF
        :86:020~00Przelew~20Faktura FV/1
        ~21/2026~32Jan Kowalski
        -
        """
        let transactions = MT940Parser.parse(text)
        #expect(transactions.count == 1)
        #expect(transactions.first?.amount == 1234.56)
        #expect(transactions.first?.title.contains("Faktura FV/1") == true)
        #expect(transactions.first?.counterparty == "Jan Kowalski")
    }

    @Test("Dekodowanie wyciągu zapisanego w Windows-1250 zachowuje polskie znaki")
    func dekodowanieCP1250() {
        // „Opłata” w Windows-1250 (0xB3 = ł); bajt 0xB3 psuje UTF-8, więc
        // dekodowanie wpada w drugie kodowanie z listy (CP1250).
        let data = Data([0x4F, 0x70, 0xB3, 0x61, 0x74, 0x61])
        let decoded = MT940Parser.decode(data)
        #expect(decoded == "Opłata")
    }
}
