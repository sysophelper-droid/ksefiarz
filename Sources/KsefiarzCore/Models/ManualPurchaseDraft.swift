import Foundation

/// Błędy walidacji ręcznie dodawanej faktury kosztowej.
public enum ManualPurchaseValidationError: LocalizedError, Hashable {
    case emptyDocumentNumber
    case emptySellerName
    case zeroAmount
    case missingExchangeRate

    public var errorDescription: String? {
        switch self {
        case .emptyDocumentNumber:
            return "Podaj numer dokumentu (faktury lub paragonu)."
        case .emptySellerName:
            return "Podaj nazwę sprzedawcy."
        case .zeroAmount:
            return "Kwota dokumentu nie może być zerowa."
        case .missingExchangeRate:
            return "Dla waluty obcej podaj kurs PLN (przycisk NBP albo ręcznie) — bez niego statystyki i JPK nie przeliczą kwot."
        }
    }
}

/// Szkic faktury kosztowej spoza KSeF — zakupy dodawane ręcznie
/// (faktury zagraniczne, paragony z NIP). Dokument istnieje wyłącznie
/// lokalnie (bez XML i numeru KSeF); kwota brutto wynika z netto + VAT.
public struct ManualPurchaseDraft: Equatable, Sendable {
    public var documentNumber: String
    public var issueDate: Date
    /// Data sprzedaży / wykonania usługi (opcjonalna).
    public var saleDate: Date?
    public var sellerName: String
    /// NIP sprzedawcy albo zagraniczny identyfikator VAT (np. "DE123456789");
    /// może być pusty (np. paragon zagraniczny).
    public var sellerTaxID: String
    public var sellerAddress: String
    /// Nabywca — dane firmy użytkownika (z Ustawień).
    public var buyerName: String
    public var buyerNIP: String
    public var netAmount: Double
    public var vatAmount: Double
    public var currency: String
    /// Kurs PLN dla waluty obcej (0 = nie dotyczy).
    public var exchangeRate: Double
    public var paymentDueDate: Date?
    public var paymentForm: PaymentForm?
    public var paymentBankAccount: String
    /// Kategoria kosztu — grupuje wydatki w raportach.
    public var costCategory: String
    public var notes: String
    public var isPaid: Bool
    public var paymentDate: Date?

    /// Kwota brutto — zawsze netto + VAT (zaokrąglenie do groszy).
    public var grossAmount: Double {
        ((netAmount + vatAmount) * 100).rounded() / 100
    }

    public init(
        documentNumber: String = "",
        issueDate: Date = .now,
        saleDate: Date? = nil,
        sellerName: String = "",
        sellerTaxID: String = "",
        sellerAddress: String = "",
        buyerName: String = "",
        buyerNIP: String = "",
        netAmount: Double = 0,
        vatAmount: Double = 0,
        currency: String = "PLN",
        exchangeRate: Double = 0,
        paymentDueDate: Date? = nil,
        paymentForm: PaymentForm? = nil,
        paymentBankAccount: String = "",
        costCategory: String = "",
        notes: String = "",
        isPaid: Bool = false,
        paymentDate: Date? = nil
    ) {
        self.documentNumber = documentNumber
        self.issueDate = issueDate
        self.saleDate = saleDate
        self.sellerName = sellerName
        self.sellerTaxID = sellerTaxID
        self.sellerAddress = sellerAddress
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.netAmount = netAmount
        self.vatAmount = vatAmount
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.paymentDueDate = paymentDueDate
        self.paymentForm = paymentForm
        self.paymentBankAccount = paymentBankAccount
        self.costCategory = costCategory
        self.notes = notes
        self.isPaid = isPaid
        self.paymentDate = paymentDate
    }

    /// Waliduje szkic; pusta lista błędów oznacza dane gotowe do zapisu.
    public func validate() -> [ManualPurchaseValidationError] {
        var errors: [ManualPurchaseValidationError] = []
        if documentNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyDocumentNumber)
        }
        if sellerName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptySellerName)
        }
        if abs(grossAmount) < 0.005 {
            errors.append(.zeroAmount)
        }
        if currency != "PLN", exchangeRate <= 0 {
            errors.append(.missingExchangeRate)
        }
        return errors
    }

    /// Buduje nową fakturę zakupową (dokument tylko lokalny, bez KSeF).
    public func makeInvoice() -> Invoice {
        let invoice = Invoice(
            invoiceNumber: documentNumber.trimmingCharacters(in: .whitespaces),
            issueDate: issueDate,
            sellerName: sellerName.trimmingCharacters(in: .whitespaces),
            sellerNIP: sellerTaxID.trimmingCharacters(in: .whitespaces),
            sellerAddress: sellerAddress,
            buyerName: buyerName,
            buyerNIP: buyerNIP,
            netAmount: netAmount,
            vatAmount: vatAmount,
            grossAmount: grossAmount,
            isPaid: isPaid,
            paymentDueDate: paymentDueDate,
            paymentForm: paymentForm,
            paymentBankAccount: paymentBankAccount.isEmpty ? nil : paymentBankAccount,
            paymentDate: isPaid ? (paymentDate ?? issueDate) : nil,
            notes: notes,
            currency: currency,
            exchangeRate: exchangeRate,
            saleDate: saleDate,
            kind: .purchase
        )
        invoice.costCategory = costCategory.trimmingCharacters(in: .whitespaces)
        return invoice
    }

    /// Nanosi szkic na istniejący ręczny zakup (edycja).
    /// Statusu „opłacona” nie cofa — ręczna decyzja użytkownika jest
    /// nadrzędna (niezmiennik `isPaid`); może go tylko ustawić.
    public func apply(to invoice: Invoice) {
        invoice.invoiceNumber = documentNumber.trimmingCharacters(in: .whitespaces)
        invoice.issueDate = issueDate
        invoice.saleDate = saleDate
        invoice.sellerName = sellerName.trimmingCharacters(in: .whitespaces)
        invoice.sellerNIP = sellerTaxID.trimmingCharacters(in: .whitespaces)
        invoice.sellerAddress = sellerAddress
        invoice.buyerName = buyerName
        invoice.buyerNIP = buyerNIP
        invoice.netAmount = netAmount
        invoice.vatAmount = vatAmount
        invoice.grossAmount = grossAmount
        invoice.currency = currency
        invoice.exchangeRate = exchangeRate
        invoice.paymentDueDate = paymentDueDate
        invoice.paymentForm = paymentForm
        invoice.paymentBankAccount = paymentBankAccount.isEmpty ? nil : paymentBankAccount
        invoice.costCategory = costCategory.trimmingCharacters(in: .whitespaces)
        invoice.notes = notes
        if isPaid {
            invoice.isPaid = true
            invoice.paymentDate = paymentDate ?? issueDate
        }
    }
}

public extension ManualPurchaseDraft {
    /// Odtwarza szkic z zapisanego ręcznego zakupu (edycja).
    init(from invoice: Invoice) {
        self.init(
            documentNumber: invoice.invoiceNumber,
            issueDate: invoice.issueDate,
            saleDate: invoice.saleDate,
            sellerName: invoice.sellerName,
            sellerTaxID: invoice.sellerNIP,
            sellerAddress: invoice.sellerAddress,
            buyerName: invoice.buyerName,
            buyerNIP: invoice.buyerNIP,
            netAmount: invoice.netAmount,
            vatAmount: invoice.vatAmount,
            currency: invoice.currency,
            exchangeRate: invoice.exchangeRate,
            paymentDueDate: invoice.paymentDueDate,
            paymentForm: invoice.paymentForm,
            paymentBankAccount: invoice.paymentBankAccount ?? "",
            costCategory: invoice.costCategory,
            notes: invoice.notes,
            isPaid: invoice.isPaid,
            paymentDate: invoice.paymentDate
        )
    }
}

public extension Invoice {
    /// Faktura kosztowa dodana ręcznie (spoza KSeF) — można ją edytować
    /// i usuwać, w odróżnieniu od zakupów pobranych z KSeF.
    var isManualPurchase: Bool {
        kind == .purchase && ksefId == nil
    }
}
