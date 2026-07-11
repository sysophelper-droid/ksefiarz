import Foundation
import Testing
@testable import KsefiarzCore

/// Wysyłka faktury NA ŻYWO — WYŁĄCZNIE środowisko testowe KSeF.
///
/// Test jest podwójnie zabezpieczony przed produkcją:
/// 1. wymaga jawnej zgody `KSEF_LIVE_SEND=1` oraz `KSEF_LIVE_ENV=test`,
/// 2. `KSeFService` jest tworzony z zaszytym `.test` — nawet błędna zmienna
///    środowiskowa nie skieruje wysyłki na produkcję.
///
/// Uruchomienie (token testowy ze Scripts/get-test-token.py):
/// KSEF_LIVE_SEND=1 KSEF_LIVE_ENV=test KSEF_LIVE_NIP=... KSEF_LIVE_TOKEN=... \
///   swift test --filter LiveSendTests
@Suite("Wysyłka faktury na żywo (środowisko testowe)")
struct LiveSendTests {

    static var credentials: (nip: String, token: String)? {
        let env = ProcessInfo.processInfo.environment
        guard env["KSEF_LIVE_SEND"] == "1",
              env["KSEF_LIVE_ENV"] == KSeFEnvironment.test.rawValue,
              let nip = env["KSEF_LIVE_NIP"], !nip.isEmpty,
              let token = env["KSEF_LIVE_TOKEN"], !token.isEmpty else { return nil }
        return (nip, token)
    }

    @Test("Pełny cykl wystawienia: wysyłka FA(3), numer KSeF, UPO", .enabled(if: credentials != nil))
    func pelnyCyklWystawienia() async throws {
        let credentials = try #require(Self.credentials)
        let service = KSeFService(
            environment: .test,
            nip: credentials.nip,
            authToken: credentials.token
        )

        // Unikatowy numer faktury per przebieg — KSeF odrzuca duplikaty
        // numeru w obrębie tego samego wystawcy.
        let stamp = Int(Date.now.timeIntervalSince1970)
        let draft = InvoiceDraft(
            invoiceNumber: "E2E/\(stamp)",
            issueDate: .now,
            sellerName: "Ksefiarz — test E2E",
            sellerNIP: credentials.nip,
            sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
            buyerName: "Nabywca Testowy Sp. z o.o.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Przykładowa 2, 30-001 Kraków",
            lines: [
                InvoiceLineDraft(
                    name: "Usługa testowa E2E",
                    unit: "szt.",
                    quantity: 1,
                    unitNetPrice: 100,
                    vatRate: .standard
                )
            ],
            paymentDueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            paymentForm: .transfer
        )

        let result = try await service.sendInvoice(draft)
        print("✓ Wysłano — referencja: \(result.invoiceReferenceNumber)")
        print("  Sesja: \(result.sessionReferenceNumber)")
        #expect(!result.sessionReferenceNumber.isEmpty)
        #expect(!result.invoiceReferenceNumber.isEmpty)

        let ksefNumber = try #require(
            result.ksefNumber,
            "Nie otrzymano numeru KSeF; dokument nadal jest przetwarzany"
        )
        #expect(ksefNumber.hasPrefix(credentials.nip))

        // UPO bywa dostępne z opóźnieniem po zamknięciu sesji.
        var upo: Data?
        for _ in 0..<10 where upo == nil {
            upo = try? await service.downloadUPO(
                sessionReference: result.sessionReferenceNumber,
                ksefNumber: ksefNumber
            )
            if upo == nil { try await Task.sleep(for: .seconds(3)) }
        }
        let upoData = try #require(upo, "UPO niedostępne po 30 s")
        let upoText = String(decoding: upoData, as: UTF8.self)
        #expect(upoText.contains(ksefNumber))
        print("✓ UPO pobrane (\(upoData.count) bajtów)")
    }
}
