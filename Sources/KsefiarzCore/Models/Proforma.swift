import Foundation
import SwiftData

/// Faktura proforma — **dokument handlowy**, a NIE dokument księgowy.
///
/// Proforma nie idzie do KSeF, nie tworzy obowiązku VAT i nie wchodzi do
/// żadnej ewidencji podatkowej (KPiR, ryczałt, JPK_V7, VAT-UE) ani statystyk.
/// Dlatego jest **osobnym modelem SwiftData** — strukturalnie nie może trafić
/// do żadnego `FetchDescriptor<Invoice>`/`@Query<Invoice>`, więc żadna
/// agregacja faktur (Kokpit, raporty, historia kontrahenta, terminy) nie
/// policzy jej przez pomyłkę. To świadoma decyzja: zamiast pamiętać
/// o wykluczeniu proformy w ~20 miejscach, izolujemy ją typem.
///
/// Cykl życia: aktywna → (opcjonalnie opłacona zaliczkowo) → **rozliczona**
/// właściwą fakturą VAT (konwersja przez `NewInvoiceView`, wypełniony
/// `invoiceDraft()`; po zapisie faktury proforma dostaje numer i datę
/// rozliczenia). Do wydruku i e-maila proforma reużywa infrastruktury faktur
/// przez PRZEJŚCIOWĄ (nieutrwaloną) `Invoice` — patrz `transientInvoice()`.
@Model
public final class Proforma {

    /// Unikalny identyfikator lokalny.
    @Attribute(.unique) public var id: UUID

    /// Numer własny proformy (np. PF/2026/07/001) — niezależny od serii VAT.
    public var proformaNumber: String

    /// Data wystawienia.
    public var issueDate: Date

    /// „Ważna do" — data ważności oferty/proformy (opcjonalna).
    public var validUntil: Date?

    /// Dane sprzedawcy (nasza firma).
    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String = ""

    /// Dane nabywcy. NIP jest OPCJONALNY (proforma bywa wystawiana
    /// konsumentowi albo kontrahentowi zagranicznemu).
    public var buyerName: String
    public var buyerNIP: String = ""
    public var buyerAddress: String = ""

    /// Kwoty: netto, VAT, brutto.
    public var netAmount: Double
    public var vatAmount: Double
    public var grossAmount: Double

    /// Waluta (kwoty są w tej walucie).
    public var currency: String = "PLN"
    /// Kurs PLN dla waluty obcej (0 = nie dotyczy) — do przeliczeń informacyjnych.
    public var exchangeRate: Double = 0

    /// Znacznik opłacenia (np. klient wpłacił zaliczkę na poczet proformy).
    /// Domyślnie `false` — sensem proformy jest oczekiwanie na wpłatę.
    public var isPaid: Bool = false
    /// Data wpłaty (opcjonalna).
    public var paymentDate: Date?
    /// Termin płatności (opcjonalny).
    public var paymentDueDate: Date?
    /// Forma płatności (kod słownika `PaymentForm`).
    public var paymentFormRaw: String?
    /// Numer rachunku bankowego do płatności (NRB).
    public var paymentBankAccount: String?

    /// Uwagi (dopisek drukowany na proformie).
    public var notes: String = ""

    /// Kiedy dokument utworzono lokalnie.
    public var createdAt: Date = Date.now

    /// Numer właściwej faktury VAT, którą rozliczono tę proformę.
    /// Pusty = proforma jeszcze nierozliczona.
    public var convertedInvoiceNumber: String = ""
    /// Data rozliczenia (wystawienia właściwej faktury z proformy).
    public var convertedAt: Date? = nil

    /// Data przekazania proformy do wysyłki e-mailem (nil = nie wysyłano).
    public var emailSentAt: Date? = nil
    /// Adres, na który przekazano proformę e-mailem.
    public var emailSentTo: String = ""

    /// Pozycje proformy.
    @Relationship(deleteRule: .cascade, inverse: \ProformaLine.proforma)
    public var lines: [ProformaLine] = []

    public init(
        id: UUID = UUID(),
        proformaNumber: String,
        issueDate: Date,
        validUntil: Date? = nil,
        sellerName: String,
        sellerNIP: String,
        sellerAddress: String = "",
        buyerName: String,
        buyerNIP: String = "",
        buyerAddress: String = "",
        netAmount: Double,
        vatAmount: Double,
        grossAmount: Double,
        currency: String = "PLN",
        exchangeRate: Double = 0,
        isPaid: Bool = false,
        paymentDate: Date? = nil,
        paymentDueDate: Date? = nil,
        paymentForm: PaymentForm? = nil,
        paymentBankAccount: String? = nil,
        notes: String = "",
        createdAt: Date = .now,
        convertedInvoiceNumber: String = "",
        convertedAt: Date? = nil
    ) {
        self.id = id
        self.proformaNumber = proformaNumber
        self.issueDate = issueDate
        self.validUntil = validUntil
        self.sellerName = sellerName
        self.sellerNIP = sellerNIP
        self.sellerAddress = sellerAddress
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.buyerAddress = buyerAddress
        self.netAmount = netAmount
        self.vatAmount = vatAmount
        self.grossAmount = grossAmount
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.isPaid = isPaid
        self.paymentDate = paymentDate
        self.paymentDueDate = paymentDueDate
        self.paymentFormRaw = paymentForm?.rawValue
        self.paymentBankAccount = paymentBankAccount
        self.notes = notes
        self.createdAt = createdAt
        self.convertedInvoiceNumber = convertedInvoiceNumber
        self.convertedAt = convertedAt
    }

    /// Forma płatności jako enum (jeśli znana).
    public var paymentForm: PaymentForm? {
        get { paymentFormRaw.flatMap(PaymentForm.init(rawValue:)) }
        set { paymentFormRaw = newValue?.rawValue }
    }

    /// Pozycje posortowane po numerze wiersza.
    public var sortedLines: [ProformaLine] {
        lines.sorted { $0.index < $1.index }
    }

    /// Zastępuje pozycje podczas edycji i jawnie usuwa poprzednie modele.
    /// Samo przypisanie nowej tablicy odłącza stare `ProformaLine`, ale ich nie
    /// kasuje, przez co kolejne edycje zostawiały osierocone rekordy w bazie.
    public func replaceLines(with newLines: [ProformaLine], in context: ModelContext) {
        let previousLines = lines
        lines = []
        previousLines.forEach(context.delete)
        lines = newLines
    }

    /// Czy proforma została już rozliczona właściwą fakturą VAT.
    public var isConverted: Bool {
        !convertedInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Saldo pozostałe „do zapłaty" — kwota brutto, gdy nieopłacona; 0 gdy
    /// opłacona. Proforma nie prowadzi historii wpłat częściowych.
    public var outstandingAmount: Double {
        isPaid ? 0 : max(0, grossAmount)
    }

    /// Proforma po terminie płatności (nieopłacona) na wskazany moment.
    public func isOverdue(asOf date: Date = .now) -> Bool {
        guard !isPaid, let due = paymentDueDate else { return false }
        // Termin wskazany w DatePickerze jest datą kalendarzową: dokument
        // staje się zaległy dopiero następnego dnia, a nie o północy terminu.
        return Calendar.current.compare(date, to: due, toGranularity: .day) == .orderedDescending
    }

    /// Zaległość względem chwili bieżącej.
    public var isOverdue: Bool { isOverdue(asOf: .now) }

    /// Czy proforma utraciła ważność (minęła data „ważna do") na dany moment.
    public func isExpired(asOf date: Date = .now) -> Bool {
        guard !isConverted, let validUntil else { return false }
        // „Ważna do" obejmuje cały wskazany dzień kalendarzowy.
        return Calendar.current.compare(date, to: validUntil, toGranularity: .day) == .orderedDescending
    }

    /// Oznacza proformę jako rozliczoną wskazaną fakturą VAT.
    public func markConverted(toInvoiceNumber number: String, at date: Date = .now) {
        convertedInvoiceNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        convertedAt = date
    }

    /// Oznacza konwersję i przenosi ręcznie potwierdzony status zapłaty na
    /// właściwą fakturę. Status może zostać wyłącznie ustawiony — nie cofamy
    /// opłacenia nadanego fakturze np. przez `PaymentFormPolicy`.
    public func markConverted(to invoice: Invoice, at date: Date = .now) {
        markConverted(toInvoiceNumber: invoice.invoiceNumber, at: date)
        guard isPaid else { return }
        invoice.isPaid = true
        if invoice.paymentDate == nil {
            invoice.paymentDate = paymentDate
        }
    }

    /// PRZEJŚCIOWA (nieutrwalona!) faktura sprzedaży zbudowana z proformy —
    /// most do reużycia generatora PDF i wysyłki e-mail bez duplikowania ich
    /// logiki. Obiekt NIE jest wstawiany do żadnego kontekstu SwiftData;
    /// służy wyłącznie jako źródło danych do renderu/e-maila i po użyciu ginie.
    ///
    /// Rodzaj `sales` i pusty `ksefId` sprawiają, że generator dokłada kod QR
    /// płatności (klient płaci za proformę), a NIE dokłada kodów weryfikacyjnych
    /// KSeF (dokument nie jest w KSeF). Rodzaj dokumentu „PRO" wybiera na
    /// wydruku tytuł „Faktura PROFORMA" i adnotację o charakterze dokumentu.
    public func transientInvoice() -> Invoice {
        let invoice = Invoice(
            invoiceNumber: proformaNumber,
            issueDate: issueDate,
            sellerName: sellerName,
            sellerNIP: sellerNIP,
            sellerAddress: sellerAddress,
            buyerName: buyerName,
            buyerNIP: buyerNIP,
            buyerAddress: buyerAddress,
            netAmount: netAmount,
            vatAmount: vatAmount,
            grossAmount: grossAmount,
            isPaid: isPaid,
            paymentDueDate: paymentDueDate,
            paymentForm: paymentForm,
            paymentBankAccount: paymentBankAccount,
            paymentDate: paymentDate,
            documentType: "PRO",
            notes: notes,
            currency: currency,
            exchangeRate: exchangeRate,
            kind: .sales
        )
        invoice.lines = sortedLines.map { line in
            InvoiceLine(
                index: line.index,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu
            )
        }
        return invoice
    }
}

/// Pojedyncza pozycja proformy — odwzorowanie handlowe pozycji faktury
/// (bez pól typowo podatkowych: GTU, procedury, OSS, VAT RR).
@Model
public final class ProformaLine {
    /// Numer wiersza (od 1).
    public var index: Int
    /// Nazwa towaru lub usługi.
    public var name: String
    /// Jednostka miary (np. "szt.").
    public var unit: String
    /// Ilość.
    public var quantity: Double
    /// Cena jednostkowa netto.
    public var unitNetPrice: Double
    /// Wartość netto pozycji.
    public var netAmount: Double
    /// Stawka VAT (rawValue `VATRate`, np. "23").
    public var vatRate: String
    /// Kwota VAT pozycji.
    public var vatAmount: Double
    /// Kod CN lub PKWiU (opcjonalny).
    public var cnPkwiu: String = ""

    /// Proforma, do której należy pozycja.
    public var proforma: Proforma?

    public init(
        index: Int,
        name: String,
        unit: String = "szt.",
        quantity: Double = 1,
        unitNetPrice: Double = 0,
        netAmount: Double = 0,
        vatRate: String = "23",
        vatAmount: Double = 0,
        cnPkwiu: String = ""
    ) {
        self.index = index
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitNetPrice = unitNetPrice
        self.netAmount = netAmount
        self.vatRate = vatRate
        self.vatAmount = vatAmount
        self.cnPkwiu = cnPkwiu
    }
}
