import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Zapis plików faktur (XML / PDF) przez systemowy panel zapisu.
@MainActor
public enum FileExportService {

    /// Eksportuje oryginalny dokument XML faktury.
    /// Zwraca `true` tylko, gdy plik faktycznie zapisano (nie przy anulowaniu).
    @discardableResult
    public static func exportXML(of invoice: Invoice) -> Bool {
        guard let xml = invoice.rawXmlContent, !xml.isEmpty else { return false }
        return save(
            data: Data(xml.utf8),
            suggestedName: "Faktura_\(sanitized(invoice.invoiceNumber)).xml",
            contentType: .xml
        )
    }

    /// Eksportuje dowolne dane (np. UPO) przez panel zapisu.
    /// Zwraca `true` tylko, gdy plik faktycznie zapisano (nie przy anulowaniu).
    @discardableResult
    public static func exportData(_ data: Data, suggestedName: String, contentType: UTType) -> Bool {
        save(data: data, suggestedName: suggestedName, contentType: contentType)
    }

    /// Eksportuje listę faktur do pliku CSV.
    /// Zwraca `true` tylko, gdy plik faktycznie zapisano (nie przy anulowaniu).
    @discardableResult
    public static func exportCSV(of invoices: [Invoice], suggestedName: String) -> Bool {
        guard !invoices.isEmpty else { return false }
        return save(
            data: Data(InvoiceCSVExporter.csv(for: invoices).utf8),
            suggestedName: suggestedName,
            contentType: .commaSeparatedText
        )
    }

    /// Eksportuje fakturę jako dokument PDF (opcjonalnie w układzie
    /// dwujęzycznym PL/EN dla kontrahentów zagranicznych).
    /// Zwraca `true` tylko, gdy plik faktycznie zapisano (nie przy anulowaniu).
    @discardableResult
    public static func exportPDF(of invoice: Invoice, bilingual: Bool = false) -> Bool {
        guard let pdf = InvoicePDFGenerator.pdfData(for: invoice, bilingual: bilingual) else { return false }
        let suffix = bilingual ? "_PL-EN" : ""
        return save(
            data: pdf,
            suggestedName: "Faktura_\(sanitized(invoice.invoiceNumber))\(suffix).pdf",
            contentType: .pdf
        )
    }

    /// Otwiera systemowe okno drukowania macOS dla gotowego dokumentu PDF.
    /// Budowanie zbiorczego PDF pozostaje po stronie wywołującego
    /// (`BatchInvoicePDFBuilder`), aby jego błąd nie mylił się z anulowaniem.
    @discardableResult
    public static func printPDF(data: Data) -> Bool {
        guard
            let document = PDFDocument(data: data),
            let operation = document.printOperation(
                for: NSPrintInfo.shared,
                scalingMode: .pageScaleToFit,
                autoRotate: true
            )
        else { return false }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation.run()
    }

    /// Otwiera NSSavePanel i zapisuje dane pod wybraną ścieżką.
    /// Zwraca `true` po udanym zapisie; `false` przy anulowaniu lub błędzie.
    private static func save(data: Data, suggestedName: String, contentType: UTType) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Otwiera panel wyboru pliku i zwraca jego zawartość (np. import kopii zapasowej).
    public static func importData(allowedTypes: [UTType]) -> Data? {
        guard let url = importFileURL(allowedTypes: allowedTypes) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Panel wyboru pliku bez ograniczenia typu — np. wyciągi MT940, które
    /// banki zapisują pod różnymi rozszerzeniami (.sta, .mt940, .txt, .940).
    public static func importAnyData(message: String = "") -> Data? {
        guard let url = importFileURL(message: message) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Panel wyboru pliku zwracający URL zamiast zawartości — np. skan/PDF
    /// faktury do OCR, gdzie plik czytają PDFKit/Vision. Pusta lista typów
    /// oznacza brak ograniczenia.
    public static func importFileURL(allowedTypes: [UTType] = [], message: String = "") -> URL? {
        let panel = NSOpenPanel()
        if !allowedTypes.isEmpty { panel.allowedContentTypes = allowedTypes }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if !message.isEmpty { panel.message = message }

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Numer faktury bez znaków niedozwolonych w nazwie pliku.
    private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }
}
