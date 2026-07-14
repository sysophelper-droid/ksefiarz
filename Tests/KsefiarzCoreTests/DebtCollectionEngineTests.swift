import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Windykacja — etapy, eskalacja i dane do pozwu EPU")
@MainActor
struct DebtCollectionEngineTests {

    /// 15 lipca 2026, południe.
    private let now = FA2Format.dateFormatter.date(from: "2026-07-15")!
        .addingTimeInterval(12 * 3600)

    private func date(_ text: String) -> Date {
        FA2Format.dateFormatter.date(from: text)!
    }

    private func makeInvoice(
        number: String = "FV/1/2026",
        due: String = "2026-06-30",
        gross: Double = 1230,
        isPaid: Bool = false,
        hidden: Bool = false,
        currency: String = "PLN",
        kind: Invoice.Kind = .sales
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: date("2026-06-01"),
            sellerName: "ACME Sp. z o.o.", sellerNIP: "5260250274",
            sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
            buyerName: "Dłużnik S.A.", buyerNIP: "1111111111",
            buyerAddress: "ul. Zaległa 7, 30-001 Kraków",
            netAmount: gross / 1.23, vatAmount: gross - gross / 1.23, grossAmount: gross,
            isPaid: isPaid,
            paymentDueDate: FA2Format.dateFormatter.date(from: due),
            isArchivedOrHidden: hidden,
            currency: currency,
            kind: kind
        )
    }

    private func makeItem(
        number: String = "FV/1/2026",
        issue: String = "2026-06-01",
        due: String = "2026-06-30",
        outstanding: Double = 1230,
        currency: String = "PLN"
    ) -> PaymentDemandItem {
        PaymentDemandItem(
            invoiceNumber: number,
            issueDate: date(issue),
            dueDate: date(due),
            outstanding: outstanding,
            daysOverdue: 15,
            interest: 0,
            currency: currency
        )
    }

    // MARK: Etapy i odnotowywanie działań

    @Test("Etap windykacji to najdalszy odnotowany krok eskalacji")
    func stageDerivation() {
        let invoice = makeInvoice()
        #expect(invoice.collectionStage == .none)

        DebtCollectionEngine.record(.reminder, on: [invoice], at: now)
        #expect(invoice.collectionStage == .reminded)
        #expect(invoice.collectionReminderCount == 1)

        DebtCollectionEngine.record(.demand, on: [invoice], at: now)
        #expect(invoice.collectionStage == .demanded)

        DebtCollectionEngine.record(.interestNote, on: [invoice], at: now)
        #expect(invoice.collectionStage == .interestNoted)

        DebtCollectionEngine.record(.epu, on: [invoice], at: now)
        #expect(invoice.collectionStage == .epuPrepared)

        // Wcześniejsze daty pozostają nietknięte.
        #expect(invoice.collectionReminderAt != nil)
        #expect(invoice.collectionDemandAt != nil)
    }

    @Test("Ponowne przypomnienie aktualizuje datę i licznik, nie cofa etapu wezwania")
    func repeatedReminder() {
        let invoice = makeInvoice()
        DebtCollectionEngine.record(.reminder, on: [invoice], at: date("2026-07-01"))
        DebtCollectionEngine.record(.reminder, on: [invoice], at: date("2026-07-08"))
        #expect(invoice.collectionReminderCount == 2)
        #expect(invoice.collectionReminderAt == date("2026-07-08"))

        DebtCollectionEngine.record(.demand, on: [invoice], at: date("2026-07-10"))
        DebtCollectionEngine.record(.reminder, on: [invoice], at: date("2026-07-12"))
        #expect(invoice.collectionStage == .demanded)
    }

    @Test("Kolejność etapów jest porównywalna (Comparable)")
    func stageOrdering() {
        #expect(DebtCollectionStage.none < .reminded)
        #expect(DebtCollectionStage.reminded < .demanded)
        #expect(DebtCollectionStage.demanded < .interestNoted)
        #expect(DebtCollectionStage.interestNoted < .epuPrepared)
    }

    // MARK: Sugestie eskalacji

    @Test("Zaległa faktura bez działań: sugerowane przypomnienie")
    func suggestReminder() {
        let suggestion = DebtCollectionEngine.suggestion(for: makeInvoice(), asOf: now)
        #expect(suggestion?.action == .reminder)
    }

    @Test("Opłacona, ukryta, przed terminem albo zakup — bez sugestii")
    func noSuggestionWhenNotApplicable() {
        #expect(DebtCollectionEngine.suggestion(for: makeInvoice(isPaid: true), asOf: now) == nil)
        #expect(DebtCollectionEngine.suggestion(for: makeInvoice(hidden: true), asOf: now) == nil)
        #expect(DebtCollectionEngine.suggestion(for: makeInvoice(due: "2026-08-01"), asOf: now) == nil)
        #expect(DebtCollectionEngine.suggestion(for: makeInvoice(kind: .purchase), asOf: now) == nil)
    }

    @Test("Po przypomnieniu wezwanie dopiero po progach dni (zaległość i odstęp)")
    func suggestDemandAfterThresholds() {
        // Termin 30.06, dziś 15.07 → 15 dni zaległości (próg 14 spełniony).
        let invoice = makeInvoice()
        DebtCollectionEngine.record(.reminder, on: [invoice], at: date("2026-07-01"))
        // Od przypomnienia (1.07) do 15.07 minęło 14 dni ≥ 7 — sugeruj wezwanie.
        #expect(DebtCollectionEngine.suggestion(for: invoice, asOf: now)?.action == .demand)

        // Świeże przypomnienie (12.07) — za wcześnie na wezwanie.
        let fresh = makeInvoice()
        DebtCollectionEngine.record(.reminder, on: [fresh], at: date("2026-07-12"))
        #expect(DebtCollectionEngine.suggestion(for: fresh, asOf: now) == nil)

        // Krótka zaległość (termin 10.07 → 5 dni) — mimo starego przypomnienia
        // wezwanie jeszcze nie jest sugerowane.
        let shortOverdue = makeInvoice(due: "2026-07-10")
        DebtCollectionEngine.record(.reminder, on: [shortOverdue], at: date("2026-07-01"))
        #expect(DebtCollectionEngine.suggestion(for: shortOverdue, asOf: now) == nil)
    }

    @Test("Po wezwaniu nota, po nocie EPU; po EPU ścieżka wyczerpana")
    func suggestNoteThenEPU() {
        let invoice = makeInvoice()
        DebtCollectionEngine.record(.demand, on: [invoice], at: date("2026-06-30"))
        // 14 dni po wezwaniu (30.06 → 15.07 = 15 dni) — sugeruj notę.
        #expect(DebtCollectionEngine.suggestion(for: invoice, asOf: now)?.action == .interestNote)

        DebtCollectionEngine.record(.interestNote, on: [invoice], at: date("2026-07-01"))
        // Nota 1.07 → 15.07 = 14 dni — sugeruj dane do EPU.
        #expect(DebtCollectionEngine.suggestion(for: invoice, asOf: now)?.action == .epu)

        DebtCollectionEngine.record(.epu, on: [invoice], at: date("2026-07-10"))
        #expect(DebtCollectionEngine.suggestion(for: invoice, asOf: now) == nil)
    }

    // MARK: Rodzaje dokumentów windykacyjnych

    @Test("Przypomnienie i EPU nie naliczają odsetek; mapowanie na działania")
    func kindHelpers() {
        #expect(!PaymentDemandKind.reminder.includesInterest)
        #expect(PaymentDemandKind.demand.includesInterest)
        #expect(PaymentDemandKind.interestNote.includesInterest)
        #expect(!PaymentDemandKind.epu.includesInterest)
        #expect(PaymentDemandKind.reminder.collectionAction == .reminder)
        #expect(PaymentDemandKind.demand.collectionAction == .demand)
        #expect(PaymentDemandKind.interestNote.collectionAction == .interestNote)
        #expect(PaymentDemandKind.epu.collectionAction == .epu)
        #expect(DebtCollectionAction.epu.stage == .epuPrepared)
    }

    @Test("PDF przypomnienia generuje się bez odsetek; dane EPU bez PDF")
    func reminderPDFAndNoEPUPDF() {
        let items = PaymentDemandEngine.items(
            for: [makeInvoice()],
            annualRatePercent: 0,
            asOf: now
        )
        #expect(items.first?.interest == 0)
        var document = PaymentDemandDocument(
            kind: .reminder,
            sellerName: "ACME Sp. z o.o.",
            sellerAddress: "ul. Przykładowa 1, Warszawa",
            sellerNIP: "5260250274",
            bankAccount: "11222233334444555566667777",
            buyerName: "Dłużnik S.A.",
            buyerNIP: "1111111111",
            buyerAddress: "",
            items: items,
            annualRatePercent: 0,
            paymentDays: 7
        )
        let pdf = PaymentDemandPDFGenerator.pdfData(for: document)
        #expect(pdf?.prefix(5) == Data("%PDF-".utf8))

        document.kind = .epu
        #expect(PaymentDemandPDFGenerator.pdfData(for: document) == nil)
    }

    // MARK: EPU — kwalifikacja roszczeń

    @Test("EPU: waluty obce i roszczenia starsze niż 3 lata poza pozwem")
    func epuEligibility() {
        let ok = makeItem(number: "FV/1")
        let euro = makeItem(number: "FV/2", currency: "EUR")
        let stale = makeItem(number: "FV/3", due: "2023-06-30")
        let result = DebtCollectionEngine.epuEligibleItems(
            from: [ok, euro, stale], asOf: now
        )
        #expect(result.eligible.map(\.invoiceNumber) == ["FV/1"])
        #expect(result.omissions.count == 2)
        #expect(result.omissions.contains { $0.invoiceNumber == "FV/2" && $0.reason.contains("walut") })
        #expect(result.omissions.contains { $0.invoiceNumber == "FV/3" && $0.reason.contains("3 lata") })
    }

    @Test("WPS: suma należności głównych zaokrąglona w górę do pełnego złotego")
    func epuDisputeValue() {
        #expect(DebtCollectionEngine.epuDisputeValue(of: []) == 0)
        #expect(DebtCollectionEngine.epuDisputeValue(of: [
            makeItem(outstanding: 100.01), makeItem(outstanding: 200.50)
        ]) == 301)
        #expect(DebtCollectionEngine.epuDisputeValue(of: [makeItem(outstanding: 500)]) == 500)
    }

    @Test("Opłata EPU: 1/4 opłaty z art. 13 uksc, nie mniej niż 30 zł")
    func epuCourtFee() {
        // Widełki art. 13 ust. 1 (do 20 000 zł) — czwarta część, min. 30 zł.
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 0) == 0)
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 400) == 30)    // 30/4 → min 30
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 1000) == 30)   // 100/4 = 25 → min 30
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 3000) == 50)   // 200/4
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 5000) == 100)  // 400/4
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 9000) == 125)  // 500/4
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 12_000) == 188) // 750/4 = 187,5 → w górę
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 18_000) == 250) // 1000/4
        // Powyżej 20 000 zł: 5% WPS (maks. 100 000 zł), czwarta część.
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 30_000) == 375)  // 1500/4
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 100_001) == 1251) // 5001/4 → w górę
        #expect(DebtCollectionEngine.epuCourtFee(disputeValue: 3_000_000) == 25_000) // cap 100 000/4
    }

    // MARK: EPU — ostrzeżenia i tekst pozwu

    private var parties: DebtCollectionEngine.EPUParties {
        DebtCollectionEngine.EPUParties(
            claimantName: "ACME Sp. z o.o.",
            claimantNIP: "5260250274",
            claimantAddress: "ul. Przykładowa 1, 00-001 Warszawa",
            claimantBankAccount: "11222233334444555566667777",
            defendantName: "Dłużnik S.A.",
            defendantNIP: "1111111111",
            defendantAddress: "ul. Zaległa 7, 30-001 Kraków"
        )
    }

    @Test("Ostrzeżenia EPU: brak wezwania, adresu i NIP pozwanego, brak roszczeń")
    func epuWarnings() {
        let complete = DebtCollectionEngine.epuWarnings(
            parties: parties, items: [makeItem()], demandSentAt: now
        )
        #expect(complete.isEmpty)

        var incomplete = parties
        incomplete.defendantAddress = " "
        incomplete.defendantNIP = ""
        let warnings = DebtCollectionEngine.epuWarnings(
            parties: incomplete, items: [], demandSentAt: nil
        )
        #expect(warnings.count == 4)
        #expect(warnings.contains { $0.contains("wezwania") })
        #expect(warnings.contains { $0.contains("adresu pozwanego") })
        #expect(warnings.contains { $0.contains("NIP pozwanego") })
        #expect(warnings.contains { $0.contains("Brak roszczeń") })
    }

    @Test("Tekst danych EPU: strony, WPS, opłata, odsetki od dnia po terminie i dowody")
    func epuTextContent() {
        let items = [
            makeItem(number: "FV/1/2026", due: "2026-06-30", outstanding: 1000),
            makeItem(number: "FV/2/2026", due: "2026-05-31", outstanding: 500.25),
        ]
        let text = DebtCollectionEngine.epuText(
            parties: parties,
            items: items,
            demandSentAt: date("2026-07-05"),
            omissions: [("FV/9/2026", "waluta EUR — pozew EPU obejmuje kwoty w złotych")],
            date: now
        )
        #expect(text.contains("ELEKTRONICZNE POSTĘPOWANIE UPOMINAWCZE"))
        #expect(text.contains("ACME Sp. z o.o."))
        #expect(text.contains("NIP: 5260250274"))
        #expect(text.contains("Dłużnik S.A."))
        // WPS: 1000 + 500,25 = 1500,25 → 1501 zł; opłata: art. 13 (1500–4000)
        // = 200 zł, czwarta część = 50 zł.
        #expect(text.contains("WARTOŚĆ PRZEDMIOTU SPORU: 1501 zł"))
        #expect(text.contains("OPŁATA OD POZWU: 50 zł"))
        // Odsetki liczone od dnia następnego po terminie płatności.
        #expect(text.contains("od dnia 01.07.2026 do dnia zapłaty"))
        #expect(text.contains("od dnia 01.06.2026 do dnia zapłaty"))
        // Dowody: obie faktury i wezwanie z datą.
        #expect(text.contains("Faktura nr FV/1/2026 z dnia 01.06.2026"))
        #expect(text.contains("Wezwanie do zapłaty z dnia 05.07.2026"))
        #expect(text.contains("art. 187 § 1 pkt 3 KPC"))
        // Jawna lista roszczeń poza pozwem.
        #expect(text.contains("FV/9/2026 — waluta EUR"))
        #expect(text.contains("e-sad.gov.pl"))
    }

    @Test("Tekst EPU bez wezwania nie wymyśla dowodu ani próby polubownej")
    func epuTextWithoutDemand() {
        let text = DebtCollectionEngine.epuText(
            parties: parties,
            items: [makeItem()],
            demandSentAt: nil,
            date: now
        )
        #expect(!text.contains("Wezwanie do zapłaty z dnia"))
        #expect(!text.contains("art. 187"))
    }

    // MARK: Kopia zapasowa v14

    @Test("Kopia zapasowa zachowuje pola windykacji (roundtrip v14)")
    func backupRoundtrip() throws {
        let invoice = makeInvoice()
        DebtCollectionEngine.record(.reminder, on: [invoice], at: date("2026-07-01"))
        DebtCollectionEngine.record(.reminder, on: [invoice], at: date("2026-07-08"))
        DebtCollectionEngine.record(.demand, on: [invoice], at: date("2026-07-10"))

        let data = try BackupService.makeBackup(invoices: [invoice], settings: [:])
        let decoded = try BackupService.decode(data)
        #expect(decoded.version == 14)
        let restored = BackupService.makeInvoice(from: try #require(decoded.invoices.first))
        #expect(restored.collectionReminderAt == date("2026-07-08"))
        #expect(restored.collectionReminderCount == 2)
        #expect(restored.collectionDemandAt == date("2026-07-10"))
        #expect(restored.collectionInterestNoteAt == nil)
        #expect(restored.collectionEPUAt == nil)
        #expect(restored.collectionStage == .demanded)
    }

    @Test("Starsza kopia bez pól windykacji odtwarza fakturę z etapem „bez działań”")
    func backupBackwardCompatible() throws {
        // Kopia bieżącej wersji, ale bez działań — pola nil/0 jak w starszych plikach.
        let data = try BackupService.makeBackup(invoices: [makeInvoice()], settings: [:])
        let decoded = try BackupService.decode(data)
        let restored = BackupService.makeInvoice(from: try #require(decoded.invoices.first))
        #expect(restored.collectionStage == .none)
        #expect(restored.collectionReminderCount == 0)
    }

    @Test("Przywracanie ustawień: wartości logiczne i liczbowe wracają pod natywnym typem")
    func typedSettingsRestore() throws {
        let suiteName = "ksefiarz.tests.applySetting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        BackupService.applySetting(
            key: AppSettingsKeys.reminderEmailsEnabled, value: "1", defaults: defaults
        )
        BackupService.applySetting(
            key: AppSettingsKeys.reminderDaysBefore, value: "5", defaults: defaults
        )
        BackupService.applySetting(
            key: AppSettingsKeys.demandInterestRate, value: "13.5", defaults: defaults
        )
        BackupService.applySetting(
            key: AppSettingsKeys.nip, value: "5260250274", defaults: defaults
        )
        #expect(defaults.object(forKey: AppSettingsKeys.reminderEmailsEnabled) as? Bool == true)
        #expect(defaults.object(forKey: AppSettingsKeys.reminderDaysBefore) as? Int == 5)
        #expect(defaults.object(forKey: AppSettingsKeys.demandInterestRate) as? Double == 13.5)
        // NIP pozostaje tekstem — mimo że wygląda jak liczba.
        #expect(defaults.object(forKey: AppSettingsKeys.nip) as? String == "5260250274")
    }
}
