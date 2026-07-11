import Foundation

public enum InvoiceAutomationEngine {
    /// Duplikat nie dziedziczy numeru, korekty ani urzędowych identyfikatorów.
    public static func duplicate(
        _ invoice: Invoice,
        issueDate: Date = .now,
        dueDays: Int? = nil
    ) -> InvoiceDraft {
        let original = InvoiceDraft(from: invoice)
        let days = dueDays ?? invoice.paymentDueDate.map {
            max(0, Calendar.current.dateComponents([.day], from: invoice.issueDate, to: $0).day ?? 14)
        } ?? 14
        return InvoicePreset(draft: original).draft(issueDate: issueDate, dueDays: days)
    }

    public static func isDue(_ schedule: RecurringInvoice, asOf date: Date = .now) -> Bool {
        schedule.isActive && schedule.nextIssueDate <= date
    }

    public static func draft(for schedule: RecurringInvoice, invoiceNumber: String = "") -> InvoiceDraft? {
        schedule.preset?.draft(invoiceNumber: invoiceNumber,
                               issueDate: schedule.nextIssueDate,
                               dueDays: schedule.dueDays)
    }

    /// Przesuwa dokładnie o jeden okres dopiero po zatwierdzeniu dokumentu.
    public static func markApproved(_ schedule: RecurringInvoice, at date: Date = .now) {
        schedule.lastApprovedAt = date
        schedule.nextIssueDate = Calendar.current.date(
            byAdding: schedule.unit.calendarComponent,
            value: max(1, schedule.recurrenceInterval),
            to: schedule.nextIssueDate
        ) ?? schedule.nextIssueDate
    }
}
