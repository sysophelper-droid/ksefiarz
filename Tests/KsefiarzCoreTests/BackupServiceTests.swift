import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Kopia zapasowa danych")
struct BackupServiceTests {

    private func makeInvoiceWithDetails() -> Invoice {
        let invoice = makeTestInvoice(number: "FV/2026/06/001", isPaid: true, ksefId: "KSEF-B1")
        invoice.sellerAddress = "ul. Testowa 1, 00-001 Warszawa"
        invoice.paymentBankAccount = "11222233334444555566667777"
        invoice.paymentFormRaw = PaymentForm.transfer.rawValue
        invoice.rawXmlContent = "<Faktura/>"
        invoice.ksefSessionReference = "SESS-9"
        invoice.ksefInvoiceReference = "INV-REF-9"
        invoice.ksefSubmissionStatus = .accepted
        invoice.ksefStatusCode = 200
        invoice.ksefStatusDescription = "Przyjęta"
        invoice.ksefLastCheckedAt = Date(timeIntervalSince1970: 1_800_000_000)
        invoice.ksefAcceptedAt = Date(timeIntervalSince1970: 1_800_000_001)
        invoice.ksefEnvironmentRaw = KSeFEnvironment.test.rawValue
        invoice.upoXmlContent = "<UPO/>"
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa", unit: "godz.", quantity: 2, unitNetPrice: 50, netAmount: 100, vatRate: "23", vatAmount: 23),
        ]
        return invoice
    }

    @Test("Round-trip: eksport → import zachowuje wszystkie dane faktury")
    func roundTrip() throws {
        let invoice = makeInvoiceWithDetails()
        let settings = [AppSettingsKeys.nip: "1111111111", AppSettingsKeys.sellerName: "Moja Firma"]

        let data = try BackupService.makeBackup(invoices: [invoice], settings: settings)
        let decoded = try BackupService.decode(data)

        #expect(decoded.version == BackupService.currentVersion)
        #expect(decoded.settings == settings)
        #expect(decoded.invoices.count == 1)

        let entry = try #require(decoded.invoices.first)
        #expect(entry.id == invoice.id)
        #expect(entry.ksefId == "KSEF-B1")
        #expect(entry.invoiceNumber == "FV/2026/06/001")
        #expect(entry.isPaid)
        #expect(entry.sellerAddress == "ul. Testowa 1, 00-001 Warszawa")
        #expect(entry.paymentBankAccount == "11222233334444555566667777")
        #expect(entry.rawXmlContent == "<Faktura/>")
        #expect(entry.ksefSessionReference == "SESS-9")
        #expect(entry.ksefInvoiceReference == "INV-REF-9")
        #expect(entry.ksefSubmissionStatusRaw == KSeFSubmissionStatus.accepted.rawValue)
        #expect(entry.ksefStatusCode == 200)
        #expect(entry.ksefStatusDescription == "Przyjęta")
        #expect(entry.ksefEnvironmentRaw == KSeFEnvironment.test.rawValue)
        #expect(entry.upoXmlContent == "<UPO/>")
        #expect(entry.lines.count == 1)
        #expect(entry.lines.first?.name == "Usługa")

        // Odtworzony model ma te same wartości.
        let restored = BackupService.makeInvoice(from: entry)
        #expect(restored.id == invoice.id)
        #expect(restored.invoiceNumber == invoice.invoiceNumber)
        #expect(restored.isPaid == invoice.isPaid)
        #expect(restored.paymentForm == .transfer)
        #expect(restored.ksefInvoiceReference == "INV-REF-9")
        #expect(restored.ksefSubmissionStatus == .accepted)
        #expect(restored.ksefStatusCode == 200)
        #expect(restored.upoXmlContent == "<UPO/>")
        let restoredLines = BackupService.makeLines(for: entry)
        #expect(restoredLines.count == 1)
        #expect(restoredLines.first?.netAmount == 100)
    }

    @Test("Import pomija duplikaty po id oraz po numerze KSeF")
    func deduplication() throws {
        let original = makeInvoiceWithDetails()
        let data = try BackupService.makeBackup(invoices: [original], settings: [:])
        let backup = try BackupService.decode(data)

        // Identyczna faktura już w bazie (to samo id) → nic do importu.
        #expect(BackupService.invoicesToImport(from: backup, existing: [original]).isEmpty)

        // Inny lokalny id, ale ten sam numer KSeF → też duplikat.
        let sameKsef = makeTestInvoice(number: "INNY-NUMER", ksefId: "KSEF-B1")
        #expect(BackupService.invoicesToImport(from: backup, existing: [sameKsef]).isEmpty)

        // Ta sama referencja wysyłki również identyfikuje dokument, zanim
        // KSeF nada mu docelowy numer.
        let sameReference = makeTestInvoice(number: "JESZCZE-INNY")
        sameReference.ksefInvoiceReference = "INV-REF-9"
        #expect(BackupService.invoicesToImport(from: backup, existing: [sameReference]).isEmpty)

        // Pusta baza → import wszystkiego.
        #expect(BackupService.invoicesToImport(from: backup, existing: []).count == 1)
    }

    @Test("Kopia zachowuje kategorię kosztu i flagę dokumentów dwujęzycznych (wersja 6)")
    func versionSixFields() throws {
        let invoice = makeInvoiceWithDetails()
        invoice.costCategory = "Paliwo i transport"

        let contractor = Contractor()
        contractor.name = "Foreign Ltd."
        contractor.nip = "1111111111"
        contractor.prefersBilingualDocuments = true

        let data = try BackupService.makeBackup(
            invoices: [invoice], settings: [:], contractors: [contractor]
        )
        let decoded = try BackupService.decode(data)

        let entry = try #require(decoded.invoices.first)
        #expect(entry.costCategory == "Paliwo i transport")
        #expect(BackupService.makeInvoice(from: entry).costCategory == "Paliwo i transport")

        let contractorEntry = try #require(decoded.contractors?.first)
        #expect(contractorEntry.prefersBilingualDocuments == true)
        #expect(BackupService.makeContractor(from: contractorEntry).prefersBilingualDocuments)

        // Starsze kopie (bez pól wersji 6) odtwarzają wartości domyślne.
        let legacyInvoice = BackupService.makeInvoice(
            from: try #require(decoded.invoices.first.map { entry in
                var legacy = entry
                legacy.costCategory = nil
                return legacy
            })
        )
        #expect(legacyInvoice.costCategory == "")
    }

    @Test("Uszkodzony plik kopii jest odrzucany")
    func rejectsCorruptedFile() {
        #expect(throws: KSeFError.self) {
            _ = try BackupService.decode(Data("to nie json".utf8))
        }
    }

    @Test("Faktury lokalne (bez numeru KSeF) nie są błędnie deduplikowane")
    func localInvoicesNotDeduplicatedByNilKsef() throws {
        let localA = makeTestInvoice(number: "LOKALNA-A")
        let localB = makeTestInvoice(number: "LOKALNA-B")
        let data = try BackupService.makeBackup(invoices: [localA], settings: [:])
        let backup = try BackupService.decode(data)

        // Inna lokalna faktura bez ksefId nie blokuje importu (nil ≠ nil).
        #expect(BackupService.invoicesToImport(from: backup, existing: [localB]).count == 1)
    }
}
