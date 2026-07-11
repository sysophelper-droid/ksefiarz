import Foundation
import SwiftData

/// Rachunek bankowy w słowniku — numer podstawiany do pola płatności faktury.
/// Wszystkie pola mają wartości domyślne (lekka migracja istniejącej bazy).
@Model
public final class BankAccount {

    @Attribute(.unique) public var id: UUID = UUID()

    /// Identyfikator własny (np. „Firmowy PLN”).
    public var label: String = ""
    /// Numer rachunku bankowego (NRB/IBAN — wymagany).
    public var accountNumber: String = ""
    /// Nazwa banku.
    public var bankName: String = ""
    /// Kod SWIFT/BIC.
    public var swift: String = ""
    /// Waluta konta.
    public var currency: String = "PLN"
    /// Numer powiązanego rachunku VAT (split payment).
    public var vatAccountNumber: String = ""

    public init() {}

    /// Nazwa prezentowana na listach wyboru.
    public var displayName: String {
        label.isEmpty ? accountNumber : "\(label) (\(accountNumber.suffix(4)))"
    }
}
