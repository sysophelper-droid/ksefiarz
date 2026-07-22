import Foundation

/// Globalna wyszukiwarka ⌘K (F3) — czysta logika dopasowań i rankingu.
/// Widok (`GlobalSearchView`) mapuje modele na lekkie pozycje `Item`
/// i decyduje o nawigacji; silnik tylko normalizuje, punktuje i sortuje.
public enum GlobalSearchEngine {

    /// Rodzaj pozycji wyniku — decyduje o grupowaniu i ikonie.
    public enum Kind: String, CaseIterable, Sendable {
        case section
        case invoice
        case proforma
        case contractor
        case setting

        public var displayName: String {
            switch self {
            case .section: return "Sekcje"
            case .invoice: return "Faktury"
            case .proforma: return "Proformy"
            case .contractor: return "Kontrahenci"
            case .setting: return "Ustawienia"
            }
        }

        public var icon: String {
            switch self {
            case .section: return "sidebar.left"
            case .invoice: return "doc.text"
            case .proforma: return "doc.plaintext"
            case .contractor: return "person.2"
            case .setting: return "gearshape"
            }
        }
    }

    /// Lekka pozycja wyszukiwania — bez referencji do modeli SwiftData,
    /// żeby dopasowanie dało się testować jednostkowo.
    public struct Item: Identifiable, Equatable, Sendable {
        public let kind: Kind
        public let id: String
        public let title: String
        public let subtitle: String
        public let keywords: [String]

        public init(kind: Kind, id: String, title: String, subtitle: String, keywords: [String]) {
            self.kind = kind
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.keywords = keywords
        }
    }

    // MARK: Normalizacja

    /// Postać porównywalna: małe litery bez znaków diakrytycznych.
    /// `ł` nie jest składane przez `diacriticInsensitive` (litera
    /// z kreską, nie znak łączący) — zamieniane ręcznie, żeby „zolw”
    /// znajdował „Żółw”.
    public static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "pl_PL"))
    }

    // MARK: Punktacja

    /// Punktuje pozycję dla zapytania; `nil` = brak dopasowania.
    /// Każdy wyraz zapytania musi pasować gdziekolwiek (tytuł, podtytuł
    /// albo słowa kluczowe); wynik to suma najlepszych trafień wyrazów.
    static func score(query: String, item: Item) -> Int? {
        let tokens = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        let title = normalized(item.title)
        let titleWords = title.split(separator: " ").map(String.init)
        let secondary = ([item.subtitle] + item.keywords).map(normalized)

        var total = 0
        for token in tokens {
            let tokenScore: Int
            if title.hasPrefix(token) {
                tokenScore = 100
            } else if titleWords.contains(where: { $0.hasPrefix(token) }) {
                tokenScore = 80
            } else if title.contains(token) {
                tokenScore = 60
            } else if secondary.contains(where: { $0.hasPrefix(token) }) {
                tokenScore = 40
            } else if secondary.contains(where: { $0.contains(token) }) {
                tokenScore = 20
            } else {
                return nil // wyraz bez trafienia dyskwalifikuje pozycję
            }
            total += tokenScore
        }
        return total
    }

    /// Zwraca pozycje pasujące do zapytania, od najlepszych. Puste
    /// zapytanie daje pustą listę (widok pokazuje wtedy sekcje aplikacji).
    public static func search(_ query: String, in items: [Item], limit: Int = 40) -> [Item] {
        let safeLimit = max(0, limit)
        let scored = items.compactMap { item -> (Item, Int)? in
            guard let score = score(query: query, item: item) else { return nil }
            return (item, score)
        }
        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
            }
            .prefix(safeLimit)
            .map(\.0)
    }

    // MARK: Mapowanie modeli

    /// Pozycja dla faktury: tytułem numer, w podtytule kierunek, druga
    /// strona i kwota; NIP-y oraz numer KSeF w słowach kluczowych.
    public static func item(for invoice: Invoice) -> Item {
        let counterparty = invoice.kind == .sales ? invoice.buyerName : invoice.sellerName
        return Item(
            kind: .invoice,
            id: invoice.id.uuidString,
            title: invoice.invoiceNumber,
            subtitle: "\(invoice.kind.displayName) · \(counterparty) · "
                + "\(FA2Format.amount(invoice.grossAmount)) \(invoice.currency) · "
                + FA2Format.dateFormatter.string(from: invoice.issueDate),
            keywords: [
                invoice.buyerName,
                invoice.sellerName,
                invoice.buyerNIP,
                invoice.sellerNIP,
                invoice.ksefId ?? "",
            ].filter { !$0.isEmpty }
        )
    }

    /// Pozycja dla proformy.
    public static func item(for proforma: Proforma) -> Item {
        Item(
            kind: .proforma,
            id: proforma.id.uuidString,
            title: proforma.proformaNumber,
            subtitle: "Proforma · \(proforma.buyerName) · "
                + "\(FA2Format.amount(proforma.grossAmount)) \(proforma.currency) · "
                + FA2Format.dateFormatter.string(from: proforma.issueDate),
            keywords: [proforma.buyerName, proforma.sellerName, proforma.buyerNIP]
                .filter { !$0.isEmpty }
        )
    }

    /// Pozycja dla kontrahenta ze słownika.
    public static func item(for contractor: Contractor) -> Item {
        var subtitleParts: [String] = []
        if !contractor.nip.isEmpty { subtitleParts.append("NIP \(contractor.nip)") }
        if !contractor.city.isEmpty { subtitleParts.append(contractor.city) }
        return Item(
            kind: .contractor,
            id: contractor.id.uuidString,
            title: contractor.displayName,
            subtitle: subtitleParts.joined(separator: " · "),
            keywords: [
                contractor.name,
                contractor.nameLine2,
                contractor.nip,
                contractor.city,
                contractor.email,
                contractor.invoiceEmail,
            ].filter { !$0.isEmpty }
        )
    }
}
