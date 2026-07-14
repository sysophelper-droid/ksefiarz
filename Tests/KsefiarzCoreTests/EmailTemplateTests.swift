import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Szablony e-mail — render, symbole i własne wzory (F5)")
struct EmailTemplateTests {

    private func makeInvoice(
        ksefId: String? = "1111111111-20260711-AAAAAAAAAAAA-AA",
        paymentDueDate: Date? = FA2Format.dateFormatter.date(from: "2026-07-15")!,
        paymentBankAccount: String? = "11222233334444555566667777"
    ) -> Invoice {
        Invoice(
            ksefId: ksefId,
            invoiceNumber: "FV/7/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            paymentDueDate: paymentDueDate,
            paymentBankAccount: paymentBankAccount,
            kind: .sales
        )
    }

    // MARK: Render

    @Test("Symbole są podstawiane, a nieznany symbol zostaje dosłownie")
    func substitutionAndUnknownSymbol() {
        let rendered = EmailTemplate.render(
            "Faktura {numer} dla {nabywca} {literowka}",
            values: ["numer": "FV/1", "nabywca": "ACME"]
        )
        #expect(rendered == "Faktura FV/1 dla ACME {literowka}")
    }

    @Test("Wiersz, którego wszystkie znane symbole są puste, jest pomijany")
    func emptyPlaceholderLineDropped() {
        let rendered = EmailTemplate.render(
            "Numer: {numer}\nTermin płatności: {termin}.\nPozdrawiamy",
            values: ["numer": "FV/1", "termin": ""]
        )
        #expect(rendered == "Numer: FV/1\nPozdrawiamy")
    }

    @Test("Wiersz z symbolem pustym i niepustym zostaje (pusty znika z treści)")
    func mixedPlaceholderLineKept() {
        let rendered = EmailTemplate.render(
            "Kwota {kwota} (termin: {termin})",
            values: ["kwota": "100 PLN", "termin": ""]
        )
        #expect(rendered == "Kwota 100 PLN (termin: )")
    }

    @Test("Niedomknięty nawias i symbol z wielkimi literami zostają dosłownie")
    func malformedPlaceholders() {
        #expect(EmailTemplate.render("Otwarte {numer", values: ["numer": "X"]) == "Otwarte {numer")
        #expect(EmailTemplate.render("{Numer}", values: ["numer": "X"]) == "{Numer}")
    }

    @Test("Temat renderuje się do jednego wiersza")
    func subjectSingleLine() {
        let subject = EmailTemplate.renderSubject(
            "Faktura {numer}\ndruga linia", values: ["numer": "FV/1"]
        )
        #expect(subject == "Faktura FV/1 druga linia")
    }

    // MARK: Wartości symboli

    @Test("Wartości symboli faktury: numer, kwoty, termin, rachunek, KSeF i dni po terminie")
    func invoiceValues() {
        let asOf = FA2Format.dateFormatter.date(from: "2026-07-20")!
        let values = EmailTemplate.values(for: makeInvoice(), language: .polish, asOf: asOf)
        #expect(values["numer"] == "FV/7/2026")
        #expect(values["kwota"] == "123.00 PLN")
        #expect(values["saldo"] == "123.00 PLN")
        #expect(values["data"]?.contains("lipca 2026") == true)
        #expect(values["termin"]?.contains("15 lipca 2026") == true)
        #expect(values["rachunek"] == "11222233334444555566667777")
        #expect(values["ksef"] == "1111111111-20260711-AAAAAAAAAAAA-AA")
        #expect(values["sprzedawca"] == "ACME Sp. z o.o.")
        #expect(values["nabywca"] == "Kontrahent S.A.")
        #expect(values["dni_po_terminie"] == "5")
    }

    @Test("Brak terminu daje puste symbole terminu i dni po terminie")
    func missingDueDateValues() {
        let values = EmailTemplate.values(
            for: makeInvoice(paymentDueDate: nil), language: .polish
        )
        #expect(values["termin"] == "")
        #expect(values["dni_po_terminie"] == "")
    }

    // MARK: Zgodność szablonów domyślnych z dotychczasowymi tekstami

    @Test("Domyślna treść wiadomości faktury (PL) jest identyczna z dotychczasową")
    func defaultInvoiceBodyMatchesLegacy() {
        let body = InvoiceEmailComposer.defaultBody(for: makeInvoice())
        let expected = """
        Dzień dobry,

        w załączeniu przesyłamy fakturę FV/7/2026 z dnia 1 lipca 2026 na kwotę 123.00 PLN brutto.
        Termin płatności: 15 lipca 2026.
        Numer rachunku do wpłaty: 11222233334444555566667777.
        Faktura znajduje się w KSeF pod numerem: 1111111111-20260711-AAAAAAAAAAAA-AA.

        Pozdrawiamy
        ACME Sp. z o.o.
        """
        #expect(body == expected)
    }

    @Test("Faktura bez terminu, rachunku i numeru KSeF nie ma odpowiadających wierszy")
    func defaultInvoiceBodyDropsMissingLines() {
        let invoice = makeInvoice(ksefId: nil, paymentDueDate: nil, paymentBankAccount: nil)
        let body = InvoiceEmailComposer.defaultBody(for: invoice)
        #expect(!body.contains("Termin płatności"))
        #expect(!body.contains("rachunku"))
        #expect(!body.contains("KSeF"))
        #expect(body.contains("Pozdrawiamy\nACME Sp. z o.o."))
    }

    @Test("Domyślna treść proformy zawiera adnotację o dokumencie handlowym")
    func defaultProformaBody() {
        let proforma = Proforma(
            proformaNumber: "PF/1/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Klient",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123
        )
        let subject = ProformaEmailView.defaultSubject(for: proforma, language: .polish)
        let body = ProformaEmailView.defaultBody(for: proforma, language: .polish)
        #expect(subject == "Proforma PF/1/2026 — ACME Sp. z o.o.")
        #expect(body.contains("fakturę proforma PF/1/2026"))
        #expect(body.contains("nie stanowi faktury VAT"))
        #expect(body.contains("po zaksięgowaniu wpłaty"))
    }

    // MARK: Własne wzory

    @Test("Własny wzór tematu i treści ma pierwszeństwo przed domyślnym")
    func customTemplateOverride() {
        let templates = EmailTemplates(custom: [
            EmailTemplate.storageKey(kind: .invoice, field: "subject", language: .polish):
                "Dokument {numer} od {sprzedawca}",
            EmailTemplate.storageKey(kind: .invoice, field: "body", language: .polish):
                "Cześć!\nKwota: {kwota}\nRachunek: {rachunek}.",
        ])
        let invoice = makeInvoice(paymentBankAccount: nil)
        let subject = InvoiceEmailComposer.subject(for: invoice, language: .polish, templates: templates)
        let body = InvoiceEmailComposer.body(for: invoice, language: .polish, templates: templates)
        #expect(subject == "Dokument FV/7/2026 od ACME Sp. z o.o.")
        #expect(body == "Cześć!\nKwota: 123.00 PLN")
    }

    @Test("Własny wzór dotyczy tylko wskazanego języka — angielski zostaje domyślny")
    func customTemplateOnlyForItsLanguage() {
        let templates = EmailTemplates(custom: [
            EmailTemplate.storageKey(kind: .invoice, field: "subject", language: .polish):
                "Własny {numer}",
        ])
        let english = InvoiceEmailComposer.subject(
            for: makeInvoice(), language: .english, templates: templates
        )
        #expect(english == "Invoice FV/7/2026 — ACME Sp. z o.o.")
    }

    @Test("Przypomnienie po terminie używa własnego wzoru z symbolem dni po terminie")
    func reminderTemplatesApplied() {
        let templates = EmailTemplates(custom: [
            EmailTemplate.storageKey(kind: .reminderOverdue, field: "subject", language: .polish):
                "Zaległość {numer} ({dni_po_terminie} dni)",
        ])
        let asOf = FA2Format.dateFormatter.date(from: "2026-07-20")!
        let invoice = makeInvoice()
        let contractor = Contractor()
        contractor.nip = "1111111111"
        contractor.email = "biuro@kontrahent.pl"
        let result = PaymentReminderEngine.candidates(
            invoices: [invoice],
            contractors: [contractor],
            settings: PaymentReminderSettings(),
            asOf: asOf,
            templates: templates
        )
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.subject == "Zaległość FV/7/2026 (5 dni)")
        // Treść bez własnego wzoru pozostaje domyślna.
        #expect(result.candidates.first?.body.contains("uprzejmie przypominamy") == true)
    }

    @Test("Domyślne treści przypomnień są zgodne z dotychczasowymi")
    func defaultReminderBodiesMatchLegacy() {
        let asOf = FA2Format.dateFormatter.date(from: "2026-07-20")!
        let overdue = PaymentReminderEngine.body(
            for: makeInvoice(), phase: .overdue, language: .polish, asOf: asOf
        )
        #expect(overdue.contains("upłynął 15 lipca 2026 (5 dni temu). Do zapłaty pozostaje 123.00 PLN."))
        #expect(overdue.contains("Prosimy o uregulowanie należności albo kontakt w sprawie płatności.\nNumer rachunku do wpłaty: 11222233334444555566667777."))
        #expect(overdue.contains("Jeżeli płatność została już zrealizowana"))

        let before = PaymentReminderEngine.body(
            for: makeInvoice(), phase: .beforeDue, language: .english, asOf: asOf
        )
        #expect(before.contains("is due for payment on 15 July 2026. The outstanding amount is 123.00 PLN."))
        #expect(before.contains("Kind regards\nACME Sp. z o.o."))
    }

    // MARK: Ustawienia i kopia zapasowa

    @Test("Zestaw szablonów wczytuje własne wzory z UserDefaults")
    func fromDefaultsReadsCustomTemplates() throws {
        let suiteName = "EmailTemplateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = EmailTemplate.storageKey(kind: .proforma, field: "body", language: .english)
        defaults.set("Custom {numer}", forKey: key)

        let templates = EmailTemplates.fromDefaults(defaults)
        #expect(templates.bodyTemplate(kind: .proforma, language: .english) == "Custom {numer}")
        // Pozostałe kombinacje wracają do wbudowanych wzorów.
        #expect(templates.bodyTemplate(kind: .proforma, language: .polish)
            == EmailTemplate.defaultBodyTemplate(kind: .proforma, language: .polish))
    }

    @Test("Klucze szablonów: 16 kombinacji, wszystkie w kopii zapasowej")
    func storageKeysInBackup() {
        #expect(EmailTemplate.allStorageKeys.count == 16)
        #expect(EmailTemplate.allStorageKeys.contains("email.template.invoice.subject.pl"))
        #expect(EmailTemplate.allStorageKeys.contains("email.template.reminderOverdue.body.en"))
        for key in EmailTemplate.allStorageKeys {
            #expect(BackupService.backedUpSettingsKeys.contains(key))
        }
    }
}
