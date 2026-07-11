import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Silnik synchronizacji — scalanie faktur z KSeF")
@MainActor
struct InvoiceSyncEngineTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Invoice.self, configurations: configuration)
        return ModelContext(container)
    }

    private func makeData(ksefId: String, number: String = "F/1/2026") -> FA2InvoiceData {
        FA2InvoiceData(
            ksefId: ksefId,
            invoiceNumber: number,
            issueDate: .now,
            sellerName: "Sprzedawca",
            sellerNIP: "9999999999",
            sellerAddress: "Adres 1",
            buyerName: "Nabywca",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            lines: [FA2InvoiceLine(index: 1, name: "Pozycja", netAmount: 100)],
            rawXML: "<Faktura/>"
        )
    }

    @Test("Nowa faktura jest wstawiana wraz z pozycjami i zapisywana")
    func wstawianieNowej() throws {
        let context = try makeContext()

        try InvoiceSyncEngine.merge(
            [makeData(ksefId: "KSEF-1")], kind: .purchase, prepaidForms: [], context: context
        )

        let saved = try context.fetch(FetchDescriptor<Invoice>())
        #expect(saved.count == 1)
        #expect(saved.first?.ksefId == "KSEF-1")
        #expect(saved.first?.lines.count == 1)
        #expect(context.hasChanges == false) // jawny zapis wykonany
    }

    @Test("Duplikat po ksefId nie tworzy drugiej faktury, tylko uzupełnia szczegóły")
    func deduplikacja() throws {
        let context = try makeContext()
        let existing = Invoice(
            ksefId: "KSEF-1", invoiceNumber: "F/1/2026", issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123, kind: .purchase
        )
        context.insert(existing)

        try InvoiceSyncEngine.merge(
            [makeData(ksefId: "KSEF-1")], kind: .purchase, prepaidForms: [], context: context
        )

        let saved = try context.fetch(FetchDescriptor<Invoice>())
        #expect(saved.count == 1)
        #expect(saved.first?.sellerAddress == "Adres 1") // szczegóły uzupełnione
    }

    @Test("Faktura oczekująca jest scalana po numerze dokumentu po nadaniu numeru KSeF")
    func oczekujacaNieTworzyDuplikatu() throws {
        let context = try makeContext()
        let pending = Invoice(
            invoiceNumber: "F/1/2026", issueDate: .now,
            sellerName: "Sprzedawca", sellerNIP: "9999999999",
            buyerName: "Nabywca", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            ksefSessionReference: "SESS-1",
            ksefInvoiceReference: "INV-1",
            ksefSubmissionStatus: .processing,
            kind: .sales
        )
        context.insert(pending)

        try InvoiceSyncEngine.merge(
            [makeData(ksefId: "KSEF-FINAL", number: "F/1/2026")],
            kind: .sales,
            prepaidForms: [],
            context: context
        )

        let saved = try context.fetch(FetchDescriptor<Invoice>())
        #expect(saved.count == 1)
        #expect(saved.first?.id == pending.id)
        #expect(saved.first?.ksefId == "KSEF-FINAL")
        #expect(saved.first?.ksefSubmissionStatus == .accepted)
    }

    @Test("Ukryta faktura nie wraca przy synchronizacji (niezmiennik nr 2)")
    func ukrytaNieWraca() throws {
        let context = try makeContext()
        let hidden = Invoice(
            ksefId: "KSEF-UKRYTA", invoiceNumber: "F/6/2026", issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 1, vatAmount: 0, grossAmount: 1,
            isArchivedOrHidden: true, kind: .purchase
        )
        context.insert(hidden)

        try InvoiceSyncEngine.merge(
            [makeData(ksefId: "KSEF-UKRYTA")], kind: .purchase, prepaidForms: [], context: context
        )

        let saved = try context.fetch(FetchDescriptor<Invoice>())
        #expect(saved.count == 1)
        #expect(saved.first?.isArchivedOrHidden == true)
    }

    @Test("Ręczny status „Opłacona” nie jest cofany przez synchronizację (niezmiennik nr 1)")
    func isPaidNieCofane() throws {
        let context = try makeContext()
        let paid = Invoice(
            ksefId: "KSEF-1", invoiceNumber: "F/1/2026", issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            isPaid: true, kind: .purchase
        )
        context.insert(paid)

        // Dokument z KSeF bez znacznika „Zaplacono”.
        try InvoiceSyncEngine.merge(
            [makeData(ksefId: "KSEF-1")], kind: .purchase, prepaidForms: [], context: context
        )

        #expect(try context.fetch(FetchDescriptor<Invoice>()).first?.isPaid == true)
    }
}
