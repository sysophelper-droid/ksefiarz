import Foundation

/// Wysyłka wsadowa do KSeF (sesja batch/ZIP) — czysta logika koordynująca:
/// kwalifikacja lokalnych dokumentów, plan paczek per schema (FA(3) i FA_RR(1)
/// mają osobne formCode, więc i osobne sesje), oznaczenie wysłanych dokumentów,
/// korelacja wyników po skrócie SHA-256 (zalecenie ksef-docs) oraz domykanie
/// sesji, których przetwarzanie trwało dłużej niż budżet odpytywania.
///
/// Sesja wsadowa nie zwraca referencji per faktura w chwili wysyłki — dopiero
/// po przetworzeniu paczki. Dokument „w drodze" jest więc rozpoznawany po
/// stanie: `processing` + numer sesji + BRAK referencji faktury; korelacją
/// zajmuje się `reconcilePending` (wpięte w SyncCenter).
@MainActor
public enum BatchSendEngine {

    // MARK: Plan wysyłki

    /// Dokument zakwalifikowany do paczki: wygenerowany XML i jego skrót.
    public struct Candidate {
        public let invoice: Invoice
        public let file: KSeFBatchFile
        /// Skrót SHA-256 (Base64) dokumentu — klucz korelacji wyników.
        public let hashBase64: String
    }

    /// Dokument odrzucony z planu (np. błędy walidacji) wraz z powodem.
    public struct Exclusion {
        public let invoice: Invoice
        public let reason: String
    }

    /// Grupa dokumentów jednej schemy — jedna sesja wsadowa.
    public struct Group {
        public let schema: KSeFInvoiceSchema
        public let candidates: [Candidate]
    }

    /// Plan wysyłki: paczki per schema + dokumenty wykluczone z powodem.
    public struct Plan {
        public let groups: [Group]
        public let excluded: [Exclusion]

        /// Wszystkie dokumenty planu w kolejności grup.
        public var candidates: [Candidate] { groups.flatMap(\.candidates) }
    }

    /// Dokumenty, które w ogóle kwalifikują się do wysyłki wsadowej:
    /// istniejące wyłącznie lokalnie (nigdy nie przekazane do KSeF),
    /// z cyklem wysyłki zarządzanym przez aplikację i niekryte.
    /// Kolejka offline ma własną, automatyczną ścieżkę dosłań
    /// (`OfflineQueueEngine`) — dokumenty offline nie wchodzą do paczki.
    public static func eligible(in invoices: [Invoice]) -> [Invoice] {
        invoices.filter {
            $0.isLocalOnly && $0.hasKSeFSubmissionLifecycle && !$0.isArchivedOrHidden
        }
    }

    /// Buduje plan: walidacja każdego dokumentu, generacja XML (FA(3) albo
    /// FA_RR(1) — jak przy wysyłce interaktywnej) i podział na grupy schem.
    /// Dokument z błędami walidacji trafia do `excluded` i nie blokuje reszty.
    public static func plan(for invoices: [Invoice], generatedAt: Date = .now) -> Plan {
        var bySchema: [String: (schema: KSeFInvoiceSchema, candidates: [Candidate])] = [:]
        var excluded: [Exclusion] = []

        for invoice in eligible(in: invoices) {
            let draft = InvoiceDraft(from: invoice)
            let errors = InvoiceValidator.validate(draft)
            guard errors.isEmpty else {
                excluded.append(Exclusion(
                    invoice: invoice,
                    reason: errors.compactMap(\.errorDescription).joined(separator: " ")
                ))
                continue
            }

            let xml = FA2XMLGenerator.generateXML(for: draft, generatedAt: generatedAt)
            let xmlData = Data(xml.utf8)
            let schema = KSeFInvoiceSchema.detect(in: xmlData)
            let index = (bySchema[schema.systemCode]?.candidates.count ?? 0) + 1
            let candidate = Candidate(
                invoice: invoice,
                file: KSeFBatchFile(
                    fileName: String(format: "faktura_%05d.xml", index),
                    content: xmlData
                ),
                hashBase64: KSeFCrypto.sha256Base64(xmlData)
            )
            bySchema[schema.systemCode, default: (schema, [])].candidates.append(candidate)
        }

        // Stała kolejność grup (FA przed FA_RR) — przewidywalny przebieg i testy.
        let groups = bySchema.values
            .sorted { $0.schema.systemCode < $1.schema.systemCode }
            .map { Group(schema: $0.schema, candidates: $0.candidates) }
        return Plan(groups: groups, excluded: excluded)
    }

    // MARK: Wysyłka i zastosowanie wyników

    /// Podsumowanie zastosowania wyników sesji do dokumentów lokalnych.
    public struct ApplySummary: Equatable, Sendable {
        public var accepted = 0
        public var rejected = 0
        public var processing = 0
        /// Dokumenty bez wyniku w ZAKOŃCZONEJ sesji — przywrócone do stanu
        /// lokalnego (paczka nie dostarczyła ich do KSeF).
        public var reverted = 0

        public init() {}
    }

    /// Wysyła jedną grupę planu w sesji wsadowej i nanosi wyniki na dokumenty.
    /// Po pomyślnym zamknięciu sesji dokumenty przechodzą w stan „w toku"
    /// z numerem sesji; wyniki dostępne od razu są nanoszone natychmiast,
    /// a pozostałe domyka późniejsza synchronizacja (`reconcilePending`).
    @discardableResult
    public static func send(
        group: Group,
        environmentRaw: String,
        using service: KSeFBatchSending,
        offlineMode: Bool = false,
        now: Date = .now,
        onPhase: (@MainActor (KSeFBatchPhase) -> Void)? = nil
    ) async throws -> (result: KSeFBatchSendResult, summary: ApplySummary) {
        let result = try await service.sendInvoicesBatch(
            files: group.candidates.map(\.file),
            schema: group.schema,
            offlineMode: offlineMode,
            onPhase: onPhase
        )

        // Paczka dotarła do KSeF — od tej chwili dokumenty są „w toku"
        // (niezmienialne), dopóki nie poznamy wyniku przetwarzania.
        markSent(
            group.candidates,
            sessionReference: result.sessionReferenceNumber,
            environmentRaw: environmentRaw,
            now: now
        )

        let summary = apply(
            outcomes: result.invoiceOutcomes,
            sessionStatus: result.sessionStatus,
            to: group.candidates.map(\.invoice),
            now: now
        )
        return (result, summary)
    }

    /// Oznacza dokumenty jako przekazane w sesji wsadowej: stan „w toku",
    /// numer sesji, środowisko i DOKŁADNIE wysłany XML (jego skrót jest
    /// kluczem korelacji przy domykaniu).
    static func markSent(
        _ candidates: [Candidate],
        sessionReference: String,
        environmentRaw: String,
        now: Date = .now
    ) {
        for candidate in candidates {
            let invoice = candidate.invoice
            invoice.rawXmlContent = String(decoding: candidate.file.content, as: UTF8.self)
            invoice.ksefSessionReference = sessionReference
            invoice.ksefInvoiceReference = nil
            invoice.ksefSubmissionStatus = .processing
            invoice.ksefStatusCode = nil
            invoice.ksefStatusDescription =
                "Przekazana w paczce wsadowej — oczekuje na przetworzenie przez KSeF."
            invoice.ksefLastCheckedAt = now
            invoice.ksefEnvironmentRaw = environmentRaw
        }
    }

    /// Nanosi wyniki sesji na dokumenty: korelacja po skrócie SHA-256
    /// zapisanego XML. Dokument bez wyniku wraca do stanu lokalnego TYLKO
    /// wtedy, gdy brak wyniku jest pewny: sesja zakończyła się błędem paczki
    /// (kody ≥ 400 — żaden dokument nie został przyjęty) albo sesja jest
    /// przetworzona i dysponujemy pełną listą wyników, w której dokumentu
    /// nie ma. Kompletność listy potwierdzają liczniki statusu sesji; lista
    /// pusta, częściowa albo bez liczników przy statusie 200 zostawia dokument
    /// „w toku" — bez ryzyka ponownej wysyłki czegoś, co KSeF już przyjął.
    @discardableResult
    static func apply(
        outcomes: [KSeFBatchInvoiceOutcome],
        sessionStatus: KSeFBatchSessionStatus,
        to invoices: [Invoice],
        now: Date = .now
    ) -> ApplySummary {
        var summary = ApplySummary()
        let reportedOutcomeCount: Int? = {
            if let successful = sessionStatus.successfulInvoiceCount,
               let failed = sessionStatus.failedInvoiceCount {
                let total = successful + failed
                if let invoiceCount = sessionStatus.invoiceCount,
                   invoiceCount != total {
                    return nil
                }
                return total
            }
            return sessionStatus.invoiceCount
        }()
        let hasCompleteOutcomeList = reportedOutcomeCount == outcomes.count
            && reportedOutcomeCount != nil
        let canRevertUnmatched = sessionStatus.isFailed
            || (sessionStatus.isProcessed && hasCompleteOutcomeList)

        // Kubełki wyników per skrót — duplikat skrótu (identyczne dokumenty)
        // jest przydzielany kolejno, nie wielokrotnie do jednej faktury.
        var bucket: [String: [KSeFBatchInvoiceOutcome]] = [:]
        for outcome in outcomes.reversed() {
            bucket[outcome.invoiceHash, default: []].append(outcome)
        }

        for invoice in invoices {
            guard let xml = invoice.rawXmlContent, !xml.isEmpty else { continue }
            let hash = KSeFCrypto.sha256Base64(Data(xml.utf8))

            if var matches = bucket[hash], let outcome = matches.popLast() {
                bucket[hash] = matches
                applyOutcome(outcome, to: invoice, now: now)
                switch outcome.result.status {
                case .accepted: summary.accepted += 1
                case .rejected: summary.rejected += 1
                default: summary.processing += 1
                }
            } else if canRevertUnmatched {
                // Dokumentu na pewno nie ma w wynikach sesji — nie został
                // dostarczony (np. błąd całej paczki). Przywrócenie stanu
                // lokalnego umożliwia poprawę i ponowną wysyłkę.
                revertToLocal(invoice, sessionStatus: sessionStatus, now: now)
                summary.reverted += 1
            } else {
                summary.processing += 1
            }
        }
        return summary
    }

    /// Nanosi pojedynczy wynik na dokument (te same pola co przy sesji
    /// interaktywnej — `OfflineQueueEngine.send` / widok szczegółów).
    private static func applyOutcome(
        _ outcome: KSeFBatchInvoiceOutcome,
        to invoice: Invoice,
        now: Date
    ) {
        invoice.ksefInvoiceReference = outcome.referenceNumber
        invoice.ksefSubmissionStatus = outcome.result.status
        invoice.ksefStatusCode = outcome.result.statusCode
        invoice.ksefStatusDescription = outcome.result.description
        invoice.ksefLastCheckedAt = now
        if let ksefNumber = outcome.result.ksefNumber {
            invoice.ksefId = ksefNumber
            invoice.ksefAcceptedAt = outcome.result.acquisitionDate ?? now
        }
    }

    /// Przywraca dokument do stanu lokalnego po nieudanej paczce.
    /// Dokument nigdy nie został przyjęty przez KSeF, więc pozostaje
    /// edytowalny; opis błędu sesji zostaje do wglądu.
    private static func revertToLocal(
        _ invoice: Invoice,
        sessionStatus: KSeFBatchSessionStatus,
        now: Date
    ) {
        invoice.ksefSessionReference = nil
        invoice.ksefInvoiceReference = nil
        invoice.ksefSubmissionStatus = .local
        invoice.ksefStatusCode = sessionStatus.code
        invoice.ksefStatusDescription =
            "Wysyłka wsadowa nie powiodła się: \(sessionStatus.description)"
        invoice.ksefLastCheckedAt = now
    }

    // MARK: Domykanie sesji wsadowych

    /// Dokumenty przekazane wsadowo, czekające na wynik przetworzenia paczki:
    /// stan „w toku" z numerem sesji, ale BEZ referencji faktury (tę nadaje
    /// dopiero wynik sesji; wysyłka interaktywna zawsze ustawia referencję).
    public static func pendingReconciliation(
        in invoices: [Invoice],
        environmentRaw: String
    ) -> [Invoice] {
        invoices.filter {
            $0.ksefSubmissionStatus == .processing
                && $0.ksefSessionReference != nil
                && $0.ksefInvoiceReference == nil
                && !($0.rawXmlContent ?? "").isEmpty
                && ($0.ksefEnvironmentRaw.isEmpty || $0.ksefEnvironmentRaw == environmentRaw)
        }
    }

    /// Podsumowanie domykania sesji wsadowych.
    public struct ReconcileSummary: Equatable, Sendable {
        public var checked = 0
        public var accepted = 0
        public var rejected = 0
        public var failures = 0

        public init() {}
    }

    /// Domyka sesje wsadowe: dla każdej sesji z oczekującymi dokumentami
    /// sprawdza status i — po zakończeniu przetwarzania — nanosi wyniki.
    /// Sesja wciąż przetwarzana ani błąd sieci nie zmieniają dokumentów.
    public static func reconcilePending(
        _ invoices: [Invoice],
        environmentRaw: String,
        using service: KSeFBatchStatusProviding,
        now: Date = .now
    ) async -> ReconcileSummary {
        var summary = ReconcileSummary()
        let pending = pendingReconciliation(in: invoices, environmentRaw: environmentRaw)
        let bySessions = Dictionary(grouping: pending) { $0.ksefSessionReference ?? "" }

        for (sessionReference, sessionInvoices) in bySessions where !sessionReference.isEmpty {
            do {
                let status = try await service.fetchBatchSessionStatus(
                    referenceNumber: sessionReference
                )
                guard status.isTerminal else { continue }

                // Sesja z błędem paczki nie przyjęła żadnego dokumentu —
                // nieudane pobranie (pustej zwykle) listy nie blokuje
                // przywrócenia dokumentów. Dla sesji przetworzonej lista
                // jest obowiązkowa: bez niej nie wolno niczego cofać.
                let outcomes: [KSeFBatchInvoiceOutcome]
                if status.isFailed {
                    outcomes = (try? await service.fetchBatchSessionInvoices(
                        referenceNumber: sessionReference
                    )) ?? []
                } else {
                    outcomes = try await service.fetchBatchSessionInvoices(
                        referenceNumber: sessionReference
                    )
                }
                let applied = apply(
                    outcomes: outcomes,
                    sessionStatus: status,
                    to: sessionInvoices,
                    now: now
                )
                summary.checked += sessionInvoices.count
                summary.accepted += applied.accepted
                summary.rejected += applied.rejected
            } catch {
                summary.failures += 1
            }
        }
        return summary
    }
}
