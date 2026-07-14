import Foundation
import SwiftData

// MARK: - Format pliku kopii zapasowej

/// Pozycja faktury w kopii zapasowej.
public struct BackupLine: Codable, Equatable, Sendable {
    public var index: Int
    public var name: String
    public var unit: String
    public var quantity: Double
    public var unitNetPrice: Double
    public var netAmount: Double
    public var vatRate: String
    public var vatAmount: Double
    /// Pola od wersji 2 — opcjonalne, żeby czytać starsze kopie.
    public var cnPkwiu: String?
    public var gtu: String?
    public var procedure: String?
    /// Pole od wersji 5 — stawka OSS pozycji (P_12_XII).
    public var ossRate: Double?
    /// Pole od wersji 6 — klasa/jakość pozycji VAT RR (P_6C).
    public var rrQuality: String?
}

/// Faktura w kopii zapasowej — pełne odwzorowanie modelu SwiftData.
public struct BackupInvoice: Codable, Equatable, Sendable {
    public var id: UUID
    public var ksefId: String?
    public var invoiceNumber: String
    public var issueDate: Date
    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    public var netAmount: Double
    public var vatAmount: Double
    public var grossAmount: Double
    public var isPaid: Bool
    public var paymentDueDate: Date?
    public var paymentFormRaw: String?
    public var paymentBankAccount: String?
    public var paymentDate: Date?
    public var isArchivedOrHidden: Bool
    public var rawXmlContent: String?
    public var documentTypeRaw: String
    public var correctionReason: String?
    public var correctedInvoiceNumber: String?
    public var correctedInvoiceKsefId: String?
    public var correctedInvoiceIssueDate: Date?
    public var ksefSessionReference: String?
    public var kindRaw: String
    public var lines: [BackupLine]
    /// Pola od wersji 2 — opcjonalne, żeby czytać starsze kopie.
    public var notes: String?
    public var currency: String?
    public var exchangeRate: Double?
    public var splitPayment: Bool?
    public var saleDate: Date?
    public var advanceInvoiceRefs: [String]?
    public var marginProcedure: String?
    /// Pola od wersji 3 — pełny cykl statusu wysyłki KSeF.
    public var ksefInvoiceReference: String?
    public var ksefSubmissionStatusRaw: String?
    public var ksefStatusCode: Int?
    public var ksefStatusDescription: String?
    public var ksefLastCheckedAt: Date?
    public var ksefAcceptedAt: Date?
    public var ksefEnvironmentRaw: String?
    public var upoXmlContent: String?
    /// Pola od wersji 4 — tryb offline24.
    public var isOfflineMode: Bool?
    public var offlineHashBase64: String?
    /// Pola od wersji 4 — historia wpłat (płatności częściowe).
    public var payments: [BackupPayment]?
    /// Pola od wersji 5 — tryby awaryjne KSeF, załącznik FA(3), e-mail.
    public var offlineReasonRaw: String?
    public var offlineEventEndedAt: Date?
    public var attachmentJSON: String?
    public var emailSentAt: Date?
    public var emailSentTo: String?
    /// Pole od wersji 6 — kategoria kosztu (raporty zakupów).
    public var costCategory: String?
    /// Pola od wersji 8 — lokalna klasyfikacja podatkowa KPiR.
    public var isExcludedFromKPiR: Bool?
    public var kpirColumnRaw: String?
    public var kpirEventDate: Date?
    public var kpirDescription: String?
    public var kpirNotes: String?
    public var kpirAmountOverride: Double?
    public var kpirResearchDevelopmentCost: Double?
    /// Pola od wersji 9 — lokalna klasyfikacja ryczałtu (ewidencja przychodów).
    public var isExcludedFromRyczalt: Bool?
    public var ryczaltRateRaw: String?
    public var ryczaltEntryDate: Date?
    public var ryczaltEventDate: Date?
    public var ryczaltAmountOverride: Double?
    public var ryczaltNotes: String?
    /// Pole od wersji 12 — samofakturowanie (Adnotacje P_17 = 1).
    public var isSelfInvoicing: Bool?
    /// Pole od wersji 13 — powiązanie z komunikatem API Latarni KSeF.
    public var offlineEventId: Int?
    /// Pola od wersji 14 — ścieżka windykacji (przypomnienie → wezwanie →
    /// nota odsetkowa → dane do pozwu EPU).
    public var collectionReminderAt: Date?
    public var collectionReminderCount: Int?
    public var collectionDemandAt: Date?
    public var collectionInterestNoteAt: Date?
    public var collectionEPUAt: Date?
}

/// Pozycja proformy w kopii zapasowej.
public struct BackupProformaLine: Codable, Equatable, Sendable {
    public var index: Int
    public var name: String
    public var unit: String
    public var quantity: Double
    public var unitNetPrice: Double
    public var netAmount: Double
    public var vatRate: String
    public var vatAmount: Double
    public var cnPkwiu: String?
}

/// Faktura proforma w kopii zapasowej (osobny model, od wersji 11).
public struct BackupProforma: Codable, Equatable, Sendable {
    public var id: UUID
    public var proformaNumber: String
    public var issueDate: Date
    public var validUntil: Date?
    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    public var netAmount: Double
    public var vatAmount: Double
    public var grossAmount: Double
    public var currency: String
    public var exchangeRate: Double
    public var isPaid: Bool
    public var paymentDate: Date?
    public var paymentDueDate: Date?
    public var paymentFormRaw: String?
    public var paymentBankAccount: String?
    public var notes: String
    public var createdAt: Date
    public var convertedInvoiceNumber: String
    public var convertedAt: Date?
    public var emailSentAt: Date?
    public var emailSentTo: String?
    public var lines: [BackupProformaLine]
}

/// Wpłata do faktury w kopii zapasowej.
public struct BackupPayment: Codable, Equatable, Sendable {
    public var id: UUID
    public var amount: Double
    public var date: Date
    public var note: String?
    public var sourceRaw: String?
}

/// Kontrahent w kopii zapasowej (słownik, od wersji 2).
public struct BackupContractor: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nameLine2: String
    public var nip: String
    public var uePrefix: String
    public var isSupplier: Bool
    public var isRecipient: Bool
    public var isNaturalPerson: Bool
    public var consentsToEInvoices: Bool
    public var consentsToMarketing: Bool
    public var street: String
    public var houseNumber: String
    public var apartmentNumber: String
    public var postalCode: String
    public var city: String
    public var countryName: String
    public var countryCode: String
    public var phone1: String
    public var phone2: String
    public var fax: String
    /// Opcjonalne — najwcześniejsze kopie wersji 2 miały w tym miejscu pole `skype`.
    public var messenger: String?
    public var messengerAddress: String?
    public var email: String
    public var invoiceEmail: String
    public var website: String
    public var notes: String
    /// Pole od wersji 6 — dokumenty dwujęzyczne (PDF PL/EN, e-mail EN).
    public var prefersBilingualDocuments: Bool?
}

/// Towar/usługa w kopii zapasowej (słownik, od wersji 2).
public struct BackupProduct: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var typeRaw: String
    public var unit: String
    public var category: String
    public var sku: String
    public var brand: String
    public var ean: String
    public var cnPkwiu: String
    public var gtu: String
    public var isAttachment15: Bool
    public var basePriceNet: Double
    public var basePriceVatRateRaw: String
    public var purchasePriceNet: Double
    public var purchasePriceVatRateRaw: String
}

/// Rachunek bankowy w kopii zapasowej (słownik, od wersji 2).
public struct BackupBankAccount: Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var accountNumber: String
    public var bankName: String
    public var swift: String
    public var currency: String
    public var vatAccountNumber: String
}

public struct BackupInvoiceTemplate: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var presetData: Data
}

public struct BackupRecurringInvoice: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var recurrenceUnitRaw: String
    public var recurrenceInterval: Int
    public var nextIssueDate: Date
    public var dueDays: Int
    public var isActive: Bool
    public var lastApprovedAt: Date?
    public var presetData: Data
}

/// Plik kopii zapasowej: faktury + ustawienia + słowniki.
public struct BackupFile: Codable, Sendable {
    public var version: Int
    public var exportedAt: Date
    /// Ustawienia (UserDefaults) — od wersji 2 bez tokenu KSeF.
    public var settings: [String: String]
    public var invoices: [BackupInvoice]
    /// Słowniki — opcjonalne (brak w kopiach wersji 1).
    public var contractors: [BackupContractor]?
    public var products: [BackupProduct]?
    public var bankAccounts: [BackupBankAccount]?
    /// Szablony i harmonogramy — opcjonalne dla kopii sprzed wersji 4.
    public var invoiceTemplates: [BackupInvoiceTemplate]?
    public var recurringInvoices: [BackupRecurringInvoice]?
    /// Faktury proforma — opcjonalne (brak w kopiach sprzed wersji 11).
    public var proformas: [BackupProforma]?
}

// MARK: - Usługa kopii zapasowej

/// Eksport i import danych aplikacji do/z pliku JSON — umożliwia
/// przeniesienie faktur i konfiguracji na inny komputer bez ponownego
/// pobierania wszystkiego z KSeF.
public enum BackupService {

    /// Bieżąca wersja formatu pliku (14: windykacja — daty działań na
    /// fakturze i ustawienia przypomnień/wezwań; 13: + eventId Latarni KSeF;
    /// 12: samofakturowanie — pole isSelfInvoicing i wzorzec numeracji
    /// samofaktur; 11 dodała faktury proforma i wzorzec ich numeracji;
    /// 10 — ustawienia kalendarza i prognozy podatkowej). Starsze pliki są
    /// nadal poprawnie importowane.
    public static let currentVersion = 14

    /// Klucze ustawień obejmowane kopią zapasową.
    /// Tokenu KSeF celowo tu nie ma — sekret żyje w pęku kluczy i nie może
    /// wyciekać do pliku JSON (starsze kopie, które go zawierają, są przy
    /// imporcie kierowane do `TokenStore`).
    public static let backedUpSettingsKeys: [String] = [
        AppSettingsKeys.sellerName,
        AppSettingsKeys.sellerAddress,
        AppSettingsKeys.nip,
        AppSettingsKeys.bankAccount,
        AppSettingsKeys.taxForm,
        AppSettingsKeys.ryczaltDefaultRate,
        AppSettingsKeys.kpirIncomeTaxMethod,
        AppSettingsKeys.incomeTaxSettlementCycle,
        AppSettingsKeys.vatSettlementCycle,
        AppSettingsKeys.isActiveVATPayer,
        AppSettingsKeys.pdfBrandingEnabled,
        AppSettingsKeys.pdfBrandingLogo,
        AppSettingsKeys.pdfBrandingPrimaryColor,
        AppSettingsKeys.pdfBrandingAccentColor,
        AppSettingsKeys.pdfBrandingFooter,
        AppSettingsKeys.pdfPaymentQR,
        AppSettingsKeys.paymentQRRecipientName,
        AppSettingsKeys.environment,
        AppSettingsKeys.numberPattern,
        AppSettingsKeys.numberPatternZAL,
        AppSettingsKeys.numberPatternROZ,
        AppSettingsKeys.numberPatternUPR,
        AppSettingsKeys.numberPatternKOR,
        AppSettingsKeys.numberPatternRR,
        AppSettingsKeys.numberPatternSF,
        AppSettingsKeys.numberPatternPRO,
        AppSettingsKeys.rangeMode,
        AppSettingsKeys.demandInterestRate,
        AppSettingsKeys.demandPaymentDays,
        AppSettingsKeys.reminderEmailsEnabled,
        AppSettingsKeys.reminderDaysBefore,
        AppSettingsKeys.reminderRepeatDays,
        AppSettingsKeys.reminderDeliveryMode,
    ]

    /// Klucze ustawień o typach natywnych innych niż String. Kopia zapasowa
    /// przechowuje wartości jako tekst („1”, „7”, „13.5”), a `@AppStorage`
    /// czyta z UserDefaults obiekt konkretnego typu — bez przywrócenia
    /// natywnego typu ustawienie po imporcie wracałoby do wartości domyślnej.
    static let boolSettingsKeys: Set<String> = [
        AppSettingsKeys.isActiveVATPayer,
        AppSettingsKeys.pdfBrandingEnabled,
        AppSettingsKeys.pdfPaymentQR,
        AppSettingsKeys.reminderEmailsEnabled,
    ]
    static let integerSettingsKeys: Set<String> = [
        AppSettingsKeys.demandPaymentDays,
        AppSettingsKeys.reminderDaysBefore,
        AppSettingsKeys.reminderRepeatDays,
    ]
    static let doubleSettingsKeys: Set<String> = [
        AppSettingsKeys.demandInterestRate,
    ]

    /// Zapisuje przywracane ustawienie pod właściwym typem. Wartość
    /// nieparsowalna zostaje tekstem (nie przepada — jak dotychczas).
    public static func applySetting(key: String, value: String, defaults: UserDefaults) {
        if boolSettingsKeys.contains(key) {
            defaults.set((value as NSString).boolValue, forKey: key)
        } else if integerSettingsKeys.contains(key), let intValue = Int(value) {
            defaults.set(intValue, forKey: key)
        } else if doubleSettingsKeys.contains(key), let doubleValue = Double(value) {
            defaults.set(doubleValue, forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    /// Buduje pełną kopię bieżącego stanu aplikacji: wszystkie faktury,
    /// słowniki i ustawienia (bez tokenu KSeF). Wspólne dla eksportu
    /// ręcznego i kopii automatycznej.
    @MainActor
    public static func makeCurrentBackup(context: ModelContext) throws -> Data {
        var settings: [String: String] = [:]
        for key in backedUpSettingsKeys {
            if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
                settings[key] = value
            }
        }
        return try makeBackup(
            invoices: try context.fetch(FetchDescriptor<Invoice>()),
            settings: settings,
            contractors: try context.fetch(FetchDescriptor<Contractor>()),
            products: try context.fetch(FetchDescriptor<Product>()),
            bankAccounts: try context.fetch(FetchDescriptor<BankAccount>()),
            invoiceTemplates: try context.fetch(FetchDescriptor<InvoiceTemplate>()),
            recurringInvoices: try context.fetch(FetchDescriptor<RecurringInvoice>()),
            proformas: try context.fetch(FetchDescriptor<Proforma>())
        )
    }

    /// Serializuje faktury, ustawienia i słowniki do JSON (ISO-8601, czytelny format).
    public static func makeBackup(
        invoices: [Invoice],
        settings: [String: String],
        contractors: [Contractor] = [],
        products: [Product] = [],
        bankAccounts: [BankAccount] = [],
        invoiceTemplates: [InvoiceTemplate] = [],
        recurringInvoices: [RecurringInvoice] = [],
        proformas: [Proforma] = [],
        exportedAt: Date = .now
    ) throws -> Data {
        let file = BackupFile(
            version: currentVersion,
            exportedAt: exportedAt,
            settings: settings,
            invoices: invoices.map(backupInvoice(from:)),
            contractors: contractors.map(backupContractor(from:)),
            products: products.map(backupProduct(from:)),
            bankAccounts: bankAccounts.map(backupBankAccount(from:)),
            invoiceTemplates: invoiceTemplates.map {
                BackupInvoiceTemplate(id: $0.id, name: $0.name, createdAt: $0.createdAt,
                                      updatedAt: $0.updatedAt, presetData: $0.presetData)
            },
            recurringInvoices: recurringInvoices.map {
                BackupRecurringInvoice(id: $0.id, name: $0.name, createdAt: $0.createdAt,
                    recurrenceUnitRaw: $0.recurrenceUnitRaw,
                    recurrenceInterval: $0.recurrenceInterval,
                    nextIssueDate: $0.nextIssueDate, dueDays: $0.dueDays,
                    isActive: $0.isActive, lastApprovedAt: $0.lastApprovedAt,
                    presetData: $0.presetData)
            },
            proformas: proformas.map(backupProforma(from:))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Dekoduje plik kopii zapasowej.
    public static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw KSeFError.invalidResponse
        }
    }

    /// Zwraca faktury z kopii, których nie ma jeszcze w bazie.
    /// Duplikaty rozpoznawane po lokalnym `id` oraz po numerze KSeF.
    public static func invoicesToImport(
        from backup: BackupFile,
        existing: [Invoice]
    ) -> [BackupInvoice] {
        let existingIds = Set(existing.map(\.id))
        let existingKsefIds = Set(existing.compactMap(\.ksefId))
        let existingInvoiceReferences = Set(existing.compactMap(\.ksefInvoiceReference))
        return backup.invoices.filter { candidate in
            if existingIds.contains(candidate.id) { return false }
            if let ksefId = candidate.ksefId, existingKsefIds.contains(ksefId) { return false }
            if let reference = candidate.ksefInvoiceReference,
               existingInvoiceReferences.contains(reference) { return false }
            return true
        }
    }

    /// Buduje model SwiftData z wpisu kopii zapasowej.
    /// Pozycje należy przypisać po wstawieniu do kontekstu — patrz `makeLines(for:)`.
    public static func makeInvoice(from backup: BackupInvoice) -> Invoice {
        let invoice = Invoice(
            id: backup.id,
            ksefId: backup.ksefId,
            invoiceNumber: backup.invoiceNumber,
            issueDate: backup.issueDate,
            sellerName: backup.sellerName,
            sellerNIP: backup.sellerNIP,
            sellerAddress: backup.sellerAddress,
            buyerName: backup.buyerName,
            buyerNIP: backup.buyerNIP,
            buyerAddress: backup.buyerAddress,
            netAmount: backup.netAmount,
            vatAmount: backup.vatAmount,
            grossAmount: backup.grossAmount,
            isPaid: backup.isPaid,
            paymentDueDate: backup.paymentDueDate,
            paymentForm: backup.paymentFormRaw.flatMap(PaymentForm.init(rawValue:)),
            paymentBankAccount: backup.paymentBankAccount,
            paymentDate: backup.paymentDate,
            isArchivedOrHidden: backup.isArchivedOrHidden,
            rawXmlContent: backup.rawXmlContent,
            documentType: backup.documentTypeRaw,
            correctionReason: backup.correctionReason,
            correctedInvoiceNumber: backup.correctedInvoiceNumber,
            correctedInvoiceKsefId: backup.correctedInvoiceKsefId,
            correctedInvoiceIssueDate: backup.correctedInvoiceIssueDate,
            ksefSessionReference: backup.ksefSessionReference,
            ksefInvoiceReference: backup.ksefInvoiceReference,
            ksefSubmissionStatus: backup.ksefSubmissionStatusRaw.flatMap(KSeFSubmissionStatus.init(rawValue:)),
            ksefStatusCode: backup.ksefStatusCode,
            ksefStatusDescription: backup.ksefStatusDescription,
            ksefLastCheckedAt: backup.ksefLastCheckedAt,
            ksefAcceptedAt: backup.ksefAcceptedAt,
            ksefEnvironmentRaw: backup.ksefEnvironmentRaw ?? "",
            upoXmlContent: backup.upoXmlContent,
            notes: backup.notes ?? "",
            currency: backup.currency ?? "PLN",
            exchangeRate: backup.exchangeRate ?? 0,
            splitPayment: backup.splitPayment ?? false,
            saleDate: backup.saleDate,
            advanceInvoiceRefs: backup.advanceInvoiceRefs ?? [],
            marginProcedure: backup.marginProcedure ?? "",
            isSelfInvoicing: backup.isSelfInvoicing ?? false,
            kind: Invoice.Kind(rawValue: backup.kindRaw) ?? .purchase
        )
        invoice.isOfflineMode = backup.isOfflineMode ?? false
        invoice.offlineHashBase64 = backup.offlineHashBase64 ?? ""
        invoice.offlineReasonRaw = backup.offlineReasonRaw ?? ""
        invoice.offlineEventEndedAt = backup.offlineEventEndedAt
        invoice.offlineEventId = backup.offlineEventId
        invoice.attachmentJSON = backup.attachmentJSON ?? ""
        invoice.emailSentAt = backup.emailSentAt
        invoice.emailSentTo = backup.emailSentTo ?? ""
        invoice.costCategory = backup.costCategory ?? ""
        invoice.isExcludedFromKPiR = backup.isExcludedFromKPiR ?? false
        invoice.kpirColumnRaw = backup.kpirColumnRaw ?? ""
        invoice.kpirEventDate = backup.kpirEventDate
        invoice.kpirDescription = backup.kpirDescription ?? ""
        invoice.kpirNotes = backup.kpirNotes ?? ""
        invoice.kpirAmountOverride = backup.kpirAmountOverride
        invoice.kpirResearchDevelopmentCost = backup.kpirResearchDevelopmentCost ?? 0
        invoice.isExcludedFromRyczalt = backup.isExcludedFromRyczalt ?? false
        invoice.ryczaltRateRaw = backup.ryczaltRateRaw ?? ""
        invoice.ryczaltEntryDate = backup.ryczaltEntryDate
        invoice.ryczaltEventDate = backup.ryczaltEventDate
        invoice.ryczaltAmountOverride = backup.ryczaltAmountOverride
        invoice.ryczaltNotes = backup.ryczaltNotes ?? ""
        invoice.collectionReminderAt = backup.collectionReminderAt
        invoice.collectionReminderCount = backup.collectionReminderCount ?? 0
        invoice.collectionDemandAt = backup.collectionDemandAt
        invoice.collectionInterestNoteAt = backup.collectionInterestNoteAt
        invoice.collectionEPUAt = backup.collectionEPUAt
        return invoice
    }

    /// Modele wpłat dla zaimportowanej faktury (przypisywać po wstawieniu
    /// faktury do kontekstu — relacja SwiftData, jak pozycje).
    public static func makePayments(for backup: BackupInvoice) -> [PaymentRecord] {
        (backup.payments ?? []).map { payment in
            PaymentRecord(
                id: payment.id,
                amount: payment.amount,
                date: payment.date,
                note: payment.note ?? "",
                source: payment.sourceRaw.flatMap(PaymentRecord.Source.init(rawValue:)) ?? .manual
            )
        }
    }

    /// Modele pozycji dla zaimportowanej faktury.
    public static func makeLines(for backup: BackupInvoice) -> [InvoiceLine] {
        backup.lines.map { line in
            InvoiceLine(
                index: line.index,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu ?? "",
                gtu: line.gtu ?? "",
                procedure: line.procedure ?? "",
                ossRate: line.ossRate,
                rrQuality: line.rrQuality ?? ""
            )
        }
    }

    // MARK: Słowniki (od wersji 2)

    /// Kontrahenci z kopii nieobecni w bazie (duplikaty po `id` i NIP).
    public static func contractorsToImport(
        from backup: BackupFile,
        existing: [Contractor]
    ) -> [BackupContractor] {
        let ids = Set(existing.map(\.id))
        let nips = Set(existing.map(\.nip).filter { !$0.isEmpty })
        return (backup.contractors ?? []).filter {
            !ids.contains($0.id) && !nips.contains($0.nip)
        }
    }

    /// Towary/usługi z kopii nieobecne w bazie (duplikaty po `id` i nazwie).
    public static func productsToImport(
        from backup: BackupFile,
        existing: [Product]
    ) -> [BackupProduct] {
        let ids = Set(existing.map(\.id))
        let names = Set(existing.map(\.name))
        return (backup.products ?? []).filter {
            !ids.contains($0.id) && !names.contains($0.name)
        }
    }

    /// Rachunki z kopii nieobecne w bazie (duplikaty po `id` i numerze).
    public static func bankAccountsToImport(
        from backup: BackupFile,
        existing: [BankAccount]
    ) -> [BackupBankAccount] {
        let ids = Set(existing.map(\.id))
        let numbers = Set(existing.map(\.accountNumber))
        return (backup.bankAccounts ?? []).filter {
            !ids.contains($0.id) && !numbers.contains($0.accountNumber)
        }
    }

    /// Model kontrahenta z wpisu kopii zapasowej.
    public static func makeContractor(from backup: BackupContractor) -> Contractor {
        let contractor = Contractor()
        contractor.id = backup.id
        contractor.name = backup.name
        contractor.nameLine2 = backup.nameLine2
        contractor.nip = backup.nip
        contractor.uePrefix = backup.uePrefix
        contractor.isSupplier = backup.isSupplier
        contractor.isRecipient = backup.isRecipient
        contractor.isNaturalPerson = backup.isNaturalPerson
        contractor.consentsToEInvoices = backup.consentsToEInvoices
        contractor.consentsToMarketing = backup.consentsToMarketing
        contractor.street = backup.street
        contractor.houseNumber = backup.houseNumber
        contractor.apartmentNumber = backup.apartmentNumber
        contractor.postalCode = backup.postalCode
        contractor.city = backup.city
        contractor.countryName = backup.countryName
        contractor.countryCode = backup.countryCode
        contractor.phone1 = backup.phone1
        contractor.phone2 = backup.phone2
        contractor.fax = backup.fax
        contractor.messenger = backup.messenger ?? ""
        contractor.messengerAddress = backup.messengerAddress ?? ""
        contractor.email = backup.email
        contractor.invoiceEmail = backup.invoiceEmail
        contractor.website = backup.website
        contractor.notes = backup.notes
        contractor.prefersBilingualDocuments = backup.prefersBilingualDocuments ?? false
        return contractor
    }

    /// Model towaru/usługi z wpisu kopii zapasowej.
    public static func makeProduct(from backup: BackupProduct) -> Product {
        let product = Product()
        product.id = backup.id
        product.name = backup.name
        product.typeRaw = backup.typeRaw
        product.unit = backup.unit
        product.category = backup.category
        product.sku = backup.sku
        product.brand = backup.brand
        product.ean = backup.ean
        product.cnPkwiu = backup.cnPkwiu
        product.gtu = backup.gtu
        product.isAttachment15 = backup.isAttachment15
        product.basePriceNet = backup.basePriceNet
        product.basePriceVatRateRaw = backup.basePriceVatRateRaw
        product.purchasePriceNet = backup.purchasePriceNet
        product.purchasePriceVatRateRaw = backup.purchasePriceVatRateRaw
        return product
    }

    /// Model rachunku bankowego z wpisu kopii zapasowej.
    public static func makeBankAccount(from backup: BackupBankAccount) -> BankAccount {
        let account = BankAccount()
        account.id = backup.id
        account.label = backup.label
        account.accountNumber = backup.accountNumber
        account.bankName = backup.bankName
        account.swift = backup.swift
        account.currency = backup.currency
        account.vatAccountNumber = backup.vatAccountNumber
        return account
    }

    public static func templatesToImport(from backup: BackupFile, existing: [InvoiceTemplate]) -> [BackupInvoiceTemplate] {
        let ids = Set(existing.map(\.id))
        return (backup.invoiceTemplates ?? []).filter { !ids.contains($0.id) }
    }

    public static func schedulesToImport(from backup: BackupFile, existing: [RecurringInvoice]) -> [BackupRecurringInvoice] {
        let ids = Set(existing.map(\.id))
        return (backup.recurringInvoices ?? []).filter { !ids.contains($0.id) }
    }

    public static func makeTemplate(from backup: BackupInvoiceTemplate) -> InvoiceTemplate? {
        guard let preset = try? JSONDecoder().decode(InvoicePreset.self, from: backup.presetData) else { return nil }
        let result = InvoiceTemplate(id: backup.id, name: backup.name, preset: preset, now: backup.createdAt)
        result.updatedAt = backup.updatedAt
        return result
    }

    public static func makeSchedule(from backup: BackupRecurringInvoice) -> RecurringInvoice? {
        guard let preset = try? JSONDecoder().decode(InvoicePreset.self, from: backup.presetData) else { return nil }
        let result = RecurringInvoice(id: backup.id, name: backup.name, preset: preset,
            unit: RecurrenceUnit(rawValue: backup.recurrenceUnitRaw) ?? .month,
            interval: backup.recurrenceInterval, nextIssueDate: backup.nextIssueDate,
            dueDays: backup.dueDays, isActive: backup.isActive, createdAt: backup.createdAt)
        result.lastApprovedAt = backup.lastApprovedAt
        return result
    }

    // MARK: Faktury proforma (od wersji 11)

    /// Proformy z kopii nieobecne w bazie (duplikaty po `id` oraz numerze).
    public static func proformasToImport(
        from backup: BackupFile,
        existing: [Proforma]
    ) -> [BackupProforma] {
        let ids = Set(existing.map(\.id))
        let numbers = Set(existing.map { InvoiceValidator.normalizedNumber($0.proformaNumber) })
        return (backup.proformas ?? []).filter {
            !ids.contains($0.id)
                && !numbers.contains(InvoiceValidator.normalizedNumber($0.proformaNumber))
        }
    }

    /// Buduje model SwiftData z wpisu kopii zapasowej. Pozycje należy przypisać
    /// po wstawieniu do kontekstu — patrz `makeProformaLines(for:)`.
    public static func makeProforma(from backup: BackupProforma) -> Proforma {
        let proforma = Proforma(
            id: backup.id,
            proformaNumber: backup.proformaNumber,
            issueDate: backup.issueDate,
            validUntil: backup.validUntil,
            sellerName: backup.sellerName,
            sellerNIP: backup.sellerNIP,
            sellerAddress: backup.sellerAddress,
            buyerName: backup.buyerName,
            buyerNIP: backup.buyerNIP,
            buyerAddress: backup.buyerAddress,
            netAmount: backup.netAmount,
            vatAmount: backup.vatAmount,
            grossAmount: backup.grossAmount,
            currency: backup.currency,
            exchangeRate: backup.exchangeRate,
            isPaid: backup.isPaid,
            paymentDate: backup.paymentDate,
            paymentDueDate: backup.paymentDueDate,
            paymentForm: backup.paymentFormRaw.flatMap(PaymentForm.init(rawValue:)),
            paymentBankAccount: backup.paymentBankAccount,
            notes: backup.notes,
            createdAt: backup.createdAt,
            convertedInvoiceNumber: backup.convertedInvoiceNumber,
            convertedAt: backup.convertedAt
        )
        proforma.emailSentAt = backup.emailSentAt
        proforma.emailSentTo = backup.emailSentTo ?? ""
        return proforma
    }

    /// Modele pozycji dla zaimportowanej proformy.
    public static func makeProformaLines(for backup: BackupProforma) -> [ProformaLine] {
        backup.lines.map { line in
            ProformaLine(
                index: line.index,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu ?? ""
            )
        }
    }

    /// Odwzorowanie modelu SwiftData na wpis kopii zapasowej.
    private static func backupInvoice(from invoice: Invoice) -> BackupInvoice {
        BackupInvoice(
            id: invoice.id,
            ksefId: invoice.ksefId,
            invoiceNumber: invoice.invoiceNumber,
            issueDate: invoice.issueDate,
            sellerName: invoice.sellerName,
            sellerNIP: invoice.sellerNIP,
            sellerAddress: invoice.sellerAddress,
            buyerName: invoice.buyerName,
            buyerNIP: invoice.buyerNIP,
            buyerAddress: invoice.buyerAddress,
            netAmount: invoice.netAmount,
            vatAmount: invoice.vatAmount,
            grossAmount: invoice.grossAmount,
            isPaid: invoice.isPaid,
            paymentDueDate: invoice.paymentDueDate,
            paymentFormRaw: invoice.paymentFormRaw,
            paymentBankAccount: invoice.paymentBankAccount,
            paymentDate: invoice.paymentDate,
            isArchivedOrHidden: invoice.isArchivedOrHidden,
            rawXmlContent: invoice.rawXmlContent,
            documentTypeRaw: invoice.documentTypeRaw,
            correctionReason: invoice.correctionReason,
            correctedInvoiceNumber: invoice.correctedInvoiceNumber,
            correctedInvoiceKsefId: invoice.correctedInvoiceKsefId,
            correctedInvoiceIssueDate: invoice.correctedInvoiceIssueDate,
            ksefSessionReference: invoice.ksefSessionReference,
            kindRaw: invoice.kindRaw,
            lines: invoice.sortedLines.map { line in
                BackupLine(
                    index: line.index,
                    name: line.name,
                    unit: line.unit,
                    quantity: line.quantity,
                    unitNetPrice: line.unitNetPrice,
                    netAmount: line.netAmount,
                    vatRate: line.vatRate,
                    vatAmount: line.vatAmount,
                    cnPkwiu: line.cnPkwiu.isEmpty ? nil : line.cnPkwiu,
                    gtu: line.gtu.isEmpty ? nil : line.gtu,
                    procedure: line.procedure.isEmpty ? nil : line.procedure,
                    ossRate: line.ossRate,
                    rrQuality: line.rrQuality.isEmpty ? nil : line.rrQuality
                )
            },
            notes: invoice.notes.isEmpty ? nil : invoice.notes,
            currency: invoice.currency,
            exchangeRate: invoice.exchangeRate,
            splitPayment: invoice.splitPayment,
            saleDate: invoice.saleDate,
            advanceInvoiceRefs: invoice.advanceInvoiceRefs.isEmpty ? nil : invoice.advanceInvoiceRefs,
            marginProcedure: invoice.marginProcedureRaw.isEmpty ? nil : invoice.marginProcedureRaw,
            ksefInvoiceReference: invoice.ksefInvoiceReference,
            ksefSubmissionStatusRaw: invoice.ksefSubmissionStatusRaw.isEmpty
                ? nil : invoice.ksefSubmissionStatusRaw,
            ksefStatusCode: invoice.ksefStatusCode,
            ksefStatusDescription: invoice.ksefStatusDescription,
            ksefLastCheckedAt: invoice.ksefLastCheckedAt,
            ksefAcceptedAt: invoice.ksefAcceptedAt,
            ksefEnvironmentRaw: invoice.ksefEnvironmentRaw.isEmpty ? nil : invoice.ksefEnvironmentRaw,
            upoXmlContent: invoice.upoXmlContent,
            isOfflineMode: invoice.isOfflineMode ? true : nil,
            offlineHashBase64: invoice.offlineHashBase64.isEmpty ? nil : invoice.offlineHashBase64,
            payments: invoice.payments.isEmpty ? nil : invoice.sortedPayments.map { payment in
                BackupPayment(
                    id: payment.id,
                    amount: payment.amount,
                    date: payment.date,
                    note: payment.note.isEmpty ? nil : payment.note,
                    sourceRaw: payment.sourceRaw
                )
            },
            offlineReasonRaw: invoice.offlineReasonRaw.isEmpty ? nil : invoice.offlineReasonRaw,
            offlineEventEndedAt: invoice.offlineEventEndedAt,
            attachmentJSON: invoice.attachmentJSON.isEmpty ? nil : invoice.attachmentJSON,
            emailSentAt: invoice.emailSentAt,
            emailSentTo: invoice.emailSentTo.isEmpty ? nil : invoice.emailSentTo,
            costCategory: invoice.costCategory.isEmpty ? nil : invoice.costCategory,
            isExcludedFromKPiR: invoice.isExcludedFromKPiR ? true : nil,
            kpirColumnRaw: invoice.kpirColumnRaw.isEmpty ? nil : invoice.kpirColumnRaw,
            kpirEventDate: invoice.kpirEventDate,
            kpirDescription: invoice.kpirDescription.isEmpty ? nil : invoice.kpirDescription,
            kpirNotes: invoice.kpirNotes.isEmpty ? nil : invoice.kpirNotes,
            kpirAmountOverride: invoice.kpirAmountOverride,
            kpirResearchDevelopmentCost: invoice.kpirResearchDevelopmentCost == 0
                ? nil : invoice.kpirResearchDevelopmentCost,
            isExcludedFromRyczalt: invoice.isExcludedFromRyczalt ? true : nil,
            ryczaltRateRaw: invoice.ryczaltRateRaw.isEmpty ? nil : invoice.ryczaltRateRaw,
            ryczaltEntryDate: invoice.ryczaltEntryDate,
            ryczaltEventDate: invoice.ryczaltEventDate,
            ryczaltAmountOverride: invoice.ryczaltAmountOverride,
            ryczaltNotes: invoice.ryczaltNotes.isEmpty ? nil : invoice.ryczaltNotes,
            isSelfInvoicing: invoice.isSelfInvoicing ? true : nil,
            offlineEventId: invoice.offlineEventId,
            collectionReminderAt: invoice.collectionReminderAt,
            collectionReminderCount: invoice.collectionReminderCount == 0
                ? nil : invoice.collectionReminderCount,
            collectionDemandAt: invoice.collectionDemandAt,
            collectionInterestNoteAt: invoice.collectionInterestNoteAt,
            collectionEPUAt: invoice.collectionEPUAt
        )
    }

    /// Odwzorowanie proformy na wpis kopii zapasowej.
    private static func backupProforma(from proforma: Proforma) -> BackupProforma {
        BackupProforma(
            id: proforma.id,
            proformaNumber: proforma.proformaNumber,
            issueDate: proforma.issueDate,
            validUntil: proforma.validUntil,
            sellerName: proforma.sellerName,
            sellerNIP: proforma.sellerNIP,
            sellerAddress: proforma.sellerAddress,
            buyerName: proforma.buyerName,
            buyerNIP: proforma.buyerNIP,
            buyerAddress: proforma.buyerAddress,
            netAmount: proforma.netAmount,
            vatAmount: proforma.vatAmount,
            grossAmount: proforma.grossAmount,
            currency: proforma.currency,
            exchangeRate: proforma.exchangeRate,
            isPaid: proforma.isPaid,
            paymentDate: proforma.paymentDate,
            paymentDueDate: proforma.paymentDueDate,
            paymentFormRaw: proforma.paymentFormRaw,
            paymentBankAccount: proforma.paymentBankAccount,
            notes: proforma.notes,
            createdAt: proforma.createdAt,
            convertedInvoiceNumber: proforma.convertedInvoiceNumber,
            convertedAt: proforma.convertedAt,
            emailSentAt: proforma.emailSentAt,
            emailSentTo: proforma.emailSentTo.isEmpty ? nil : proforma.emailSentTo,
            lines: proforma.sortedLines.map { line in
                BackupProformaLine(
                    index: line.index,
                    name: line.name,
                    unit: line.unit,
                    quantity: line.quantity,
                    unitNetPrice: line.unitNetPrice,
                    netAmount: line.netAmount,
                    vatRate: line.vatRate,
                    vatAmount: line.vatAmount,
                    cnPkwiu: line.cnPkwiu.isEmpty ? nil : line.cnPkwiu
                )
            }
        )
    }

    /// Odwzorowania słowników na wpisy kopii zapasowej.
    private static func backupContractor(from contractor: Contractor) -> BackupContractor {
        BackupContractor(
            id: contractor.id,
            name: contractor.name,
            nameLine2: contractor.nameLine2,
            nip: contractor.nip,
            uePrefix: contractor.uePrefix,
            isSupplier: contractor.isSupplier,
            isRecipient: contractor.isRecipient,
            isNaturalPerson: contractor.isNaturalPerson,
            consentsToEInvoices: contractor.consentsToEInvoices,
            consentsToMarketing: contractor.consentsToMarketing,
            street: contractor.street,
            houseNumber: contractor.houseNumber,
            apartmentNumber: contractor.apartmentNumber,
            postalCode: contractor.postalCode,
            city: contractor.city,
            countryName: contractor.countryName,
            countryCode: contractor.countryCode,
            phone1: contractor.phone1,
            phone2: contractor.phone2,
            fax: contractor.fax,
            messenger: contractor.messenger,
            messengerAddress: contractor.messengerAddress,
            email: contractor.email,
            invoiceEmail: contractor.invoiceEmail,
            website: contractor.website,
            notes: contractor.notes,
            prefersBilingualDocuments: contractor.prefersBilingualDocuments ? true : nil
        )
    }

    private static func backupProduct(from product: Product) -> BackupProduct {
        BackupProduct(
            id: product.id,
            name: product.name,
            typeRaw: product.typeRaw,
            unit: product.unit,
            category: product.category,
            sku: product.sku,
            brand: product.brand,
            ean: product.ean,
            cnPkwiu: product.cnPkwiu,
            gtu: product.gtu,
            isAttachment15: product.isAttachment15,
            basePriceNet: product.basePriceNet,
            basePriceVatRateRaw: product.basePriceVatRateRaw,
            purchasePriceNet: product.purchasePriceNet,
            purchasePriceVatRateRaw: product.purchasePriceVatRateRaw
        )
    }

    private static func backupBankAccount(from account: BankAccount) -> BackupBankAccount {
        BackupBankAccount(
            id: account.id,
            label: account.label,
            accountNumber: account.accountNumber,
            bankName: account.bankName,
            swift: account.swift,
            currency: account.currency,
            vatAccountNumber: account.vatAccountNumber
        )
    }
}
