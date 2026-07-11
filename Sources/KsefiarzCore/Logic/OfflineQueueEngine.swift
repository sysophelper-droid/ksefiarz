import Foundation

/// Minimalny kontrakt wysyłki gotowego XML — testy podstawiają atrapę.
public protocol KSeFInvoiceSending: AnyObject {
    func sendInvoiceXML(_ xmlData: Data, offlineMode: Bool) async throws -> KSeFSendResult
}

extension KSeFService: KSeFInvoiceSending {}

/// Kolejka dokumentów offline24: wyszukuje faktury oczekujące na dosłanie
/// do KSeF i wysyła ZAPISANY dokument XML (bajt w bajt — jego skrót widnieje
/// w kodach QR na przekazanym nabywcy egzemplarzu).
@MainActor
public enum OfflineQueueEngine {

    public struct SendSummary: Equatable, Sendable {
        public var sent = 0
        public var accepted = 0
        public var rejected = 0
        public var failures = 0

        public init() {}
    }

    /// Faktury oczekujące w kolejce offline dla bieżącego środowiska.
    public static func pending(in invoices: [Invoice], environmentRaw: String) -> [Invoice] {
        invoices.filter {
            $0.ksefSubmissionStatus == .offlinePending
                && ($0.ksefEnvironmentRaw.isEmpty || $0.ksefEnvironmentRaw == environmentRaw)
                && !($0.rawXmlContent ?? "").isEmpty
        }
    }

    /// Dosyła pojedynczy dokument offline. Aktualizuje pola faktury
    /// (referencje, status, numer KSeF) zgodnie z wynikiem.
    @discardableResult
    public static func send(
        _ invoice: Invoice,
        using service: KSeFInvoiceSending,
        now: Date = .now
    ) async throws -> KSeFSendResult {
        guard invoice.ksefSubmissionStatus == .offlinePending,
              let xml = invoice.rawXmlContent, !xml.isEmpty else {
            throw KSeFError.invalidResponse
        }
        let result = try await service.sendInvoiceXML(Data(xml.utf8), offlineMode: true)

        invoice.ksefSessionReference = result.sessionReferenceNumber
        invoice.ksefInvoiceReference = result.invoiceReferenceNumber
        invoice.ksefSubmissionStatus = result.processingResult.status
        invoice.ksefStatusCode = result.processingResult.statusCode
        invoice.ksefStatusDescription = result.processingResult.description
        invoice.ksefLastCheckedAt = now
        if let ksefNumber = result.ksefNumber {
            invoice.ksefId = ksefNumber
            invoice.ksefAcceptedAt = result.processingResult.acquisitionDate ?? now
        }
        return result
    }

    /// Dosyła wszystkie oczekujące dokumenty. Błąd (np. brak sieci) zostawia
    /// dokument w kolejce — kolejna próba przy następnym przebiegu.
    public static func sendPending(
        _ invoices: [Invoice],
        environmentRaw: String,
        using service: KSeFInvoiceSending,
        now: Date = .now
    ) async -> SendSummary {
        var summary = SendSummary()
        for invoice in pending(in: invoices, environmentRaw: environmentRaw) {
            do {
                let result = try await send(invoice, using: service, now: now)
                summary.sent += 1
                if result.processingResult.status == .accepted { summary.accepted += 1 }
                if result.processingResult.status == .rejected { summary.rejected += 1 }
            } catch {
                summary.failures += 1
            }
        }
        return summary
    }
}
