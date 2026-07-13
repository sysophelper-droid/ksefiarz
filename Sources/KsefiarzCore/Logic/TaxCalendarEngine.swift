import Foundation

/// Częstotliwość rozliczania podatku. JPK pozostaje miesięczny niezależnie
/// od kwartalnego rozliczenia VAT.
public enum TaxSettlementCycle: String, CaseIterable, Identifiable, Sendable {
    case monthly
    case quarterly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .monthly: return "Miesięcznie"
        case .quarterly: return "Kwartalnie"
        }
    }

    public static func resolve(_ raw: String) -> TaxSettlementCycle {
        TaxSettlementCycle(rawValue: raw) ?? .monthly
    }
}

/// Sposób obliczania zaliczki PIT dla podatnika prowadzącego KPiR.
public enum KPiRIncomeTaxMethod: String, CaseIterable, Identifiable, Sendable {
    case scale
    case linear

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scale: return "Skala podatkowa (12% / 32%)"
        case .linear: return "Podatek liniowy (19%)"
        }
    }

    public static func resolve(_ raw: String) -> KPiRIncomeTaxMethod {
        KPiRIncomeTaxMethod(rawValue: raw) ?? .scale
    }
}

/// Czysta logika terminarza i roboczej prognozy podatkowej.
public enum TaxCalendarEngine {

    public enum DeadlineKind: String, CaseIterable, Sendable {
        case zus, incomeTax, jpk, vat

        public var title: String {
            switch self {
            case .zus: return "ZUS i deklaracja DRA"
            case .incomeTax: return "Zaliczka PIT"
            case .jpk: return "Wysyłka JPK_V7"
            case .vat: return "Płatność VAT"
            }
        }

        public var systemImage: String {
            switch self {
            case .zus: return "person.text.rectangle"
            case .incomeTax: return "banknote"
            case .jpk: return "doc.badge.arrow.up"
            case .vat: return "building.columns"
            }
        }
    }

    public struct Period: Equatable, Sendable {
        public let year: Int
        public let months: [Int]

        public var label: String {
            if months.count == 1 {
                return Self.monthFormatter.string(from: date(year: year, month: months[0]))
            }
            let quarter = ((months[0] - 1) / 3) + 1
            return "\(quarter) kwartał \(year)"
        }

        private static let monthFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pl_PL")
            formatter.dateFormat = "LLLL yyyy"
            return formatter
        }()

        private func date(year: Int, month: Int) -> Date {
            var components = DateComponents()
            components.calendar = PolishBusinessCalendar.calendar
            components.timeZone = PolishBusinessCalendar.calendar.timeZone
            components.year = year
            components.month = month
            components.day = 1
            return components.date ?? .distantPast
        }

        public func contains(_ date: Date, calendar: Calendar = PolishBusinessCalendar.calendar) -> Bool {
            let components = calendar.dateComponents([.year, .month], from: date)
            return components.year == year && months.contains(components.month ?? -1)
        }
    }

    public struct Deadline: Identifiable, Equatable, Sendable {
        public var id: String { kind.rawValue }
        public let kind: DeadlineKind
        public let dueDate: Date
        public let period: Period
    }

    public struct Forecast: Equatable, Sendable {
        public let vatPeriod: Period
        public let vatApplies: Bool
        public let outputVAT: Double
        public let inputVAT: Double
        /// Dodatnia kwota oznacza wpłatę, ujemna — nadwyżkę podatku naliczonego.
        public let vatBalance: Double
        public let incomeTaxPeriod: Period
        public let incomeTaxBase: Double
        public let incomeTax: Double
        public let incomeTaxLabel: String
        public let warnings: [String]
    }

    public struct Snapshot: Equatable, Sendable {
        public let deadlines: [Deadline]
        public let forecast: Forecast
    }

    /// Najbliższe przyszłe terminy każdego rodzaju oraz prognoza dla trwających
    /// okresów rozliczeniowych. Ukryte faktury są pomijane także defensywnie.
    public static func snapshot(
        invoices: [Invoice],
        taxForm: TaxForm,
        defaultRyczaltRate: RyczaltRate,
        incomeTaxMethod: KPiRIncomeTaxMethod,
        incomeTaxCycle: TaxSettlementCycle,
        vatCycle: TaxSettlementCycle,
        isActiveVATPayer: Bool = true,
        now: Date = .now,
        calendar: Calendar = PolishBusinessCalendar.calendar
    ) -> Snapshot {
        let visible = invoices.filter { !$0.isArchivedOrHidden }
        let vatPeriod = currentPeriod(cycle: vatCycle, at: now, calendar: calendar)
        let incomePeriod = currentPeriod(cycle: incomeTaxCycle, at: now, calendar: calendar)

        var warnings: [String] = []
        var outputVAT = 0.0
        var inputVAT = 0.0
        for invoice in visible where isActiveVATPayer
            && vatPeriod.contains(JPKV7Generator.periodDate(invoice), calendar: calendar) {
            if invoice.kind == .sales {
                var invoiceWarnings: [String] = []
                outputVAT += JPKV7Generator.salesBuckets(for: invoice, warnings: &invoiceWarnings).vat
                warnings += invoiceWarnings
            } else {
                if invoice.isRR {
                    warnings.append(
                        "Faktura \(invoice.invoiceNumber): VAT RR nie został ujęty w podatku naliczonym — wymaga osobnego rozliczenia."
                    )
                    continue
                }
                inputVAT += JPKV7Generator.amountInPLN(
                    invoice.vatAmount, invoice: invoice, warnings: &warnings
                )
            }
        }

        let income: (base: Double, tax: Double, label: String)
        switch taxForm {
        case .ryczalt:
            let rows = RyczaltEngine.rows(
                from: visible,
                period: .init(year: incomePeriod.year),
                defaultRate: defaultRyczaltRate,
                calendar: calendar
            ).filter { incomePeriod.contains($0.revenueDate, calendar: calendar) }
            let summary = RyczaltEngine.summary(for: rows)
            income = (summary.totalRevenue, summary.estimatedTax, "Ryczałt (bez odliczeń)")

        case .kpir:
            let yearRows = KPiREngine.rows(
                from: visible,
                period: .init(year: incomePeriod.year),
                calendar: calendar
            )
            let throughCurrentPeriod = yearRows.filter {
                let components = calendar.dateComponents([.year, .month], from: $0.eventDate)
                return components.year == incomePeriod.year
                    && (components.month ?? 13) <= (incomePeriod.months.last ?? 12)
            }
            let beforeCurrentPeriod = yearRows.filter {
                let month = calendar.component(.month, from: $0.eventDate)
                return month < (incomePeriod.months.first ?? 1)
            }
            let currentBase = max(0, KPiREngine.summary(for: throughCurrentPeriod).income)
            let previousBase = max(0, KPiREngine.summary(for: beforeCurrentPeriod).income)
            let currentTax = cumulativePIT(base: currentBase, method: incomeTaxMethod)
            let previousTax = cumulativePIT(base: previousBase, method: incomeTaxMethod)
            income = (
                currentBase,
                max(0, rounded(currentTax - previousTax)),
                incomeTaxMethod == .scale ? "PIT — skala (szacunek narastający)" : "PIT liniowy (szacunek narastający)"
            )
        }

        var deadlines: [Deadline] = []
        deadlines.append(nextDeadline(kind: .zus, cycle: .monthly, day: 20, now: now, calendar: calendar))
        deadlines.append(nextDeadline(kind: .incomeTax, cycle: incomeTaxCycle, day: 20, now: now, calendar: calendar))
        if isActiveVATPayer {
            deadlines.append(nextDeadline(kind: .jpk, cycle: .monthly, day: 25, now: now, calendar: calendar))
            deadlines.append(nextDeadline(kind: .vat, cycle: vatCycle, day: 25, now: now, calendar: calendar))
        }
        deadlines.sort {
            $0.dueDate == $1.dueDate
                ? $0.kind.rawValue < $1.kind.rawValue
                : $0.dueDate < $1.dueDate
        }

        return Snapshot(
            deadlines: deadlines,
            forecast: Forecast(
                vatPeriod: vatPeriod,
                vatApplies: isActiveVATPayer,
                outputVAT: rounded(outputVAT),
                inputVAT: rounded(inputVAT),
                vatBalance: rounded(outputVAT - inputVAT),
                incomeTaxPeriod: incomePeriod,
                incomeTaxBase: rounded(income.base),
                incomeTax: rounded(income.tax),
                incomeTaxLabel: income.label,
                warnings: Array(Set(warnings)).sorted()
            )
        )
    }

    static func currentPeriod(
        cycle: TaxSettlementCycle,
        at date: Date,
        calendar: Calendar
    ) -> Period {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        switch cycle {
        case .monthly:
            return Period(year: year, months: [month])
        case .quarterly:
            let first = ((month - 1) / 3) * 3 + 1
            return Period(year: year, months: Array(first...(first + 2)))
        }
    }

    static func cumulativePIT(base: Double, method: KPiRIncomeTaxMethod) -> Double {
        let taxable = max(0, base)
        switch method {
        case .linear:
            return rounded(taxable * 0.19)
        case .scale:
            if taxable <= 120_000 {
                return max(0, rounded(taxable * 0.12 - 3_600))
            }
            return rounded(10_800 + (taxable - 120_000) * 0.32)
        }
    }

    static func nextDeadline(
        kind: DeadlineKind,
        cycle: TaxSettlementCycle,
        day: Int,
        now: Date,
        calendar: Calendar
    ) -> Deadline {
        let today = calendar.startOfDay(for: now)
        var candidates: [(period: Period, due: Date)] = []
        let nowYear = calendar.component(.year, from: now)

        switch cycle {
        case .monthly:
            for offset in -1...18 {
                guard let reference = calendar.date(byAdding: .month, value: offset, to: now) else { continue }
                let components = calendar.dateComponents([.year, .month], from: reference)
                guard let year = components.year, let month = components.month,
                      let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)
                else { continue }
                let dueComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                let nominal = calendar.date(from: DateComponents(
                    year: dueComponents.year, month: dueComponents.month, day: day
                ))!
                candidates.append((Period(year: year, months: [month]), adjustedDeadline(nominal, calendar: calendar)))
            }
        case .quarterly:
            for year in (nowYear - 1)...(nowYear + 2) {
                for firstMonth in [1, 4, 7, 10] {
                    let nextMonth = firstMonth == 10 ? 1 : firstMonth + 3
                    let dueYear = firstMonth == 10 ? year + 1 : year
                    let nominal = calendar.date(from: DateComponents(year: dueYear, month: nextMonth, day: day))!
                    candidates.append((
                        Period(year: year, months: Array(firstMonth...(firstMonth + 2))),
                        adjustedDeadline(nominal, calendar: calendar)
                    ))
                }
            }
        }

        let selected = candidates
            .filter { $0.due >= today }
            .min { $0.due < $1.due }
            ?? candidates.max { $0.due < $1.due }!
        return Deadline(kind: kind, dueDate: selected.due, period: selected.period)
    }

    private static func adjustedDeadline(_ nominal: Date, calendar: Calendar) -> Date {
        var result = calendar.startOfDay(for: nominal)
        while !PolishBusinessCalendar.isBusinessDay(result) {
            result = calendar.date(byAdding: .day, value: 1, to: result)!
        }
        return result
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
