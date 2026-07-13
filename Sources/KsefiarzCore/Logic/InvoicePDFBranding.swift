import Foundation

/// Personalizacja wydruku własnych faktur. Typ przechowuje wyłącznie dane,
/// dzięki czemu decyzję o zastosowaniu brandingu można testować bez renderera.
public struct InvoicePDFBranding: Equatable, Sendable {
    public static let defaultPrimaryHex = "#1E4D6B"
    public static let defaultAccentHex = "#2E8B8B"

    public var isEnabled: Bool
    public var companyNIP: String
    public var logoData: Data?
    public var primaryColorHex: String
    public var accentColorHex: String
    public var footer: String

    public init(
        isEnabled: Bool = false,
        companyNIP: String = "",
        logoData: Data? = nil,
        primaryColorHex: String = Self.defaultPrimaryHex,
        accentColorHex: String = Self.defaultAccentHex,
        footer: String = ""
    ) {
        self.isEnabled = isEnabled
        self.companyNIP = companyNIP
        self.logoData = logoData
        self.primaryColorHex = Self.normalizedHex(primaryColorHex) ?? Self.defaultPrimaryHex
        self.accentColorHex = Self.normalizedHex(accentColorHex) ?? Self.defaultAccentHex
        self.footer = footer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Konfiguracja klasyczna, niezmieniająca dotychczasowego wydruku.
    public static let classic = InvoicePDFBranding()

    /// Odczytuje konfigurację zapisaną przez ekran Ustawień.
    public static func current(defaults: UserDefaults = .standard) -> InvoicePDFBranding {
        let encodedLogo = defaults.string(forKey: AppSettingsKeys.pdfBrandingLogo) ?? ""
        return InvoicePDFBranding(
            isEnabled: defaults.bool(forKey: AppSettingsKeys.pdfBrandingEnabled),
            companyNIP: defaults.string(forKey: AppSettingsKeys.nip) ?? "",
            logoData: Data(base64Encoded: encodedLogo),
            primaryColorHex: defaults.string(forKey: AppSettingsKeys.pdfBrandingPrimaryColor)
                ?? defaultPrimaryHex,
            accentColorHex: defaults.string(forKey: AppSettingsKeys.pdfBrandingAccentColor)
                ?? defaultAccentHex,
            footer: defaults.string(forKey: AppSettingsKeys.pdfBrandingFooter) ?? ""
        )
    }

    /// Branding dotyczy wyłącznie dokumentów firmy użytkownika. Dla VAT RR
    /// wystawcą dokumentu jest nabywca, dlatego sprawdzamy jego NIP.
    /// Samofakturowanie jest wyłączone w obie strony: samofaktura, którą
    /// wystawiamy, jest formalnie fakturą DOSTAWCY (nasze logo by ją
    /// przekłamywało), a naszą sprzedaż z adnotacją P_17 wystawił klient.
    public func applies(to invoice: Invoice) -> Bool {
        guard isEnabled else { return false }
        guard !invoice.isSelfInvoicing else { return false }
        let ownNIP = Self.onlyDigits(companyNIP)
        guard !ownNIP.isEmpty else { return false }
        if invoice.isRR {
            return Self.onlyDigits(invoice.buyerNIP) == ownNIP
        }
        return Self.onlyDigits(invoice.sellerNIP) == ownNIP
    }

    /// Normalizuje zapis koloru do #RRGGBB; odrzuca wartości niepełne.
    public static func normalizedHex(_ value: String) -> String? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(hex)"
    }

    private static func onlyDigits(_ value: String) -> String {
        String(value.filter(\.isNumber))
    }
}
