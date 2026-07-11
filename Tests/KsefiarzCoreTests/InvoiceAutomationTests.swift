import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Szablony i automatyzacja wystawiania")
struct InvoiceAutomationTests {
    private func date(_ value: String) -> Date {
        FA2Format.dateFormatter.date(from: value)!
    }

    private func sampleDraft(issueDate: Date? = nil) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "FV/2026/077",
            issueDate: issueDate ?? date("2026-06-10"),
            sellerName: "Moja Firma", sellerNIP: "1111111111",
            sellerAddress: "ul. Własna 1",
            buyerName: "Stały Klient", buyerNIP: "5260250274",
            buyerAddress: "ul. Klienta 2",
            lines: [InvoiceLineDraft(name: "Abonament", unit: "mies.", quantity: 1,
                                     unitNetPrice: 200, vatRate: .standard,
                                     cnPkwiu: "62.01.11.0", gtu: "GTU_12")],
            paymentDueDate: date("2026-06-24"), paymentForm: .transfer,
            paymentBankAccount: "11222233334444555566667777",
            notes: "Umowa A", currency: "EUR", exchangeRate: 4.25,
            splitPayment: true, saleDate: date("2026-06-10")
        )
    }

    @Test("Szablon zachowuje dane handlowe, ale nadaje nowy numer i daty")
    func presetRoundTrip() {
        let preset = InvoicePreset(draft: sampleDraft())
        let newDate = date("2026-07-01")
        let restored = preset.draft(issueDate: newDate, dueDays: 21)

        #expect(restored.invoiceNumber.isEmpty)
        #expect(restored.issueDate == newDate)
        #expect(restored.paymentDueDate == date("2026-07-22"))
        #expect(restored.saleDate == newDate)
        #expect(restored.buyerName == "Stały Klient")
        #expect(restored.lines.first?.name == "Abonament")
        #expect(restored.lines.first?.cnPkwiu == "62.01.11.0")
        #expect(restored.currency == "EUR")
        #expect(restored.splitPayment)
        #expect(restored.correction == nil)
    }

    @Test("Duplikat faktury nie dziedziczy numeru ani korekty")
    func duplicateResetsIdentity() {
        let invoice = makeTestInvoice(number: "KOR/77", kind: .sales)
        invoice.documentTypeRaw = "KOR"
        invoice.correctedInvoiceNumber = "FV/70"
        invoice.issueDate = date("2026-06-10")
        invoice.paymentDueDate = date("2026-06-24")
        invoice.lines = [InvoiceLine(index: 1, name: "Usługa", quantity: 1,
                                     unitNetPrice: 100, netAmount: 100,
                                     vatRate: "23", vatAmount: 23)]

        let duplicated = InvoiceAutomationEngine.duplicate(invoice, issueDate: date("2026-07-05"))
        #expect(duplicated.invoiceNumber.isEmpty)
        #expect(duplicated.correction == nil)
        #expect(duplicated.invoiceType == "VAT")
        #expect(duplicated.paymentDueDate == date("2026-07-19"))
        #expect(duplicated.lines.count == 1)
    }

    @Test("Nieaktywny harmonogram nie oczekuje na zatwierdzenie")
    func inactiveIsNotDue() {
        let schedule = RecurringInvoice(name: "Abonament", preset: InvoicePreset(draft: sampleDraft()),
                                        nextIssueDate: date("2026-07-01"), isActive: false)
        #expect(!InvoiceAutomationEngine.isDue(schedule, asOf: date("2026-07-10")))
        schedule.isActive = true
        #expect(InvoiceAutomationEngine.isDue(schedule, asOf: date("2026-07-10")))
        #expect(!InvoiceAutomationEngine.isDue(schedule, asOf: date("2026-06-30")))
    }

    @Test("Zatwierdzenie przesuwa miesięczny termin tylko o jeden okres")
    func approvalAdvancesSchedule() {
        let schedule = RecurringInvoice(name: "Abonament", preset: InvoicePreset(draft: sampleDraft()),
                                        unit: .month, interval: 1,
                                        nextIssueDate: date("2026-01-31"), dueDays: 7)
        let prepared = InvoiceAutomationEngine.draft(for: schedule)
        #expect(prepared?.issueDate == date("2026-01-31"))
        #expect(prepared?.paymentDueDate == date("2026-02-07"))

        InvoiceAutomationEngine.markApproved(schedule, at: date("2026-02-03"))
        #expect(schedule.lastApprovedAt == date("2026-02-03"))
        #expect(schedule.nextIssueDate == date("2026-02-28"))
    }

    @Test("Szablon i harmonogram są trwale zapisywane w SwiftData")
    func persistence() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: InvoiceTemplate.self, RecurringInvoice.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let preset = InvoicePreset(draft: sampleDraft())
        context.insert(InvoiceTemplate(name: "Stała obsługa", preset: preset))
        context.insert(RecurringInvoice(name: "Co miesiąc", preset: preset,
                                        nextIssueDate: date("2026-08-01")))
        try context.save()

        let templates = try context.fetch(FetchDescriptor<InvoiceTemplate>())
        let schedules = try context.fetch(FetchDescriptor<RecurringInvoice>())
        #expect(templates.first?.preset?.buyerNIP == "5260250274")
        #expect(schedules.first?.preset?.lines.first?.name == "Abonament")
        #expect(schedules.first?.unit == .month)
    }

    @Test("Kopia zapasowa zachowuje szablony i harmonogramy")
    func backupRoundTrip() throws {
        let preset = InvoicePreset(draft: sampleDraft())
        let template = InvoiceTemplate(name: "Stała obsługa", preset: preset)
        let schedule = RecurringInvoice(name: "Co miesiąc", preset: preset,
                                        nextIssueDate: date("2026-08-01"))
        let data = try BackupService.makeBackup(invoices: [], settings: [:],
                                                invoiceTemplates: [template],
                                                recurringInvoices: [schedule])
        let backup = try BackupService.decode(data)
        let restoredTemplate = try #require(
            backup.invoiceTemplates?.first.flatMap(BackupService.makeTemplate(from:))
        )
        let restoredSchedule = try #require(
            backup.recurringInvoices?.first.flatMap(BackupService.makeSchedule(from:))
        )
        #expect(restoredTemplate.name == "Stała obsługa")
        #expect(restoredTemplate.preset?.buyerName == "Stały Klient")
        #expect(restoredSchedule.nextIssueDate == date("2026-08-01"))
        #expect(restoredSchedule.preset?.lines.count == 1)
    }
}
