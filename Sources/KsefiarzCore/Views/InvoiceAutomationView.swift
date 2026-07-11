import SwiftUI
import SwiftData

/// Centrum szablonów i faktur cyklicznych. Harmonogramy wyłącznie
/// przygotowują formularz — żadna faktura nie jest wysyłana automatycznie.
public struct InvoiceAutomationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InvoiceTemplate.updatedAt, order: .reverse) private var templates: [InvoiceTemplate]
    @Query(sort: \RecurringInvoice.nextIssueDate) private var schedules: [RecurringInvoice]

    @State private var templateToUse: InvoiceTemplate?
    @State private var templateForSchedule: InvoiceTemplate?
    @State private var scheduleToReview: RecurringInvoice?

    private var dueSchedules: [RecurringInvoice] {
        schedules.filter { InvoiceAutomationEngine.isDue($0) }
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dueSection
                schedulesSection
                templatesSection
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("Szablony i cykle")
        .sheet(item: $templateToUse) { template in
            if let preset = template.preset {
                NewInvoiceView(
                    initialDraft: preset.draft(),
                    sourceTitle: "Nowa z szablonu: \(template.name)"
                )
            }
        }
        .sheet(item: $templateForSchedule) { template in
            ScheduleEditorView(template: template)
        }
        .sheet(item: $scheduleToReview) { schedule in
            if let draft = InvoiceAutomationEngine.draft(for: schedule) {
                NewInvoiceView(
                    initialDraft: draft,
                    sourceTitle: "Do zatwierdzenia: \(schedule.name)"
                ) {
                    InvoiceAutomationEngine.markApproved(schedule)
                    try? modelContext.save()
                }
            }
        }
    }

    @ViewBuilder
    private var dueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Oczekują na decyzję", systemImage: "checkmark.seal")
                .font(.title2.weight(.semibold))
            if dueSchedules.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Brak faktur cyklicznych do zatwierdzenia.")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(dueSchedules) { schedule in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(schedule.name).font(.headline)
                            Text("Planowana data: \(schedule.nextIssueDate.formatted(date: .long, time: .omitted))")
                                .foregroundStyle(.secondary)
                            Text("Nic nie zostanie wysłane bez otwarcia formularza i zatwierdzenia.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Przejrzyj i wystaw") { scheduleToReview = schedule }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(16)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.3)))
                }
            }
        }
    }

    @ViewBuilder
    private var schedulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Harmonogramy").font(.title2.weight(.semibold))
            if schedules.isEmpty {
                Text("Utwórz harmonogram z wybranego szablonu poniżej.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(schedules) { schedule in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { schedule.isActive },
                            set: { schedule.isActive = $0; try? modelContext.save() }
                        )).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedule.name).font(.headline)
                            Text("Co \(schedule.recurrenceInterval) \(schedule.unit.displayName) · następna: \(schedule.nextIssueDate.formatted(date: .abbreviated, time: .omitted)) · termin płatności +\(schedule.dueDays) dni")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { modelContext.delete(schedule) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Usuń harmonogram")
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Szablony").font(.title2.weight(.semibold))
            Text("Szablon zapiszesz w formularzu faktury albo podczas duplikowania istniejącego dokumentu.")
                .foregroundStyle(.secondary)
            if templates.isEmpty {
                ContentUnavailableView(
                    "Brak szablonów", systemImage: "doc.on.doc",
                    description: Text("Otwórz nową lub istniejącą fakturę i wybierz „Zapisz jako szablon”.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(templates) { template in
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.title2).foregroundStyle(.blue)
                            Text(template.name).font(.headline).lineLimit(2)
                            if let preset = template.preset {
                                Text("\(preset.buyerName) · \(preset.lines.count) poz.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Użyj") { templateToUse = template }
                                    .buttonStyle(.borderedProminent)
                                Menu {
                                    Button("Utwórz harmonogram") { templateForSchedule = template }
                                    Divider()
                                    Button("Usuń", role: .destructive) { modelContext.delete(template) }
                                } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct ScheduleEditorView: View {
    let template: InvoiceTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var unit: RecurrenceUnit = .month
    @State private var interval = 1
    @State private var nextDate = Date.now
    @State private var dueDays = 14

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Faktura cykliczna") {
                    TextField("Nazwa harmonogramu", text: $name)
                    DatePicker("Pierwsza data wystawienia", selection: $nextDate, displayedComponents: .date)
                    Picker("Okres", selection: $unit) {
                        Text("Tygodnie").tag(RecurrenceUnit.week)
                        Text("Miesiące").tag(RecurrenceUnit.month)
                        Text("Lata").tag(RecurrenceUnit.year)
                    }
                    Stepper("Co \(interval) \(unit.displayName)", value: $interval, in: 1...24)
                    Stepper("Termin płatności: +\(dueDays) dni", value: $dueDays, in: 0...120)
                }
                Section {
                    Label("W terminie aplikacja pokaże dokument do przejrzenia. Nie wyśle go automatycznie.", systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                Spacer()
                Button("Utwórz harmonogram") {
                    guard let preset = template.preset else { return }
                    modelContext.insert(RecurringInvoice(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        preset: preset, unit: unit, interval: interval,
                        nextIssueDate: nextDate, dueDays: dueDays
                    ))
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding()
        }
        .frame(width: 520, height: 430)
        .navigationTitle("Nowy harmonogram")
        .onAppear { if name.isEmpty { name = template.name } }
    }
}
