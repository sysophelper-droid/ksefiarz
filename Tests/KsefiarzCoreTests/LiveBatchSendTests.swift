import Foundation
import Testing
@testable import KsefiarzCore

/// Wysyłka wsadowa NA ŻYWO — WYŁĄCZNIE środowisko testowe KSeF.
///
/// Test jest podwójnie zabezpieczony przed produkcją (jak `LiveSendTests`):
/// 1. wymaga jawnej zgody `KSEF_LIVE_SEND=1` oraz `KSEF_LIVE_ENV=test`,
/// 2. `KSeFService` jest tworzony z zaszytym `.test` — nawet błędna zmienna
///    środowiskowa nie skieruje wysyłki na produkcję.
///
/// Uruchomienie (token testowy ze Scripts/get-test-token.py):
/// KSEF_LIVE_SEND=1 KSEF_LIVE_ENV=test KSEF_LIVE_NIP=... KSEF_LIVE_TOKEN=... \
///   swift test --filter LiveBatchSendTests
@Suite("Wysyłka wsadowa na żywo (środowisko testowe)")
struct LiveBatchSendTests {

    static var credentials: (nip: String, token: String)? {
        let env = ProcessInfo.processInfo.environment
        guard env["KSEF_LIVE_SEND"] == "1",
              env["KSEF_LIVE_ENV"] == KSeFEnvironment.test.rawValue,
              let nip = env["KSEF_LIVE_NIP"], !nip.isEmpty,
              let token = env["KSEF_LIVE_TOKEN"], !token.isEmpty else { return nil }
        return (nip, token)
    }

    private func makeDraft(nip: String, number: String) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: number,
            issueDate: .now,
            sellerName: "Ksefiarz — test wsadowy E2E",
            sellerNIP: nip,
            sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
            buyerName: "Nabywca Testowy Sp. z o.o.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Przykładowa 2, 30-001 Kraków",
            lines: [
                InvoiceLineDraft(
                    name: "Usługa testowa wsadowa",
                    unit: "szt.",
                    quantity: 1,
                    unitNetPrice: 100,
                    vatRate: .standard
                ),
            ],
            paymentDueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            paymentForm: .transfer
        )
    }

    @Test(
        "Sesja wsadowa: paczka 3 faktur, statusy per dokument, numery KSeF i UPO",
        .enabled(if: credentials != nil)
    )
    func pelnyCyklWsadowy() async throws {
        let credentials = try #require(Self.credentials)
        let service = KSeFService(
            environment: .test,
            nip: credentials.nip,
            authToken: credentials.token
        )
        // Przetwarzanie paczki bywa wolniejsze niż pojedynczej faktury.
        service.maxPollAttempts = 60

        // Unikatowe numery per przebieg — KSeF odrzuca duplikaty numeru
        // w obrębie tego samego wystawcy.
        let stamp = Int(Date.now.timeIntervalSince1970)
        let files: [KSeFBatchFile] = (1...3).map { index in
            let draft = makeDraft(nip: credentials.nip, number: "E2E-BATCH/\(stamp)/\(index)")
            let xml = FA2XMLGenerator.generateXML(for: draft)
            return KSeFBatchFile(
                fileName: String(format: "faktura_%05d.xml", index),
                content: Data(xml.utf8)
            )
        }
        let hashes = files.map { KSeFCrypto.sha256Base64($0.content) }

        let result = try await service.sendInvoicesBatch(files: files, schema: .fa3)
        print("✓ Sesja wsadowa: \(result.sessionReferenceNumber)")
        print("  Status: \(result.sessionStatus.code ?? -1) — \(result.sessionStatus.description)")
        #expect(result.sessionStatus.isProcessed)
        #expect(result.sessionStatus.invoiceCount == 3)
        #expect(result.sessionStatus.successfulInvoiceCount == 3)

        // Każdy dokument z paczki jest skorelowany po skrócie i przyjęty.
        #expect(result.invoiceOutcomes.count == 3)
        for hash in hashes {
            let outcome = try #require(
                result.invoiceOutcomes.first { $0.invoiceHash == hash },
                "Brak wyniku dla dokumentu o skrócie \(hash)"
            )
            #expect(outcome.result.status == .accepted)
            let ksefNumber = try #require(outcome.result.ksefNumber)
            #expect(ksefNumber.hasPrefix(credentials.nip))
            print("  ✓ \(outcome.invoiceFileName ?? "?") → \(ksefNumber)")
        }

        // UPO pierwszej faktury — wspólny endpoint sesji (batch i online).
        let firstNumber = try #require(result.invoiceOutcomes.first?.result.ksefNumber)
        var upo: Data?
        for _ in 0..<10 where upo == nil {
            upo = try? await service.downloadUPO(
                sessionReference: result.sessionReferenceNumber,
                ksefNumber: firstNumber
            )
            if upo == nil { try await Task.sleep(for: .seconds(3)) }
        }
        let upoData = try #require(upo, "UPO niedostępne po 30 s")
        #expect(String(decoding: upoData, as: UTF8.self).contains(firstNumber))
        print("✓ UPO pobrane (\(upoData.count) bajtów)")
    }
}
