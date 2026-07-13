import Foundation

/// Rodzaj danych obsługiwany przez kreator importu wsadowego.
public enum BulkImportEntity: String, CaseIterable, Identifiable, Sendable {
    case contractors
    case products
    case invoices

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .contractors: return "Kontrahenci"
        case .products: return "Towary i usługi"
        case .invoices: return "Faktury"
        }
    }
}

/// Pole docelowe wybierane w mapowaniu kolumn CSV/XLSX.
public enum BulkImportField: String, CaseIterable, Identifiable, Sendable {
    // Kontrahenci
    case contractorName, contractorNameLine2, contractorNIP, contractorUEPrefix
    case contractorSupplier, contractorRecipient, contractorStreet, contractorHouseNumber
    case contractorApartmentNumber, contractorPostalCode, contractorCity
    case contractorCountryName, contractorCountryCode, contractorPhone
    case contractorEmail, contractorInvoiceEmail, contractorWebsite, contractorNotes
    case contractorBilingual

    // Towary i usługi
    case productName, productType, productUnit, productCategory, productSKU
    case productBrand, productEAN, productCNPkwiu, productGTU, productAttachment15
    case productSalePriceNet, productSalePriceGross, productSaleVAT
    case productPurchasePriceNet, productPurchaseVAT, productPurchasePriceKind

    // Faktury i opcjonalne pozycje
    case invoiceNumber, invoiceIssueDate, invoiceKind, invoiceKSeFID
    case invoiceContractorName, invoiceContractorNIP, invoiceContractorAddress
    case invoiceSellerName, invoiceSellerNIP, invoiceSellerAddress
    case invoiceBuyerName, invoiceBuyerNIP, invoiceBuyerAddress
    case invoiceNet, invoiceVAT, invoiceGross, invoiceCurrency, invoiceExchangeRate
    case invoicePaid, invoicePaymentDueDate, invoicePaymentDate, invoicePaymentForm
    case invoiceBankAccount, invoiceSplitPayment, invoiceDocumentType, invoiceNotes
    case invoiceCostCategory
    case lineName, lineUnit, lineQuantity, lineUnitNetPrice, lineNet, lineVATRate
    case lineVAT, lineCNPkwiu, lineGTU

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .contractorName: return "Nazwa firmy"
        case .contractorNameLine2: return "Druga linia nazwy"
        case .contractorNIP: return "NIP / identyfikator podatkowy"
        case .contractorUEPrefix: return "Prefiks VAT UE"
        case .contractorSupplier: return "Rola: dostawca"
        case .contractorRecipient: return "Rola: odbiorca"
        case .contractorStreet: return "Ulica"
        case .contractorHouseNumber: return "Numer domu"
        case .contractorApartmentNumber: return "Numer lokalu"
        case .contractorPostalCode: return "Kod pocztowy"
        case .contractorCity: return "Miejscowość"
        case .contractorCountryName: return "Kraj"
        case .contractorCountryCode: return "Kod kraju"
        case .contractorPhone: return "Telefon"
        case .contractorEmail: return "E-mail"
        case .contractorInvoiceEmail: return "E-mail do faktur"
        case .contractorWebsite: return "WWW"
        case .contractorNotes: return "Uwagi"
        case .contractorBilingual: return "Dokumenty PL/EN"
        case .productName: return "Nazwa towaru/usługi"
        case .productType: return "Typ (towar/usługa)"
        case .productUnit: return "Jednostka"
        case .productCategory: return "Kategoria"
        case .productSKU: return "SKU / indeks"
        case .productBrand: return "Marka"
        case .productEAN: return "EAN / GTIN"
        case .productCNPkwiu: return "CN / PKWiU"
        case .productGTU: return "GTU"
        case .productAttachment15: return "Załącznik 15"
        case .productSalePriceNet: return "Cena sprzedaży netto"
        case .productSalePriceGross: return "Cena sprzedaży brutto"
        case .productSaleVAT: return "VAT sprzedaży"
        case .productPurchasePriceNet: return "Cena zakupu netto"
        case .productPurchaseVAT: return "VAT zakupu"
        case .productPurchasePriceKind: return "Rodzaj ceny zakupu (netto/brutto)"
        case .invoiceNumber: return "Numer faktury"
        case .invoiceIssueDate: return "Data wystawienia"
        case .invoiceKind: return "Rodzaj (sprzedaż/zakup)"
        case .invoiceKSeFID: return "Numer KSeF"
        case .invoiceContractorName: return "Nazwa kontrahenta"
        case .invoiceContractorNIP: return "NIP kontrahenta"
        case .invoiceContractorAddress: return "Adres kontrahenta"
        case .invoiceSellerName: return "Nazwa sprzedawcy"
        case .invoiceSellerNIP: return "NIP sprzedawcy"
        case .invoiceSellerAddress: return "Adres sprzedawcy"
        case .invoiceBuyerName: return "Nazwa nabywcy"
        case .invoiceBuyerNIP: return "NIP nabywcy"
        case .invoiceBuyerAddress: return "Adres nabywcy"
        case .invoiceNet: return "Faktura: netto"
        case .invoiceVAT: return "Faktura: VAT"
        case .invoiceGross: return "Faktura: brutto"
        case .invoiceCurrency: return "Waluta"
        case .invoiceExchangeRate: return "Kurs waluty"
        case .invoicePaid: return "Opłacona"
        case .invoicePaymentDueDate: return "Termin płatności"
        case .invoicePaymentDate: return "Data zapłaty"
        case .invoicePaymentForm: return "Forma płatności"
        case .invoiceBankAccount: return "Rachunek bankowy"
        case .invoiceSplitPayment: return "Podzielona płatność"
        case .invoiceDocumentType: return "Typ dokumentu"
        case .invoiceNotes: return "Uwagi faktury"
        case .invoiceCostCategory: return "Kategoria kosztu"
        case .lineName: return "Pozycja: nazwa"
        case .lineUnit: return "Pozycja: jednostka"
        case .lineQuantity: return "Pozycja: ilość"
        case .lineUnitNetPrice: return "Pozycja: cena netto"
        case .lineNet: return "Pozycja: wartość netto"
        case .lineVATRate: return "Pozycja: stawka VAT"
        case .lineVAT: return "Pozycja: kwota VAT"
        case .lineCNPkwiu: return "Pozycja: CN / PKWiU"
        case .lineGTU: return "Pozycja: GTU"
        }
    }

    public var isRequired: Bool {
        switch self {
        case .contractorName, .contractorNIP, .productName, .invoiceNumber, .invoiceIssueDate:
            return true
        default:
            return false
        }
    }

    public static func fields(for entity: BulkImportEntity) -> [BulkImportField] {
        switch entity {
        case .contractors:
            return [.contractorName, .contractorNameLine2, .contractorNIP, .contractorUEPrefix,
                    .contractorSupplier, .contractorRecipient, .contractorStreet,
                    .contractorHouseNumber, .contractorApartmentNumber, .contractorPostalCode,
                    .contractorCity, .contractorCountryName, .contractorCountryCode,
                    .contractorPhone, .contractorEmail, .contractorInvoiceEmail,
                    .contractorWebsite, .contractorNotes, .contractorBilingual]
        case .products:
            return [.productName, .productType, .productUnit, .productCategory, .productSKU,
                    .productBrand, .productEAN, .productCNPkwiu, .productGTU,
                    .productAttachment15, .productSalePriceNet, .productSalePriceGross,
                    .productSaleVAT, .productPurchasePriceNet, .productPurchaseVAT,
                    .productPurchasePriceKind]
        case .invoices:
            return [.invoiceNumber, .invoiceIssueDate, .invoiceKind, .invoiceKSeFID,
                    .invoiceContractorName, .invoiceContractorNIP, .invoiceContractorAddress,
                    .invoiceSellerName, .invoiceSellerNIP, .invoiceSellerAddress,
                    .invoiceBuyerName, .invoiceBuyerNIP, .invoiceBuyerAddress,
                    .invoiceNet, .invoiceVAT, .invoiceGross, .invoiceCurrency,
                    .invoiceExchangeRate, .invoicePaid, .invoicePaymentDueDate,
                    .invoicePaymentDate, .invoicePaymentForm, .invoiceBankAccount,
                    .invoiceSplitPayment, .invoiceDocumentType, .invoiceNotes,
                    .invoiceCostCategory, .lineName, .lineUnit, .lineQuantity,
                    .lineUnitNetPrice, .lineNet, .lineVATRate, .lineVAT,
                    .lineCNPkwiu, .lineGTU]
        }
    }
}

/// Znormalizowana tabela wejściowa. Pierwszy wiersz zawiera nagłówki.
public struct TabularSheet: Equatable, Sendable {
    public var name: String
    public var rows: [[String]]

    public init(name: String, rows: [[String]]) {
        self.name = name
        self.rows = rows
    }

    public var headers: [String] { rows.first ?? [] }
    public var dataRows: [[String]] { Array(rows.dropFirst()) }
}

public struct BulkImportCompany: Equatable, Sendable {
    public var name: String
    public var nip: String
    public var address: String

    public init(name: String = "", nip: String = "", address: String = "") {
        self.name = name
        self.nip = nip
        self.address = address
    }
}

public struct BulkImportOptions: Equatable, Sendable {
    public var defaultInvoiceKind: Invoice.Kind
    public var company: BulkImportCompany

    public init(defaultInvoiceKind: Invoice.Kind = .sales, company: BulkImportCompany = .init()) {
        self.defaultInvoiceKind = defaultInvoiceKind
        self.company = company
    }
}

/// Klucze rekordów już istniejących w bazie. Widok tworzy je z pełnych
/// fetchy, bez filtrowania faktur ukrytych, aby synchronizacja/import nigdy
/// nie przywróciły ukrytego dokumentu jako duplikatu.
public struct BulkImportExistingKeys: Equatable, Sendable {
    public var contractors: Set<String>
    public var products: Set<String>
    public var invoices: Set<String>

    public init(contractors: Set<String> = [], products: Set<String> = [], invoices: Set<String> = []) {
        self.contractors = contractors
        self.products = products
        self.invoices = invoices
    }
}

public struct ImportedContractor: Equatable, Sendable {
    public var name = ""
    public var nameLine2 = ""
    public var nip = ""
    public var uePrefix = ""
    public var isSupplier = true
    public var isRecipient = true
    public var street = ""
    public var houseNumber = ""
    public var apartmentNumber = ""
    public var postalCode = ""
    public var city = ""
    public var countryName = "Polska"
    public var countryCode = "PL"
    public var phone = ""
    public var email = ""
    public var invoiceEmail = ""
    public var website = ""
    public var notes = ""
    public var prefersBilingualDocuments = false
}

public struct ImportedProduct: Equatable, Sendable {
    public var name = ""
    public var type: Product.ProductType = .goods
    public var unit = "szt."
    public var category = ""
    public var sku = ""
    public var brand = ""
    public var ean = ""
    public var cnPkwiu = ""
    public var gtu = ""
    public var isAttachment15 = false
    public var basePriceNet: Double = 0
    public var basePriceVAT: VATRate = .standard
    public var purchasePriceNet: Double = 0
    public var purchasePriceVAT: VATRate = .standard
}

public struct ImportedInvoiceLine: Equatable, Sendable {
    public var name: String
    public var unit: String
    public var quantity: Double
    public var unitNetPrice: Double
    public var netAmount: Double
    public var vatRate: String
    public var vatAmount: Double
    public var cnPkwiu: String
    public var gtu: String
}

public struct ImportedInvoice: Equatable, Sendable {
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
    public var paymentDate: Date?
    public var paymentForm: PaymentForm?
    public var paymentBankAccount: String?
    public var currency: String
    public var exchangeRate: Double
    public var splitPayment: Bool
    public var documentType: String
    public var notes: String
    public var costCategory: String
    public var kind: Invoice.Kind
    public var lines: [ImportedInvoiceLine]
}

public struct BulkImportIssue: Equatable, Sendable {
    public enum Severity: String, Sendable { case warning, error }
    public var row: Int?
    public var severity: Severity
    public var message: String

    public init(row: Int? = nil, severity: Severity, message: String) {
        self.row = row
        self.severity = severity
        self.message = message
    }
}

public struct BulkImportPlan: Equatable, Sendable {
    public var contractors: [ImportedContractor] = []
    public var products: [ImportedProduct] = []
    public var invoices: [ImportedInvoice] = []
    public var duplicateCount = 0
    public var sourceRowCount = 0
    public var issues: [BulkImportIssue] = []

    public var importCount: Int { contractors.count + products.count + invoices.count }
    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
}

/// Czysta logika mapowania, walidacji i deduplikacji importu. Nie dotyka
/// SwiftData — widok zatwierdza gotowy plan jednym zapisem kontekstu.
public enum BulkImportEngine {

    public static func automaticMapping(
        entity: BulkImportEntity,
        headers: [String]
    ) -> [BulkImportField: Int] {
        let normalizedHeaders = headers.map(normalizedHeader)
        var result: [BulkImportField: Int] = [:]
        var used = Set<Int>()
        for field in BulkImportField.fields(for: entity) {
            let aliases = aliases(for: field).map(normalizedHeader)
            if let index = normalizedHeaders.indices.first(where: {
                !used.contains($0) && aliases.contains(normalizedHeaders[$0])
            }) {
                result[field] = index
                used.insert(index)
            }
        }
        return result
    }

    public static func plan(
        sheet: TabularSheet,
        entity: BulkImportEntity,
        mapping: [BulkImportField: Int],
        options: BulkImportOptions = .init(),
        existing: BulkImportExistingKeys = .init()
    ) -> BulkImportPlan {
        var plan = BulkImportPlan()
        plan.sourceRowCount = sheet.dataRows.filter { row in
            row.contains { !trimmed($0).isEmpty }
        }.count

        for field in BulkImportField.fields(for: entity) where field.isRequired && mapping[field] == nil {
            plan.issues.append(.init(
                severity: .error,
                message: "Nie przypisano wymaganej kolumny „\(field.label)”."
            ))
        }
        guard plan.errorCount == 0 else { return plan }

        switch entity {
        case .contractors:
            buildContractors(sheet: sheet, mapping: mapping, existing: existing, plan: &plan)
        case .products:
            buildProducts(sheet: sheet, mapping: mapping, existing: existing, plan: &plan)
        case .invoices:
            buildInvoices(sheet: sheet, mapping: mapping, options: options, existing: existing, plan: &plan)
        }
        return plan
    }

    public static func contractorKey(nip: String, name: String) -> String {
        let identifier = normalizedIdentifier(nip)
        return identifier.isEmpty ? "name:\(normalizedHeader(name))" : "tax:\(identifier)"
    }

    public static func productKey(sku: String, ean: String, name: String) -> String {
        if !trimmed(sku).isEmpty { return "sku:\(normalizedIdentifier(sku))" }
        if !trimmed(ean).isEmpty { return "ean:\(normalizedIdentifier(ean))" }
        return "name:\(normalizedHeader(name))"
    }

    public static func productKeys(sku: String, ean: String, name: String) -> Set<String> {
        var keys: Set<String> = ["name:\(normalizedHeader(name))"]
        if !trimmed(sku).isEmpty { keys.insert("sku:\(normalizedIdentifier(sku))") }
        if !trimmed(ean).isEmpty { keys.insert("ean:\(normalizedIdentifier(ean))") }
        return keys
    }

    public static func invoiceKey(
        ksefId: String?, kind: Invoice.Kind, number: String,
        sellerNIP: String, buyerNIP: String
    ) -> String {
        if let ksefId, !trimmed(ksefId).isEmpty {
            return "ksef:\(normalizedIdentifier(ksefId))"
        }
        return [kind.rawValue, InvoiceValidator.normalizedNumber(number),
                normalizedIdentifier(sellerNIP), normalizedIdentifier(buyerNIP)]
            .joined(separator: "|")
    }

    public static func invoiceKeys(
        ksefId: String?, kind: Invoice.Kind, number: String,
        sellerNIP: String, buyerNIP: String
    ) -> Set<String> {
        var keys: Set<String> = [[kind.rawValue, InvoiceValidator.normalizedNumber(number),
                                 normalizedIdentifier(sellerNIP), normalizedIdentifier(buyerNIP)]
            .joined(separator: "|")]
        if let ksefId, !trimmed(ksefId).isEmpty {
            keys.insert("ksef:\(normalizedIdentifier(ksefId))")
        }
        return keys
    }

    // MARK: Kontrahenci

    private static func buildContractors(
        sheet: TabularSheet,
        mapping: [BulkImportField: Int],
        existing: BulkImportExistingKeys,
        plan: inout BulkImportPlan
    ) {
        var known = existing.contractors
        for (offset, row) in sheet.dataRows.enumerated() {
            let rowNumber = offset + 2
            guard row.contains(where: { !trimmed($0).isEmpty }) else { continue }
            let name = value(.contractorName, row, mapping)
            let nip = value(.contractorNIP, row, mapping)
            guard !name.isEmpty else {
                plan.issues.append(.init(row: rowNumber, severity: .error, message: "Brak nazwy kontrahenta."))
                continue
            }
            guard !nip.isEmpty else {
                plan.issues.append(.init(row: rowNumber, severity: .error, message: "Brak NIP/identyfikatora kontrahenta."))
                continue
            }
            let key = contractorKey(nip: nip, name: name)
            guard !known.contains(key) else {
                plan.duplicateCount += 1
                continue
            }

            var item = ImportedContractor()
            item.name = name
            item.nameLine2 = value(.contractorNameLine2, row, mapping)
            item.nip = nip
            item.uePrefix = value(.contractorUEPrefix, row, mapping).uppercased()
            item.isSupplier = boolean(value(.contractorSupplier, row, mapping)) ?? true
            item.isRecipient = boolean(value(.contractorRecipient, row, mapping)) ?? true
            item.street = value(.contractorStreet, row, mapping)
            item.houseNumber = value(.contractorHouseNumber, row, mapping)
            item.apartmentNumber = value(.contractorApartmentNumber, row, mapping)
            item.postalCode = value(.contractorPostalCode, row, mapping)
            item.city = value(.contractorCity, row, mapping)
            item.countryName = nonEmpty(value(.contractorCountryName, row, mapping), default: "Polska")
            item.countryCode = nonEmpty(value(.contractorCountryCode, row, mapping), default: "PL").uppercased()
            item.phone = value(.contractorPhone, row, mapping)
            item.email = value(.contractorEmail, row, mapping)
            item.invoiceEmail = value(.contractorInvoiceEmail, row, mapping)
            item.website = value(.contractorWebsite, row, mapping)
            item.notes = value(.contractorNotes, row, mapping)
            item.prefersBilingualDocuments = boolean(value(.contractorBilingual, row, mapping)) ?? false
            known.insert(key)
            plan.contractors.append(item)
        }
    }

    // MARK: Towary i usługi

    private static func buildProducts(
        sheet: TabularSheet,
        mapping: [BulkImportField: Int],
        existing: BulkImportExistingKeys,
        plan: inout BulkImportPlan
    ) {
        var known = existing.products
        for (offset, row) in sheet.dataRows.enumerated() {
            let rowNumber = offset + 2
            guard row.contains(where: { !trimmed($0).isEmpty }) else { continue }
            let name = value(.productName, row, mapping)
            guard !name.isEmpty else {
                plan.issues.append(.init(row: rowNumber, severity: .error, message: "Brak nazwy towaru/usługi."))
                continue
            }
            let sku = value(.productSKU, row, mapping)
            let ean = value(.productEAN, row, mapping)
            let keys = productKeys(sku: sku, ean: ean, name: name)
            guard known.isDisjoint(with: keys) else {
                plan.duplicateCount += 1
                continue
            }

            guard let salePrice = optionalNumber(.productSalePriceNet, row, mapping, rowNumber, &plan),
                  let saleGross = optionalNumber(.productSalePriceGross, row, mapping, rowNumber, &plan),
                  let purchasePrice = optionalNumber(.productPurchasePriceNet, row, mapping, rowNumber, &plan),
                  let saleVAT = optionalVATRate(.productSaleVAT, row, mapping, rowNumber, &plan),
                  let purchaseVAT = optionalVATRate(.productPurchaseVAT, row, mapping, rowNumber, &plan) else {
                continue
            }

            let resolvedSaleVAT = saleVAT ?? .standard
            let resolvedPurchaseVAT = purchaseVAT ?? .standard
            let resolvedSalePrice = salePrice
                ?? saleGross.map { rounded($0 / (1 + resolvedSaleVAT.multiplier)) }
                ?? 0
            let purchaseKind = normalizedHeader(value(.productPurchasePriceKind, row, mapping))
            let purchaseIsGross = ["brutto", "gross", "b"].contains(purchaseKind)
            let resolvedPurchasePrice = purchaseIsGross
                ? rounded((purchasePrice ?? 0) / (1 + resolvedPurchaseVAT.multiplier))
                : (purchasePrice ?? 0)

            var item = ImportedProduct()
            item.name = name
            item.type = productType(value(.productType, row, mapping))
            item.unit = nonEmpty(value(.productUnit, row, mapping), default: "szt.")
            item.category = value(.productCategory, row, mapping)
            item.sku = sku
            item.brand = value(.productBrand, row, mapping)
            item.ean = ean
            item.cnPkwiu = value(.productCNPkwiu, row, mapping)
            item.gtu = normalizedGTU(value(.productGTU, row, mapping))
            item.isAttachment15 = boolean(value(.productAttachment15, row, mapping)) ?? false
            item.basePriceNet = resolvedSalePrice
            item.basePriceVAT = resolvedSaleVAT
            item.purchasePriceNet = resolvedPurchasePrice
            item.purchasePriceVAT = resolvedPurchaseVAT
            known.formUnion(keys)
            plan.products.append(item)
        }
    }

    // MARK: Faktury

    private struct InvoiceAccumulator {
        var invoice: ImportedInvoice
        var sourceRow: Int
    }

    private static func buildInvoices(
        sheet: TabularSheet,
        mapping: [BulkImportField: Int],
        options: BulkImportOptions,
        existing: BulkImportExistingKeys,
        plan: inout BulkImportPlan
    ) {
        var order: [String] = []
        var accumulators: [String: InvoiceAccumulator] = [:]
        var duplicateKeys = Set<String>()

        for (offset, row) in sheet.dataRows.enumerated() {
            let rowNumber = offset + 2
            guard row.contains(where: { !trimmed($0).isEmpty }) else { continue }
            let number = value(.invoiceNumber, row, mapping)
            guard !number.isEmpty else {
                plan.issues.append(.init(row: rowNumber, severity: .error, message: "Brak numeru faktury."))
                continue
            }
            guard let issueDate = parseRequiredDate(.invoiceIssueDate, row, mapping, rowNumber, &plan) else { continue }
            let kind = invoiceKind(value(.invoiceKind, row, mapping)) ?? options.defaultInvoiceKind

            let contractorName = value(.invoiceContractorName, row, mapping)
            let contractorNIP = value(.invoiceContractorNIP, row, mapping)
            let contractorAddress = value(.invoiceContractorAddress, row, mapping)
            var sellerName = value(.invoiceSellerName, row, mapping)
            var sellerNIP = value(.invoiceSellerNIP, row, mapping)
            var sellerAddress = value(.invoiceSellerAddress, row, mapping)
            var buyerName = value(.invoiceBuyerName, row, mapping)
            var buyerNIP = value(.invoiceBuyerNIP, row, mapping)
            var buyerAddress = value(.invoiceBuyerAddress, row, mapping)
            if kind == .sales {
                sellerName = nonEmpty(sellerName, default: options.company.name)
                sellerNIP = nonEmpty(sellerNIP, default: options.company.nip)
                sellerAddress = nonEmpty(sellerAddress, default: options.company.address)
                buyerName = nonEmpty(buyerName, default: contractorName)
                buyerNIP = nonEmpty(buyerNIP, default: contractorNIP)
                buyerAddress = nonEmpty(buyerAddress, default: contractorAddress)
            } else {
                sellerName = nonEmpty(sellerName, default: contractorName)
                sellerNIP = nonEmpty(sellerNIP, default: contractorNIP)
                sellerAddress = nonEmpty(sellerAddress, default: contractorAddress)
                buyerName = nonEmpty(buyerName, default: options.company.name)
                buyerNIP = nonEmpty(buyerNIP, default: options.company.nip)
                buyerAddress = nonEmpty(buyerAddress, default: options.company.address)
            }
            guard !sellerName.isEmpty, !buyerName.isEmpty else {
                plan.issues.append(.init(
                    row: rowNumber, severity: .error,
                    message: "Brak danych stron faktury. Przypisz sprzedawcę/nabywcę albo nazwę kontrahenta i uzupełnij dane firmy w Ustawieniach."
                ))
                continue
            }

            guard let amounts = invoiceAmounts(row, mapping, rowNumber, &plan),
                  let exchangeRate = optionalNumber(.invoiceExchangeRate, row, mapping, rowNumber, &plan),
                  let paymentDue = optionalDate(.invoicePaymentDueDate, row, mapping, rowNumber, &plan),
                  let paymentDate = optionalDate(.invoicePaymentDate, row, mapping, rowNumber, &plan) else {
                continue
            }

            let ksef = value(.invoiceKSeFID, row, mapping)
            let keys = invoiceKeys(
                ksefId: ksef.isEmpty ? nil : ksef, kind: kind, number: number,
                sellerNIP: sellerNIP, buyerNIP: buyerNIP
            )
            let key = invoiceKey(
                ksefId: ksef.isEmpty ? nil : ksef, kind: kind, number: number,
                sellerNIP: sellerNIP, buyerNIP: buyerNIP
            )
            if !existing.invoices.isDisjoint(with: keys) {
                if duplicateKeys.insert(key).inserted { plan.duplicateCount += 1 }
                continue
            }

            if accumulators[key] == nil {
                let paidValue = boolean(value(.invoicePaid, row, mapping)) ?? (paymentDate != nil)
                let form = paymentForm(value(.invoicePaymentForm, row, mapping))
                let item = ImportedInvoice(
                    ksefId: ksef.isEmpty ? nil : ksef,
                    invoiceNumber: number,
                    issueDate: issueDate,
                    sellerName: sellerName,
                    sellerNIP: sellerNIP,
                    sellerAddress: sellerAddress,
                    buyerName: buyerName,
                    buyerNIP: buyerNIP,
                    buyerAddress: buyerAddress,
                    netAmount: amounts.net,
                    vatAmount: amounts.vat,
                    grossAmount: amounts.gross,
                    isPaid: paidValue,
                    paymentDueDate: paymentDue,
                    paymentDate: paymentDate,
                    paymentForm: form,
                    paymentBankAccount: nilIfEmpty(value(.invoiceBankAccount, row, mapping)),
                    currency: nonEmpty(value(.invoiceCurrency, row, mapping), default: "PLN").uppercased(),
                    exchangeRate: exchangeRate ?? 0,
                    splitPayment: boolean(value(.invoiceSplitPayment, row, mapping)) ?? false,
                    documentType: normalizedDocumentType(
                        value(.invoiceDocumentType, row, mapping), rowNumber, &plan
                    ),
                    notes: value(.invoiceNotes, row, mapping),
                    costCategory: value(.invoiceCostCategory, row, mapping),
                    kind: kind,
                    lines: []
                )
                accumulators[key] = InvoiceAccumulator(invoice: item, sourceRow: rowNumber)
                order.append(key)
            } else if let stored = accumulators[key],
                      !amountsEqual(stored.invoice, amounts) {
                plan.issues.append(.init(
                    row: rowNumber, severity: .warning,
                    message: "Powtórzony numer „\(number)” ma inne sumy; zachowano wartości z pierwszego wiersza."
                ))
            }

            if let line = invoiceLine(row, mapping, rowNumber, &plan) {
                accumulators[key]?.invoice.lines.append(line)
            }
        }
        plan.invoices = order.compactMap { accumulators[$0]?.invoice }
    }

    private static func invoiceAmounts(
        _ row: [String], _ mapping: [BulkImportField: Int], _ rowNumber: Int,
        _ plan: inout BulkImportPlan
    ) -> (net: Double, vat: Double, gross: Double)? {
        let netText = value(.invoiceNet, row, mapping)
        let vatText = value(.invoiceVAT, row, mapping)
        let grossText = value(.invoiceGross, row, mapping)
        guard !netText.isEmpty || !vatText.isEmpty || !grossText.isEmpty else {
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Brak kwot faktury (netto/VAT/brutto)."))
            return nil
        }
        guard let net = parsedOptionalNumber(netText), let vat = parsedOptionalNumber(vatText),
              let gross = parsedOptionalNumber(grossText) else {
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Nieprawidłowa kwota faktury."))
            return nil
        }
        switch (net, vat, gross) {
        case let (n?, v?, g?): return (n, v, g)
        case let (n?, v?, nil): return (n, v, rounded(n + v))
        case let (n?, nil, g?): return (n, rounded(g - n), g)
        case let (nil, v?, g?): return (rounded(g - v), v, g)
        case let (n?, nil, nil):
            plan.issues.append(.init(
                row: rowNumber, severity: .warning,
                message: "Podano tylko kwotę netto; przyjęto VAT 0 i brutto równe netto."
            ))
            return (n, 0, n)
        case let (nil, nil, g?):
            plan.issues.append(.init(
                row: rowNumber, severity: .warning,
                message: "Podano tylko kwotę brutto; przyjęto VAT 0 i netto równe brutto."
            ))
            return (g, 0, g)
        default:
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Za mało danych do wyliczenia sum faktury."))
            return nil
        }
    }

    private static func invoiceLine(
        _ row: [String], _ mapping: [BulkImportField: Int], _ rowNumber: Int,
        _ plan: inout BulkImportPlan
    ) -> ImportedInvoiceLine? {
        let name = value(.lineName, row, mapping)
        guard !name.isEmpty else { return nil }
        let quantityText = value(.lineQuantity, row, mapping)
        let priceText = value(.lineUnitNetPrice, row, mapping)
        let netText = value(.lineNet, row, mapping)
        let vatText = value(.lineVAT, row, mapping)
        guard let quantity = parsedOptionalNumber(quantityText),
              let price = parsedOptionalNumber(priceText),
              let net = parsedOptionalNumber(netText),
              let vat = parsedOptionalNumber(vatText) else {
            plan.issues.append(.init(row: rowNumber, severity: .warning, message: "Pominięto pozycję z nieprawidłową liczbą."))
            return nil
        }
        let q = quantity ?? 1
        guard q != 0 else {
            plan.issues.append(.init(row: rowNumber, severity: .warning, message: "Pominięto pozycję z ilością 0."))
            return nil
        }
        let resolvedNet = net ?? rounded(q * (price ?? 0))
        let resolvedPrice = price ?? rounded(resolvedNet / q)
        let rate = normalizedVAT(value(.lineVATRate, row, mapping)) ?? VATRate.standard.rawValue
        let multiplier = VATRate(rawValue: rate)?.multiplier ?? (Double(rate).map { $0 / 100 } ?? 0)
        let resolvedVAT = vat ?? rounded(resolvedNet * multiplier)
        return ImportedInvoiceLine(
            name: name,
            unit: nonEmpty(value(.lineUnit, row, mapping), default: "szt."),
            quantity: q,
            unitNetPrice: resolvedPrice,
            netAmount: resolvedNet,
            vatRate: rate,
            vatAmount: resolvedVAT,
            cnPkwiu: value(.lineCNPkwiu, row, mapping),
            gtu: normalizedGTU(value(.lineGTU, row, mapping))
        )
    }

    // MARK: Parsowanie wartości

    private static func value(
        _ field: BulkImportField, _ row: [String], _ mapping: [BulkImportField: Int]
    ) -> String {
        guard let index = mapping[field], row.indices.contains(index) else { return "" }
        return trimmed(row[index])
    }

    private static func optionalNumber(
        _ field: BulkImportField, _ row: [String], _ mapping: [BulkImportField: Int],
        _ rowNumber: Int, _ plan: inout BulkImportPlan
    ) -> Double?? {
        let text = value(field, row, mapping)
        guard let result = parsedOptionalNumber(text) else {
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Pole „\(field.label)” nie jest liczbą."))
            return nil
        }
        return .some(result)
    }

    private static func optionalDate(
        _ field: BulkImportField, _ row: [String], _ mapping: [BulkImportField: Int],
        _ rowNumber: Int, _ plan: inout BulkImportPlan
    ) -> Date?? {
        let text = value(field, row, mapping)
        guard !text.isEmpty else { return .some(nil) }
        guard let date = date(text) else {
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Pole „\(field.label)” nie jest datą."))
            return nil
        }
        return .some(date)
    }

    private static func parseRequiredDate(
        _ field: BulkImportField, _ row: [String], _ mapping: [BulkImportField: Int],
        _ rowNumber: Int, _ plan: inout BulkImportPlan
    ) -> Date? {
        let text = value(field, row, mapping)
        guard let result = date(text) else {
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Nieprawidłowa data wystawienia „\(text)”."))
            return nil
        }
        return result
    }

    private static func optionalVATRate(
        _ field: BulkImportField, _ row: [String], _ mapping: [BulkImportField: Int],
        _ rowNumber: Int, _ plan: inout BulkImportPlan
    ) -> VATRate?? {
        let text = value(field, row, mapping)
        guard !text.isEmpty else { return .some(nil) }
        guard let raw = normalizedVAT(text), let rate = VATRate(rawValue: raw) else {
            plan.issues.append(.init(row: rowNumber, severity: .error, message: "Nieobsługiwana stawka w polu „\(field.label)”: \(text)."))
            return nil
        }
        return .some(rate)
    }

    private static func parsedOptionalNumber(_ text: String) -> Double?? {
        let text = trimmed(text)
        guard !text.isEmpty else { return .some(nil) }
        let negative = text.hasPrefix("(") && text.hasSuffix(")")
        var cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "zł", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "zl", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "PLN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "USD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if cleaned.contains(",") && cleaned.contains(".") {
            if cleaned.lastIndex(of: ",")! > cleaned.lastIndex(of: ".")! {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned) else { return nil }
        return .some(negative ? -value : value)
    }

    private static func date(_ text: String) -> Date? {
        let value = trimmed(text)
        guard !value.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "yyyy/MM/dd",
                       "yyyy-MM-dd HH:mm:ss", "dd.MM.yyyy HH:mm:ss"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func boolean(_ text: String) -> Bool? {
        switch normalizedHeader(text) {
        case "1", "tak", "true", "yes", "y", "t", "oplacona", "zaplacona", "paid": return true
        case "0", "nie", "false", "no", "n", "nieoplacona", "unpaid": return false
        default: return nil
        }
    }

    private static func invoiceKind(_ text: String) -> Invoice.Kind? {
        switch normalizedHeader(text) {
        case "sprzedaz", "sprzedazowa", "przychod", "income", "sales", "sale": return .sales
        case "zakup", "zakupowa", "koszt", "wydatek", "purchase", "expense", "cost": return .purchase
        default: return nil
        }
    }

    private static func productType(_ text: String) -> Product.ProductType {
        switch normalizedHeader(text) {
        case "usluga", "service", "u": return .service
        default: return .goods
        }
    }

    /// `Invoice.documentTypeRaw` to zamknięty słownik (filtry typów, wykrywanie
    /// korekt) — wartości z pliku sprowadzamy do znanych kodów, a nieznane
    /// zgłaszamy ostrzeżeniem i traktujemy jak zwykłą fakturę VAT.
    private static func normalizedDocumentType(
        _ text: String, _ rowNumber: Int, _ plan: inout BulkImportPlan
    ) -> String {
        switch normalizedHeader(text) {
        case "", "vat", "faktura", "faktura vat", "invoice", "sales invoice":
            return "VAT"
        case "zal", "zaliczka", "zaliczkowa", "faktura zaliczkowa", "advance", "advance invoice", "prepayment":
            return "ZAL"
        case "roz", "rozliczeniowa", "koncowa", "faktura rozliczeniowa", "faktura koncowa", "final", "final invoice":
            return "ROZ"
        case "upr", "uproszczona", "faktura uproszczona", "simplified":
            return "UPR"
        case "vat rr", "rr", "faktura rr", "faktura vat rr":
            return "VAT_RR"
        case "kor", "korekta", "korygujaca", "faktura korygujaca", "korekta faktury", "correction", "credit note":
            return "KOR"
        case "kor zal", "korekta zaliczki", "korekta faktury zaliczkowej":
            return "KOR_ZAL"
        case "kor roz", "korekta rozliczeniowej", "korekta faktury rozliczeniowej":
            return "KOR_ROZ"
        case "kor vat rr", "korekta rr", "korekta vat rr":
            return "KOR_VAT_RR"
        case "pro", "proforma", "pro forma", "faktura proforma", "faktura pro forma":
            return "PRO"
        default:
            plan.issues.append(.init(
                row: rowNumber, severity: .warning,
                message: "Nieznany typ dokumentu „\(text)”; przyjęto zwykłą fakturę VAT."
            ))
            return "VAT"
        }
    }

    private static func paymentForm(_ text: String) -> PaymentForm? {
        switch normalizedHeader(text) {
        case "1", "gotowka", "cash": return .cash
        case "2", "karta", "card": return .card
        case "3", "bon", "voucher": return .voucher
        case "4", "czek", "cheque", "check": return .cheque
        case "5", "kredyt", "credit": return .credit
        case "6", "przelew", "transfer", "bank transfer": return .transfer
        case "7", "platnosc mobilna", "mobile": return .mobile
        default: return nil
        }
    }

    private static func normalizedVAT(_ text: String) -> String? {
        let normalized = normalizedHeader(text)
            .replacingOccurrences(of: "vat", with: "")
            .trimmingCharacters(in: .whitespaces)
        if ["zw", "zwolniona", "exempt"].contains(normalized) { return VATRate.exempt.rawValue }
        guard let number = parsedOptionalNumber(normalized) ?? nil else { return nil }
        return number.rounded() == number ? String(Int(number)) : String(number)
    }

    private static func normalizedGTU(_ text: String) -> String {
        let value = trimmed(text).uppercased().replacingOccurrences(of: "-", with: "_")
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("GTU_") { return value }
        if let number = Int(value) { return String(format: "GTU_%02d", number) }
        return value
    }

    private static func amountsEqual(
        _ invoice: ImportedInvoice, _ amounts: (net: Double, vat: Double, gross: Double)
    ) -> Bool {
        abs(invoice.netAmount - amounts.net) < 0.005
            && abs(invoice.vatAmount - amounts.vat) < 0.005
            && abs(invoice.grossAmount - amounts.gross) < 0.005
    }

    private static func nonEmpty(_ value: String, default fallback: String) -> String {
        value.isEmpty ? fallback : value
    }

    private static func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
    private static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedHeader(_ value: String) -> String {
        let folded = trimmed(value)
            .replacingOccurrences(of: "ł", with: "l", options: .caseInsensitive)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
        return folded.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0 == ":" || $0 == "(" || $0 == ")" })
            .joined(separator: " ")
    }

    // Nagłówki spotykane w eksportach Fakturowni, wFirmy i typowych plikach
    // migracyjnych. Użytkownik może nadpisać każde dopasowanie w kreatorze.
    private static func aliases(for field: BulkImportField) -> [String] {
        switch field {
        case .contractorName: return ["nazwa", "nazwa firmy", "firma", "kontrahent", "client name", "name"]
        case .contractorNameLine2: return ["nazwa 2", "druga linia nazwy", "nazwa cd"]
        case .contractorNIP: return ["nip", "nip vat", "vat id", "tax id", "identyfikator podatkowy"]
        case .contractorUEPrefix: return ["prefiks ue", "prefiks vat", "kod vat ue"]
        case .contractorSupplier: return ["dostawca", "czy dostawca", "supplier"]
        case .contractorRecipient: return ["odbiorca", "czy odbiorca", "client", "customer"]
        case .contractorStreet: return ["ulica", "street"]
        case .contractorHouseNumber: return ["nr domu", "numer domu", "house number"]
        case .contractorApartmentNumber: return ["nr lokalu", "numer lokalu", "apartment"]
        case .contractorPostalCode: return ["kod pocztowy", "kod", "postal code", "zip"]
        case .contractorCity: return ["miejscowosc", "miasto", "city"]
        case .contractorCountryName: return ["kraj", "country"]
        case .contractorCountryCode: return ["kod kraju", "symbol kraju", "country code"]
        case .contractorPhone: return ["telefon", "phone", "tel"]
        case .contractorEmail: return ["email", "e mail", "adres email"]
        case .contractorInvoiceEmail: return ["email do faktur", "email faktury", "invoice email"]
        case .contractorWebsite: return ["www", "strona www", "website"]
        case .contractorNotes: return ["uwagi", "notatki", "notes"]
        case .contractorBilingual: return ["dokumenty pl en", "dwujezyczne", "bilingual"]
        case .productName: return ["nazwa", "nazwa produktu", "towar usluga", "produkt", "product name"]
        case .productType: return ["typ", "rodzaj", "towar usluga typ", "type"]
        case .productUnit: return ["jednostka", "jm", "j m", "unit"]
        case .productCategory: return ["kategoria", "category"]
        case .productSKU: return ["sku", "indeks", "kod produktu", "symbol"]
        case .productBrand: return ["marka", "brand"]
        case .productEAN: return ["ean", "gtin", "kod kreskowy"]
        case .productCNPkwiu: return ["cn pkwiu", "pkwiu", "cn", "kod cn pkwiu"]
        case .productGTU: return ["gtu", "kod gtu"]
        case .productAttachment15: return ["zalacznik 15", "zal 15", "attachment 15"]
        case .productSalePriceNet: return ["cena netto", "cena sprzedazy netto", "netto sprzedaz", "price net"]
        case .productSalePriceGross: return ["cena brutto", "cena sprzedazy brutto", "brutto sprzedaz", "price gross"]
        case .productSaleVAT: return ["vat", "stawka vat", "vat sprzedazy"]
        case .productPurchasePriceNet: return ["cena", "cena zakupu", "cena zakupu netto", "netto zakup", "purchase price", "purchase price net"]
        case .productPurchaseVAT: return ["stawka", "vat zakupu", "stawka vat zakupu", "purchase vat"]
        case .productPurchasePriceKind: return ["rodzaj ceny", "typ ceny", "price kind", "price type"]
        case .invoiceNumber: return ["numer", "numer faktury", "nr faktury", "invoice number", "number"]
        case .invoiceIssueDate: return ["data wystawienia", "data", "issue date", "invoice date"]
        case .invoiceKind: return ["rodzaj", "typ ewidencji", "sprzedaz zakup", "invoice kind"]
        case .invoiceKSeFID: return ["numer ksef", "nr ksef", "ksef id", "ksef"]
        case .invoiceContractorName: return ["kontrahent", "nazwa kontrahenta", "klient", "client", "customer", "firma"]
        case .invoiceContractorNIP: return ["nip kontrahenta", "nip klienta", "client nip", "customer vat id", "nip"]
        case .invoiceContractorAddress: return ["adres kontrahenta", "adres klienta", "client address"]
        case .invoiceSellerName: return ["sprzedawca", "nazwa sprzedawcy", "seller name"]
        case .invoiceSellerNIP: return ["nip sprzedawcy", "seller nip", "seller vat id", "seller tax no"]
        case .invoiceSellerAddress: return ["adres sprzedawcy", "seller address"]
        case .invoiceBuyerName: return ["nabywca", "nazwa nabywcy", "buyer name"]
        case .invoiceBuyerNIP: return ["nip nabywcy", "buyer nip", "buyer vat id", "buyer tax no"]
        case .invoiceBuyerAddress: return ["adres nabywcy", "buyer address"]
        case .invoiceNet: return ["netto", "wartosc netto", "razem netto", "net amount", "total net", "price net"]
        case .invoiceVAT: return ["podatek", "kwota vat", "vat", "vat amount", "razem vat"]
        case .invoiceGross: return ["brutto", "wartosc brutto", "razem brutto", "gross amount", "total gross", "price gross"]
        case .invoiceCurrency: return ["waluta", "currency"]
        case .invoiceExchangeRate: return ["kurs", "kurs waluty", "exchange rate"]
        case .invoicePaid: return ["oplacona", "zaplacona", "status platnosci", "paid", "paymentstate", "payment state"]
        case .invoicePaymentDueDate: return ["termin platnosci", "data platnosci", "due date", "payment deadline"]
        case .invoicePaymentDate: return ["data zaplaty", "payment date", "paid at"]
        case .invoicePaymentForm: return ["forma platnosci", "sposob platnosci", "payment method", "paymentmethod"]
        case .invoiceBankAccount: return ["rachunek bankowy", "konto", "nr konta", "bank account"]
        case .invoiceSplitPayment: return ["mpp", "split payment", "podzielona platnosc"]
        case .invoiceDocumentType: return ["typ dokumentu", "rodzaj dokumentu", "document type"]
        case .invoiceNotes: return ["uwagi", "opis", "notes", "description"]
        case .invoiceCostCategory: return ["kategoria kosztu", "cost category"]
        case .lineName: return ["nazwa pozycji", "pozycja", "produkt", "item", "item name", "position name"]
        case .lineUnit: return ["jednostka pozycji", "jm pozycji", "item unit"]
        case .lineQuantity: return ["ilosc", "ilosc pozycji", "quantity", "count"]
        case .lineUnitNetPrice: return ["cena jednostkowa netto", "cena pozycji netto", "unit net price"]
        case .lineNet: return ["wartosc pozycji netto", "netto pozycji", "line net"]
        case .lineVATRate: return ["stawka vat pozycji", "vat pozycji", "line vat rate", "vatcode"]
        case .lineVAT: return ["kwota vat pozycji", "podatek pozycji", "line vat"]
        case .lineCNPkwiu: return ["cn pkwiu pozycji", "pkwiu pozycji", "line cn pkwiu", "classification"]
        case .lineGTU: return ["gtu pozycji", "line gtu"]
        }
    }
}
