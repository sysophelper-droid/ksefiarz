import Foundation

/// Paczka dla księgowości: jeden plik ZIP z kompletem dokumentów wybranego
/// okresu — zestawienia CSV, oryginalne XML, wydruki PDF oraz raport
/// brakujących dokumentów i spraw wymagających uwagi.
@MainActor
public enum AccountingPackageBuilder {

    public struct Options: Sendable {
        public var includeXML = true
        public var includePDF = true

        public init(includeXML: Bool = true, includePDF: Bool = true) {
            self.includeXML = includeXML
            self.includePDF = includePDF
        }
    }

    public struct Result {
        /// Gotowe archiwum ZIP.
        public let zipData: Data
        /// Liczba faktur w paczce.
        public let invoiceCount: Int
        /// Liczba wykrytych braków (pozycji raportu).
        public let issueCount: Int
    }

    /// Buduje paczkę z przekazanych faktur (już przefiltrowanych po okresie).
    public static func makePackage(
        invoices: [Invoice],
        periodLabel: String,
        options: Options = Options(),
        now: Date = .now
    ) -> Result {
        var zip = ZipWriter()
        var issues: [(invoice: Invoice, problems: [String])] = []

        let byKind: [(Invoice.Kind, String)] = [(.sales, "sprzedaz"), (.purchase, "zakup")]

        for (kind, kindName) in byKind {
            let kindInvoices = invoices
                .filter { $0.kind == kind }
                .sorted { $0.issueDate < $1.issueDate }
            guard !kindInvoices.isEmpty else { continue }

            // Zestawienie CSV dla rodzaju.
            zip.addFile(
                path: "zestawienie_\(kindName).csv",
                data: Data(InvoiceCSVExporter.csv(for: kindInvoices).utf8),
                date: now
            )

            for invoice in kindInvoices {
                var problems = documentIssues(for: invoice)
                let baseName = "Faktura_\(sanitized(invoice.invoiceNumber))"

                if options.includeXML {
                    if let xml = invoice.rawXmlContent, !xml.isEmpty {
                        zip.addFile(
                            path: "XML/\(kindName)/\(baseName).xml",
                            data: Data(xml.utf8),
                            date: now
                        )
                    }
                }
                if options.includePDF {
                    if let pdf = InvoicePDFGenerator.pdfData(for: invoice) {
                        zip.addFile(
                            path: "PDF/\(kindName)/\(baseName).pdf",
                            data: pdf,
                            date: now
                        )
                    } else {
                        problems.append("nie udało się wygenerować wydruku PDF")
                    }
                }
                if !problems.isEmpty {
                    issues.append((invoice, problems))
                }
            }
        }

        let report = makeReport(
            invoices: invoices,
            issues: issues,
            periodLabel: periodLabel,
            now: now
        )
        zip.addFile(path: "raport.txt", data: Data(report.utf8), date: now)

        return Result(
            zipData: zip.finalized(),
            invoiceCount: invoices.count,
            issueCount: issues.reduce(0) { $0 + $1.problems.count }
        )
    }

    /// Braki i sprawy wymagające uwagi dla pojedynczej faktury —
    /// czysta logika, testowana osobno.
    static func documentIssues(for invoice: Invoice) -> [String] {
        var problems: [String] = []
        if (invoice.rawXmlContent ?? "").isEmpty {
            problems.append("brak oryginalnego dokumentu XML")
        }
        switch invoice.ksefSubmissionStatus {
        case .local where invoice.kind == .sales:
            problems.append("faktura lokalna — nie przekazana do KSeF")
        case .offlinePending:
            problems.append("offline24 — oczekuje na dosłanie do KSeF")
        case .processing:
            problems.append("w trakcie przetwarzania przez KSeF (brak numeru KSeF)")
        case .rejected:
            problems.append("ODRZUCONA przez KSeF — wymaga ponownego wystawienia")
        case .accepted where invoice.kind == .sales && (invoice.upoXmlContent ?? "").isEmpty:
            problems.append("brak pobranego UPO")
        default:
            break
        }
        if invoice.kind == .sales, invoice.buyerNIP.isEmpty {
            problems.append("brak NIP nabywcy")
        }
        return problems
    }

    /// Raport tekstowy: podsumowanie okresu + lista braków per faktura.
    static func makeReport(
        invoices: [Invoice],
        issues: [(invoice: Invoice, problems: [String])],
        periodLabel: String,
        now: Date
    ) -> String {
        var lines: [String] = []
        lines.append("PACZKA DLA KSIĘGOWOŚCI — \(periodLabel)")
        lines.append("Wygenerowano: \(FA2Format.timestampFormatter.string(from: now)) (Ksefiarz)")
        lines.append("")

        for (kind, label) in [(Invoice.Kind.sales, "Sprzedaż"), (.purchase, "Zakup")] {
            let kindInvoices = invoices.filter { $0.kind == kind }
            guard !kindInvoices.isEmpty else { continue }
            lines.append("\(label): \(kindInvoices.count) faktur")
            // Sumy per waluta (faktury walutowe nie mieszają się z PLN).
            let byCurrency = Dictionary(grouping: kindInvoices) {
                CurrencyCode.normalizedOrPLN($0.currency)
            }
            for currency in byCurrency.keys.sorted() {
                let subset = byCurrency[currency] ?? []
                let net = subset.reduce(0) { $0 + $1.netAmount }
                let vat = subset.reduce(0) { $0 + $1.vatAmount }
                let gross = subset.reduce(0) { $0 + $1.grossAmount }
                lines.append("  \(currency): netto \(FA2Format.amount(net)), VAT \(FA2Format.amount(vat)), brutto \(FA2Format.amount(gross))")
            }
        }
        lines.append("")

        if issues.isEmpty {
            lines.append("BRAKI: nie wykryto — komplet dokumentów.")
        } else {
            lines.append("BRAKI I SPRAWY WYMAGAJĄCE UWAGI (\(issues.reduce(0) { $0 + $1.problems.count })):")
            for entry in issues.sorted(by: { $0.invoice.issueDate < $1.invoice.issueDate }) {
                let kind = entry.invoice.kind == .sales ? "sprzedaż" : "zakup"
                let date = FA2Format.dateFormatter.string(from: entry.invoice.issueDate)
                lines.append("")
                lines.append("• \(entry.invoice.invoiceNumber) (\(kind), \(date), \(entry.invoice.buyerName.isEmpty ? entry.invoice.sellerName : entry.invoice.buyerName))")
                for problem in entry.problems {
                    lines.append("  – \(problem)")
                }
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Numer faktury bez znaków niedozwolonych w nazwach plików.
    static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }
}
