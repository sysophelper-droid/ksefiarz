import Foundation
import Testing
@testable import KsefiarzCore

/// Weryfikacja kodów QR NA ŻYWO — WYŁĄCZNIE środowisko testowe KSeF.
///
/// Pełny cykl trybu offline24: uwierzytelnienie certyfikatem (self-signed),
/// wniosek o certyfikat offline (typ 2), wystawienie dokumentu offline
/// (XML + skrót jak w aplikacji), dosłanie z `offlineMode: true`,
/// a następnie sprawdzenie NA BRAMCE `qr-test.ksef.mf.gov.pl`, że:
/// - KOD I prowadzi do strony potwierdzającej obecność faktury w KSeF,
/// - KOD II przechodzi weryfikację certyfikatu wystawcy.
///
/// Bramka renderuje wynik po stronie serwera (strona nieistniejącej faktury
/// zawiera „Faktura nie została znaleziona w KSeF!"), więc treść HTML
/// jest wiarygodnym wynikiem weryfikacji.
///
/// Uruchomienie:
/// KSEF_LIVE_SEND=1 KSEF_LIVE_ENV=test KSEF_LIVE_NIP=... \
///   swift test --filter LiveQRVerificationTests
@Suite("Weryfikacja kodów QR na żywo (środowisko testowe)")
struct LiveQRVerificationTests {

    static var liveNIP: String? {
        let env = ProcessInfo.processInfo.environment
        guard env["KSEF_LIVE_SEND"] == "1",
              env["KSEF_LIVE_ENV"] == KSeFEnvironment.test.rawValue,
              let nip = env["KSEF_LIVE_NIP"], !nip.isEmpty else { return nil }
        return nip
    }

    /// Pobiera stronę bramki QR i zwraca jej widoczny tekst (bez znaczników).
    private func fetchPageText(_ url: String) async throws -> String {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        var text = String(decoding: data, as: UTF8.self)
        for pattern in ["<script[^>]*>.*?</script>", "<style[^>]*>.*?</style>", "<[^>]+>"] {
            text = text.replacingOccurrences(
                of: pattern, with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return text
            .replacingOccurrences(of: "&#x105;", with: "ą") // minimalne odkodowanie encji
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("Offline24 e2e: dosłanie + KOD I i KOD II potwierdzone na bramce qr-test", .enabled(if: liveNIP != nil))
    func offlineQRCodesVerifiedOnGateway() async throws {
        let nip = try #require(Self.liveNIP)

        // 1. Uwierzytelnienie certyfikatem self-signed (bootstrap na test).
        let key = try X509Builder.generateRSAKeyPair()
        let bootstrapDER = try X509Builder.makeSelfSignedCertificate(
            subject: [
                .countryName("PL"),
                .organizationName("Ksefiarz QR E2E \(nip)"),
                .commonName("Ksefiarz QR E2E \(nip)"),
                .organizationIdentifier("VATPL-\(nip)"),
            ],
            privateKey: key
        )
        let bootstrap = KSeFCertificate(
            certificateDER: bootstrapDER,
            privateKeyDER: try X509Builder.exportPrivateKey(key)
        )
        let service = KSeFService(environment: .test, nip: nip, authToken: "", certificate: bootstrap)

        // 2. Certyfikat offline (typ 2) — do podpisu KODU II.
        let offlineCertificate = try await service.requestCertificate(
            name: "Ksefiarz QR E2E offline",
            type: .offline
        )
        print("✓ Certyfikat offline: seryjny \(offlineCertificate.serialNumberHex)")

        // 3. Dokument offline — XML i skrót dokładnie jak w aplikacji.
        let stamp = Int(Date.now.timeIntervalSince1970)
        let issueDate = Date.now
        let draft = InvoiceDraft(
            invoiceNumber: "QR-E2E/\(stamp)",
            issueDate: issueDate,
            sellerName: "Ksefiarz — test QR E2E",
            sellerNIP: nip,
            sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
            buyerName: "Nabywca Testowy Sp. z o.o.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Przykładowa 2, 30-001 Kraków",
            lines: [
                InvoiceLineDraft(
                    name: "Usługa testowa QR",
                    unit: "szt.",
                    quantity: 1,
                    unitNetPrice: 100,
                    vatRate: .standard
                )
            ],
            paymentDueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            paymentForm: .transfer
        )
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let xmlData = Data(xml.utf8)
        let hashBase64 = KSeFCrypto.sha256Base64(xmlData)

        // Linki obu kodów budowane PRZED wysyłką — jak na wydruku offline.
        let kod1 = KSeFVerificationLink.invoiceURL(
            environment: .test,
            sellerNIP: nip,
            issueDate: issueDate,
            xmlHashBase64: hashBase64
        )
        let kod2 = try KSeFVerificationLink.certificateURL(
            environment: .test,
            contextNip: nip,
            sellerNIP: nip,
            certificate: offlineCertificate,
            xmlHashBase64: hashBase64
        )
        print("KOD I:  \(kod1)")
        print("KOD II: \(kod2)")

        // Przed dosłaniem bramka nie zna faktury (kontrola wiarygodności testu).
        let beforeText = try await fetchPageText(kod1)
        #expect(beforeText.contains("nie została znaleziona"))

        // 4. Dosłanie dokumentu offline (bajt w bajt te same dane, z których
        // policzono skrót) i oczekiwanie na numer KSeF.
        let result = try await service.sendInvoiceXML(xmlData, offlineMode: true)
        let ksefNumber = try #require(result.ksefNumber, "Nie otrzymano numeru KSeF")
        print("✓ Dosłano offline — numer KSeF: \(ksefNumber)")
        #expect(ksefNumber.hasPrefix(nip))

        // 5. KOD I: bramka musi potwierdzić obecność faktury (indeksowanie
        // bywa opóźnione — do 90 s).
        var kod1Text = ""
        for attempt in 0..<18 {
            kod1Text = try await fetchPageText(kod1)
            if !kod1Text.contains("nie została znaleziona") { break }
            if attempt < 17 { try await Task.sleep(for: .seconds(5)) }
        }
        print("Strona KOD I: \(kod1Text.prefix(700))")
        // Frazy renderowane przez bramkę przy pomyślnej weryfikacji
        // (zaobserwowane 11.07.2026 na qr-test).
        #expect(kod1Text.contains("Faktura znajduje się w KSeF"))
        #expect(kod1Text.contains(ksefNumber))
        #expect(kod1Text.contains("Offline"))
        // Kluczowe: zgodność bajtów dosłanego XML z linkiem z wydruku.
        #expect(kod1Text.contains("zgodny z dokumentem, dla którego wygenerowano link weryfikacyjny Tak"))

        // 6. KOD II: weryfikacja certyfikatu wystawcy.
        let kod2Text = try await fetchPageText(kod2)
        print("Strona KOD II: \(kod2Text.prefix(700))")
        #expect(kod2Text.contains("Weryfikacja prawidłowa"))
        #expect(kod2Text.contains("Certyfikat istnieje"))
        #expect(kod2Text.contains("uprawnienia do wystawienia faktury w imieniu \(nip)"))
    }
}
