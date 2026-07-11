import Foundation
import SwiftData

/// Towar lub usługa w słowniku — dane podstawiane do pozycji faktury.
/// Po podstawieniu wszystkie pola pozycji (cena, jednostka, stawka VAT,
/// CN/PKWiU) pozostają edytowalne — słownik niczego nie wymusza.
/// Wszystkie pola mają wartości domyślne (lekka migracja istniejącej bazy).
@Model
public final class Product {

    /// Typ pozycji słownika.
    public enum ProductType: String, CaseIterable, Identifiable, Sendable {
        case goods = "towar"
        case service = "usluga"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .goods: return "Towar"
            case .service: return "Usługa"
            }
        }
    }

    @Attribute(.unique) public var id: UUID = UUID()

    // MARK: Informacje ogólne

    /// Nazwa produktu/usługi (wymagana) — trafia do P_7 pozycji.
    public var name: String = ""
    /// Typ: towar / usługa.
    public var typeRaw: String = ProductType.goods.rawValue
    /// Jednostka miary (P_8A), np. "szt.".
    public var unit: String = "szt."
    /// Kategoria (dowolny tekst porządkujący słownik).
    public var category: String = ""
    /// Kod SKU (wewnętrzny indeks).
    public var sku: String = ""
    /// Marka.
    public var brand: String = ""
    /// Kod EAN (GTIN).
    public var ean: String = ""

    // MARK: Księgowanie

    /// Kod CN (towary) lub PKWiU (usługi) — trafia do pozycji faktury.
    public var cnPkwiu: String = ""
    /// Kod GTU (np. "GTU_12").
    public var gtu: String = ""
    /// Towar/usługa z załącznika 15 (obowiązkowy split payment).
    public var isAttachment15: Bool = false

    // MARK: Cenniki (ceny netto; brutto wyliczane ze stawki)

    /// Cena bazowa netto (sprzedażowa) i jej stawka VAT.
    public var basePriceNet: Double = 0
    public var basePriceVatRateRaw: String = VATRate.standard.rawValue
    /// Cena zakupu netto i jej stawka VAT.
    public var purchasePriceNet: Double = 0
    public var purchasePriceVatRateRaw: String = VATRate.standard.rawValue

    public init() {}

    public var type: ProductType {
        get { ProductType(rawValue: typeRaw) ?? .goods }
        set { typeRaw = newValue.rawValue }
    }

    public var basePriceVatRate: VATRate {
        get { VATRate(rawValue: basePriceVatRateRaw) ?? .standard }
        set { basePriceVatRateRaw = newValue.rawValue }
    }

    public var purchasePriceVatRate: VATRate {
        get { VATRate(rawValue: purchasePriceVatRateRaw) ?? .standard }
        set { purchasePriceVatRateRaw = newValue.rawValue }
    }

    /// Cena bazowa brutto (netto + VAT wg stawki), zaokrąglona do groszy.
    public var basePriceGross: Double {
        ((basePriceNet * (1 + basePriceVatRate.multiplier)) * 100).rounded() / 100
    }

    /// Cena zakupu brutto, zaokrąglona do groszy.
    public var purchasePriceGross: Double {
        ((purchasePriceNet * (1 + purchasePriceVatRate.multiplier)) * 100).rounded() / 100
    }
}
