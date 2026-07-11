import Foundation
import SwiftData

/// Pojedyncza wpłata (lub zapłata) przypisana do faktury — element historii
/// płatności. Kwoty są w walucie faktury.
@Model
public final class PaymentRecord {

    /// Pochodzenie wpisu — ręczny albo z importu wyciągu bankowego.
    public enum Source: String, Codable, CaseIterable, Sendable {
        case manual = "reczna"
        case bankImport = "wyciag"

        public var displayName: String {
            switch self {
            case .manual: return "Ręczna"
            case .bankImport: return "Wyciąg bankowy"
            }
        }
    }

    @Attribute(.unique) public var id: UUID
    /// Kwota wpłaty w walucie faktury (dodatnia).
    public var amount: Double
    /// Data wpłaty (data księgowania z wyciągu albo wskazana ręcznie).
    public var date: Date
    /// Opis — np. tytuł przelewu z wyciągu.
    public var note: String = ""
    /// Surowe źródło wpisu (rawValue `Source`).
    public var sourceRaw: String = Source.manual.rawValue

    /// Faktura, której dotyczy wpłata.
    public var invoice: Invoice?

    public var source: Source {
        get { Source(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        note: String = "",
        source: Source = .manual
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.sourceRaw = source.rawValue
    }
}
