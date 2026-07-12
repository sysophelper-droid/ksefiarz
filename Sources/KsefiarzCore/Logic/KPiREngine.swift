import Foundation

/// Kolumny kwotowe podatkowej księgi przychodów i rozchodów według wzoru
/// obowiązującego od 1 stycznia 2026 r. (Dz.U. 2025 poz. 1299).
public enum KPiRColumn: String, CaseIterable, Codable, Sendable, Identifiable {
    case salesRevenue = "9"
    case otherRevenue = "10"
    case goodsAndMaterials = "12"
    case purchaseIncidentalCosts = "13"
    case wages = "14"
    case otherExpenses = "15"

    public var id: String { rawValue }
    public var number: Int { Int(rawValue) ?? 0 }

    public var displayName: String {
        switch self {
        case .salesRevenue: return "9 — Sprzedaż towarów i usług"
        case .otherRevenue: return "10 — Pozostałe przychody"
        case .goodsAndMaterials: return "12 — Towary handlowe i materiały"
        case .purchaseIncidentalCosts: return "13 — Koszty uboczne zakupu"
        case .wages: return "14 — Wynagrodzenia"
        case .otherExpenses: return "15 — Pozostałe wydatki"
        }
    }

    public static func choices(for kind: Invoice.Kind) -> [KPiRColumn] {
        kind == .sales ? [.salesRevenue, .otherRevenue]
            : [.goodsAndMaterials, .purchaseIncidentalCosts, .wages, .otherExpenses]
    }
}

/// Czysta logika tworzenia widoku i eksportu KPiR z faktur.
public enum KPiREngine {
    public struct Period: Equatable, Sendable {
        public let year: Int
        /// nil oznacza cały rok, 1...12 — wybrany miesiąc.
        public let month: Int?

        public init(year: Int, month: Int? = nil) {
            self.year = year
            self.month = month
        }

        public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
            let components = calendar.dateComponents([.year, .month], from: date)
            return components.year == year && (month == nil || components.month == month)
        }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let ordinal: Int
        public let eventDate: Date
        public let ksefNumber: String
        public let documentNumber: String
        public let contractorTaxID: String
        public let contractorName: String
        public let contractorAddress: String
        public let description: String
        public let column: KPiRColumn
        public let amountPLN: Double
        public let researchDevelopmentCost: Double
        public let notes: String
        public let isExcluded: Bool
        public let warning: String?

        public var salesRevenue: Double { column == .salesRevenue ? amountPLN : 0 }
        public var otherRevenue: Double { column == .otherRevenue ? amountPLN : 0 }
        public var totalRevenue: Double { salesRevenue + otherRevenue }
        public var goodsAndMaterials: Double { column == .goodsAndMaterials ? amountPLN : 0 }
        public var purchaseIncidentalCosts: Double { column == .purchaseIncidentalCosts ? amountPLN : 0 }
        public var wages: Double { column == .wages ? amountPLN : 0 }
        public var otherExpenses: Double { column == .otherExpenses ? amountPLN : 0 }
        public var totalExpenses: Double { wages + otherExpenses }
    }

    public struct Summary: Equatable, Sendable {
        public let revenue: Double
        public let goodsAndMaterials: Double
        public let purchaseIncidentalCosts: Double
        public let wages: Double
        public let otherExpenses: Double
        public let deductibleCosts: Double
        public let income: Double
    }

    public static func effectiveColumn(for invoice: Invoice) -> KPiRColumn {
        if let selected = KPiRColumn(rawValue: invoice.kpirColumnRaw),
           KPiRColumn.choices(for: invoice.kind).contains(selected) {
            return selected
        }
        return invoice.kind == .sales ? .salesRevenue : .otherExpenses
    }

    public static func effectiveDate(for invoice: Invoice) -> Date {
        invoice.kpirEventDate ?? invoice.saleDate ?? invoice.issueDate
    }

    public static func effectiveDescription(for invoice: Invoice) -> String {
        let custom = invoice.kpirDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        if invoice.kind == .sales { return "Sprzedaż towarów i usług" }
        let category = invoice.costCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        return category.isEmpty ? "Zakup towarów lub usług" : category
    }

    public static func effectiveAmount(for invoice: Invoice) -> Double {
        if let override = invoice.kpirAmountOverride { return rounded(override) }
        return rounded(DashboardAnalytics.inPLN(invoice.netAmount, invoice: invoice))
    }

    public static func rows(
        from invoices: [Invoice],
        period: Period,
        includeExcluded: Bool = false,
        calendar: Calendar = .current
    ) -> [Row] {
        let selected = invoices.filter { invoice in
            !invoice.isArchivedOrHidden
                && (includeExcluded || !invoice.isExcludedFromKPiR)
                && period.contains(effectiveDate(for: invoice), calendar: calendar)
        }.sorted {
            let lhs = effectiveDate(for: $0)
            let rhs = effectiveDate(for: $1)
            return lhs == rhs ? $0.invoiceNumber.localizedStandardCompare($1.invoiceNumber) == .orderedAscending : lhs < rhs
        }

        return selected.enumerated().map { index, invoice in
            let taxID = invoiceCounterpartyTaxID(invoice)
            let hasTaxID = !taxID.isEmpty
            return Row(
                id: invoice.id,
                ordinal: index + 1,
                eventDate: effectiveDate(for: invoice),
                ksefNumber: invoice.ksefId ?? "",
                documentNumber: invoice.invoiceNumber,
                contractorTaxID: taxID,
                // Wzór 2026 nakazuje nie wypełniać nazwy i adresu, gdy wpisano
                // identyfikator podatkowy kontrahenta (objaśnienie kol. 5–7).
                contractorName: hasTaxID ? "" : invoiceCounterpartyName(invoice),
                contractorAddress: hasTaxID ? "" : invoiceCounterpartyAddress(invoice),
                description: effectiveDescription(for: invoice),
                column: effectiveColumn(for: invoice),
                amountPLN: effectiveAmount(for: invoice),
                researchDevelopmentCost: rounded(invoice.kpirResearchDevelopmentCost),
                notes: invoice.kpirNotes,
                isExcluded: invoice.isExcludedFromKPiR,
                warning: warning(for: invoice)
            )
        }
    }

    public static func summary(for rows: [Row]) -> Summary {
        let active = rows.filter { !$0.isExcluded }
        let revenue = active.reduce(0) { $0 + $1.totalRevenue }
        let goods = active.reduce(0) { $0 + $1.goodsAndMaterials }
        let incidental = active.reduce(0) { $0 + $1.purchaseIncidentalCosts }
        let wages = active.reduce(0) { $0 + $1.wages }
        let other = active.reduce(0) { $0 + $1.otherExpenses }
        let costs = goods + incidental + wages + other
        return Summary(revenue: rounded(revenue), goodsAndMaterials: rounded(goods),
                       purchaseIncidentalCosts: rounded(incidental), wages: rounded(wages),
                       otherExpenses: rounded(other), deductibleCosts: rounded(costs),
                       income: rounded(revenue - costs))
    }

    private static func invoiceCounterpartyTaxID(_ invoice: Invoice) -> String {
        (invoice.kind == .sales ? invoice.buyerNIP : invoice.sellerNIP)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func invoiceCounterpartyName(_ invoice: Invoice) -> String {
        invoice.kind == .sales ? invoice.buyerName : invoice.sellerName
    }

    private static func invoiceCounterpartyAddress(_ invoice: Invoice) -> String {
        invoice.kind == .sales ? invoice.buyerAddress : invoice.sellerAddress
    }

    private static func warning(for invoice: Invoice) -> String? {
        if invoice.currency.uppercased() != "PLN", invoice.exchangeRate <= 0,
           invoice.kpirAmountOverride == nil {
            return "Brak kursu PLN — kwota nie została przeliczona. Uzupełnij kurs faktury albo kwotę KPiR."
        }
        return nil
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

/// Eksport pełnego układu kolumn 1–19 do CSV z separatorem zgodnym z polskim
/// Excelem/Numbers. Kolumny 11 i 16 są sumami wymaganymi przez wzór księgi.
public enum KPiRCSVExporter {
    public static let header = [
        "1 Lp.", "2 Data zdarzenia gospodarczego", "3 Numer KSeF",
        "4 Numer dowodu księgowego", "5 Identyfikator podatkowy kontrahenta",
        "6 Nazwa kontrahenta", "7 Adres kontrahenta", "8 Opis zdarzenia gospodarczego",
        "9 Sprzedaż towarów i usług", "10 Pozostałe przychody", "11 Razem przychód",
        "12 Zakup towarów i materiałów", "13 Koszty uboczne zakupu",
        "14 Wynagrodzenia", "15 Pozostałe wydatki", "16 Razem wydatki (14+15)",
        "17 Kolumna wolna", "18 Koszty działalności B+R", "19 Uwagi",
    ].joined(separator: ";")

    public static func csv(for rows: [KPiREngine.Row]) -> String {
        var output = [header]
        output += rows.filter { !$0.isExcluded }.enumerated().map { index, row in
            [
                String(index + 1), date(row.eventDate), field(row.ksefNumber), field(row.documentNumber),
                field(row.contractorTaxID), field(row.contractorName), field(row.contractorAddress),
                field(row.description), amount(row.salesRevenue), amount(row.otherRevenue),
                amount(row.totalRevenue), amount(row.goodsAndMaterials), amount(row.purchaseIncidentalCosts),
                amount(row.wages), amount(row.otherExpenses), amount(row.totalExpenses), "",
                amount(row.researchDevelopmentCost), field(row.notes),
            ].joined(separator: ";")
        }
        return output.joined(separator: "\n") + "\n"
    }

    private static func date(_ value: Date) -> String {
        FA2Format.dateFormatter.string(from: value)
    }

    private static func amount(_ value: Double) -> String {
        abs(value) < 0.005 ? "" : String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func field(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
