import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Kalendarz dni roboczych

@Suite("PolishBusinessCalendar — terminy dosłania offline24")
struct PolishBusinessCalendarTests {

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour)
        components.timeZone = TimeZone(identifier: "Europe/Warsaw")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("Wielkanoc wyliczana algorytmem Meeusa (2026: 5 kwietnia)")
    func easter() {
        let easter2026 = PolishBusinessCalendar.easterSunday(year: 2026)
        #expect(easter2026.month == 4)
        #expect(easter2026.day == 5)
        let easter2027 = PolishBusinessCalendar.easterSunday(year: 2027)
        #expect(easter2027.month == 3)
        #expect(easter2027.day == 28)
    }

    @Test("Święta stałe i ruchome nie są dniami roboczymi")
    func holidays() {
        #expect(!PolishBusinessCalendar.isBusinessDay(date(2026, 11, 11))) // Niepodległości
        #expect(!PolishBusinessCalendar.isBusinessDay(date(2026, 4, 6)))   // Poniedziałek Wielkanocny
        #expect(!PolishBusinessCalendar.isBusinessDay(date(2026, 6, 4)))   // Boże Ciało
        #expect(!PolishBusinessCalendar.isBusinessDay(date(2026, 12, 24))) // Wigilia (wolna od 2025)
        #expect(PolishBusinessCalendar.isBusinessDay(date(2024, 12, 24)))  // Wigilia 2024 — jeszcze robocza
        #expect(PolishBusinessCalendar.isBusinessDay(date(2026, 7, 10)))   // zwykły piątek
        #expect(!PolishBusinessCalendar.isBusinessDay(date(2026, 7, 11)))  // sobota
    }

    @Test("Następny dzień roboczy przeskakuje weekendy i święta")
    func nextBusinessDay() {
        let calendar = PolishBusinessCalendar.calendar

        // Piątek → poniedziałek.
        let afterFriday = PolishBusinessCalendar.nextBusinessDay(after: date(2026, 7, 10))
        #expect(calendar.dateComponents([.month, .day], from: afterFriday) == DateComponents(month: 7, day: 13))

        // Wielka Sobota → wtorek (niedziela + Poniedziałek Wielkanocny wolne).
        let afterEasterSaturday = PolishBusinessCalendar.nextBusinessDay(after: date(2026, 4, 4))
        #expect(calendar.dateComponents([.month, .day], from: afterEasterSaturday) == DateComponents(month: 4, day: 7))

        // 23 XII 2026 (środa) → 28 XII (Wigilia, święta i weekend wolne).
        let afterChristmasEve = PolishBusinessCalendar.nextBusinessDay(after: date(2026, 12, 23))
        #expect(calendar.dateComponents([.month, .day], from: afterChristmasEve) == DateComponents(month: 12, day: 28))
    }

    @Test("Termin dosłania to koniec następnego dnia roboczego (23:59:59)")
    func deadlineEndOfDay() {
        let deadline = PolishBusinessCalendar.endOfNextBusinessDay(after: date(2026, 7, 9))
        let components = PolishBusinessCalendar.calendar.dateComponents(
            [.month, .day, .hour, .minute, .second], from: deadline
        )
        #expect(components == DateComponents(month: 7, day: 10, hour: 23, minute: 59, second: 59))
    }

    @Test("Termin dosłania faktury offline24 wynika z daty wystawienia")
    func invoiceDeadline() {
        let invoice = Invoice(
            invoiceNumber: "FV/1", issueDate: date(2026, 7, 10),
            sellerName: "A", sellerNIP: "1111111111",
            buyerName: "B", buyerNIP: "2222222222",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            ksefSubmissionStatus: .offlinePending,
            kind: .sales
        )
        invoice.isOfflineMode = true
        let deadline = invoice.offlineSendDeadline
        let components = deadline.map {
            PolishBusinessCalendar.calendar.dateComponents([.month, .day, .hour], from: $0)
        }
        #expect(components == DateComponents(month: 7, day: 13, hour: 23))

        // Po dosłaniu termin znika.
        invoice.ksefSubmissionStatus = .accepted
        #expect(invoice.offlineSendDeadline == nil)
    }
}

// MARK: - Kolejka offline

/// Atrapa wysyłki — rejestruje przekazane bajty XML i flagę offline.
private final class MockInvoiceSender: KSeFInvoiceSending {
    var sentXML: [Data] = []
    var sentOfflineFlags: [Bool] = []
    var result: KSeFSendResult?
    var error: Error?

    func sendInvoiceXML(_ xmlData: Data, offlineMode: Bool) async throws -> KSeFSendResult {
        sentXML.append(xmlData)
        sentOfflineFlags.append(offlineMode)
        if let error { throw error }
        return result ?? KSeFSendResult(
            invoiceReferenceNumber: "INV-REF-OFF",
            ksefNumber: "1111111111-20260711-AAAAAAAAAAAA-AA",
            sessionReferenceNumber: "SESS-OFF",
            xml: String(decoding: xmlData, as: UTF8.self),
            processingResult: KSeFInvoiceProcessingResult(
                status: .accepted,
                statusCode: 200,
                description: "Przyjęta",
                ksefNumber: "1111111111-20260711-AAAAAAAAAAAA-AA",
                acquisitionDate: Date(timeIntervalSince1970: 1_790_000_000)
            )
        )
    }
}

private func makeOfflineInvoice(xml: String = "<Faktura>offline</Faktura>", environment: String = "production") -> Invoice {
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
    invoice.offlineHashBase64 = KSeFCrypto.sha256Base64(Data(xml.utf8))
    return invoice
}

@Suite("OfflineQueueEngine — kolejka dosłań offline24")
@MainActor
struct OfflineQueueEngineTests {

    @Test("Kolejka obejmuje tylko dokumenty offline bieżącego środowiska z zapisanym XML")
    func pendingFilter() {
        let matching = makeOfflineInvoice()
        let otherEnvironment = makeOfflineInvoice(environment: "test")
        let noXML = makeOfflineInvoice()
        noXML.rawXmlContent = ""
        let alreadySent = makeOfflineInvoice()
        alreadySent.ksefSubmissionStatus = .accepted

        let pending = OfflineQueueEngine.pending(
            in: [matching, otherEnvironment, noXML, alreadySent],
            environmentRaw: "production"
        )
        #expect(pending.count == 1)
        #expect(pending.first === matching)
    }

    @Test("Dosłanie wysyła ZAPISANY XML bajt w bajt z flagą offline i zapisuje wynik")
    func sendUsesStoredXML() async throws {
        let xml = "<Faktura>dokładnie-te-bajty</Faktura>"
        let invoice = makeOfflineInvoice(xml: xml)
        let sender = MockInvoiceSender()

        let result = try await OfflineQueueEngine.send(invoice, using: sender)

        #expect(sender.sentXML == [Data(xml.utf8)])
        #expect(sender.sentOfflineFlags == [true])
        #expect(result.ksefNumber == "1111111111-20260711-AAAAAAAAAAAA-AA")
        #expect(invoice.ksefSubmissionStatus == .accepted)
        #expect(invoice.ksefId == "1111111111-20260711-AAAAAAAAAAAA-AA")
        #expect(invoice.ksefSessionReference == "SESS-OFF")
        #expect(invoice.ksefInvoiceReference == "INV-REF-OFF")
        #expect(invoice.ksefAcceptedAt != nil)
        // XML nie został podmieniony — skrót z wydruku pozostaje aktualny.
        #expect(invoice.rawXmlContent == xml)
        #expect(invoice.offlineHashBase64 == KSeFCrypto.sha256Base64(Data(xml.utf8)))
    }

    @Test("Dokument spoza kolejki nie jest wysyłany")
    func sendRejectsNonPending() async {
        let invoice = makeOfflineInvoice()
        invoice.ksefSubmissionStatus = .accepted
        let sender = MockInvoiceSender()
        await #expect(throws: KSeFError.invalidResponse) {
            try await OfflineQueueEngine.send(invoice, using: sender)
        }
        #expect(sender.sentXML.isEmpty)
    }

    @Test("Błąd sieci zostawia dokument w kolejce (kolejna próba później)")
    func failureKeepsPending() async {
        let invoice = makeOfflineInvoice()
        let sender = MockInvoiceSender()
        sender.error = URLError(.notConnectedToInternet)

        let summary = await OfflineQueueEngine.sendPending(
            [invoice], environmentRaw: "production", using: sender
        )
        #expect(summary.failures == 1)
        #expect(summary.sent == 0)
        #expect(invoice.ksefSubmissionStatus == .offlinePending)
        #expect(invoice.ksefId == nil)
    }

    @Test("Podsumowanie zlicza wysłane i przyjęte dokumenty")
    func summaryCounts() async {
        let first = makeOfflineInvoice()
        let second = makeOfflineInvoice()
        let sender = MockInvoiceSender()

        let summary = await OfflineQueueEngine.sendPending(
            [first, second], environmentRaw: "production", using: sender
        )
        #expect(summary.sent == 2)
        #expect(summary.accepted == 2)
        #expect(summary.failures == 0)
    }
}

// MARK: - Flaga offlineMode w API

@Suite("KSeFService — wysyłka gotowego XML (offlineMode)")
struct KSeFServiceOfflineSendTests {

    @Test("sendInvoiceXML przekazuje offlineMode=true i nie zmienia bajtów dokumentu")
    func offlineFlagInPayload() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
        transport.routeOK("sessions/online/SESS-1/invoices", data: Data(#"{"referenceNumber":"INV-REF-1"}"#.utf8))
        transport.routeOK("sessions/online/SESS-1/close", data: Data("{}".utf8))
        transport.routeOK(
            "sessions/SESS-1/invoices/INV-REF-1",
            data: Data(#"{"ksefNumber":"1111111111-20260711-AAAAAAAAAAAA-AA","status":{"code":200,"description":"OK"}}"#.utf8)
        )
        transport.routeOK("sessions/online", data: Data(#"{"referenceNumber":"SESS-1"}"#.utf8))

        let service = KSeFService(
            environment: .test,
            nip: "1111111111",
            authToken: "tok",
            transport: transport,
            publicKeyResolver: { _ in keys.publicKey }
        )
        service.pollInterval = 0

        let xmlData = Data("<Faktura>offline-bajty</Faktura>".utf8)
        let result = try await service.sendInvoiceXML(xmlData, offlineMode: true)
        #expect(result.xml == "<Faktura>offline-bajty</Faktura>")

        let sendRequest = try #require(transport.request(matching: "sessions/online/SESS-1/invoices"))
        let body = try JSONSerialization.jsonObject(with: try #require(sendRequest.httpBody)) as? [String: Any]
        #expect(body?["offlineMode"] as? Bool == true)
        #expect(body?["invoiceHash"] as? String == KSeFCrypto.sha256Base64(xmlData))

        // Zaszyfrowana treść odszyfrowuje się dokładnie do przekazanych bajtów.
        let openRequest = try #require(
            transport.requests.first { ($0.url?.path ?? "").hasSuffix("sessions/online") }
        )
        let openBody = try JSONSerialization.jsonObject(with: try #require(openRequest.httpBody)) as? [String: Any]
        let encryption = openBody?["encryption"] as? [String: Any]
        let aesKey = try #require(keys.decryptOAEPSHA256(
            Data(base64Encoded: encryption?["encryptedSymmetricKey"] as? String ?? "")!
        ))
        let iv = try #require(Data(base64Encoded: encryption?["initializationVector"] as? String ?? ""))
        let encrypted = try #require(Data(base64Encoded: body?["encryptedInvoiceContent"] as? String ?? ""))
        #expect(try KSeFCrypto.aesDecryptCBC(encrypted, key: aesKey, iv: iv) == xmlData)
    }
}
