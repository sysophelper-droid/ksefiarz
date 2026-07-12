import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

private func date(_ string: String, hour: Int = 12) -> Date {
    FA2Format.dateFormatter.date(from: string)!.addingTimeInterval(Double(hour) * 3600)
}

private func makeInvoice(
    number: String = "FV/1",
    issue: String = "2026-07-14",
    kind: Invoice.Kind = .sales,
    due: String? = nil,
    isPaid: Bool = false,
    hidden: Bool = false,
    offline: Bool = false,
    offlineReason: Invoice.OfflineReason = .offline24
) -> Invoice {
    let invoice = Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: issue)!,
        sellerName: "Sprzedawca", sellerNIP: "9999999999",
        buyerName: "Nabywca", buyerNIP: "1111111111",
        netAmount: 100, vatAmount: 23, grossAmount: 123,
        isPaid: isPaid,
        paymentDueDate: due.flatMap { FA2Format.dateFormatter.date(from: $0) },
        isArchivedOrHidden: hidden,
        rawXmlContent: offline ? "<Faktura/>" : nil,
        ksefSubmissionStatus: offline ? .offlinePending : nil,
        kind: kind
    )
    if offline {
        invoice.isOfflineMode = true
        invoice.offlineReason = offlineReason
    }
    return invoice
}

// MARK: - Tryby offline i terminy dosłań

@Suite("Tryby offline KSeF — terminy dosłań (offline24 / niedostępność / awaria)")
struct OfflineModesTests {

    @Test("7. dzień roboczy po zakończeniu awarii — przykład z dokumentacji CIRFMF")
    func sevenBusinessDaysDocExample() {
        // Awaria usunięta w sobotę 2025-07-12 → termin 2025-07-22 (wtorek).
        let deadline = PolishBusinessCalendar.endOfBusinessDay(
            after: date("2025-07-12"), businessDays: 7
        )
        let components = PolishBusinessCalendar.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: deadline
        )
        #expect(components == DateComponents(
            year: 2025, month: 7, day: 22, hour: 23, minute: 59, second: 59
        ))
    }

    @Test("Offline24: termin to następny dzień roboczy po dacie wystawienia")
    func offline24Deadline() {
        let invoice = makeInvoice(issue: "2026-07-10", offline: true) // piątek
        let day = invoice.offlineSendDeadline.map {
            PolishBusinessCalendar.calendar.dateComponents([.month, .day], from: $0)
        }
        #expect(day == DateComponents(month: 7, day: 13)) // poniedziałek
    }

    @Test("Niedostępność: bez daty zakończenia termin nieznany; po dacie — następny dzień roboczy")
    func unavailabilityDeadline() {
        let invoice = makeInvoice(issue: "2026-07-10", offline: true, offlineReason: .unavailability)
        #expect(invoice.offlineSendDeadline == nil) // zdarzenie trwa

        invoice.offlineEventEndedAt = date("2026-07-10") // koniec w piątek
        let day = invoice.offlineSendDeadline.map {
            PolishBusinessCalendar.calendar.dateComponents([.month, .day], from: $0)
        }
        #expect(day == DateComponents(month: 7, day: 13)) // poniedziałek
    }

    @Test("Awaria: 7 dni roboczych od zakończenia; przed komunikatem termin nieznany")
    func failureDeadline() {
        let invoice = makeInvoice(issue: "2025-07-08", offline: true, offlineReason: .failure)
        #expect(invoice.offlineSendDeadline == nil)

        invoice.offlineEventEndedAt = date("2025-07-12")
        let day = invoice.offlineSendDeadline.map {
            PolishBusinessCalendar.calendar.dateComponents([.year, .month, .day], from: $0)
        }
        #expect(day == DateComponents(year: 2025, month: 7, day: 22))
    }

    @Test("Dokumenty sprzed migracji (puste pole) są traktowane jako offline24")
    func legacyReason() {
        let invoice = makeInvoice(offline: true)
        invoice.offlineReasonRaw = ""
        #expect(invoice.offlineReason == .offline24)
        #expect(invoice.offlineSendDeadline != nil)
    }
}

// MARK: - Powiadomienia o terminach

@Suite("Powiadomienia o terminach — płatności i dosłania offline")
struct DeadlineNotificationEngineTests {

    /// Środa 2026-07-15, południe.
    private let now = date("2026-07-15")

    @Test("Termin płatności dziś i jutro daje powiadomienie; dalszy lub opłacony — nie")
    func paymentDueNotifications() {
        let dueToday = makeInvoice(number: "FV/DZIS", due: "2026-07-15")
        let dueTomorrow = makeInvoice(number: "FV/JUTRO", kind: .purchase, due: "2026-07-16")
        let dueLater = makeInvoice(number: "FV/POZNIEJ", due: "2026-07-20")
        let paid = makeInvoice(number: "FV/OPLACONA", due: "2026-07-15", isPaid: true)
        let hidden = makeInvoice(number: "FV/UKRYTA", due: "2026-07-15", hidden: true)

        let notifications = DeadlineNotificationEngine.pending(
            invoices: [dueToday, dueTomorrow, dueLater, paid, hidden], now: now
        )
        #expect(notifications.count == 2)
        #expect(notifications.contains { $0.title == "Termin płatności dziś" && $0.body.contains("FV/DZIS") })
        #expect(notifications.contains { $0.title == "Termin płatności jutro" && $0.body.contains("FV/JUTRO") })
        // Zobowiązanie (zakup) opisane właściwą rolą.
        #expect(notifications.first { $0.body.contains("FV/JUTRO") }?.body.contains("Zobowiązanie") == true)
    }

    @Test("Doręczone powiadomienie nie wraca tego samego dnia (deduplikacja)")
    func deduplication() {
        let invoice = makeInvoice(number: "FV/DZIS", due: "2026-07-15")
        let first = DeadlineNotificationEngine.pending(invoices: [invoice], now: now)
        #expect(first.count == 1)

        let delivered = Set(first.map(\.key))
        let second = DeadlineNotificationEngine.pending(
            invoices: [invoice], now: now, alreadyDelivered: delivered
        )
        #expect(second.isEmpty)
    }

    @Test("Termin dosłania offline dziś lub po terminie daje powiadomienie")
    func offlineDeadlineNotifications() {
        // Offline24 wystawiona we wtorek 14.07 → termin: środa 15.07 (dziś).
        let deadlineToday = makeInvoice(number: "FV/OFF-DZIS", issue: "2026-07-14", offline: true)
        // Wystawiona w piątek 10.07 → termin: poniedziałek 13.07 (po terminie).
        let overdue = makeInvoice(number: "FV/OFF-PO", issue: "2026-07-10", offline: true)
        // Awaria bez daty zakończenia — termin nieznany, bez powiadomienia.
        let unknown = makeInvoice(number: "FV/OFF-AWARIA", issue: "2026-07-10",
                                  offline: true, offlineReason: .failure)

        let notifications = DeadlineNotificationEngine.pending(
            invoices: [deadlineToday, overdue, unknown], now: now
        )
        #expect(notifications.count == 2)
        #expect(notifications.contains {
            $0.title == "Dziś mija termin dosłania do KSeF" && $0.body.contains("FV/OFF-DZIS")
        })
        #expect(notifications.contains {
            $0.title == "Po terminie dosłania do KSeF!" && $0.body.contains("FV/OFF-PO")
        })
    }

    @Test("Przycinanie pamięci doręczeń zostawia tylko ostatnie 14 dni")
    func pruneDelivered() {
        let recent = "due|AAA|2026-07-14"
        let old = "due|BBB|2026-06-01"
        let malformed = "śmieć"
        let pruned = DeadlineNotificationEngine.prune(
            delivered: [recent, old, malformed], now: now
        )
        #expect(pruned == [recent])
    }
}
