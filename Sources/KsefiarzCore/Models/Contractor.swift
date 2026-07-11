import Foundation
import SwiftData

/// Kontrahent w słowniku — dane podstawiane do faktury przy wystawianiu.
/// Wszystkie pola mają wartości domyślne (lekka migracja istniejącej bazy).
@Model
public final class Contractor {

    @Attribute(.unique) public var id: UUID = UUID()

    // MARK: Ogólne

    /// Nazwa firmy (pierwsza linia — wymagana).
    public var name: String = ""
    /// Druga linia nazwy (np. ciąg dalszy długiej nazwy).
    public var nameLine2: String = ""
    /// Identyfikator podatkowy — NIP (wymagany).
    public var nip: String = ""
    /// Prefiks UE (np. "PL", "DE") — dla kontrahentów unijnych.
    public var uePrefix: String = ""
    /// Role kontrahenta.
    public var isSupplier: Bool = true
    public var isRecipient: Bool = true
    /// Kontrahent jest osobą fizyczną.
    public var isNaturalPerson: Bool = false
    /// Zgody.
    public var consentsToEInvoices: Bool = true
    public var consentsToMarketing: Bool = false

    // MARK: Adres

    public var street: String = ""
    public var houseNumber: String = ""
    public var apartmentNumber: String = ""
    public var postalCode: String = ""
    public var city: String = ""
    public var countryName: String = "Polska"
    public var countryCode: String = "PL"

    // MARK: Kontakt

    public var phone1: String = ""
    public var phone2: String = ""
    public var fax: String = ""
    /// Komunikator (nazwa z listy `Contractor.messengers`) i adres/identyfikator
    /// kontrahenta w tym komunikatorze.
    public var messenger: String = ""
    public var messengerAddress: String = ""
    public var email: String = ""
    /// Adres e-mail dedykowany fakturom (jeśli inny niż ogólny).
    public var invoiceEmail: String = ""
    public var website: String = ""
    public var notes: String = ""

    public init() {}

    /// Najpopularniejsze komunikatory do wyboru w polu `messenger`.
    public static let messengers = [
        "WhatsApp", "Telegram", "Signal", "Messenger", "Microsoft Teams",
        "Slack", "Discord", "Viber", "iMessage", "Google Chat", "Zoom",
        "WeChat", "Line", "Threema", "Element (Matrix)", "Skype",
    ]

    /// Pełna nazwa (obie linie) — podstawiana na fakturę.
    public var displayName: String {
        nameLine2.isEmpty ? name : "\(name) \(nameLine2)"
    }

    /// Adres jednolinijkowy w formacie używanym na fakturach
    /// („Ulica 1/2, 00-001 Miasto”).
    public var invoiceAddress: String {
        var streetPart = street
        if !houseNumber.isEmpty {
            streetPart += streetPart.isEmpty ? houseNumber : " \(houseNumber)"
            if !apartmentNumber.isEmpty { streetPart += "/\(apartmentNumber)" }
        }
        let cityPart = [postalCode, city].filter { !$0.isEmpty }.joined(separator: " ")
        return [streetPart, cityPart].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
