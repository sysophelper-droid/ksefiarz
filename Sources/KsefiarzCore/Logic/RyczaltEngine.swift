import Foundation

/// Forma opodatkowania podatkiem dochodowym. Decyduje, którą ewidencję prowadzi
/// aplikacja — nie można prowadzić obu równocześnie (KPiR albo ryczałt).
public enum TaxForm: String, CaseIterable, Identifiable, Sendable {
    /// Zasady ogólne albo podatek liniowy — Księga Przychodów i Rozchodów.
    case kpir
    /// Ryczałt od przychodów ewidencjonowanych — ewidencja przychodów.
    case ryczalt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kpir: return "KPiR (zasady ogólne / podatek liniowy)"
        case .ryczalt: return "Ryczałt od przychodów ewidencjonowanych"
        }
    }

    /// Odczyt z ustawień z bezpiecznym fallbackiem na KPiR.
    public static func resolve(_ raw: String) -> TaxForm {
        TaxForm(rawValue: raw) ?? .kpir
    }
}

/// Stawki ryczałtu od przychodów ewidencjonowanych ujęte we wzorze ewidencji
/// przychodów obowiązującym od 1 stycznia 2026 r. (rozporządzenie Ministra
/// Finansów i Gospodarki z 6 września 2025 r., Dz.U. 2025 poz. 1294 — kolumny
/// 7–15). Kolejność odpowiada kolejności kolumn wzoru. Wzór nie przewiduje
/// kolumny 2% (rzadka stawka sprzedaży produktów rolnych z własnej uprawy).
public enum RyczaltRate: String, CaseIterable, Codable, Sendable, Identifiable {
    case r17 = "17"
    case r15 = "15"
    case r14 = "14"
    case r12_5 = "12.5"
    case r12 = "12"
    case r10 = "10"
    case r8_5 = "8.5"
    case r5_5 = "5.5"
    case r3 = "3"

    public var id: String { rawValue }

    /// Numer kolumny wzoru (7–15) przypisany danej stawce.
    public var columnNumber: Int {
        switch self {
        case .r17: return 7
        case .r15: return 8
        case .r14: return 9
        case .r12_5: return 10
        case .r12: return 11
        case .r10: return 12
        case .r8_5: return 13
        case .r5_5: return 14
        case .r3: return 15
        }
    }

    /// Ułamek stawki (np. 0,085 dla 8,5%).
    public var fraction: Double { (Double(rawValue) ?? 0) / 100 }

    /// Etykieta z polskim przecinkiem dziesiętnym (np. „12,5%”).
    public var displayName: String {
        rawValue.replacingOccurrences(of: ".", with: ",") + "%"
    }
}

/// Czysta logika budowy i eksportu ewidencji przychodów (ryczałt) z faktur.
/// Ryczałt dotyczy WYŁĄCZNIE przychodów, więc ewidencja obejmuje tylko
/// sprzedaż; faktury zakupowe są pomijane. Faktury ukryte są bezwarunkowo
/// poza ewidencją (jak w KPiR).
public enum RyczaltEngine {
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
        /// Kol. 2 — data dokonania zapisu w ewidencji.
        public let entryDate: Date
        /// Kol. 3 — data uzyskania przychodu.
        public let revenueDate: Date
        public let ksefNumber: String
        public let documentNumber: String
        public let contractorTaxID: String
        public let rate: RyczaltRate
        public let amountPLN: Double
        public let notes: String
        public let isExcluded: Bool
        public let warning: String?

        /// Kwota przychodu w kolumnie danej stawki (0 dla pozostałych stawek).
        public func revenue(for rate: RyczaltRate) -> Double {
            self.rate == rate ? amountPLN : 0
        }

        /// Szacunkowy ryczałt od wiersza (przychód × stawka, bez odliczeń składek).
        public var estimatedTax: Double { amountPLN * rate.fraction }
    }

    public struct Summary: Equatable, Sendable {
        public let totalRevenue: Double
        public let revenueByRate: [RyczaltRate: Double]
        public let taxByRate: [RyczaltRate: Double]
        /// Suma szacowanego ryczałtu (bez odliczeń składek ZUS/zdrowotnej).
        public let estimatedTax: Double

        /// Stawki występujące w okresie, w kolejności kolumn wzoru.
        public var usedRates: [RyczaltRate] {
            RyczaltRate.allCases.filter { (revenueByRate[$0] ?? 0) != 0 }
        }
    }

    /// Domyślna stawka z ustawień (fallback 8,5% — najczęstsza stawka usługowa).
    public static func defaultRate(fromSetting raw: String) -> RyczaltRate {
        RyczaltRate(rawValue: raw) ?? .r8_5
    }

    public static func effectiveRate(for invoice: Invoice, default defaultRate: RyczaltRate) -> RyczaltRate {
        RyczaltRate(rawValue: invoice.ryczaltRateRaw) ?? defaultRate
    }

    public static func effectiveDate(for invoice: Invoice) -> Date {
        invoice.ryczaltEventDate ?? invoice.saleDate ?? invoice.issueDate
    }

    /// Data wpisu jest osobnym polem urzędowego wzoru. Dla wpisów bez
    /// ręcznego wskazania przyjmujemy datę uzyskania przychodu.
    public static func effectiveEntryDate(for invoice: Invoice) -> Date {
        invoice.ryczaltEntryDate ?? effectiveDate(for: invoice)
    }

    public static func effectiveAmount(for invoice: Invoice) -> Double {
        if let override = invoice.ryczaltAmountOverride { return rounded(override) }
        return rounded(DashboardAnalytics.inPLN(invoice.netAmount, invoice: invoice))
    }

    public static func rows(
        from invoices: [Invoice],
        period: Period,
        defaultRate: RyczaltRate,
        includeExcluded: Bool = false,
        calendar: Calendar = .current
    ) -> [Row] {
        let selected = invoices.filter { invoice in
            invoice.kind == .sales
                && !invoice.isArchivedOrHidden
                && (includeExcluded || !invoice.isExcludedFromRyczalt)
                && period.contains(effectiveDate(for: invoice), calendar: calendar)
        }.sorted {
            let lhsEntry = effectiveEntryDate(for: $0)
            let rhsEntry = effectiveEntryDate(for: $1)
            if lhsEntry != rhsEntry { return lhsEntry < rhsEntry }
            let lhsRevenue = effectiveDate(for: $0)
            let rhsRevenue = effectiveDate(for: $1)
            return lhsRevenue == rhsRevenue
                ? $0.invoiceNumber.localizedStandardCompare($1.invoiceNumber) == .orderedAscending
                : lhsRevenue < rhsRevenue
        }

        return selected.enumerated().map { index, invoice in
            let date = effectiveDate(for: invoice)
            return Row(
                id: invoice.id,
                ordinal: index + 1,
                entryDate: effectiveEntryDate(for: invoice),
                revenueDate: date,
                ksefNumber: invoice.ksefId ?? "",
                documentNumber: invoice.invoiceNumber,
                contractorTaxID: invoice.buyerNIP.trimmingCharacters(in: .whitespacesAndNewlines),
                rate: effectiveRate(for: invoice, default: defaultRate),
                amountPLN: effectiveAmount(for: invoice),
                notes: invoice.ryczaltNotes,
                isExcluded: invoice.isExcludedFromRyczalt,
                warning: warning(for: invoice)
            )
        }
    }

    public static func summary(for rows: [Row]) -> Summary {
        let active = rows.filter { !$0.isExcluded }
        var revenueByRate: [RyczaltRate: Double] = [:]
        for row in active {
            revenueByRate[row.rate, default: 0] += row.amountPLN
        }
        revenueByRate = revenueByRate.mapValues(rounded)
        var taxByRate: [RyczaltRate: Double] = [:]
        for (rate, revenue) in revenueByRate {
            taxByRate[rate] = rounded(revenue * rate.fraction)
        }
        let totalRevenue = rounded(revenueByRate.values.reduce(0, +))
        let estimatedTax = rounded(taxByRate.values.reduce(0, +))
        return Summary(totalRevenue: totalRevenue, revenueByRate: revenueByRate,
                       taxByRate: taxByRate, estimatedTax: estimatedTax)
    }

    private static func warning(for invoice: Invoice) -> String? {
        if !CurrencyCode.isPLN(invoice.currency), invoice.exchangeRate <= 0,
           invoice.ryczaltAmountOverride == nil {
            return "Brak kursu PLN — kwota nie została przeliczona. Uzupełnij kurs faktury albo kwotę przychodu."
        }
        return nil
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

/// Eksport ewidencji przychodów do CSV w układzie 17 kolumn wzoru z 2026 r.
/// (Dz.U. 2025 poz. 1294). Ostatni wiersz zawiera sumę przychodów per stawka.
public enum RyczaltCSVExporter {
    public static let header = [
        "1 Lp.", "2 Data wpisu", "3 Data uzyskania przychodu",
        "4 Numer KSeF", "5 Numer dowodu księgowego",
        "6 Identyfikator podatkowy kontrahenta",
        "7 Przychody 17%", "8 Przychody 15%", "9 Przychody 14%",
        "10 Przychody 12,5%", "11 Przychody 12%", "12 Przychody 10%",
        "13 Przychody 8,5%", "14 Przychody 5,5%", "15 Przychody 3%",
        "16 Ogółem przychody", "17 Uwagi",
    ].joined(separator: ";")

    public static func csv(for rows: [RyczaltEngine.Row]) -> String {
        var output = [header]
        let active = rows.filter { !$0.isExcluded }
        output += active.enumerated().map { index, row in
            var fields = [
                String(index + 1), date(row.entryDate), date(row.revenueDate),
                field(row.ksefNumber), field(row.documentNumber), field(row.contractorTaxID),
            ]
            for rate in RyczaltRate.allCases { fields.append(amount(row.revenue(for: rate))) }
            fields.append(amount(row.amountPLN))
            fields.append(field(row.notes))
            return fields.joined(separator: ";")
        }

        let summary = RyczaltEngine.summary(for: rows)
        var totals = ["", "", "", "", "", "Suma przychodów"]
        for rate in RyczaltRate.allCases { totals.append(amount(summary.revenueByRate[rate] ?? 0)) }
        totals.append(amount(summary.totalRevenue))
        totals.append("")
        output.append(totals.joined(separator: ";"))

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
