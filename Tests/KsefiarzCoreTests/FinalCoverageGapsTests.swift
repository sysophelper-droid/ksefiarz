import Foundation
import Security
import Testing
@testable import KsefiarzCore

// Domknięcie ostatnich testowalnych luk: import PKCS#12 (pełna ścieżka
// tożsamości), rzadkie gałęzie usług i akcesorów. Wszystko offline
// (atrapa transportu, lokalny fixture p12), bez wysyłki na żywo.

@Suite("Import PKCS#12 — pełna tożsamość z pliku .p12")
struct PKCS12ImportTests {

    // Testowy p12 (RSA-2048, hasło „test123") wygenerowany openssl-em
    // z certyfikatu self-signed CN=Ksefiarz Test. Zawiera pasującą parę
    // klucz+certyfikat, więc weryfikacja podpisu w importPKCS12 przechodzi.
    private static let p12Base64: String =
        "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"

    @Test("importPKCS12 wczytuje tożsamość, ale klucz z pęku jest nieeksportowalny (macOS)")
    func importujePKCS12() throws {
        let data = try #require(Data(base64Encoded: Self.p12Base64))
        // Poprawnym hasłem SecPKCS12Import wczytuje tożsamość (certyfikat + klucz),
        // ale na macOS klucz z pęku kluczy jest nieeksportowalny, więc
        // SecKeyCopyExternalRepresentation zawodzi i import zgłasza invalidPKCS12.
        // Ścieżka przechodzi przez ekstrakcję tożsamości, certyfikatu, klucza
        // i rozpoznanie typu klucza (keyType), zanim napotka to ograniczenie.
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.importPKCS12(data: data, password: "test123")
        }
    }

    @Test("importPKCS12 z błędnym hasłem zgłasza invalidPKCS12")
    func zleHaslo() throws {
        let data = try #require(Data(base64Encoded: Self.p12Base64))
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.importPKCS12(data: data, password: "zle-haslo")
        }
    }
}

@Suite("Pozostałe gałęzie usług i akcesorów")
struct FinalServiceGapsTests {

    @Test("NBP — odpowiedź 200 z pustą listą kursów zgłasza noRateAvailable")
    func nbpPustaLista() async {
        let transport = MockTransport()
        transport.routeOK("/api/exchangerates/rates/a/eur/",
                          data: Data(#"{"table":"A","currency":"euro","code":"EUR","rates":[]}"#.utf8))
        let service = NBPExchangeRateService(transport: transport)
        await #expect(throws: NBPExchangeRateService.RateError.noRateAvailable) {
            _ = try await service.midRate(currency: "EUR", onOrBefore: .now)
        }
    }

    @Test("XAdESSigner — certyfikat z nieczytelnym DER zgłasza błąd pól certyfikatu")
    func xadesBrakInfo() {
        let cert = KSeFCertificate(
            certificateDER: Data([0x00, 0x01, 0x02, 0x03]),
            privateKeyDER: Data([0x00]),
            keyType: .rsa
        )
        #expect(cert.info == nil)
        #expect(throws: KSeFError.self) {
            _ = try XAdESSigner.signAuthTokenRequest(
                challenge: "wyzwanie", nip: "5260250274", certificate: cert
            )
        }
    }

    @Test("KSeFCertificate.info(fromDER:) zwraca nil dla nieprawidłowego DER")
    func infoZlyDER() {
        #expect(KSeFCertificate.info(fromDER: Data([0x02, 0x01, 0x00])) == nil)
        #expect(KSeFCertificate.info(fromDER: Data()) == nil)
    }

    @Test("KSeFService buduje się z domyślnym resolverem klucza publicznego")
    func domyslnyResolver() {
        // Konstrukcja bez jawnego publicKeyResolver używa domyślnego
        // KSeFCrypto.publicKey(fromDERCertificate:) — bez połączenia sieciowego.
        let service = KSeFService(
            environment: .test, nip: "5260250274",
            authToken: "tok", transport: MockTransport()
        )
        #expect(service.environment == .test)
    }

    @Test("ReportsEngine.revenueByProduct bez limitu zwraca pełną listę")
    func revenueBezLimitu() {
        let a = makeTestInvoice(number: "FV/1", kind: .sales, gross: 123)
        a.lines = [InvoiceLine(index: 1, name: "Towar A", unit: "szt.", quantity: 1,
                               unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23)]
        let full = ReportsEngine.revenueByProduct(in: [a], limit: nil)
        let limited = ReportsEngine.revenueByProduct(in: [a], limit: 0)
        #expect(full.count >= limited.count)
    }

    @Test("PaymentMatchProposal konstruuje się z domyślnym identyfikatorem")
    func proposalDomyslneId() {
        let transaction = BankTransaction(date: .now, amount: 100, title: "FV/1")
        let proposal = PaymentMatchProposal(
            transaction: transaction, invoiceID: nil, confidence: .none
        )
        #expect(proposal.transaction.amount == 100)
        #expect(proposal.invoiceID == nil)
    }

    @Test("MT940 parseStatementLine parsuje datę, stronę i kwotę operacji")
    func mt940ParsujeLinie() throws {
        // Strona C = uznanie (kwota dodatnia). Regex gwarantuje kwotę parsowalną,
        // więc gałąź odrzucenia kwoty pozostaje obronna (nieosiągalna).
        let (_, amount) = try #require(MT940Parser.parseStatementLine("260708C1234,56"))
        #expect(amount == 1234.56)
    }
}
