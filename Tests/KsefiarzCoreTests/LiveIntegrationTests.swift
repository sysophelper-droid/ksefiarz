import Foundation
import Testing
@testable import KsefiarzCore

/// Opcjonalne testy integracyjne na żywym środowisku KSeF.
///
/// Domyślnie pomijane — aktywują się wyłącznie po ustawieniu zmiennych środowiskowych:
/// ```
/// KSEF_LIVE_NIP=... KSEF_LIVE_TOKEN=... KSEF_LIVE_ENV=test swift test --filter "na żywo"
/// ```
/// Wykonują wyłącznie operacje odczytu (uwierzytelnienie + zapytanie o metadane).
@Suite("Integracja KSeF na żywo (opcjonalna)")
struct LiveKSeFIntegrationTests {

    static var credentials: (nip: String, token: String, environment: KSeFEnvironment)? {
        let env = ProcessInfo.processInfo.environment
        guard let nip = env["KSEF_LIVE_NIP"], !nip.isEmpty,
              let token = env["KSEF_LIVE_TOKEN"], !token.isEmpty else {
            return nil
        }
        let environment = KSeFEnvironment(rawValue: env["KSEF_LIVE_ENV"] ?? "test") ?? .test
        return (nip, token, environment)
    }

    @Test("Diagnostyka pobierania XML faktur zakupowych", .enabled(if: credentials != nil))
    func liveXMLDownloadDiagnostics() async throws {
        let credentials = try #require(Self.credentials)
        let service = KSeFService(
            environment: credentials.environment,
            nip: credentials.nip,
            authToken: credentials.token
        )
        let invoices = try await service.fetchPurchaseInvoices(
            from: Calendar.current.date(byAdding: .month, value: -2, to: .now)!,
            to: .now
        )
        print("Pobrano \(invoices.count) faktur:")
        for invoice in invoices {
            let hasXML = !invoice.rawXML.isEmpty
            print("  • \(invoice.invoiceNumber): XML=\(hasXML ? "TAK (\(invoice.rawXML.count) zn.)" : "BRAK"), pozycje=\(invoice.lines.count)")
            if !hasXML, let ksefId = invoice.ksefId {
                do {
                    _ = try await service.downloadInvoice(ksefNumber: ksefId)
                    print("    → ponowna próba pobrania: SUKCES (?)")
                } catch {
                    print("    → błąd pobrania: \(error.localizedDescription)")
                }
            }
        }
    }

    @Test("Faktury sprzedażowe w KSeF (Subject1) — bieżący miesiąc", .enabled(if: credentials != nil))
    func liveSalesQuery() async throws {
        let credentials = try #require(Self.credentials)
        let service = KSeFService(
            environment: credentials.environment,
            nip: credentials.nip,
            authToken: credentials.token
        )
        let to = Date.now
        let from = Calendar.current.date(byAdding: .month, value: -1, to: to)!
        let invoices = try await service.fetchSalesInvoices(from: from, to: to)
        print("✓ Faktury sprzedażowe zarejestrowane w KSeF (ostatni miesiąc): \(invoices.count)")
        for invoice in invoices {
            print("  • \(invoice.invoiceNumber) | \(FA2Format.dateFormatter.string(from: invoice.issueDate)) | \(invoice.grossAmount) PLN | KSeF: \(invoice.ksefId ?? "—")")
        }
    }

    @Test("Uwierzytelnienie tokenem i zapytanie o faktury zakupowe", .enabled(if: credentials != nil))
    func liveAuthenticationAndQuery() async throws {
        let credentials = try #require(Self.credentials)
        let service = KSeFService(
            environment: credentials.environment,
            nip: credentials.nip,
            authToken: credentials.token
        )

        let accessToken = try await service.authenticate()
        #expect(!accessToken.isEmpty)
        print("✓ Uwierzytelnienie OK (środowisko: \(credentials.environment.rawValue))")

        let to = Date.now
        let from = Calendar.current.date(byAdding: .month, value: -1, to: to)!
        let invoices = try await service.fetchPurchaseInvoices(from: from, to: to)
        print("✓ Zapytanie OK — pobrano \(invoices.count) faktur zakupowych z ostatniego miesiąca")
        for invoice in invoices.prefix(4) {
            print("  • \(invoice.invoiceNumber) | \(invoice.sellerName) | \(invoice.grossAmount) PLN")
            print("    adres sprzedawcy: \(invoice.sellerAddress.isEmpty ? "—" : invoice.sellerAddress)")
            print("    adres nabywcy:    \(invoice.buyerAddress.isEmpty ? "—" : invoice.buyerAddress)")
            print("    pozycje: \(invoice.lines.count)", terminator: "")
            if let first = invoice.lines.first {
                print(" (1: \(first.name.prefix(40)) | \(first.netAmount) netto | VAT \(first.vatRate))")
            } else {
                print()
            }
            let form = invoice.paymentForm.flatMap { PaymentForm(rawValue: $0)?.displayName } ?? "—"
            let account = invoice.paymentBankAccount ?? "—"
            print("    płatność: forma=\(form), rachunek=\(account), zapłacono=\(invoice.isPaidMarker)")
        }
    }
}
