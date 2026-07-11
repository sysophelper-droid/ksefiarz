import Foundation
import SwiftData

@Model
public final class InvoiceTemplate {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    @Attribute(.externalStorage) public var presetData: Data

    public init(id: UUID = UUID(), name: String, preset: InvoicePreset, now: Date = .now) {
        self.id = id
        self.name = name
        createdAt = now
        updatedAt = now
        presetData = (try? JSONEncoder().encode(preset)) ?? Data()
    }

    public var preset: InvoicePreset? {
        get { try? JSONDecoder().decode(InvoicePreset.self, from: presetData) }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { return }
            presetData = data
            updatedAt = .now
        }
    }
}

public enum RecurrenceUnit: String, CaseIterable, Codable, Sendable {
    case week, month, year

    public var displayName: String {
        switch self {
        case .week: return "tygodni"
        case .month: return "miesięcy"
        case .year: return "lat"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self { case .week: return .weekOfYear; case .month: return .month; case .year: return .year }
    }
}

@Model
public final class RecurringInvoice {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var recurrenceUnitRaw: String
    public var recurrenceInterval: Int
    public var nextIssueDate: Date
    public var dueDays: Int
    public var isActive: Bool
    public var lastApprovedAt: Date?
    @Attribute(.externalStorage) public var presetData: Data

    public init(
        id: UUID = UUID(), name: String, preset: InvoicePreset,
        unit: RecurrenceUnit = .month, interval: Int = 1,
        nextIssueDate: Date = .now, dueDays: Int = 14,
        isActive: Bool = true, createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        recurrenceUnitRaw = unit.rawValue
        recurrenceInterval = max(1, interval)
        self.nextIssueDate = nextIssueDate
        self.dueDays = max(0, dueDays)
        self.isActive = isActive
        self.presetData = (try? JSONEncoder().encode(preset)) ?? Data()
    }

    public var unit: RecurrenceUnit {
        get { RecurrenceUnit(rawValue: recurrenceUnitRaw) ?? .month }
        set { recurrenceUnitRaw = newValue.rawValue }
    }

    public var preset: InvoicePreset? {
        try? JSONDecoder().decode(InvoicePreset.self, from: presetData)
    }
}
