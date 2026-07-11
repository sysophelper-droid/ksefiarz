import Foundation

/// Minimalny kontrakt potrzebny do domykania wysyłek. Testy podstawiają
/// atrapę bez wykonywania prawdziwych żądań do KSeF.
public protocol KSeFSubmissionStatusProviding: AnyObject {
    func fetchInvoiceStatus(
        sessionReference: String,
        invoiceReference: String
    ) async throws -> KSeFInvoiceProcessingResult

    func downloadUPO(sessionReference: String, ksefNumber: String) async throws -> Data
}

extension KSeFService: KSeFSubmissionStatusProviding {}

/// Czysta warstwa koordynująca odpytywanie statusu, zapis numeru KSeF
/// i automatyczne pobranie UPO do modelu faktury.
@MainActor
public enum InvoiceSubmissionStatusEngine {

    public struct RefreshSummary: Equatable, Sendable {
        public var checked = 0
        public var accepted = 0
        public var rejected = 0
        public var failures = 0

        public init() {}
    }

    /// Sprawdza jedną fakturę. Dla dokumentu już przyjętego, lecz bez UPO,
    /// nie odpytuje ponownie statusu — próbuje tylko pobrać poświadczenie.
    @discardableResult
    public static func refresh(
        _ invoice: Invoice,
        using service: KSeFSubmissionStatusProviding,
        now: Date = .now
    ) async throws -> KSeFInvoiceProcessingResult {
        guard let sessionReference = invoice.ksefSessionReference,
              let invoiceReference = invoice.ksefInvoiceReference else {
            throw KSeFError.invalidResponse
        }

        if invoice.ksefSubmissionStatus == .accepted,
           let ksefNumber = invoice.ksefId {
            invoice.ksefLastCheckedAt = now
            await tryDownloadUPO(
                for: invoice,
                sessionReference: sessionReference,
                ksefNumber: ksefNumber,
                using: service
            )
            return KSeFInvoiceProcessingResult(
                status: .accepted,
                statusCode: invoice.ksefStatusCode,
                description: invoice.ksefStatusDescription ?? "Faktura przyjęta przez KSeF.",
                ksefNumber: ksefNumber,
                acquisitionDate: invoice.ksefAcceptedAt
            )
        }

        let result = try await service.fetchInvoiceStatus(
            sessionReference: sessionReference,
            invoiceReference: invoiceReference
        )
        invoice.ksefSubmissionStatus = result.status
        invoice.ksefStatusCode = result.statusCode
        invoice.ksefStatusDescription = result.description
        invoice.ksefLastCheckedAt = now

        if result.status == .accepted, let ksefNumber = result.ksefNumber {
            invoice.ksefId = ksefNumber
            invoice.ksefAcceptedAt = result.acquisitionDate ?? now
            await tryDownloadUPO(
                for: invoice,
                sessionReference: sessionReference,
                ksefNumber: ksefNumber,
                using: service
            )
        }
        return result
    }

    /// Domyka wszystkie pasujące wysyłki. Błąd pojedynczego dokumentu nie
    /// blokuje pozostałych; liczba błędów trafia do podsumowania.
    public static func refreshOutstanding(
        _ invoices: [Invoice],
        environmentRaw: String,
        using service: KSeFSubmissionStatusProviding,
        now: Date = .now
    ) async -> RefreshSummary {
        var summary = RefreshSummary()
        let outstanding = invoices.filter {
            $0.needsKSeFFollowUp
                && ($0.ksefEnvironmentRaw.isEmpty || $0.ksefEnvironmentRaw == environmentRaw)
        }

        for invoice in outstanding {
            do {
                let result = try await refresh(invoice, using: service, now: now)
                summary.checked += 1
                if result.status == .accepted { summary.accepted += 1 }
                if result.status == .rejected { summary.rejected += 1 }
            } catch {
                summary.failures += 1
            }
        }
        return summary
    }

    private static func tryDownloadUPO(
        for invoice: Invoice,
        sessionReference: String,
        ksefNumber: String,
        using service: KSeFSubmissionStatusProviding
    ) async {
        guard (invoice.upoXmlContent ?? "").isEmpty else { return }
        guard let data = try? await service.downloadUPO(
            sessionReference: sessionReference,
            ksefNumber: ksefNumber
        ) else { return }
        invoice.upoXmlContent = String(decoding: data, as: UTF8.self)
    }
}
