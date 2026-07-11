import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Arkusz „Paczka dla księgowości”: wybór okresu i składników, podgląd
/// liczby dokumentów i braków, zapis jednego pliku ZIP (CSV + XML + PDF
/// + raport braków) przez systemowy panel zapisu.
struct AccountingPackageView: View {

    @Environment(\.dismiss) private var dismiss
    @Query private var invoices: [Invoice]

    /// Tryb wyboru okresu.
    private enum PeriodMode: String, CaseIterable, Identifiable {
        case month, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: return "Miesiąc"
            case .custom: return "Zakres dat"
            }
        }
    }

    @State private var periodMode: PeriodMode = .month
    /// Domyślnie poprzedni miesiąc — najczęstszy okres przekazywany księgowości.
    @State private var selectedMonth: Date = {
        let calendar = Calendar.current
        let startOfCurrent = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) ?? .now
        return calendar.date(byAdding: .month, value: -1, to: startOfCurrent) ?? .now
    }()
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var includeSales = true
    @State private var includePurchases = true
    @State private var includeXML = true
    @State private var includePDF = true
    @State private var statusMessage: String?

    /// Zakres dat wynikający z bieżących ustawień.
    private var dateRange: (from: Date, to: Date) {
        switch periodMode {
        case .month:
            let calendar = Calendar.current
            let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: selectedMonth)
            ) ?? selectedMonth
            let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
            return (start, end)
        case .custom:
            let start = Calendar.current.startOfDay(for: customFrom)
            let end = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 59, of: customTo
            ) ?? customTo
            return (start, end)
        }
    }

    /// Dokumenty spełniające kryteria (bez ukrytych — jak w statystykach).
    private var selectedInvoices: [Invoice] {
        let range = dateRange
        return invoices.filter { invoice in
            !invoice.isArchivedOrHidden
                && invoice.issueDate >= range.from
                && invoice.issueDate <= range.to
                && (invoice.kind == .sales ? includeSales : includePurchases)
        }
    }

    /// Liczba pozycji raportu braków dla bieżącego wyboru.
    private var issueCount: Int {
        selectedInvoices.reduce(0) {
            $0 + AccountingPackageBuilder.documentIssues(for: $1).count
        }
    }

    /// Etykieta okresu do raportu i nazwy pliku.
    private var periodLabel: String {
        switch periodMode {
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "LLLL yyyy"
            formatter.locale = Locale(identifier: "pl_PL")
            return formatter.string(from: selectedMonth)
        case .custom:
            let range = dateRange
            return "\(FA2Format.dateFormatter.string(from: range.from)) – \(FA2Format.dateFormatter.string(from: range.to))"
        }
    }

    private var suggestedFileName: String {
        switch periodMode {
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            return "ksiegowosc_\(formatter.string(from: selectedMonth)).zip"
        case .custom:
            return "ksiegowosc_\(FA2Format.dateFormatter.string(from: dateRange.from))_\(FA2Format.dateFormatter.string(from: dateRange.to)).zip"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Okres") {
                    Picker("Tryb", selection: $periodMode) {
                        ForEach(PeriodMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if periodMode == .month {
                        DatePicker(
                            "Miesiąc",
                            selection: $selectedMonth,
                            displayedComponents: .date
                        )
                        .help("Wybierz dowolny dzień miesiąca — paczka obejmie cały miesiąc.")
                    } else {
                        DatePicker("Od", selection: $customFrom, displayedComponents: .date)
                        DatePicker("Do", selection: $customTo, displayedComponents: .date)
                    }
                }
                Section("Zawartość") {
                    Toggle("Faktury sprzedażowe", isOn: $includeSales)
                    Toggle("Faktury zakupowe", isOn: $includePurchases)
                    Toggle("Oryginalne dokumenty XML", isOn: $includeXML)
                    Toggle("Wydruki PDF", isOn: $includePDF)
                }
                Section {
                    LabeledContent("Dokumenty w paczce") {
                        Text("\(selectedInvoices.count)")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Pozycje raportu braków") {
                        Text("\(issueCount)")
                            .foregroundStyle(issueCount == 0 ? .green : .orange)
                            .fontWeight(.semibold)
                    }
                } footer: {
                    Text("Paczka to jeden plik ZIP: zestawienia CSV (osobno sprzedaż i zakup), oryginalne XML, wydruki PDF oraz raport braków (m.in. dokumenty niewysłane do KSeF, odrzucone, bez UPO). Faktury ukryte nie wchodzą do paczki.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Zamknij", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    exportPackage()
                } label: {
                    Label("Zapisz paczkę…", systemImage: "archivebox")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedInvoices.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 480)
        .navigationTitle("Paczka dla księgowości")
    }

    /// Buduje ZIP i zapisuje przez panel zapisu.
    private func exportPackage() {
        let result = AccountingPackageBuilder.makePackage(
            invoices: selectedInvoices,
            periodLabel: periodLabel,
            options: .init(includeXML: includeXML, includePDF: includePDF)
        )
        let saved = FileExportService.exportData(
            result.zipData,
            suggestedName: suggestedFileName,
            contentType: .zip
        )
        if saved {
            statusMessage = "Zapisano paczkę: \(result.invoiceCount) dokumentów"
                + (result.issueCount > 0 ? ", \(result.issueCount) pozycji w raporcie braków." : ", komplet dokumentów.")
        }
    }
}
