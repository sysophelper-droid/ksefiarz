import Foundation

/// Szkic proformy — dane wprowadzane w formularzu, walidowane przed zapisem
/// (`ProformaValidator`). Kwoty netto/VAT/brutto są zawsze wyliczane z pozycji.
/// Pozycje reużywają `InvoiceLineDraft` (te same edytory), ale proforma
/// zapisuje tylko ich handlową część (bez GTU/procedur/OSS).
public struct ProformaDraft: Equatable, Sendable {
    public var proformaNumber: String
    public var issueDate: Date
    public var validUntil: Date?
    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    public var lines: [InvoiceLineDraft]
    public var paymentDueDate: Date?
    public var paymentForm: PaymentForm?
    public var paymentBankAccount: String
    public var notes: String
    public var currency: String
    public var exchangeRate: Double
    public var isPaid: Bool
    public var paymentDate: Date?

    public init(
        proformaNumber: String,
        issueDate: Date,
        validUntil: Date? = nil,
        sellerName: String,
        sellerNIP: String,
        sellerAddress: String = "",
        buyerName: String,
        buyerNIP: String = "",
        buyerAddress: String = "",
        lines: [InvoiceLineDraft] = [],
        paymentDueDate: Date? = nil,
        paymentForm: PaymentForm? = nil,
        paymentBankAccount: String = "",
        notes: String = "",
        currency: String = "PLN",
        exchangeRate: Double = 0,
        isPaid: Bool = false,
        paymentDate: Date? = nil
    ) {
        self.proformaNumber = proformaNumber
        self.issueDate = issueDate
        self.validUntil = validUntil
        self.sellerName = sellerName
        self.sellerNIP = sellerNIP
        self.sellerAddress = sellerAddress
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.buyerAddress = buyerAddress
        self.lines = lines
        self.paymentDueDate = paymentDueDate
        self.paymentForm = paymentForm
        self.paymentBankAccount = paymentBankAccount
        self.notes = notes
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.isPaid = isPaid
        self.paymentDate = paymentDate
    }

    /// Suma netto pozycji (zaokrąglona do groszy).
    public var netAmount: Double {
        ((lines.reduce(0) { $0 + $1.netAmount }) * 100).rounded() / 100
    }

    /// Suma VAT pozycji (zaokrąglona do groszy).
    public var vatAmount: Double {
        ((lines.reduce(0) { $0 + $1.vatAmount }) * 100).rounded() / 100
    }

    /// Suma brutto (netto + VAT).
    public var grossAmount: Double {
        netAmount + vatAmount
    }
}

public extension ProformaDraft {
    /// Odtwarza szkic z zapisanej proformy — do edycji.
    init(from proforma: Proforma) {
        let lines = proforma.sortedLines.map { line in
            InvoiceLineDraft(
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                vatRate: VATRate(rawValue: line.vatRate) ?? .standard,
                cnPkwiu: line.cnPkwiu
            )
        }
        self.init(
            proformaNumber: proforma.proformaNumber,
            issueDate: proforma.issueDate,
            validUntil: proforma.validUntil,
            sellerName: proforma.sellerName,
            sellerNIP: proforma.sellerNIP,
            sellerAddress: proforma.sellerAddress,
            buyerName: proforma.buyerName,
            buyerNIP: proforma.buyerNIP,
            buyerAddress: proforma.buyerAddress,
            lines: lines,
            paymentDueDate: proforma.paymentDueDate,
            paymentForm: proforma.paymentForm,
            paymentBankAccount: proforma.paymentBankAccount ?? "",
            notes: proforma.notes,
            currency: proforma.currency,
            exchangeRate: proforma.exchangeRate,
            isPaid: proforma.isPaid,
            paymentDate: proforma.paymentDate
        )
    }

    /// Szkic właściwej faktury VAT zbudowany z proformy — punkt wyjścia do
    /// konwersji (proforma → faktura). Numer jest celowo pusty: `NewInvoiceView`
    /// nadaje go z serii VAT. Termin płatności domyślnie 14 dni od dziś, gdy
    /// proforma nie miała własnego terminu.
    func invoiceDraft(issueDate: Date = .now) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "",
            issueDate: issueDate,
            sellerName: sellerName,
            sellerNIP: sellerNIP,
            sellerAddress: sellerAddress,
            buyerName: buyerName,
            buyerNIP: buyerNIP,
            buyerAddress: buyerAddress,
            lines: lines,
            paymentDueDate: paymentDueDate
                ?? Calendar.current.date(byAdding: .day, value: 14, to: issueDate),
            paymentForm: paymentForm,
            paymentBankAccount: paymentBankAccount,
            notes: notes,
            invoiceType: "VAT",
            currency: currency,
            exchangeRate: exchangeRate
        )
    }
}

public extension Proforma {
    /// Szkic faktury VAT do konwersji tej proformy (patrz `ProformaDraft.invoiceDraft`).
    func invoiceDraft(issueDate: Date = .now) -> InvoiceDraft {
        ProformaDraft(from: self).invoiceDraft(issueDate: issueDate)
    }
}
