import Foundation
import SwiftData

/// Pojedyncza pozycja faktury (FaWiersz w schemie FA(2)).
@Model
public final class InvoiceLine {
    /// Numer wiersza (NrWierszaFa) — od 1.
    public var index: Int
    /// Nazwa towaru lub usługi (P_7).
    public var name: String
    /// Jednostka miary (P_8A), np. "szt.".
    public var unit: String
    /// Ilość (P_8B).
    public var quantity: Double
    /// Cena jednostkowa netto (P_9A).
    public var unitNetPrice: Double
    /// Wartość netto pozycji (P_11).
    public var netAmount: Double
    /// Stawka VAT (P_12): "23", "8", "5", "0" lub "zw".
    public var vatRate: String
    /// Kwota VAT pozycji (wyliczana ze stawki — nie występuje wprost w XML).
    public var vatAmount: Double
    /// Kod CN (towary, np. "85234910") lub PKWiU (usługi, np. "62.01.11.0").
    /// Wartość domyślna obowiązkowa (migracja bazy).
    public var cnPkwiu: String = ""
    /// Kod GTU pozycji (np. "GTU_12"). Wartość domyślna obowiązkowa (migracja bazy).
    public var gtu: String = ""
    /// Oznaczenie procedury pozycji (np. "WSTO_EE", "IED") — element Procedura
    /// w FaWiersz. Wartość domyślna obowiązkowa (migracja bazy).
    public var procedure: String = ""
    /// Stawka podatku od wartości dodanej dla procedury OSS (P_12_XII) —
    /// nil = pozycja z polską stawką (P_12). Wartość domyślna (migracja bazy).
    public var ossRate: Double? = nil

    /// Faktura, do której należy pozycja.
    public var invoice: Invoice?

    public init(
        index: Int,
        name: String,
        unit: String = "szt.",
        quantity: Double = 1,
        unitNetPrice: Double = 0,
        netAmount: Double = 0,
        vatRate: String = "23",
        vatAmount: Double = 0,
        cnPkwiu: String = "",
        gtu: String = "",
        procedure: String = "",
        ossRate: Double? = nil
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
        self.gtu = gtu
        self.procedure = procedure
        self.ossRate = ossRate
    }
}

// MARK: - Stawki VAT

/// Stawki VAT obsługiwane w uproszczonej schemie FA(2).
public enum VATRate: String, CaseIterable, Identifiable, Sendable {
    case standard = "23"
    case reducedFirst = "8"
    case reducedSecond = "5"
    case zero = "0"
    case exempt = "zw"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .exempt: return "zw."
        default: return "\(rawValue)%"
        }
    }

    /// Mnożnik do wyliczenia kwoty VAT (zw. i 0% → 0).
    public var multiplier: Double {
        switch self {
        case .standard: return 0.23
        case .reducedFirst: return 0.08
        case .reducedSecond: return 0.05
        case .zero, .exempt: return 0
        }
    }
}

// MARK: - Pozycja w szkicu faktury

/// Pozycja faktury w formularzu wystawiania — typ wartościowy, walidowany
/// przed wygenerowaniem XML.
public struct InvoiceLineDraft: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var unit: String
    public var quantity: Double
    public var unitNetPrice: Double
    public var vatRate: VATRate
    /// Kod CN lub PKWiU (opcjonalny, edytowalny także po podstawieniu ze słownika).
    public var cnPkwiu: String
    /// Kod GTU (opcjonalny).
    public var gtu: String
    /// Oznaczenie procedury (TOznaczenieProcedury, np. "WSTO_EE") — opcjonalne.
    public var procedure: String = ""
    /// Stawka podatku od wartości dodanej państwa konsumpcji dla procedury
    /// OSS (dział XII rozdz. 6a) — gdy ustawiona, pozycja trafia do XML
    /// z P_12_XII zamiast polskiej stawki, a jej podatek do sum P_13_5/P_14_5.
    public var ossRate: Double? = nil
    /// Towar/usługa z załącznika 15 (ze słownika) — podpowiada włączenie
    /// mechanizmu podzielonej płatności na fakturze; nie trafia do XML pozycji.
    public var isAttachment15: Bool = false

    /// Dopuszczalne oznaczenia procedur (enum TOznaczenieProcedury z XSD FA(3)).
    public static let procedures = [
        "WSTO_EE", "IED", "TT_D", "I_42", "I_63",
        "B_SPV", "B_SPV_DOSTAWA", "B_MPV_PROWIZJA",
    ]

    public init(
        id: UUID = UUID(),
        name: String = "",
        unit: String = "szt.",
        quantity: Double = 1,
        unitNetPrice: Double = 0,
        vatRate: VATRate = .standard,
        cnPkwiu: String = "",
        gtu: String = "",
        procedure: String = "",
        ossRate: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitNetPrice = unitNetPrice
        self.vatRate = vatRate
        self.cnPkwiu = cnPkwiu
        self.gtu = gtu
        self.procedure = procedure
        self.ossRate = ossRate
    }

    /// Wypełnia pola pozycji danymi towaru/usługi ze słownika.
    /// Tylko podstawia wartości — wszystko pozostaje edytowalne.
    public mutating func apply(product: Product) {
        name = product.name
        unit = product.unit
        unitNetPrice = product.basePriceNet
        vatRate = product.basePriceVatRate
        cnPkwiu = product.cnPkwiu
        gtu = product.gtu
        isAttachment15 = product.isAttachment15
    }

    /// Wartość netto pozycji (ilość × cena), zaokrąglona do groszy.
    public var netAmount: Double {
        ((quantity * unitNetPrice) * 100).rounded() / 100
    }

    /// Kwota VAT pozycji, zaokrąglona do groszy. Pozycja OSS liczy podatek
    /// od wartości dodanej według stawki państwa konsumpcji.
    public var vatAmount: Double {
        let multiplier = ossRate.map { $0 / 100 } ?? vatRate.multiplier
        return ((netAmount * multiplier) * 100).rounded() / 100
    }

    /// Wartość brutto pozycji.
    public var grossAmount: Double {
        netAmount + vatAmount
    }
}

// MARK: - Formy płatności FA(2)

/// Forma płatności zgodna ze słownikiem TFormaPlatnosci schemy FA(2).
public enum PaymentForm: String, CaseIterable, Identifiable, Sendable {
    case cash = "1"
    case card = "2"
    case voucher = "3"
    case cheque = "4"
    case credit = "5"
    case transfer = "6"
    case mobile = "7"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cash: return "Gotówka"
        case .card: return "Karta"
        case .voucher: return "Bon"
        case .cheque: return "Czek"
        case .credit: return "Kredyt"
        case .transfer: return "Przelew"
        case .mobile: return "Płatność mobilna"
        }
    }
}
