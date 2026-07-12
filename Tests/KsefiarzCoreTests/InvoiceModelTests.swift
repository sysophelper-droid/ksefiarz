import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

/// Fabryka faktur testowych.
func makeTestInvoice(
    number: String = "FV/1",
    kind: Invoice.Kind = .purchase,
    isPaid: Bool = false,
    isHidden: Bool = false,
    gross: Double = 123.0,
    dueDate: Date? = nil,
    sellerName: String = "Dostawca Sp. z o.o.",
    sellerNIP: String = "5260250274",
    buyerName: String = "Moja Firma",
    buyerNIP: String = "1111111111",
    ksefId: String? = nil
) -> Invoice {
    Invoice(
        ksefId: ksefId,
        invoiceNumber: number,
        issueDate: .now,
        sellerName: sellerName,
        sellerNIP: sellerNIP,
        buyerName: buyerName,
        buyerNIP: buyerNIP,
        netAmount: gross / 1.23,
        vatAmount: gross - gross / 1.23,
        grossAmount: gross,
        isPaid: isPaid,
        paymentDueDate: dueDate,
        isArchivedOrHidden: isHidden,
        kind: kind
    )
}

@Suite("Model Invoice — SwiftData")
struct InvoiceModelTests {

    /// Tworzy świeży kontekst SwiftData w pamięci (bez zapisu na dysk).
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Invoice.self, configurations: configuration)
        return ModelContext(container)
    }

    @Test("Nowa faktura ma domyślnie status nieopłaconej i nieukrytej")
    func defaults() {
        let invoice = makeTestInvoice()
        #expect(invoice.isPaid == false)
        #expect(invoice.isArchivedOrHidden == false)
        #expect(invoice.ksefId == nil)
        #expect(invoice.isExcludedFromKPiR == false)
        #expect(invoice.kpirColumnRaw.isEmpty)
        #expect(invoice.kpirEventDate == nil)
        #expect(invoice.kpirAmountOverride == nil)
        #expect(invoice.kpirResearchDevelopmentCost == 0)
    }

    @Test("Zapis i odczyt faktury z bazy zachowuje wszystkie pola")
    func persistence() throws {
        let context = try makeContext()
        let invoice = makeTestInvoice(number: "FV/2026/06/007", ksefId: "KSEF-7")
        invoice.ksefSessionReference = "SESS-7"
        invoice.ksefInvoiceReference = "INV-7"
        invoice.ksefSubmissionStatus = .accepted
        invoice.ksefStatusCode = 200
        invoice.ksefStatusDescription = "Przyjęta"
        invoice.ksefEnvironmentRaw = KSeFEnvironment.production.rawValue
        invoice.upoXmlContent = "<UPO/>"
        invoice.kpirColumnRaw = KPiRColumn.goodsAndMaterials.rawValue
        invoice.isExcludedFromKPiR = true
        invoice.kpirEventDate = Date(timeIntervalSince1970: 1_800_100_000)
        invoice.kpirDescription = "Zakup materiałów"
        invoice.kpirNotes = "KPiR"
        invoice.kpirAmountOverride = 90
        invoice.kpirResearchDevelopmentCost = 25
        context.insert(invoice)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Invoice>())
        #expect(fetched.count == 1)
        let saved = try #require(fetched.first)
        #expect(saved.invoiceNumber == "FV/2026/06/007")
        #expect(saved.ksefId == "KSEF-7")
        #expect(saved.ksefInvoiceReference == "INV-7")
        #expect(saved.ksefSubmissionStatus == .accepted)
        #expect(saved.ksefStatusCode == 200)
        #expect(saved.ksefEnvironmentRaw == KSeFEnvironment.production.rawValue)
        #expect(saved.upoXmlContent == "<UPO/>")
        #expect(saved.kpirColumnRaw == KPiRColumn.goodsAndMaterials.rawValue)
        #expect(saved.isExcludedFromKPiR)
        #expect(saved.kpirEventDate == invoice.kpirEventDate)
        #expect(saved.kpirDescription == "Zakup materiałów")
        #expect(saved.kpirNotes == "KPiR")
        #expect(saved.kpirAmountOverride == 90)
        #expect(saved.kpirResearchDevelopmentCost == 25)
        #expect(saved.sellerNIP == "5260250274")
        #expect(abs(saved.grossAmount - 123.0) < 0.001)
    }

    @Test("Predykat list pomija faktury ukryte i innego rodzaju")
    func visibilityPredicate() throws {
        let context = try makeContext()
        context.insert(makeTestInvoice(number: "ZAKUP-WIDOCZNA", kind: .purchase))
        context.insert(makeTestInvoice(number: "ZAKUP-UKRYTA", kind: .purchase, isHidden: true))
        context.insert(makeTestInvoice(number: "SPRZEDAZ", kind: .sales))
        try context.save()

        // Ten sam predykat, którego używa InvoiceListView dla zakupów.
        let raw = Invoice.Kind.purchase.rawValue
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.kindRaw == raw && $0.isArchivedOrHidden == false }
        )
        let visible = try context.fetch(descriptor)

        #expect(visible.count == 1)
        #expect(visible.first?.invoiceNumber == "ZAKUP-WIDOCZNA")
    }

    @Test("Ukrycie faktury przenosi ją do sekcji ukrytych")
    func hideInvoice() throws {
        let context = try makeContext()
        let invoice = makeTestInvoice(number: "PODEJRZANA")
        context.insert(invoice)
        try context.save()

        // Użytkownik klika „Ukryj (nieuprawniona)”.
        invoice.isArchivedOrHidden = true
        try context.save()

        let hidden = try context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.isArchivedOrHidden == true })
        )
        let visible = try context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.isArchivedOrHidden == false })
        )
        #expect(hidden.count == 1)
        #expect(hidden.first?.invoiceNumber == "PODEJRZANA")
        #expect(visible.isEmpty)
    }

    @Test("Zmiana statusu opłacenia jest trwała")
    func togglePaid() throws {
        let context = try makeContext()
        let invoice = makeTestInvoice()
        context.insert(invoice)
        try context.save()

        invoice.isPaid = true
        try context.save()

        let paid = try context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.isPaid == true })
        )
        #expect(paid.count == 1)
    }

    @Test("Wykrywanie zaległości względem terminu płatności")
    func overdueDetection() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!

        // Po terminie i nieopłacona — zaległa.
        #expect(makeTestInvoice(dueDate: yesterday).isOverdue(asOf: now))
        // Przed terminem — nie jest zaległa.
        #expect(!makeTestInvoice(dueDate: tomorrow).isOverdue(asOf: now))
        // Opłacona — nigdy nie jest zaległa.
        #expect(!makeTestInvoice(isPaid: true, dueDate: yesterday).isOverdue(asOf: now))
        // Bez terminu — nie jest zaległa.
        #expect(!makeTestInvoice().isOverdue(asOf: now))
    }

    @Test("Mapowanie danych FA(2) na model Invoice")
    func mappingFromFA2Data() {
        let data = FA2InvoiceData(
            ksefId: "KSEF-42",
            invoiceNumber: "ZK/42",
            issueDate: .now,
            sellerName: "Dostawca",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Dostawcza 7, 00-950 Warszawa",
            buyerName: "My",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Własna 12",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            paymentDueDate: nil,
            paymentForm: "6",
            paymentBankAccount: "11222233334444555566667777",
            rawXML: "<Faktura/>"
        )
        let invoice = Invoice(from: data, kind: .purchase)

        #expect(invoice.ksefId == "KSEF-42")
        #expect(invoice.invoiceNumber == "ZK/42")
        #expect(invoice.kind == .purchase)
        #expect(invoice.rawXmlContent == "<Faktura/>")
        #expect(invoice.isPaid == false)
        #expect(invoice.isArchivedOrHidden == false)
        #expect(invoice.sellerAddress == "ul. Dostawcza 7, 00-950 Warszawa")
        #expect(invoice.buyerAddress == "ul. Własna 12")
        #expect(invoice.paymentForm == .transfer)
        #expect(invoice.paymentBankAccount == "11222233334444555566667777")
    }

    @Test("Znacznik Zaplacono z FA(2) ustawia status opłacenia")
    func paidMarkerSetsStatus() {
        let data = FA2InvoiceData(
            ksefId: "KSEF-43",
            invoiceNumber: "ZK/43",
            issueDate: .now,
            sellerName: "Dostawca",
            sellerNIP: "5260250274",
            buyerName: "My",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            isPaidMarker: true
        )
        #expect(Invoice(from: data, kind: .purchase).isPaid)
    }

    @Test("Pozycje faktury są zapisywane i odczytywane przez relację")
    func linesPersistence() throws {
        let context = try makeContext()
        let invoice = makeTestInvoice(number: "FV/Z-POZYCJAMI")
        context.insert(invoice)
        invoice.lines = [
            InvoiceLine(index: 2, name: "Druga", quantity: 1, unitNetPrice: 50, netAmount: 50, vatRate: "8", vatAmount: 4),
            InvoiceLine(index: 1, name: "Pierwsza", quantity: 2, unitNetPrice: 100, netAmount: 200, vatRate: "23", vatAmount: 46),
        ]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Invoice>())
        let saved = try #require(fetched.first)
        #expect(saved.lines.count == 2)
        // sortedLines porządkuje po numerze wiersza.
        #expect(saved.sortedLines.map(\.name) == ["Pierwsza", "Druga"])
        #expect(saved.sortedLines.first?.vatRate == "23")
    }

    @Test("applyDetails uzupełnia szczegóły, nie cofając decyzji użytkownika")
    func applyDetailsPreservesUserDecisions() throws {
        let context = try makeContext()
        // Faktura zaimportowana wcześniej bez szczegółów, ręcznie opłacona i ukryta.
        let invoice = makeTestInvoice(number: "FV/STARA", isPaid: true, isHidden: true, ksefId: "KSEF-1")
        context.insert(invoice)
        try context.save()

        let details = FA2InvoiceData(
            ksefId: "KSEF-1",
            invoiceNumber: "FV/STARA",
            issueDate: .now,
            sellerName: "Dostawca",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Nowa 1",
            buyerName: "My",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            paymentBankAccount: "112222333344445555666677",
            isPaidMarker: false, // brak znacznika nie może cofnąć ręcznego „opłacona"
            lines: [FA2InvoiceLine(index: 1, name: "Pozycja", netAmount: 100, vatRate: "23", vatAmount: 23)],
            rawXML: "<Faktura/>"
        )
        invoice.applyDetails(from: details)
        try context.save()

        #expect(invoice.isPaid == true)
        #expect(invoice.isArchivedOrHidden == true)
        #expect(invoice.sellerAddress == "ul. Nowa 1")
        #expect(invoice.paymentBankAccount == "112222333344445555666677")
        #expect(invoice.lines.count == 1)
        #expect(invoice.rawXmlContent == "<Faktura/>")
    }
}
