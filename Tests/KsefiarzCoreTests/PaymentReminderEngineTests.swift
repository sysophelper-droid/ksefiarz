import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Przypomnienia e-mail o płatnościach — kandydaci, treść i skrypt Mail")
@MainActor
struct PaymentReminderEngineTests {

    /// 15 lipca 2026, południe.
    private let now = FA2Format.dateFormatter.date(from: "2026-07-15")!
        .addingTimeInterval(12 * 3600)

    private func date(_ text: String) -> Date {
        FA2Format.dateFormatter.date(from: text)!
    }

    private let settings = PaymentReminderSettings(daysBeforeDue: 3, repeatAfterDays: 7)

    /// Kontener w pamięci — wymagany do przypisania relacji wpłat.
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, PaymentRecord.self, configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeInvoice(
        number: String = "FV/1/2026",
        due: String? = "2026-07-20",
        gross: Double = 1230,
        isPaid: Bool = false,
        hidden: Bool = false,
        buyerNIP: String = "1111111111",
        kind: Invoice.Kind = .sales
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: date("2026-07-01"),
            sellerName: "ACME Sp. z o.o.", sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.", buyerNIP: buyerNIP,
            netAmount: gross / 1.23, vatAmount: gross - gross / 1.23, grossAmount: gross,
            isPaid: isPaid,
            paymentDueDate: due.map(date),
            paymentBankAccount: "11222233334444555566667777",
            isArchivedOrHidden: hidden,
            kind: kind
        )
    }

    private func makeContractor(
        nip: String = "1111111111",
        email: String = "biuro@kontrahent.pl",
        bilingual: Bool = false
    ) -> Contractor {
        let contractor = Contractor()
        contractor.name = "Kontrahent S.A."
        contractor.nip = nip
        contractor.email = email
        contractor.prefersBilingualDocuments = bilingual
        return contractor
    }

    // MARK: Okna przypomnień

    @Test("Przed terminem: przypomnienie w oknie dni uprzedzenia, poza oknem cisza")
    func beforeDueWindow() {
        // Termin 17.07, dziś 15.07, okno 3 dni → kandydat (faza przed terminem).
        let inWindow = makeInvoice(due: "2026-07-17")
        // Termin 20.07 → 5 dni, poza oknem.
        let outside = makeInvoice(number: "FV/2/2026", due: "2026-07-20")
        let result = PaymentReminderEngine.candidates(
            invoices: [inWindow, outside],
            contractors: [makeContractor()],
            settings: settings,
            asOf: now
        )
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.invoice.invoiceNumber == "FV/1/2026")
        #expect(result.candidates.first?.phase == .beforeDue)
        #expect(result.omissions.isEmpty)
    }

    @Test("Dzień terminu należy do okna uprzedzenia; przy oknie 0 dni tylko on")
    func dueDayIncluded() {
        let dueToday = makeInvoice(due: "2026-07-15")
        let zeroWindow = PaymentReminderSettings(daysBeforeDue: 0, repeatAfterDays: 7)
        let result = PaymentReminderEngine.candidates(
            invoices: [dueToday],
            contractors: [makeContractor()],
            settings: zeroWindow,
            asOf: now
        )
        #expect(result.candidates.first?.phase == .beforeDue)
    }

    @Test("Po terminie: pierwsze ponaglenie od razu, kolejne dopiero po odstępie")
    func overdueRepeats() {
        let overdue = makeInvoice(due: "2026-07-01")
        var result = PaymentReminderEngine.candidates(
            invoices: [overdue], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(result.candidates.first?.phase == .overdue)

        // Przypomnienie sprzed 3 dni — odstęp 7 dni jeszcze nie minął.
        overdue.collectionReminderAt = date("2026-07-12")
        result = PaymentReminderEngine.candidates(
            invoices: [overdue], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(result.candidates.isEmpty)

        // Przypomnienie sprzed 7 dni — czas na kolejne ponaglenie.
        overdue.collectionReminderAt = date("2026-07-08")
        result = PaymentReminderEngine.candidates(
            invoices: [overdue], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(result.candidates.count == 1)
    }

    @Test("Jedno uprzedzenie na okno przed terminem — wysłane nie wraca")
    func beforeDueDeduplicated() {
        let invoice = makeInvoice(due: "2026-07-17")
        // Przypomnienie wysłane wczoraj (już w oknie 14–17.07).
        invoice.collectionReminderAt = date("2026-07-14")
        let result = PaymentReminderEngine.candidates(
            invoices: [invoice], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(result.candidates.isEmpty)

        // Przypomnienie sprzed okna (np. z poprzedniej faktury) nie blokuje.
        invoice.collectionReminderAt = date("2026-07-10")
        let again = PaymentReminderEngine.candidates(
            invoices: [invoice], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(again.candidates.count == 1)
    }

    // MARK: Wykluczenia

    @Test("Opłacone, ukryte, zakupy, bez terminu i z saldem 0 — poza silnikiem")
    func filteredOut() throws {
        let context = try makeContext()
        let paid = makeInvoice(due: "2026-07-01", isPaid: true)
        let hidden = makeInvoice(due: "2026-07-01", hidden: true)
        let purchase = makeInvoice(due: "2026-07-01", kind: .purchase)
        let noDue = makeInvoice(due: nil)
        let settled = makeInvoice(due: "2026-07-01")
        [paid, hidden, purchase, noDue, settled].forEach(context.insert)
        settled.payments = [PaymentRecord(amount: 1230, date: now)]
        try context.save()
        let result = PaymentReminderEngine.candidates(
            invoices: [paid, hidden, purchase, noDue, settled],
            contractors: [makeContractor()],
            settings: settings,
            asOf: now
        )
        #expect(result.candidates.isEmpty)
        #expect(result.omissions.isEmpty)
    }

    @Test("Formalne wezwanie wstrzymuje miękkie przypomnienia (jawne pominięcie)")
    func demandStopsSoftReminders() {
        let invoice = makeInvoice(due: "2026-07-01")
        invoice.collectionDemandAt = date("2026-07-05")
        let result = PaymentReminderEngine.candidates(
            invoices: [invoice], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(result.candidates.isEmpty)
        #expect(result.omissions.count == 1)
        #expect(result.omissions.first?.kind == .formalCollection)
        #expect(result.omissions.first?.reason.contains("windykacja") == true)
    }

    @Test("Brak adresu e-mail w słowniku — jawne pominięcie, nie cicha zguba")
    func missingEmailOmitted() {
        let result = PaymentReminderEngine.candidates(
            invoices: [makeInvoice(due: "2026-07-01")],
            contractors: [makeContractor(email: "")],
            settings: settings,
            asOf: now
        )
        #expect(result.candidates.isEmpty)
        #expect(result.omissions.first?.kind == .missingRecipient)
        #expect(result.omissions.first?.reason.contains("e-mail") == true)
    }

    @Test("Braki adresów tworzą jawne podsumowanie, formalna windykacja nie")
    func missingRecipientNotificationSummary() {
        let omissions = [
            PaymentReminderOmission(
                invoiceNumber: "FV/1", kind: .formalCollection,
                reason: "formalna windykacja w toku"
            ),
            PaymentReminderOmission(
                invoiceNumber: "FV/2", kind: .missingRecipient,
                reason: "brak adresu e-mail"
            ),
        ]
        let body = PaymentReminderEngine.missingRecipientNotificationBody(
            omissions: omissions
        )
        #expect(body?.contains("1 faktury") == true)
        #expect(body?.contains("FV/2") == true)
        #expect(body?.contains("FV/1") == false)
        #expect(PaymentReminderEngine.missingRecipientNotificationBody(
            omissions: [omissions[0]]
        ) == nil)
    }

    // MARK: Treść wiadomości

    @Test("Treść PL: saldo (nie brutto), termin, rachunek i prośba o zignorowanie")
    func polishBody() throws {
        let context = try makeContext()
        let invoice = makeInvoice(due: "2026-07-01")
        context.insert(invoice)
        invoice.payments = [PaymentRecord(amount: 230, date: now)]
        try context.save()
        let result = PaymentReminderEngine.candidates(
            invoices: [invoice], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        let candidate = result.candidates.first
        #expect(candidate?.language == .polish)
        #expect(candidate?.subject.contains("FV/1/2026") == true)
        #expect(candidate?.recipient == "biuro@kontrahent.pl")
        let body = candidate?.body ?? ""
        // Saldo po wpłacie częściowej: 1230 − 230 = 1000.
        #expect(body.contains("1000.00 PLN"))
        #expect(!body.contains("1230.00"))
        #expect(body.contains("14 dni temu"))
        #expect(body.contains("11222233334444555566667777"))
        #expect(body.contains("prosimy zignorować"))
        #expect(body.contains("ACME Sp. z o.o."))
    }

    @Test("Kontrahent dwujęzyczny dostaje wiadomość po angielsku")
    func englishForBilingual() {
        let result = PaymentReminderEngine.candidates(
            invoices: [makeInvoice(due: "2026-07-17")],
            contractors: [makeContractor(bilingual: true)],
            settings: settings,
            asOf: now
        )
        let candidate = result.candidates.first
        #expect(candidate?.language == .english)
        #expect(candidate?.subject.contains("due soon") == true)
        #expect(candidate?.body.contains("friendly reminder") == true)
        #expect(candidate?.body.contains("disregard") == true)
    }

    @Test("Kandydaci uporządkowani od najdawniej wymagalnych")
    func sortedByDueDate() {
        let older = makeInvoice(number: "FV/старsza", due: "2026-06-01")
        let newer = makeInvoice(number: "FV/nowsza", due: "2026-07-01")
        let result = PaymentReminderEngine.candidates(
            invoices: [newer, older], contractors: [makeContractor()],
            settings: settings, asOf: now
        )
        #expect(result.candidates.map(\.invoice.invoiceNumber)
            == ["FV/старsza", "FV/nowsza"])
    }

    @Test("Ustawienia spoza zakresu są przycinane (bez pętli przypomnień)")
    func settingsClamped() {
        let tooLow = PaymentReminderSettings(daysBeforeDue: -5, repeatAfterDays: 0)
        #expect(tooLow.daysBeforeDue == 0)
        #expect(tooLow.repeatAfterDays == 1)

        let tooHigh = PaymentReminderSettings(daysBeforeDue: 365, repeatAfterDays: 365)
        #expect(tooHigh.daysBeforeDue == 30)
        #expect(tooHigh.repeatAfterDays == 60)
    }

    @Test("Cykl automatyzacji restartuje się po zmianie każdego ustawienia")
    func automationConfigurationIdentity() {
        let base = PaymentReminderAutomationConfiguration(
            isEnabled: true,
            daysBeforeDue: 3,
            repeatAfterDays: 7,
            deliveryModeRaw: "draft"
        )
        #expect(base != PaymentReminderAutomationConfiguration(
            isEnabled: false,
            daysBeforeDue: 3,
            repeatAfterDays: 7,
            deliveryModeRaw: "draft"
        ))
        #expect(base != PaymentReminderAutomationConfiguration(
            isEnabled: true,
            daysBeforeDue: 5,
            repeatAfterDays: 7,
            deliveryModeRaw: "draft"
        ))
        #expect(base != PaymentReminderAutomationConfiguration(
            isEnabled: true,
            daysBeforeDue: 3,
            repeatAfterDays: 14,
            deliveryModeRaw: "draft"
        ))
        #expect(base != PaymentReminderAutomationConfiguration(
            isEnabled: true,
            daysBeforeDue: 3,
            repeatAfterDays: 7,
            deliveryModeRaw: "send"
        ))
    }

    // MARK: Skrypt AppleScript dla Mail

    @Test("Escaping AppleScript: cudzysłowy, backslashe i znaki nowej linii")
    func scriptEscaping() {
        #expect(MailAutomationScript.escaped(#"a "b" c"#) == #"a \"b\" c"#)
        #expect(MailAutomationScript.escaped(#"back\slash"#) == #"back\\slash"#)
        #expect(MailAutomationScript.escaped("linia1\nlinia2") == #"linia1\nlinia2"#)
        #expect(MailAutomationScript.escaped("crlf\r\nkoniec") == #"crlf\nkoniec"#)
        #expect(MailAutomationScript.escaped("cr\rkoniec") == #"cr\rkoniec"#)
        #expect(MailAutomationScript.escaped("tab\tkoniec") == #"tab\tkoniec"#)
        // Próba wstrzyknięcia polecenia kończy się w literale, nie w skrypcie.
        let hostile = MailAutomationScript.escaped("\"\ntell application \"Finder\"")
        #expect(!hostile.contains("\n"))
        #expect(!hostile.contains(#"tell application "Finder""#))
    }

    @Test("Skrypt Mail: adresat, temat, treść; wysyłka vs szkic")
    func scriptStructure() {
        let sendScript = MailAutomationScript.build(
            recipient: "biuro@kontrahent.pl",
            subject: "Przypomnienie \"ważne\"",
            body: "Dzień dobry,\nsaldo: 100 zł",
            send: true
        )
        #expect(sendScript.contains(#"tell application "Mail""#))
        #expect(sendScript.contains(#"{address:"biuro@kontrahent.pl"}"#))
        #expect(sendScript.contains(#"subject:"Przypomnienie \"ważne\""#))
        #expect(sendScript.contains(#"Dzień dobry,\nsaldo: 100 zł"#))
        #expect(sendScript.contains("send theMessage"))
        #expect(!sendScript.contains("save theMessage"))
        #expect(sendScript.contains("visible:false"))

        let draftScript = MailAutomationScript.build(
            recipient: "a@b.pl", subject: "T", body: "B", send: false
        )
        #expect(draftScript.contains("save theMessage"))
        #expect(!draftScript.contains("send theMessage"))
    }

    @Test("Tryby dostarczania mają polskie etykiety")
    func deliveryModeLabels() {
        #expect(MailAutomationService.DeliveryMode.draft.displayName.contains("Szkice"))
        #expect(MailAutomationService.DeliveryMode.send.displayName.contains("automatycznie"))
        #expect(MailAutomationService.DeliveryMode.allCases.count == 2)
    }
}
