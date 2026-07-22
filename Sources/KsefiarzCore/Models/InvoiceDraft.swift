import Foundation

/// Szkic faktury sprzedażowej — dane wprowadzane w formularzu,
/// walidowane przed wygenerowaniem XML FA(3) lub FA_RR(1) i wysyłką do KSeF.
public struct InvoiceDraft: Equatable, Sendable {
    public var invoiceNumber: String
    public var issueDate: Date
    public var sellerName: String
    public var sellerNIP: String
    /// Adres sprzedawcy — wymagany przez schemę FA(2) (Podmiot1/Adres).
    public var sellerAddress: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    /// Pozycje faktury. Gdy niepuste, kwoty netto/VAT/brutto są z nich wyliczane.
    public var lines: [InvoiceLineDraft]
    public var netAmount: Double
    public var vatAmount: Double
    public var grossAmount: Double
    public var paymentDueDate: Date?
    public var paymentForm: PaymentForm?
    public var paymentBankAccount: String
    /// Uwagi (dopisek na fakturze) — Stopka/Informacje/StopkaFaktury w XML.
    public var notes: String = ""
    /// Rodzaj faktury: "VAT", "ZAL", "ROZ", "UPR" lub "VAT_RR";
    /// korekta (`correction != nil`) ma pierwszeństwo i daje "KOR".
    public var invoiceType: String = "VAT"
    /// Waluta faktury (KodWaluty).
    public var currency: String = "PLN"
    /// Kurs PLN dla waluty obcej (0 = nie dotyczy) — pola P_14_xW.
    public var exchangeRate: Double = 0
    /// Mechanizm podzielonej płatności (Adnotacje P_18A = 1).
    public var splitPayment: Bool = false
    /// Samofakturowanie (Adnotacje P_17 = 1, art. 106d ustawy o VAT) —
    /// wystawiamy dokument jako NABYWCA w imieniu dostawcy (sprzedawcy).
    /// Role stron są już zamienione w polach szkicu (seller = dostawca,
    /// buyer = nasza firma); zapisany dokument jest zakupem. Wysyłka wymaga
    /// uprawnienia SelfInvoicing nadanego nam przez dostawcę w KSeF.
    public var isSelfInvoicing: Bool = false
    /// Data dokonania dostawy / otrzymania zapłaty (P_6).
    public var saleDate: Date?
    /// Numery KSeF faktur zaliczkowych rozliczanych dokumentem ROZ.
    public var advanceInvoiceRefs: [String] = []
    /// Procedura marży (Adnotacje/PMarzy): "" = brak, "2" = biura podróży,
    /// "3_1" = towary używane, "3_2" = dzieła sztuki, "3_3" = antyki.
    public var marginProcedure: String = ""
    /// Załącznik do faktury (element Zalacznik FA(3)) — bloki danych.
    public var attachments: [FA3AttachmentBlock] = []

    /// Rodzaj dokumentu po uwzględnieniu korekty — korekta zaliczkowej
    /// to KOR_ZAL, rozliczeniowej KOR_ROZ.
    public var documentType: String {
        guard correction != nil else { return invoiceType }
        if invoiceType == "VAT_RR" { return "KOR_VAT_RR" }
        switch invoiceType {
        case "ZAL": return "KOR_ZAL"
        case "ROZ": return "KOR_ROZ"
        default: return "KOR"
        }
    }
    /// Dokument korzysta z osobnej struktury logicznej FA_RR(1).
    public var isRR: Bool { invoiceType == "VAT_RR" }
    /// Dane faktury korygowanej — gdy ustawione, dokument jest korektą (KOR),
    /// a kwoty wyrażają różnicę względem faktury pierwotnej (mogą być ujemne).
    public var correction: InvoiceCorrectionInfo?

    public init(
        invoiceNumber: String,
        issueDate: Date,
        sellerName: String,
        sellerNIP: String,
        sellerAddress: String = "",
        buyerName: String,
        buyerNIP: String,
        buyerAddress: String = "",
        lines: [InvoiceLineDraft] = [],
        netAmount: Double = 0,
        vatAmount: Double = 0,
        grossAmount: Double? = nil,
        paymentDueDate: Date? = nil,
        paymentForm: PaymentForm? = nil,
        paymentBankAccount: String = "",
        notes: String = "",
        invoiceType: String = "VAT",
        currency: String = "PLN",
        exchangeRate: Double = 0,
        splitPayment: Bool = false,
        isSelfInvoicing: Bool = false,
        saleDate: Date? = nil,
        advanceInvoiceRefs: [String] = [],
        marginProcedure: String = "",
        attachments: [FA3AttachmentBlock] = [],
        correction: InvoiceCorrectionInfo? = nil
    ) {
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.sellerName = sellerName
        self.sellerNIP = sellerNIP
        self.sellerAddress = sellerAddress
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.buyerAddress = buyerAddress
        self.lines = lines

        if lines.isEmpty {
            // Tryb uproszczony — kwoty podane wprost.
            self.netAmount = netAmount
            self.vatAmount = vatAmount
            self.grossAmount = grossAmount ?? (netAmount + vatAmount)
        } else {
            // Kwoty wyliczane z pozycji.
            let net = lines.reduce(0) { $0 + $1.netAmount }
            let vat = lines.reduce(0) { $0 + $1.vatAmount }
            self.netAmount = (net * 100).rounded() / 100
            self.vatAmount = (vat * 100).rounded() / 100
            self.grossAmount = self.netAmount + self.vatAmount
        }

        self.paymentDueDate = paymentDueDate
        self.paymentForm = paymentForm
        self.paymentBankAccount = paymentBankAccount
        self.notes = notes
        self.invoiceType = invoiceType
        self.currency = CurrencyCode.normalizedOrPLN(currency)
        self.exchangeRate = exchangeRate
        self.splitPayment = splitPayment
        self.isSelfInvoicing = isSelfInvoicing
        self.saleDate = saleDate
        self.advanceInvoiceRefs = advanceInvoiceRefs
        self.marginProcedure = marginProcedure
        self.attachments = attachments
        self.correction = correction
    }
}

public extension InvoiceDraft {
    /// Odtwarza szkic z zapisanej faktury — np. do późniejszej wysyłki
    /// faktury zapisanej tylko lokalnie.
    init(from invoice: Invoice) {
        let correction: InvoiceCorrectionInfo? = invoice.isCorrection
            ? InvoiceCorrectionInfo(
                originalNumber: invoice.correctedInvoiceNumber ?? "",
                originalIssueDate: invoice.correctedInvoiceIssueDate ?? invoice.issueDate,
                originalKsefNumber: invoice.correctedInvoiceKsefId,
                reason: invoice.correctionReason
            )
            : nil

        let lines = invoice.sortedLines.map { line in
            InvoiceLineDraft(
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                vatRate: VATRate(rawValue: line.vatRate) ?? .standard,
                cnPkwiu: line.cnPkwiu,
                gtu: line.gtu,
                procedure: line.procedure,
                ossRate: line.ossRate,
                rrQuality: line.rrQuality
            )
        }

        self.init(
            invoiceNumber: invoice.invoiceNumber,
            issueDate: invoice.issueDate,
            sellerName: invoice.sellerName,
            sellerNIP: invoice.sellerNIP,
            sellerAddress: invoice.sellerAddress,
            buyerName: invoice.buyerName,
            buyerNIP: invoice.buyerNIP,
            buyerAddress: invoice.buyerAddress,
            lines: lines,
            netAmount: invoice.netAmount,
            vatAmount: invoice.vatAmount,
            grossAmount: invoice.grossAmount,
            paymentDueDate: invoice.paymentDueDate,
            paymentForm: invoice.paymentForm,
            paymentBankAccount: invoice.paymentBankAccount ?? "",
            notes: invoice.notes,
            invoiceType: InvoiceDraft.baseType(for: invoice.documentTypeRaw),
            currency: invoice.currency,
            exchangeRate: invoice.exchangeRate,
            splitPayment: invoice.splitPayment,
            isSelfInvoicing: invoice.isSelfInvoicing,
            saleDate: invoice.saleDate,
            advanceInvoiceRefs: invoice.advanceInvoiceRefs,
            marginProcedure: invoice.marginProcedureRaw,
            attachments: .decoded(from: invoice.attachmentJSON),
            correction: correction
        )
    }

    /// Typ bazowy dokumentu (bez przedrostka korekty):
    /// KOR→VAT, KOR_ZAL→ZAL, KOR_ROZ→ROZ, pozostałe bez zmian.
    static func baseType(for documentType: String) -> String {
        switch documentType {
        case "KOR": return "VAT"
        case "KOR_VAT_RR": return "VAT_RR"
        case "KOR_ZAL": return "ZAL"
        case "KOR_ROZ": return "ROZ"
        default: return documentType
        }
    }
}

/// Trwała, przenośna migawka danych faktury używana przez szablony i
/// harmonogramy. Numer i daty są przy odtwarzaniu nadawane na nowo.
public struct InvoicePreset: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var name: String
        public var unit: String
        public var quantity: Double
        public var unitNetPrice: Double
        public var vatRate: String
        public var cnPkwiu: String
        public var gtu: String
        public var procedure: String
        /// Stawka OSS (P_12_XII) — opcjonalna, aby szablony zapisane przed
        /// jej wprowadzeniem dekodowały się bez zmian.
        public var ossRate: Double?
        /// Opcjonalne dla zgodności z szablonami zapisanymi przed obsługą RR.
        public var rrQuality: String?
    }

    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    public var lines: [Line]
    public var paymentFormRaw: String?
    public var paymentBankAccount: String
    public var notes: String
    public var invoiceType: String
    public var currency: String
    public var exchangeRate: Double
    public var splitPayment: Bool
    /// Samofakturowanie — opcjonalne dla zgodności z szablonami zapisanymi
    /// przed obsługą samofaktur (nil = zwykła faktura).
    public var isSelfInvoicing: Bool?
    public var hasSaleDate: Bool
    public var advanceInvoiceRefs: [String]
    public var marginProcedure: String
    /// Załącznik FA(3) — opcjonalny (szablony sprzed wprowadzenia pola).
    public var attachments: [FA3AttachmentBlock]?

    public init(draft: InvoiceDraft) {
        sellerName = draft.sellerName
        sellerNIP = draft.sellerNIP
        sellerAddress = draft.sellerAddress
        buyerName = draft.buyerName
        buyerNIP = draft.buyerNIP
        buyerAddress = draft.buyerAddress
        lines = draft.lines.map {
            Line(name: $0.name, unit: $0.unit, quantity: $0.quantity,
                 unitNetPrice: $0.unitNetPrice, vatRate: $0.vatRate.rawValue,
                 cnPkwiu: $0.cnPkwiu, gtu: $0.gtu, procedure: $0.procedure,
                 ossRate: $0.ossRate, rrQuality: $0.rrQuality)
        }
        paymentFormRaw = draft.paymentForm?.rawValue
        paymentBankAccount = draft.paymentBankAccount
        notes = draft.notes
        invoiceType = draft.invoiceType
        currency = draft.currency
        exchangeRate = draft.exchangeRate
        splitPayment = draft.splitPayment
        isSelfInvoicing = draft.isSelfInvoicing ? true : nil
        hasSaleDate = draft.saleDate != nil
        advanceInvoiceRefs = draft.advanceInvoiceRefs
        marginProcedure = draft.marginProcedure
        attachments = draft.attachments.isEmpty ? nil : draft.attachments
    }

    public func draft(
        invoiceNumber: String = "",
        issueDate: Date = .now,
        dueDays: Int = 14
    ) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: invoiceNumber,
            issueDate: issueDate,
            sellerName: sellerName,
            sellerNIP: sellerNIP,
            sellerAddress: sellerAddress,
            buyerName: buyerName,
            buyerNIP: buyerNIP,
            buyerAddress: buyerAddress,
            lines: lines.map {
                InvoiceLineDraft(name: $0.name, unit: $0.unit, quantity: $0.quantity,
                    unitNetPrice: $0.unitNetPrice,
                    vatRate: VATRate(rawValue: $0.vatRate) ?? .standard,
                    cnPkwiu: $0.cnPkwiu, gtu: $0.gtu, procedure: $0.procedure,
                    ossRate: $0.ossRate, rrQuality: $0.rrQuality ?? "")
            },
            paymentDueDate: Calendar.current.date(byAdding: .day, value: dueDays, to: issueDate),
            paymentForm: paymentFormRaw.flatMap(PaymentForm.init(rawValue:)),
            paymentBankAccount: paymentBankAccount,
            notes: notes,
            invoiceType: invoiceType,
            currency: currency,
            exchangeRate: exchangeRate,
            splitPayment: splitPayment,
            isSelfInvoicing: isSelfInvoicing ?? false,
            saleDate: hasSaleDate ? issueDate : nil,
            advanceInvoiceRefs: advanceInvoiceRefs,
            marginProcedure: marginProcedure,
            attachments: attachments ?? []
        )
    }
}
