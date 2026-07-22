import Foundation

/// Raporty sprzedaży i kosztów: najlepsi kontrahenci, przychody per
/// towar/usługa oraz koszty per kategoria. Czysta logika liczona
/// z widocznych faktur (ukryte są pomijane wewnątrz silnika).
/// Kwoty w PLN — faktury walutowe po kursie z faktury; bez kursu nominalnie
/// (spójnie z `DashboardAnalytics.inPLN`).
public enum ReportsEngine {

    /// Czyści etykietę prezentacyjną bez zmiany jej pisowni.
    fileprivate static func displayLabel(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Klucz grupowania odporny na wielkość liter, diakrytyki i nadmiarowe
    /// białe znaki. Etykieta wyświetlana pozostaje pobrana z pierwszego wpisu.
    fileprivate static func groupingKey(_ value: String) -> String {
        let compact = displayLabel(value)
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
        return compact.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "pl_PL")
        )
    }

    /// Przychody od jednego kontrahenta (nabywcy faktur sprzedażowych).
    public struct ContractorRevenue: Equatable, Sendable, Identifiable {
        /// NIP (znormalizowany), a dla braku NIP — nazwa.
        public let id: String
        public let name: String
        public let nip: String
        public let invoiceCount: Int
        public let netPLN: Double
        public let grossPLN: Double
    }

    /// Przychody z jednego towaru/usługi (pozycje faktur sprzedażowych).
    public struct ProductRevenue: Equatable, Sendable, Identifiable {
        /// Nazwa pozycji (klucz grupowania bez wielkości liter).
        public let id: String
        public let name: String
        /// Suma ilości (jednostki mogą się różnić między fakturami).
        public let quantity: Double
        public let netPLN: Double
    }

    /// Koszty jednej kategorii (faktury zakupowe).
    public struct CategoryCost: Equatable, Sendable, Identifiable {
        public var id: String { category }
        /// Nazwa kategorii; pusta kategoria faktury → `CostCategories.none`.
        public let category: String
        public let invoiceCount: Int
        public let netPLN: Double
        public let vatPLN: Double
        public let grossPLN: Double
    }

    /// Najlepsi kontrahenci sprzedaży — grupowanie po NIP nabywcy
    /// (bez NIP: po nazwie), malejąco po kwocie brutto.
    public static func topContractors(in invoices: [Invoice], limit: Int? = nil) -> [ContractorRevenue] {
        struct Accumulator {
            var id = ""
            var name = ""
            var nip = ""
            var count = 0
            var net = 0.0
            var gross = 0.0
        }
        var groups: [String: Accumulator] = [:]
        for invoice in invoices where invoice.kind == .sales && !invoice.isArchivedOrHidden {
            let nip = invoice.buyerNIP.filter(\.isNumber)
            let name = displayLabel(invoice.buyerName)
            let nameKey = groupingKey(name)
            let key = nip.isEmpty ? "name:\(nameKey)" : "nip:\(nip)"
            guard !nameKey.isEmpty || !nip.isEmpty else { continue }
            var group = groups[key] ?? Accumulator()
            if group.id.isEmpty { group.id = nip.isEmpty ? nameKey : nip }
            if group.name.isEmpty { group.name = name }
            if group.nip.isEmpty { group.nip = nip }
            group.count += 1
            group.net += DashboardAnalytics.inPLN(invoice.netAmount, invoice: invoice)
            group.gross += DashboardAnalytics.inPLN(invoice.grossAmount, invoice: invoice)
            groups[key] = group
        }
        let sorted = groups
            .map { key, group in
                ContractorRevenue(
                    id: group.id,
                    name: group.name,
                    nip: group.nip,
                    invoiceCount: group.count,
                    netPLN: group.net,
                    grossPLN: group.gross
                )
            }
            .sorted { $0.grossPLN > $1.grossPLN }
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// Przychody per towar/usługa — pozycje faktur sprzedażowych grupowane
    /// po nazwie (bez wielkości liter), malejąco po wartości netto.
    public static func revenueByProduct(in invoices: [Invoice], limit: Int? = nil) -> [ProductRevenue] {
        struct Accumulator {
            var name = ""
            var quantity = 0.0
            var net = 0.0
        }
        var groups: [String: Accumulator] = [:]
        for invoice in invoices where invoice.kind == .sales && !invoice.isArchivedOrHidden {
            for line in invoice.lines {
                let name = displayLabel(line.name)
                guard !name.isEmpty else { continue }
                let key = groupingKey(name)
                var group = groups[key] ?? Accumulator()
                if group.name.isEmpty { group.name = name }
                group.quantity += line.quantity
                group.net += DashboardAnalytics.inPLN(line.netAmount, invoice: invoice)
                groups[key] = group
            }
        }
        let sorted = groups
            .map { key, group in
                ProductRevenue(id: key, name: group.name, quantity: group.quantity, netPLN: group.net)
            }
            .sorted { $0.netPLN > $1.netPLN }
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// Koszty per kategoria — faktury zakupowe grupowane po `costCategory`,
    /// malejąco po kwocie brutto. Faktury bez kategorii trafiają do wspólnej
    /// grupy `CostCategories.none`.
    public static func costsByCategory(in invoices: [Invoice]) -> [CategoryCost] {
        struct Accumulator {
            var label = ""
            var count = 0
            var net = 0.0
            var vat = 0.0
            var gross = 0.0
        }
        var groups: [String: Accumulator] = [:]
        for invoice in invoices where invoice.kind == .purchase && !invoice.isArchivedOrHidden {
            let raw = displayLabel(invoice.costCategory)
            let category = raw.isEmpty ? CostCategories.none : raw
            let key = groupingKey(category)
            var group = groups[key] ?? Accumulator()
            if group.label.isEmpty { group.label = category }
            group.count += 1
            group.net += DashboardAnalytics.inPLN(invoice.netAmount, invoice: invoice)
            group.vat += DashboardAnalytics.inPLN(invoice.vatAmount, invoice: invoice)
            group.gross += DashboardAnalytics.inPLN(invoice.grossAmount, invoice: invoice)
            groups[key] = group
        }
        return groups
            .map { _, group in
                CategoryCost(
                    category: group.label,
                    invoiceCount: group.count,
                    netPLN: group.net,
                    vatPLN: group.vat,
                    grossPLN: group.gross
                )
            }
            .sorted { $0.grossPLN > $1.grossPLN }
    }
}

/// Kategorie kosztów na fakturach zakupowych (pole `Invoice.costCategory`).
public enum CostCategories {

    /// Etykieta zakupów bez przypisanej kategorii.
    public static let none = "Bez kategorii"

    /// Podpowiedzi typowych kategorii — pole pozostaje dowolnym tekstem.
    public static let suggestions = [
        "Biuro i materiały",
        "Czynsz i media",
        "Księgowość i usługi prawne",
        "Marketing",
        "Oprogramowanie i licencje",
        "Paliwo i transport",
        "Podróże służbowe",
        "Sprzęt IT",
        "Telekomunikacja",
        "Ubezpieczenia",
        "Usługi obce",
        "Inne",
    ]

    /// Kategorie już użyte na fakturach (posortowane, bez pustych) —
    /// do podpowiedzi przy edycji.
    public static func used(in invoices: [Invoice]) -> [String] {
        var labelsByKey: [String: String] = [:]
        for invoice in invoices where !invoice.isArchivedOrHidden {
            let label = ReportsEngine.displayLabel(invoice.costCategory)
            guard !label.isEmpty else { continue }
            let key = ReportsEngine.groupingKey(label)
            if labelsByKey[key] == nil { labelsByKey[key] = label }
        }
        return labelsByKey.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
