import Foundation
import Testing
@testable import KsefiarzCore

/// Odczytowy test publicznej bramki anonimowego dostępu KSeF.
///
/// Uruchomienie (bez tokenu i bez logowania):
/// KSEF_LIVE_ANONYMOUS=1 KSEF_LIVE_ENV=test \
/// KSEF_LIVE_ANON_KSEF_NUMBER=... KSEF_LIVE_ANON_INVOICE_NUMBER=... \
/// KSEF_LIVE_ANON_BUYER_NIP=... KSEF_LIVE_ANON_BUYER_NAME=... \
/// KSEF_LIVE_ANON_AMOUNT=123.00 swift test --filter LiveAnonymousAccessTests
@Suite("Anonimowy dostęp na żywo (wyłącznie odczyt)")
struct LiveAnonymousAccessTests {
    struct Input {
        let environment: KSeFEnvironment
        let ksefNumber: String
        let invoiceNumber: String
        let buyerNIP: String
        let buyerName: String
        let amount: Decimal
    }

    static var input: Input? {
        let env = ProcessInfo.processInfo.environment
        guard env["KSEF_LIVE_ANONYMOUS"] == "1",
              let environmentRaw = env["KSEF_LIVE_ENV"],
              let environment = KSeFEnvironment(rawValue: environmentRaw),
              let ksefNumber = env["KSEF_LIVE_ANON_KSEF_NUMBER"],
              let invoiceNumber = env["KSEF_LIVE_ANON_INVOICE_NUMBER"],
              let buyerNIP = env["KSEF_LIVE_ANON_BUYER_NIP"],
              let buyerName = env["KSEF_LIVE_ANON_BUYER_NAME"],
              let amountText = env["KSEF_LIVE_ANON_AMOUNT"],
              let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return Input(
            environment: environment,
            ksefNumber: ksefNumber,
            invoiceNumber: invoiceNumber,
            buyerNIP: buyerNIP,
            buyerName: buyerName,
            amount: amount
        )
    }

    @Test("Pobranie XML po danych identyfikujących", .enabled(if: input != nil))
    func downloadsXMLReadOnly() async throws {
        let input = try #require(Self.input)
        let service = KSeFAnonymousAccessService(environment: input.environment)
        let xml = try await service.downloadInvoice(AnonymousInvoiceAccessRequest(
            ksefNumber: input.ksefNumber,
            invoiceNumber: input.invoiceNumber,
            buyerIdentifierValue: input.buyerNIP,
            buyerName: input.buyerName,
            grossAmount: input.amount
        ))
        let invoice = try FA2XMLParser.parse(data: xml)

        #expect(invoice.invoiceNumber == input.invoiceNumber)
        #expect(invoice.buyerNIP == input.buyerNIP)
        #expect(invoice.rawXML.contains("<Faktura"))
    }
}
