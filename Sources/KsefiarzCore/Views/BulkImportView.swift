import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Kreator importu CSV/XLSX: wybór rodzaju danych, mapowanie kolumn,
/// podgląd bilansu i jedno zatwierdzenie do SwiftData.
struct BulkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var contractors: [Contractor]
    @Query private var products: [Product]
    @Query private var invoices: [Invoice]

    @AppStorage(AppSettingsKeys.sellerName) private var companyName = ""
    @AppStorage(AppSettingsKeys.nip) private var companyNIP = ""
    @AppStorage(AppSettingsKeys.sellerAddress) private var companyAddress = ""

    @State private var entity: BulkImportEntity = .contractors
    @State private var defaultInvoiceKind: Invoice.Kind = .sales
    @State private var sheet: TabularSheet?
    @State private var mapping: [BulkImportField: Int] = [:]
    @State private var plan = BulkImportPlan()
    @State private var fileName = ""
    @State private var statusMessage: String?
    @State private var didImport = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let sheet {
                HSplitView {
                    mappingPane(sheet)
                        .frame(minWidth: 390, idealWidth: 440)
                    previewPane(sheet)
                        .frame(minWidth: 420, idealWidth: 500)
                }
            } else {
                emptyState
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 650)
        .onChange(of: entity) {
            remapAndRebuild()
        }
        .onChange(of: defaultInvoiceKind) {
            rebuildPlan()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import danych")
                    .font(.title2.weight(.semibold))
                Text("CSV, TSV lub pierwszy arkusz skoroszytu Excel (.xlsx)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Dane", selection: $entity) {
                ForEach(BulkImportEntity.allCases) { entity in
                    Text(entity.displayName).tag(entity)
                }
            }
            .frame(width: 230)
            if entity == .invoices {
                Picker("Domyślnie", selection: $defaultInvoiceKind) {
                    ForEach(Invoice.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .frame(width: 180)
                .help("Używane, gdy plik nie ma kolumny rodzaju faktury")
            }
            Button {
                chooseFile()
            } label: {
                Label(sheet == nil ? "Wybierz plik" : "Zmień plik", systemImage: "doc.badge.plus")
            }
        }
        .padding(18)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Wybierz plik do importu", systemImage: "tablecells")
        } description: {
            Text("Ksefiarz sam dopasuje typowe nagłówki Fakturowni i wFirmy. Przed zapisem możesz zmienić każde przypisanie kolumny.")
        } actions: {
            Button("Wybierz CSV lub Excel") { chooseFile() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mappingPane(_ sheet: TabularSheet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mapowanie kolumn")
                        .font(.headline)
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(sheet.headers.count) kol.")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(BulkImportField.fields(for: entity)) { field in
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Text(field.label)
                                if field.isRequired {
                                    Text("*").foregroundStyle(.red)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("", selection: mappingBinding(field)) {
                                Text("— pomiń —").tag(Optional<Int>.none)
                                ForEach(sheet.headers.indices, id: \.self) { index in
                                    Text("\(columnName(index)) · \(headerLabel(sheet.headers[index]))")
                                        .tag(Optional(index))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 205)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func previewPane(_ sheet: TabularSheet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bilans importu")
                    .font(.headline)
                HStack(spacing: 0) {
                    balanceValue(plan.importCount, label: "do importu", color: .green)
                    Divider().frame(height: 42)
                    balanceValue(plan.duplicateCount, label: "duplikaty", color: .secondary)
                    Divider().frame(height: 42)
                    balanceValue(plan.errorCount, label: "błędy", color: plan.errorCount == 0 ? .secondary : .red)
                    Divider().frame(height: 42)
                    balanceValue(plan.warningCount, label: "ostrzeżenia", color: plan.warningCount == 0 ? .secondary : .orange)
                }
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourcePreview(sheet)
                    issuesPreview
                }
                .padding(14)
            }
        }
    }

    private func balanceValue(_ value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourcePreview(_ sheet: TabularSheet) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Podgląd źródła")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    previewRow(sheet.headers, isHeader: true)
                    ForEach(Array(sheet.dataRows.prefix(6).enumerated()), id: \.offset) { _, row in
                        previewRow(row, isHeader: false)
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.6)))
            }
        }
    }

    private func previewRow(_ row: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.prefix(8).enumerated()), id: \.offset) { _, value in
                Text(value.isEmpty ? " " : value)
                    .font(isHeader ? .caption.weight(.semibold) : .caption.monospacedDigit())
                    .lineLimit(1)
                    .frame(width: 132, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(isHeader ? Color.accentColor.opacity(0.10) : Color.clear)
                    .overlay(alignment: .trailing) { Divider() }
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var issuesPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Kontrola danych")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if plan.issues.count > 30 {
                    Text("pierwsze 30 z \(plan.issues.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if plan.issues.isEmpty {
                Label("Nie wykryto problemów w danych.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(plan.issues.prefix(30).enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: issue.severity == .error
                                  ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                            Text(issue.row.map { "Wiersz \($0): \(issue.message)" } ?? issue.message)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let statusMessage {
                Label(statusMessage, systemImage: didImport ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(didImport ? .green : .red)
            } else if sheet != nil {
                Text("Duplikaty są pomijane. Import nie nadpisuje istniejących danych.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(didImport ? "Gotowe" : "Anuluj", role: didImport ? nil : .cancel) { dismiss() }
            if !didImport {
                Button(plan.errorCount > 0 ? "Importuj poprawne rekordy" : "Importuj") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(14)
    }

    private var canImport: Bool {
        plan.importCount > 0 && !plan.issues.contains { $0.severity == .error && $0.row == nil }
    }

    private func mappingBinding(_ field: BulkImportField) -> Binding<Int?> {
        Binding(
            get: { mapping[field] },
            set: { newValue in
                if let newValue { mapping[field] = newValue }
                else { mapping.removeValue(forKey: field) }
                didImport = false
                statusMessage = nil
                rebuildPlan()
            }
        )
    }

    @MainActor
    private func chooseFile() {
        let types = [UTType.commaSeparatedText, .tabSeparatedText, .plainText,
                     UTType(filenameExtension: "xlsx")].compactMap { $0 }
        guard let url = FileExportService.importFileURL(
            allowedTypes: types,
            message: "Wybierz plik CSV, TSV lub Excel (.xlsx) z nagłówkami w pierwszym wierszu."
        ) else { return }
        do {
            let loaded = try TabularFileReader.read(url: url)
            sheet = loaded
            fileName = url.lastPathComponent
            didImport = false
            statusMessage = nil
            remapAndRebuild()
        } catch {
            sheet = nil
            mapping = [:]
            plan = BulkImportPlan()
            didImport = false
            statusMessage = error.localizedDescription
        }
    }

    private func remapAndRebuild() {
        guard let sheet else { return }
        mapping = BulkImportEngine.automaticMapping(entity: entity, headers: sheet.headers)
        didImport = false
        statusMessage = nil
        rebuildPlan()
    }

    private func rebuildPlan() {
        guard let sheet else {
            plan = BulkImportPlan()
            return
        }
        let options = BulkImportOptions(
            defaultInvoiceKind: defaultInvoiceKind,
            company: .init(name: companyName, nip: companyNIP, address: companyAddress)
        )
        plan = BulkImportEngine.plan(
            sheet: sheet,
            entity: entity,
            mapping: mapping,
            options: options,
            existing: existingKeys
        )
    }

    private var existingKeys: BulkImportExistingKeys {
        BulkImportService.existingKeys(
            contractors: contractors, products: products, invoices: invoices
        )
    }

    private func performImport() {
        do {
            let count = try BulkImportService.apply(plan, to: modelContext)
            didImport = true
            statusMessage = "Zaimportowano \(count) rekordów."
        } catch {
            didImport = false
            statusMessage = "Import nie został zapisany: \(error.localizedDescription)"
        }
    }

    private func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        }
        return result
    }

    private func headerLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(bez nagłówka)" : trimmed
    }
}
