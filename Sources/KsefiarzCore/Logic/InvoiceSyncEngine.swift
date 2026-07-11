import Foundation
import SwiftData

/// Wspólna logika synchronizacji faktur z KSeF — używana przez ręczne
/// odświeżanie list, pobieranie przy starcie i synchronizację automatyczną.
@MainActor
public enum InvoiceSyncEngine {

    /// Pobiera faktury wskazanego rodzaju z KSeF i scala je z bazą.
    /// Zakres dat pochodzi z ustawień importu; faktury z kompletem danych
    /// lokalnie nie są pobierane ponownie (oszczędność limitu 16 pobrań/min).
    /// Zwraca liczbę NOWO wstawionych faktur (np. do powiadomień).
    @discardableResult
    public static func sync(
        kind: Invoice.Kind,
        service: KSeFService,
        from: Date,
        to: Date,
        prepaidForms: Set<String>,
        context: ModelContext
    ) async throws -> Int {
        let allInvoices = try context.fetch(FetchDescriptor<Invoice>())
        let complete = Set(allInvoices.compactMap { invoice in
            (invoice.rawXmlContent ?? "").isEmpty ? nil : invoice.ksefId
        })
        let fetched = try await service.fetchInvoices(
            role: kind == .purchase ? .buyer : .seller,
            from: from,
            to: to,
            skipDocumentsFor: complete
        )
        let inserted = try merge(fetched, kind: kind, prepaidForms: prepaidForms, context: context)
        // Znacznik dla etykiety „Ostatnia synchronizacja” w pasku bocznym —
        // ustawiany po udanym przebiegu (ręcznym i automatycznym).
        UserDefaults.standard.set(
            Date.now.timeIntervalSince1970, forKey: AppSettingsKeys.lastSyncAt
        )
        return inserted
    }

    /// Wstawia nowe faktury i uzupełnia szczegóły już istniejących
    /// (deduplikacja po ksefId). Sprawdzamy WSZYSTKIE faktury (również
    /// ukryte), aby ukryta faktura nie została ponownie zaimportowana.
    /// Na końcu jawny zapis kontekstu — listy (@Query) odświeżają się
    /// dopiero przy zapisie. Zwraca liczbę nowo wstawionych faktur.
    @discardableResult
    static func merge(
        _ fetched: [FA2InvoiceData],
        kind: Invoice.Kind,
        prepaidForms: Set<String>,
        context: ModelContext
    ) throws -> Int {
        let allInvoices = try context.fetch(FetchDescriptor<Invoice>())
        let existingByKsefId = Dictionary(
            allInvoices.compactMap { invoice in invoice.ksefId.map { ($0, invoice) } },
            uniquingKeysWith: { first, _ in first }
        )
        // Zabezpieczenie przed duplikatem: dokument mógł pojawić się w
        // zapytaniu sprzedażowym zanim osobne odpytywanie statusu dopisało
        // numer KSeF do lokalnego rekordu. Numery sprzedażowe są unikalne
        // i walidowane przy zapisie.
        let submittedByInvoiceNumber = Dictionary(
            allInvoices.compactMap { invoice -> (String, Invoice)? in
                guard invoice.kind == kind,
                      invoice.ksefId == nil,
                      invoice.ksefInvoiceReference != nil else { return nil }
                return (InvoiceValidator.normalizedNumber(invoice.invoiceNumber), invoice)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var inserted = 0
        for item in fetched {
            let submittedMatch = submittedByInvoiceNumber[
                InvoiceValidator.normalizedNumber(item.invoiceNumber)
            ]
            if let ksefId = item.ksefId,
               let existing = existingByKsefId[ksefId] ?? submittedMatch {
                existing.ksefId = ksefId
                existing.ksefSubmissionStatus = .accepted
                existing.ksefAcceptedAt = existing.ksefAcceptedAt ?? .now
                // Faktura już istnieje — uzupełniamy szczegóły (adresy, pozycje,
                // dane płatności), bez nadpisywania decyzji użytkownika.
                if existing.lines.isEmpty || (existing.rawXmlContent ?? "").isEmpty
                    || existing.sellerAddress.isEmpty {
                    existing.applyDetails(from: item)
                }
                PaymentFormPolicy.apply(to: existing, prepaidForms: prepaidForms)
                continue
            }
            let invoice = Invoice(from: item, kind: kind)
            context.insert(invoice)
            invoice.applyDetails(from: item)
            // Formy płatności „z góry” (np. gotówka/karta) → od razu opłacona.
            PaymentFormPolicy.apply(to: invoice, prepaidForms: prepaidForms)
            inserted += 1
        }
        try context.save()
        return inserted
    }
}
