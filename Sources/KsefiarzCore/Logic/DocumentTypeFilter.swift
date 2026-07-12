import Foundation

/// Filtr rodzaju dokumentu na listach faktur.
public enum DocumentTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case vat
    case zal
    case roz
    case upr
    case rr
    case corrections

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "Wszystkie rodzaje"
        case .vat: return "VAT"
        case .zal: return "Zaliczkowe (ZAL)"
        case .roz: return "Rozliczeniowe (ROZ)"
        case .upr: return "Uproszczone (UPR)"
        case .rr: return "VAT RR"
        case .corrections: return "Korekty (KOR…)"
        }
    }

    /// Czy faktura o danym RodzajFaktury przechodzi przez filtr.
    /// Korekty obejmują wszystkie odmiany (KOR, KOR_ZAL, KOR_ROZ).
    public func matches(_ documentTypeRaw: String) -> Bool {
        switch self {
        case .all: return true
        case .vat: return documentTypeRaw == "VAT"
        case .zal: return documentTypeRaw == "ZAL"
        case .roz: return documentTypeRaw == "ROZ"
        case .upr: return documentTypeRaw == "UPR"
        case .rr: return documentTypeRaw == "VAT_RR"
        case .corrections: return documentTypeRaw.hasPrefix("KOR")
        }
    }

    /// Filtruje listę faktur.
    public func apply(to invoices: [Invoice]) -> [Invoice] {
        guard self != .all else { return invoices }
        return invoices.filter { matches($0.documentTypeRaw) }
    }
}
