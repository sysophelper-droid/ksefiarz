import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

/// Poprawny, walidowalny dokument lokalny (sprzedaż VAT).
@MainActor
private func makeLocalSalesInvoice(
    number: String = "FV/2026/07/001",
    isSelfInvoicing: Bool = false,
    kind: Invoice.Kind = .sales
) -> Invoice {
    Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
        sellerName: "ACME Sp. z o.o.",
        sellerNIP: "5260250274",
        sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
        buyerName: "Kontrahent S.A.",
        buyerNIP: "1111111111",
        buyerAddress: "ul. Testowa 2, 30-001 Kraków",
        netAmount: 100,
        vatAmount: 23,
        grossAmount: 123,
        isSelfInvoicing: isSelfInvoicing,
        kind: kind
    )
}

/// Lokalna faktura VAT RR (dokument zakupowy wystawiany przez nas jako
/// nabywcę) — struktura FA_RR(1), osobny formCode sesji.
@MainActor
private func makeLocalRRInvoice(number: String = "RR/2026/07/001") -> Invoice {
    Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
        sellerName: "Rolnik Ryczałtowy",
        sellerNIP: "1111111111",
        sellerAddress: "Wieś 1, 00-002 Pole",
        buyerName: "ACME Sp. z o.o.",
        buyerNIP: "5260250274",
        buyerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
        netAmount: 100,
        vatAmount: 7,
        grossAmount: 107,
        documentType: "VAT_RR",
        kind: .purchase
    )
}

/// Skrót dokumentu tak, jak liczy go korelacja wyników (SHA-256 zapisanego XML).
@MainActor
private func storedHash(of invoice: Invoice) -> String {
    KSeFCrypto.sha256Base64(Data((invoice.rawXmlContent ?? "").utf8))
}

private func acceptedOutcome(
    hash: String,
    ksefNumber: String = "5260250274-20260701-ABCDEF-ABCDEF-AB",
    reference: String = "20260701-EE-AAA-BBB-01"
) -> KSeFBatchInvoiceOutcome {
    KSeFBatchInvoiceOutcome(
        referenceNumber: reference,
        invoiceNumber: nil,
        invoiceHash: hash,
        invoiceFileName: nil,
        result: KSeFInvoiceProcessingResult(
            status: .accepted,
            statusCode: 200,
            description: "Sukces",
            ksefNumber: ksefNumber,
            acquisitionDate: Date(timeIntervalSince1970: 1_790_000_000)
        )
    )
}

private func rejectedOutcome(hash: String) -> KSeFBatchInvoiceOutcome {
    KSeFBatchInvoiceOutcome(
        referenceNumber: "20260701-EE-AAA-BBB-02",
        invoiceNumber: nil,
        invoiceHash: hash,
        invoiceFileName: nil,
        result: KSeFInvoiceProcessingResult(
            status: .rejected,
            statusCode: 440,
            description: "Duplikat faktury"
        )
    )
}

private let processedStatus = KSeFBatchSessionStatus(
    code: 200, description: "Sesja wsadowa przetworzona pomyślnie",
    invoiceCount: nil, successfulInvoiceCount: nil, failedInvoiceCount: nil
)
private let inProgressStatus = KSeFBatchSessionStatus(
    code: 150, description: "Trwa przetwarzanie",
    invoiceCount: nil, successfulInvoiceCount: nil, failedInvoiceCount: nil
)
private let failedStatus = KSeFBatchSessionStatus(
    code: 435, description: "Błąd odszyfrowania zaszyfrowanych części archiwum",
    invoiceCount: nil, successfulInvoiceCount: nil, failedInvoiceCount: nil
)

// MARK: - Paczka ZIP

@Suite("Paczka wsadowa — ZIP i podział na części")
struct KSeFBatchPackageTests {

    private let files = [
        KSeFBatchFile(fileName: "faktura_00001.xml", content: Data("<Faktura>1</Faktura>".utf8)),
        KSeFBatchFile(fileName: "faktura_00002.xml", content: Data("<Faktura>2</Faktura>".utf8)),
    ]

    @Test("Mała paczka: jedna część, skrót liczony z surowego ZIP")
    func malaPaczka() throws {
        let package = try KSeFBatchPackage.build(files: files)
        #expect(package.parts.count == 1)
        #expect(package.parts.first == package.zipData)
        #expect(package.zipHashBase64 == KSeFCrypto.sha256Base64(package.zipData))
        // Archiwum zawiera nagłówki lokalne obu plików.
        #expect(package.zipData.count > files.reduce(0) { $0 + $1.content.count })
    }

    @Test("Pusta lista plików jest odrzucana")
    func pustaLista() {
        #expect(throws: KSeFError.self) {
            try KSeFBatchPackage.build(files: [])
        }
    }

    @Test("Przekroczenie liczby części zatrzymuje budowę paczki")
    func limitCzesci() {
        // Wymuszenie wielu części małym limitem rozmiaru.
        #expect(throws: KSeFError.self) {
            try KSeFBatchPackage.build(files: files, maxPartSize: 16, maxPartCount: 2)
        }
    }

    @Test("Podział binarny: dane mniejsze niż limit pozostają jedną częścią")
    func podzialJednaCzesc() {
        let data = Data((0..<100).map { UInt8($0) })
        #expect(KSeFBatchPackage.splitParts(data, maxPartSize: 100) == [data])
        #expect(KSeFBatchPackage.splitParts(Data(), maxPartSize: 100).isEmpty)
    }

    @Test("Podział binarny: części są wyrównane, mieszczą się w limicie i składają w oryginał")
    func podzialWieleCzesci() {
        // 250 bajtów przy limicie 100 → 3 części po ⌈250/3⌉ = 84, 84, 82.
        let data = Data((0..<250).map { UInt8($0 % 251) })
        let parts = KSeFBatchPackage.splitParts(data, maxPartSize: 100)
        #expect(parts.count == 3)
        #expect(parts.map(\.count) == [84, 84, 82])
        #expect(parts.allSatisfy { $0.count <= 100 })
        #expect(parts.reduce(Data(), +) == data)
    }

    @Test("Podział binarny: wielokrotność limitu daje równe części")
    func podzialRownyLimit() {
        let data = Data(repeating: 0xAB, count: 200)
        let parts = KSeFBatchPackage.splitParts(data, maxPartSize: 100)
        #expect(parts.map(\.count) == [100, 100])
        #expect(parts.reduce(Data(), +) == data)
    }
}

// MARK: - Silnik wysyłki wsadowej

/// Atrapa stanu sesji wsadowej do testów domykania.
private final class MockBatchStatusService: KSeFBatchStatusProviding {
    var statusBySession: [String: KSeFBatchSessionStatus] = [:]
    var outcomesBySession: [String: [KSeFBatchInvoiceOutcome]] = [:]
    var statusError: Error?
    var invoicesError: Error?
    private(set) var statusCalls: [String] = []

    func fetchBatchSessionStatus(
        referenceNumber: String
    ) async throws -> KSeFBatchSessionStatus {
        statusCalls.append(referenceNumber)
        if let statusError { throw statusError }
        guard let status = statusBySession[referenceNumber] else {
            throw KSeFError.invalidResponse
        }
        return status
    }

    func fetchBatchSessionInvoices(
        referenceNumber: String
    ) async throws -> [KSeFBatchInvoiceOutcome] {
        if let invoicesError { throw invoicesError }
        return outcomesBySession[referenceNumber] ?? []
    }
}

@Suite("Silnik wysyłki wsadowej — plan, wyniki i domykanie")
@MainActor
struct BatchSendEngineTests {

    // MARK: Kwalifikacja i plan

    @Test("Kwalifikują się wyłącznie lokalne dokumenty z cyklem wysyłki KSeF")
    func kwalifikacja() throws {
        let local = makeLocalSalesInvoice()
        let rr = makeLocalRRInvoice()

        let sent = makeLocalSalesInvoice(number: "FV/2")
        sent.ksefId = "5260250274-20260701-AAAAAA-AAAAAA-AA"
        let hidden = makeLocalSalesInvoice(number: "FV/3")
        hidden.isArchivedOrHidden = true
        let offline = makeLocalSalesInvoice(number: "FV/4")
        offline.ksefSubmissionStatus = .offlinePending
        // Sprzedaż z P_17 wystawił klient w naszym imieniu — nie wysyłamy jej.
        let selfInvoicedSales = makeLocalSalesInvoice(number: "FV/5", isSelfInvoicing: true)
        // Zwykły zakup pobrany z KSeF/ręczny nie ma cyklu wysyłki.
        let purchase = makeLocalSalesInvoice(number: "FV/6", kind: .purchase)

        let eligible = BatchSendEngine.eligible(
            in: [local, rr, sent, hidden, offline, selfInvoicedSales, purchase]
        )
        #expect(eligible.map(\.invoiceNumber) == [local.invoiceNumber, rr.invoiceNumber])
    }

    @Test("Plan grupuje dokumenty per schema i wyklucza błędy walidacji")
    func planGrupyIWykluczenia() throws {
        let vat = makeLocalSalesInvoice()
        let rr = makeLocalRRInvoice()
        let invalid = makeLocalSalesInvoice(number: "FV/BAD")
        invalid.buyerNIP = "1234567890" // błędna suma kontrolna

        let plan = BatchSendEngine.plan(for: [vat, rr, invalid])

        #expect(plan.groups.count == 2)
        #expect(plan.groups.first?.schema == .fa3)
        #expect(plan.groups.last?.schema == .faRR)
        #expect(plan.groups.allSatisfy { $0.candidates.count == 1 })

        // Nazwy plików numerowane w obrębie grupy, XML i skrót spójne.
        let candidate = try #require(plan.groups.first?.candidates.first)
        #expect(candidate.file.fileName == "faktura_00001.xml")
        #expect(candidate.hashBase64 == KSeFCrypto.sha256Base64(candidate.file.content))
        let xml = String(decoding: candidate.file.content, as: UTF8.self)
        #expect(xml.contains("FV/2026/07/001"))

        #expect(plan.excluded.count == 1)
        #expect(plan.excluded.first?.invoice.invoiceNumber == "FV/BAD")
        #expect(plan.excluded.first?.reason.contains("NIP nabywcy") == true)
    }

    // MARK: Oznaczenie wysłania i naniesienie wyników

    @Test("Oznaczenie wysłania: stan „w toku” z sesją, bez referencji faktury")
    func oznaczenieWyslania() throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(
            plan.candidates, sessionReference: "SB-1", environmentRaw: "test"
        )

        #expect(invoice.ksefSubmissionStatus == .processing)
        #expect(invoice.ksefSessionReference == "SB-1")
        #expect(invoice.ksefInvoiceReference == nil)
        #expect(invoice.ksefEnvironmentRaw == "test")
        #expect(invoice.isLocalOnly == false)
        // Zapisany XML to dokładnie zawartość pliku z paczki.
        #expect(Data((invoice.rawXmlContent ?? "").utf8) == plan.candidates.first?.file.content)
    }

    @Test("Wynik przyjęcia nadaje numer KSeF, referencję i datę przyjęcia")
    func wynikPrzyjecia() throws {
        let invoice = makeLocalSalesInvoice()
        invoice.isPaid = true // niezmiennik: wysyłka nie dotyka statusu opłacenia
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let summary = BatchSendEngine.apply(
            outcomes: [acceptedOutcome(hash: storedHash(of: invoice))],
            sessionStatus: processedStatus,
            to: [invoice]
        )

        #expect(summary == {
            var expected = BatchSendEngine.ApplySummary()
            expected.accepted = 1
            return expected
        }())
        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefId == "5260250274-20260701-ABCDEF-ABCDEF-AB")
        #expect(invoice.ksefInvoiceReference == "20260701-EE-AAA-BBB-01")
        #expect(invoice.ksefAcceptedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(invoice.isPaid == true)
    }

    @Test("Wynik odrzucenia zapisuje kod i opis błędu")
    func wynikOdrzucenia() throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let summary = BatchSendEngine.apply(
            outcomes: [rejectedOutcome(hash: storedHash(of: invoice))],
            sessionStatus: processedStatus,
            to: [invoice]
        )

        #expect(summary.rejected == 1)
        #expect(invoice.ksefSubmissionStatus == .rejected)
        #expect(invoice.ksefStatusCode == 440)
        #expect(invoice.ksefStatusDescription == "Duplikat faktury")
        #expect(invoice.ksefId == nil)
    }

    @Test("Brak wyniku w sesji zakończonej błędem paczki przywraca stan lokalny")
    func bladPaczkiPrzywracaLokalny() throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let summary = BatchSendEngine.apply(
            outcomes: [],
            sessionStatus: failedStatus,
            to: [invoice]
        )

        #expect(summary.reverted == 1)
        #expect(invoice.ksefSubmissionStatus == .local)
        #expect(invoice.isLocalOnly == true)
        #expect(invoice.ksefSessionReference == nil)
        #expect(invoice.ksefStatusDescription?.contains("odszyfrowania") == true)
    }

    @Test("Sesja przetworzona z pustą listą wyników NIE cofa dokumentów")
    func pustaListaNieCofa() throws {
        // Pobranie listy mogło się nie udać — cofnięcie dokumentu, który
        // KSeF przyjął, groziłoby duplikatem przy ponownej wysyłce.
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let summary = BatchSendEngine.apply(
            outcomes: [],
            sessionStatus: processedStatus,
            to: [invoice]
        )

        #expect(summary.processing == 1)
        #expect(invoice.ksefSubmissionStatus == .processing)
        #expect(invoice.ksefSessionReference == "SB-1")
    }

    @Test("Sesja przetworzona: dokument spoza listy wyników wraca do lokalnego")
    func dokumentSpozaListy() throws {
        let matched = makeLocalSalesInvoice()
        let missing = makeLocalSalesInvoice(number: "FV/2026/07/002")
        let plan = BatchSendEngine.plan(for: [matched, missing])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        // Liczniki potwierdzają, że pełna lista sesji zawiera jeden wynik.
        let completeStatus = KSeFBatchSessionStatus(
            code: 200, description: "Sesja wsadowa przetworzona pomyślnie",
            invoiceCount: 1, successfulInvoiceCount: 1, failedInvoiceCount: 0
        )
        let summary = BatchSendEngine.apply(
            outcomes: [acceptedOutcome(hash: storedHash(of: matched))],
            sessionStatus: completeStatus,
            to: [matched, missing]
        )

        #expect(summary.accepted == 1)
        #expect(summary.reverted == 1)
        #expect(matched.ksefSubmissionStatus == .accepted)
        #expect(missing.ksefSubmissionStatus == .local)
    }

    @Test("Sesja przetworzona: częściowa lista wyników NIE cofa brakujących dokumentów")
    func czesciowaListaNieCofa() throws {
        let matched = makeLocalSalesInvoice()
        let missing = makeLocalSalesInvoice(number: "FV/2026/07/002")
        let plan = BatchSendEngine.plan(for: [matched, missing])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        // Status zapowiada dwa wyniki, ale pobrano tylko jeden. Dopóki kolejna
        // próba nie pobierze kompletnej listy, brakująca faktura musi pozostać
        // nieedytowalna — mogła już zostać przyjęta przez KSeF.
        let incompleteStatus = KSeFBatchSessionStatus(
            code: 200, description: "Sesja wsadowa przetworzona pomyślnie",
            invoiceCount: 2, successfulInvoiceCount: 2, failedInvoiceCount: 0
        )
        let summary = BatchSendEngine.apply(
            outcomes: [acceptedOutcome(hash: storedHash(of: matched))],
            sessionStatus: incompleteStatus,
            to: [matched, missing]
        )

        #expect(summary.accepted == 1)
        #expect(summary.processing == 1)
        #expect(summary.reverted == 0)
        #expect(matched.ksefSubmissionStatus == .accepted)
        #expect(missing.ksefSubmissionStatus == .processing)
        #expect(missing.ksefSessionReference == "SB-1")
    }

    @Test("Sesja w toku zostawia dokumenty „w toku”")
    func sesjaWTokuBezZmian() throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let summary = BatchSendEngine.apply(
            outcomes: [],
            sessionStatus: inProgressStatus,
            to: [invoice]
        )

        #expect(summary.processing == 1)
        #expect(invoice.ksefSubmissionStatus == .processing)
    }

    @Test("Duplikat skrótu: każdy wynik trafia do innego dokumentu")
    func duplikatSkrotu() throws {
        // Dwa identyczne dokumenty (ten sam XML → ten sam skrót).
        let first = makeLocalSalesInvoice()
        let second = makeLocalSalesInvoice()
        let generatedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let plan = BatchSendEngine.plan(for: [first, second], generatedAt: generatedAt)
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")
        let hash = storedHash(of: first)
        #expect(hash == storedHash(of: second))

        let summary = BatchSendEngine.apply(
            outcomes: [
                acceptedOutcome(hash: hash, ksefNumber: "NR-1", reference: "REF-1"),
                acceptedOutcome(hash: hash, ksefNumber: "NR-2", reference: "REF-2"),
            ],
            sessionStatus: processedStatus,
            to: [first, second]
        )

        #expect(summary.accepted == 2)
        #expect(Set([first.ksefId, second.ksefId]) == Set(["NR-1", "NR-2"]))
    }

    // MARK: Domykanie sesji

    @Test("Do domknięcia kwalifikuje się tylko dokument wsadowy bez referencji")
    func filtrDomykania() throws {
        let batchPending = makeLocalSalesInvoice()
        batchPending.ksefSubmissionStatus = .processing
        batchPending.ksefSessionReference = "SB-1"
        batchPending.rawXmlContent = "<Faktura/>"
        batchPending.ksefEnvironmentRaw = "test"

        // Wysyłka interaktywna zawsze ma referencję faktury — poza filtrem.
        let interactive = makeLocalSalesInvoice(number: "FV/INT")
        interactive.ksefSubmissionStatus = .processing
        interactive.ksefSessionReference = "SO-1"
        interactive.ksefInvoiceReference = "REF-1"
        interactive.rawXmlContent = "<Faktura/>"
        interactive.ksefEnvironmentRaw = "test"

        let otherEnvironment = makeLocalSalesInvoice(number: "FV/ENV")
        otherEnvironment.ksefSubmissionStatus = .processing
        otherEnvironment.ksefSessionReference = "SB-2"
        otherEnvironment.rawXmlContent = "<Faktura/>"
        otherEnvironment.ksefEnvironmentRaw = "production"

        let pending = BatchSendEngine.pendingReconciliation(
            in: [batchPending, interactive, otherEnvironment],
            environmentRaw: "test"
        )
        #expect(pending.map(\.invoiceNumber) == [batchPending.invoiceNumber])
    }

    @Test("Domykanie nanosi wyniki zakończonej sesji")
    func domykanieZakonczonejSesji() async throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let service = MockBatchStatusService()
        service.statusBySession["SB-1"] = processedStatus
        service.outcomesBySession["SB-1"] = [acceptedOutcome(hash: storedHash(of: invoice))]

        let summary = await BatchSendEngine.reconcilePending(
            [invoice], environmentRaw: "test", using: service
        )

        #expect(summary.checked == 1)
        #expect(summary.accepted == 1)
        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefInvoiceReference != nil)
    }

    @Test("Domykanie sesji w toku niczego nie zmienia")
    func domykanieSesjiWToku() async throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let service = MockBatchStatusService()
        service.statusBySession["SB-1"] = inProgressStatus

        let summary = await BatchSendEngine.reconcilePending(
            [invoice], environmentRaw: "test", using: service
        )

        #expect(summary == BatchSendEngine.ReconcileSummary())
        #expect(invoice.ksefSubmissionStatus == .processing)
    }

    @Test("Domykanie: błąd paczki przywraca dokumenty mimo błędu listy wyników")
    func domykanieBladPaczki() async throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let service = MockBatchStatusService()
        service.statusBySession["SB-1"] = failedStatus
        service.invoicesError = KSeFError.invalidResponse

        let summary = await BatchSendEngine.reconcilePending(
            [invoice], environmentRaw: "test", using: service
        )

        #expect(summary.checked == 1)
        #expect(invoice.ksefSubmissionStatus == .local)
        #expect(invoice.isLocalOnly == true)
    }

    @Test("Domykanie: sesja przetworzona bez listy wyników pozostaje do ponowienia")
    func domykanieBladListyWynikow() async throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let service = MockBatchStatusService()
        service.statusBySession["SB-1"] = processedStatus
        service.invoicesError = KSeFError.invalidResponse

        let summary = await BatchSendEngine.reconcilePending(
            [invoice], environmentRaw: "test", using: service
        )

        #expect(summary.failures == 1)
        #expect(invoice.ksefSubmissionStatus == .processing)
        #expect(invoice.ksefSessionReference == "SB-1")
    }

    @Test("Domykanie: błąd statusu sesji liczy się jako niepowodzenie bez zmian")
    func domykanieBladStatusu() async throws {
        let invoice = makeLocalSalesInvoice()
        let plan = BatchSendEngine.plan(for: [invoice])
        BatchSendEngine.markSent(plan.candidates, sessionReference: "SB-1", environmentRaw: "test")

        let service = MockBatchStatusService()
        service.statusError = KSeFError.badStatus(code: 500, message: "awaria")

        let summary = await BatchSendEngine.reconcilePending(
            [invoice], environmentRaw: "test", using: service
        )

        #expect(summary.failures == 1)
        #expect(invoice.ksefSubmissionStatus == .processing)
    }
}

// MARK: - Usługa KSeF: pełny przepływ sesji wsadowej na atrapie transportu

/// Lustro żądania otwarcia sesji wsadowej — do weryfikacji wysłanego JSON.
private struct OpenBatchBody: Decodable {
    struct FormCode: Decodable {
        let systemCode: String
        let schemaVersion: String
        let value: String
    }
    struct Part: Decodable {
        let ordinalNumber: Int
        let fileSize: Int
        let fileHash: String
    }
    struct BatchFile: Decodable {
        let fileSize: Int
        let fileHash: String
        let fileParts: [Part]
    }
    struct Encryption: Decodable {
        let encryptedSymmetricKey: String
        let initializationVector: String
    }
    let formCode: FormCode
    let batchFile: BatchFile
    let encryption: Encryption
    let offlineMode: Bool
}

/// Licznik odpytań o status sesji — pierwsza odpowiedź „w toku”, potem sukces.
private final class CallCounter {
    var count = 0
}

@Suite("KSeFService — sesja wsadowa (KSeF 2.0)")
struct KSeFBatchServiceTests {

    private let files = [
        KSeFBatchFile(
            fileName: "faktura_00001.xml",
            content: Data("<Faktura>pierwsza</Faktura>".utf8)
        ),
        KSeFBatchFile(
            fileName: "faktura_00002.xml",
            content: Data("<Faktura>druga</Faktura>".utf8)
        ),
    ]

    private func makeService(
        transport: MockTransport,
        keys: TestRSAKeyPair
    ) -> KSeFService {
        let service = KSeFService(
            environment: .test,
            nip: "1111111111",
            authToken: "tok-abc",
            transport: transport,
            publicKeyResolver: { _ in keys.publicKey }
        )
        service.pollInterval = 0
        return service
    }

    private func routeAuth(_ transport: MockTransport) {
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
    }

    /// Trasa otwarcia sesji: jedna część do wysłania pod adres magazynu.
    /// Uwaga na kolejność tras — „close” zawiera w ścieżce „sessions/batch”,
    /// więc rejestruje się PRZED trasą otwarcia (pierwsza pasująca wygrywa).
    private func routeBatchFlow(
        _ transport: MockTransport,
        statusCounter: CallCounter,
        finalStatusCode: Int = 200
    ) {
        transport.route("sessions/batch/BATCH-REF-1/close") { _ in (204, Data()) }
        transport.route("sessions/BATCH-REF-1/invoices") { request in
            if request.value(forHTTPHeaderField: "x-continuation-token") == "TOK-2" {
                return (200, Data("""
                {"continuationToken":null,"invoices":[
                  {"ordinalNumber":2,"referenceNumber":"REF-2","invoiceHash":"HASH-2",
                   "invoicingDate":"2026-07-01T10:00:00+00:00",
                   "status":{"code":440,"description":"Duplikat faktury",
                             "details":["Faktura została już przesłana"]}},
                  {"ordinalNumber":3,"referenceNumber":"REF-3","invoiceHash":"HASH-3",
                   "invoicingDate":"2026-07-01T10:00:00+00:00",
                   "status":{"code":150,"description":"Trwa przetwarzanie"}}
                ]}
                """.utf8))
            }
            return (200, Data("""
            {"continuationToken":"TOK-2","invoices":[
              {"ordinalNumber":1,"invoiceNumber":"FV/1","ksefNumber":"1111111111-20260701-AAAAAA-AAAAAA-AA",
               "referenceNumber":"REF-1","invoiceHash":"HASH-1","invoiceFileName":"faktura_00001.xml",
               "acquisitionDate":"2026-07-01T10:00:16.0154302+00:00",
               "invoicingDate":"2026-07-01T10:00:00+00:00",
               "status":{"code":200,"description":"Sukces"}}
            ]}
            """.utf8))
        }
        transport.route("sessions/batch") { _ in
            (201, Data("""
            {"referenceNumber":"BATCH-REF-1","partUploadRequests":[
              {"ordinalNumber":1,"method":"PUT",
               "url":"https://storage.example.test/storage-part/1?sig=abc",
               "headers":{"x-ms-blob-type":"BlockBlob"}}
            ]}
            """.utf8))
        }
        transport.route("sessions/BATCH-REF-1") { _ in
            statusCounter.count += 1
            if statusCounter.count == 1 {
                return (200, Data(#"{"status":{"code":150,"description":"Trwa przetwarzanie"},"dateCreated":"2026-07-01T10:00:00+00:00","dateUpdated":"2026-07-01T10:00:01+00:00"}"#.utf8))
            }
            return (200, Data("""
            {"status":{"code":\(finalStatusCode),"description":"Sesja wsadowa zakończona"},
             "dateCreated":"2026-07-01T10:00:00+00:00","dateUpdated":"2026-07-01T10:00:05+00:00",
             "invoiceCount":2,"successfulInvoiceCount":1,"failedInvoiceCount":1}
            """.utf8))
        }
        transport.route("storage-part/1") { _ in (201, Data()) }
    }

    @Test("Pełny przepływ: paczka, szyfrowanie części, upload, statusy i wyniki")
    func pelnyPrzeplyw() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        routeBatchFlow(transport, statusCounter: CallCounter())
        let service = makeService(transport: transport, keys: keys)

        let result = try await service.sendInvoicesBatch(files: files, schema: .fa3)

        #expect(result.sessionReferenceNumber == "BATCH-REF-1")
        #expect(result.sessionStatus.isProcessed)
        #expect(result.sessionStatus.invoiceCount == 2)
        #expect(result.sessionStatus.successfulInvoiceCount == 1)

        // Deklaracja paczki: schema FA(3) i spójne metadane części.
        let openRequest = try #require(transport.request(matching: "sessions/batch"))
        let body = try JSONDecoder().decode(
            OpenBatchBody.self, from: try #require(openRequest.httpBody)
        )
        #expect(body.formCode.systemCode == "FA (3)")
        #expect(body.formCode.schemaVersion == "1-0E")
        #expect(body.formCode.value == "FA")
        #expect(body.offlineMode == false)
        #expect(body.batchFile.fileParts.count == 1)
        #expect(body.batchFile.fileParts.first?.ordinalNumber == 1)

        // Upload części: dokładnie wskazana metoda i nagłówki, BEZ tokenu.
        let upload = try #require(transport.request(matching: "storage-part/1"))
        #expect(upload.httpMethod == "PUT")
        #expect(upload.value(forHTTPHeaderField: "x-ms-blob-type") == "BlockBlob")
        #expect(upload.value(forHTTPHeaderField: "Authorization") == nil)

        // Kryptografia: część odszyfrowana kluczem sesji składa się w surowy
        // ZIP o zadeklarowanym skrócie, zawierający oba dokumenty.
        let encryptedPart = try #require(upload.httpBody)
        #expect(body.batchFile.fileParts.first?.fileHash == KSeFCrypto.sha256Base64(encryptedPart))
        #expect(body.batchFile.fileParts.first?.fileSize == encryptedPart.count)
        let encryptedKey = try #require(
            Data(base64Encoded: body.encryption.encryptedSymmetricKey)
        )
        let aesKey = try #require(keys.decryptOAEPSHA256(encryptedKey))
        let iv = try #require(Data(base64Encoded: body.encryption.initializationVector))
        #expect(aesKey.count == 32)
        #expect(iv.count == 16)
        let zip = try KSeFCrypto.aesDecryptCBC(encryptedPart, key: aesKey, iv: iv)
        #expect(body.batchFile.fileHash == KSeFCrypto.sha256Base64(zip))
        #expect(body.batchFile.fileSize == zip.count)
        for file in files {
            #expect(zip.range(of: file.content) != nil)
            #expect(zip.range(of: Data(file.fileName.utf8)) != nil)
        }

        // Wyniki z dwóch stron (kontynuacja przez nagłówek x-continuation-token).
        #expect(result.invoiceOutcomes.count == 3)
        let accepted = result.invoiceOutcomes[0]
        #expect(accepted.result.status == .accepted)
        #expect(accepted.result.ksefNumber == "1111111111-20260701-AAAAAA-AAAAAA-AA")
        #expect(accepted.invoiceFileName == "faktura_00001.xml")
        #expect(accepted.result.acquisitionDate != nil)
        let rejected = result.invoiceOutcomes[1]
        #expect(rejected.result.status == .rejected)
        #expect(rejected.result.description.contains("Duplikat faktury"))
        #expect(rejected.result.description.contains("została już przesłana"))
        #expect(result.invoiceOutcomes[2].result.status == .processing)

        let pagedRequests = transport.requests.filter {
            ($0.url?.path ?? "").contains("BATCH-REF-1/invoices")
        }
        #expect(pagedRequests.count == 2)
        #expect(pagedRequests.last?.value(forHTTPHeaderField: "x-continuation-token") == "TOK-2")
    }

    @Test("Błąd paczki (kod 435) jest zwracany jako końcowy stan sesji")
    func bladPaczki() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        let counter = CallCounter()
        counter.count = 1 // od razu odpowiedź końcowa
        routeBatchFlow(transport, statusCounter: counter, finalStatusCode: 435)
        // Sesja z błędem paczki zwraca pustą listę faktur.
        let service = makeService(transport: transport, keys: keys)

        let result = try await service.sendInvoicesBatch(files: files, schema: .fa3)

        #expect(result.sessionStatus.isFailed)
        #expect(result.sessionStatus.code == 435)
    }

    @Test("Powtórzony token stronicowania nie zwraca częściowej listy wyników")
    func powtorzonyTokenStronicowania() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        transport.route("sessions/SB-LOOP/invoices") { _ in
            (200, Data("""
            {"continuationToken":"TEN-SAM-TOKEN","invoices":[
              {"referenceNumber":"REF-1","invoiceHash":"HASH-1",
               "invoicingDate":"2026-07-01T10:00:00+00:00",
               "status":{"code":200,"description":"Sukces"}}
            ]}
            """.utf8))
        }
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await service.fetchBatchSessionInvoices(referenceNumber: "SB-LOOP")
        }

        let requests = transport.requests.filter {
            ($0.url?.path ?? "").contains("SB-LOOP/invoices")
        }
        #expect(requests.count == 2)
    }

    @Test("Wynik bez wymaganego skrótu jest odrzucany zamiast pomijany")
    func wynikBezSkrotu() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        transport.route("sessions/SB-BAD/invoices") { _ in
            (200, Data("""
            {"continuationToken":null,"invoices":[
              {"referenceNumber":"REF-1",
               "invoicingDate":"2026-07-01T10:00:00+00:00",
               "status":{"code":200,"description":"Sukces"}}
            ]}
            """.utf8))
        }
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await service.fetchBatchSessionInvoices(referenceNumber: "SB-BAD")
        }
    }

    @Test("Wynik z pustym skrótem jest odrzucany zamiast cofać dokument")
    func wynikZPustymSkrotem() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        transport.route("sessions/SB-EMPTY/invoices") { _ in
            (200, Data("""
            {"continuationToken":null,"invoices":[
              {"referenceNumber":"REF-1","invoiceHash":"",
               "invoicingDate":"2026-07-01T10:00:00+00:00",
               "status":{"code":200,"description":"Sukces"}}
            ]}
            """.utf8))
        }
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await service.fetchBatchSessionInvoices(referenceNumber: "SB-EMPTY")
        }
    }

    @Test("Odmowa magazynu przy uploadzie części przerywa wysyłkę")
    func bladUploadu() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        // Pierwsza pasująca trasa wygrywa — odmowa rejestrowana przed
        // kompletem tras przepływu przesłania trasę poprawnego uploadu.
        transport.route("storage-part/1") { _ in (403, Data("brak uprawnień".utf8)) }
        routeBatchFlow(transport, statusCounter: CallCounter())
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.badStatus(code: 403, message: "brak uprawnień")) {
            try await service.sendInvoicesBatch(files: files, schema: .fa3)
        }
    }

    @Test("Niezgodna liczba instrukcji uploadu z liczbą części jest błędem")
    func niezgodnaLiczbaCzesci() async throws {
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        transport.route("sessions/batch") { _ in
            (201, Data("""
            {"referenceNumber":"BATCH-REF-1","partUploadRequests":[
              {"ordinalNumber":1,"method":"PUT","url":"https://s/1","headers":{}},
              {"ordinalNumber":2,"method":"PUT","url":"https://s/2","headers":{}}
            ]}
            """.utf8))
        }
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.invalidResponse) {
            try await service.sendInvoicesBatch(files: files, schema: .fa3)
        }
    }

    @Test("Błąd sieci po zamknięciu sesji nie wywraca wysyłki wyjątkiem")
    func bladPoZamknieciuSesji() async throws {
        // Po zamknięciu sesji paczka jest już w KSeF — wyjątek zgubiłby numer
        // sesji, dokumenty zostałyby „lokalne” i ponowna wysyłka groziłaby
        // duplikatami. Wysyłka ma zwrócić stan nieterminalny do domknięcia
        // przez synchronizację.
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        // Odpytanie o status pada — rejestrowane przed trasami przepływu.
        transport.route("sessions/BATCH-REF-1/invoices") { _ in (500, Data()) }
        transport.route("sessions/BATCH-REF-1") { _ in (500, Data("awaria".utf8)) }
        routeBatchFlow(transport, statusCounter: CallCounter())
        let service = makeService(transport: transport, keys: keys)
        service.maxPollAttempts = 3
        service.rateLimitRetryDelay = 0

        let result = try await service.sendInvoicesBatch(files: files, schema: .fa3)

        #expect(result.sessionReferenceNumber == "BATCH-REF-1")
        #expect(result.sessionStatus.isTerminal == false)
        #expect(result.invoiceOutcomes.isEmpty)
    }

    @Test("Brak potwierdzenia zamknięcia sesji nie gubi jej numeru")
    func brakPotwierdzeniaZamkniecia() async throws {
        // Odpowiedź błędna/utracona na POST /close nie dowodzi, że KSeF nie
        // rozpoczął przetwarzania. Wynik musi zachować numer sesji, aby silnik
        // oznaczył dokumenty „w toku” zamiast dopuścić ponowną wysyłkę.
        let transport = MockTransport()
        let keys = TestRSAKeyPair()
        routeAuth(transport)
        transport.route("sessions/batch/BATCH-REF-1/close") { _ in
            (500, Data("utracono potwierdzenie".utf8))
        }
        routeBatchFlow(transport, statusCounter: CallCounter())
        let service = makeService(transport: transport, keys: keys)
        service.maxPollAttempts = 1
        service.rateLimitRetryDelay = 0

        let result = try await service.sendInvoicesBatch(files: files, schema: .fa3)

        #expect(result.sessionReferenceNumber == "BATCH-REF-1")
        #expect(result.sessionStatus.code == 150)
        #expect(result.invoiceOutcomes.isEmpty)
    }

    @Test("Pusta paczka jest odrzucana przed komunikacją z API")
    func pustaPaczka() async throws {
        let transport = MockTransport()
        let service = makeService(transport: transport, keys: TestRSAKeyPair())
        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await service.sendInvoicesBatch(files: [], schema: .fa3)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("Znaczniki czasu KSeF: ułamki sekund o dowolnej długości")
    func znacznikiCzasu() {
        // Typowa odpowiedź KSeF ma 7 cyfr ułamka — systemowy parser tego
        // nie akceptuje, więc ułamek jest przycinany do milisekund.
        #expect(KSeFService.parseKSeFTimestamp("2026-07-01T10:00:16.0154302+00:00") != nil)
        #expect(KSeFService.parseKSeFTimestamp("2026-07-01T10:00:16.015+00:00") != nil)
        #expect(KSeFService.parseKSeFTimestamp("2026-07-01T10:00:16+00:00") != nil)
        #expect(KSeFService.parseKSeFTimestamp("2026-07-01T10:00:16.0154302Z") != nil)
        #expect(KSeFService.parseKSeFTimestamp("nie-data") == nil)

        let expected = ISO8601DateFormatter().date(from: "2026-07-01T10:00:16+00:00")!
        let parsed = KSeFService.parseKSeFTimestamp("2026-07-01T10:00:16.0154302+00:00")!
        #expect(abs(parsed.timeIntervalSince(expected)) < 0.1)
    }
}
