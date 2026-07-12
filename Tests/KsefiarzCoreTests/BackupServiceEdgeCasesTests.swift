import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

/// Testy domykające pokrycie usług kopii zapasowej: budowa kopii wprost
/// z kontekstu SwiftData, odtwarzanie słowników (towary, rachunki) oraz
/// filtry importu szablonów i harmonogramów. Uzupełniają
/// `BackupServiceTests` o rzadziej odwiedzane gałęzie.
@Suite("Kopia zapasowa — przypadki brzegowe i słowniki")
struct BackupServiceEdgeCasesTests {

    // MARK: Pomocnicze

    /// Kontener SwiftData w pamięci z pełnym schematem aplikacji — pozwala
    /// wykonać wszystkie `fetch` z `makeCurrentBackup` bez dotykania dysku
    /// ani prawdziwej bazy użytkownika.
    private func makeInMemoryContext_backup() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, PaymentRecord.self, Contractor.self, Product.self,
            BankAccount.self, InvoiceTemplate.self, RecurringInvoice.self, SyncRun.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    /// Minimalny szablon danych handlowych — do budowy istniejących modeli
    /// szablonu/harmonogramu w testach filtrów importu.
    private func samplePreset_backup() -> InvoicePreset {
        InvoicePreset(draft: InvoiceDraft(
            invoiceNumber: "", issueDate: .now,
            sellerName: "Moja Firma", sellerNIP: "1111111111",
            buyerName: "Klient", buyerNIP: "5260250274"
        ))
    }

    /// Wpis towaru w kopii z rozpoznawalnymi wartościami wszystkich pól.
    private func sampleBackupProduct_backup(
        id: UUID = UUID(), name: String = "Router XR"
    ) -> BackupProduct {
        BackupProduct(
            id: id,
            name: name,
            typeRaw: Product.ProductType.goods.rawValue,
            unit: "szt.",
            category: "Sieć",
            sku: "RTR-001",
            brand: "Acme",
            ean: "5901234567890",
            cnPkwiu: "8517.62.00",
            gtu: "GTU_07",
            isAttachment15: true,
            basePriceNet: 499.90,
            basePriceVatRateRaw: "23",
            purchasePriceNet: 320.00,
            purchasePriceVatRateRaw: "23"
        )
    }

    /// Wpis rachunku bankowego w kopii z rozpoznawalnymi wartościami pól.
    private func sampleBackupBankAccount_backup(
        id: UUID = UUID(), number: String = "11222233334444555566667777"
    ) -> BackupBankAccount {
        BackupBankAccount(
            id: id,
            label: "Firmowy PLN",
            accountNumber: number,
            bankName: "Bank Testowy",
            swift: "TESTPLPW",
            currency: "PLN",
            vatAccountNumber: "99888877776666555544443333"
        )
    }

    // MARK: makeCurrentBackup

    @Test("makeCurrentBackup buduje kopię wprost z kontekstu SwiftData")
    @MainActor
    func makeCurrentBackupZKontekstu() throws {
        // Jeden klucz ustawień z niepustą wartością wymusza gałąź zapisu
        // ustawień do kopii (makeCurrentBackup czyta UserDefaults.standard,
        // więc nie da się tu użyć suiteName). Pracujemy na domenie procesu
        // testowego (NIE na domenie aplikacji pl.itkrak.ksefiarz) i cofamy
        // zmianę w defer, żeby nie zostawić śladu.
        let settingsKey = AppSettingsKeys.sellerName
        let previousValue = UserDefaults.standard.string(forKey: settingsKey)
        let brandingKey = AppSettingsKeys.pdfBrandingEnabled
        let previousBrandingValue = UserDefaults.standard.object(forKey: brandingKey)
        UserDefaults.standard.set("Firma Edge Sp. z o.o.", forKey: settingsKey)
        UserDefaults.standard.set(true, forKey: brandingKey)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: settingsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingsKey)
            }
            if let previousBrandingValue {
                UserDefaults.standard.set(previousBrandingValue, forKey: brandingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: brandingKey)
            }
        }

        let context = try makeInMemoryContext_backup()

        // Do bazy trafiają obiekty z różnych słowników, żeby wszystkie
        // `fetch` w makeCurrentBackup zwróciły niepuste kolekcje.
        let invoice = makeTestInvoice(number: "FV/EDGE/1", ksefId: "KSEF-EDGE-1")
        context.insert(invoice)
        // Pozycje przypisujemy PO wstawieniu (relacja SwiftData — niezmiennik #5).
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa", unit: "godz.", quantity: 1,
                        unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23),
        ]

        let contractor = Contractor()
        contractor.name = "Kontrahent Edge"
        contractor.nip = "5260250274"
        context.insert(contractor)

        let product = Product()
        product.name = "Towar Edge"
        context.insert(product)

        let account = BankAccount()
        account.accountNumber = "11112222333344445555666677"
        context.insert(account)
        try context.save()

        let data = try BackupService.makeCurrentBackup(context: context)
        let decoded = try BackupService.decode(data)

        #expect(decoded.version == BackupService.currentVersion)
        // Niepusta wartość ustawienia trafiła do kopii (gałąź true pętli).
        #expect(decoded.settings[settingsKey] == "Firma Edge Sp. z o.o.")
        #expect(decoded.settings[brandingKey] != nil)
        #expect(decoded.invoices.count == 1)
        #expect(decoded.invoices.first?.ksefId == "KSEF-EDGE-1")
        #expect(decoded.contractors?.count == 1)
        #expect(decoded.products?.count == 1)
        #expect(decoded.bankAccounts?.count == 1)
        // Szablonów i harmonogramów nie dodawaliśmy — puste, ale obecne kolekcje.
        #expect(decoded.invoiceTemplates?.isEmpty == true)
        #expect(decoded.recurringInvoices?.isEmpty == true)
    }

    // MARK: Odtwarzanie słowników

    @Test("makeProduct odtwarza wszystkie pola towaru ze słownika kopii")
    func makeProductOdtwarzaTowar() {
        let id = UUID()
        let entry = sampleBackupProduct_backup(id: id, name: "Router XR")

        let product = BackupService.makeProduct(from: entry)

        #expect(product.id == id)
        #expect(product.name == "Router XR")
        #expect(product.typeRaw == Product.ProductType.goods.rawValue)
        #expect(product.unit == "szt.")
        #expect(product.category == "Sieć")
        #expect(product.sku == "RTR-001")
        #expect(product.brand == "Acme")
        #expect(product.ean == "5901234567890")
        #expect(product.cnPkwiu == "8517.62.00")
        #expect(product.gtu == "GTU_07")
        #expect(product.isAttachment15)
        #expect(product.basePriceNet == 499.90)
        #expect(product.basePriceVatRateRaw == "23")
        #expect(product.purchasePriceNet == 320.00)
        #expect(product.purchasePriceVatRateRaw == "23")
    }

    @Test("makeBankAccount odtwarza wszystkie pola rachunku ze słownika kopii")
    func makeBankAccountOdtwarzaRachunek() {
        let id = UUID()
        let entry = sampleBackupBankAccount_backup(id: id)

        let account = BackupService.makeBankAccount(from: entry)

        #expect(account.id == id)
        #expect(account.label == "Firmowy PLN")
        #expect(account.accountNumber == "11222233334444555566667777")
        #expect(account.bankName == "Bank Testowy")
        #expect(account.swift == "TESTPLPW")
        #expect(account.currency == "PLN")
        #expect(account.vatAccountNumber == "99888877776666555544443333")
    }

    // MARK: Filtry importu szablonów i harmonogramów

    /// Buduje plik kopii z jednym szablonem i jednym harmonogramem o zadanych id.
    private func backupFileWithAutomation_backup(
        templateID: UUID, scheduleID: UUID
    ) -> BackupFile {
        let template = BackupInvoiceTemplate(
            id: templateID, name: "Stała obsługa",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            presetData: Data("{}".utf8)
        )
        let schedule = BackupRecurringInvoice(
            id: scheduleID, name: "Co miesiąc",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            recurrenceUnitRaw: RecurrenceUnit.month.rawValue,
            recurrenceInterval: 1,
            nextIssueDate: Date(timeIntervalSince1970: 1_800_100_000),
            dueDays: 14, isActive: true, lastApprovedAt: nil,
            presetData: Data("{}".utf8)
        )
        return BackupFile(
            version: BackupService.currentVersion,
            exportedAt: .now,
            settings: [:],
            invoices: [],
            contractors: nil,
            products: nil,
            bankAccounts: nil,
            invoiceTemplates: [template],
            recurringInvoices: [schedule]
        )
    }

    @Test("templatesToImport importuje nowe, pomija szablon o istniejącym id")
    func templatesToImportFiltrujePoId() {
        let templateID = UUID()
        let backup = backupFileWithAutomation_backup(templateID: templateID, scheduleID: UUID())

        // Pusta baza → szablon do importu.
        #expect(BackupService.templatesToImport(from: backup, existing: []).count == 1)

        // Szablon o tym samym id już istnieje → pominięty.
        let existing = InvoiceTemplate(id: templateID, name: "Istniejący",
                                       preset: samplePreset_backup())
        #expect(BackupService.templatesToImport(from: backup, existing: [existing]).isEmpty)
    }

    @Test("schedulesToImport importuje nowe, pomija harmonogram o istniejącym id")
    func schedulesToImportFiltrujePoId() {
        let scheduleID = UUID()
        let backup = backupFileWithAutomation_backup(templateID: UUID(), scheduleID: scheduleID)

        // Pusta baza → harmonogram do importu.
        #expect(BackupService.schedulesToImport(from: backup, existing: []).count == 1)

        // Harmonogram o tym samym id już istnieje → pominięty.
        let existing = RecurringInvoice(id: scheduleID, name: "Istniejący",
                                        preset: samplePreset_backup())
        #expect(BackupService.schedulesToImport(from: backup, existing: [existing]).isEmpty)
    }
}

// MARK: - Automatyczna kopia zapasowa — właściwości pomocnicze

@Suite("Automatyczna kopia zapasowa — tryb rotacji i katalog")
struct AutoBackupServiceEdgeCasesTests {

    @Test("RotationMode udostępnia identyfikator i nazwę wyświetlaną")
    func rotationModeIdentyfikatorINazwa() {
        // Identyfikator = surowa wartość (Identifiable).
        #expect(AutoBackupService.RotationMode.keepCount.id == "count")
        #expect(AutoBackupService.RotationMode.keepDays.id == "days")

        // Nazwy wyświetlane obu wariantów.
        #expect(AutoBackupService.RotationMode.keepCount.displayName == "liczba kopii")
        #expect(AutoBackupService.RotationMode.keepDays.displayName == "dni wstecz")

        // Wszystkie warianty dostępne przez CaseIterable.
        #expect(AutoBackupService.RotationMode.allCases.count == 2)
    }

    @Test("Domyślny katalog kopii wskazuje podkatalog Ksefiarz/Backups")
    func domyslnyKatalog() {
        // Sam odczyt URL-a nie tworzy katalogu ani nie dotyka dysku.
        let directory = AutoBackupService.defaultDirectory
        #expect(directory.pathComponents.suffix(2) == ["Ksefiarz", "Backups"])
        #expect(directory.hasDirectoryPath)
    }
}
