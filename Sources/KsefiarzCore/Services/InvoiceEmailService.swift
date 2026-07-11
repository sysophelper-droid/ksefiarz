import AppKit
import Foundation

/// Błędy przekazania faktury do wysyłki e-mail.
public enum InvoiceEmailError: LocalizedError {
    case composeUnavailable
    case missingPDF
    case missingXML

    public var errorDescription: String? {
        switch self {
        case .composeUnavailable:
            return "Nie można otworzyć okna nowej wiadomości — sprawdź, czy w aplikacji Mail jest skonfigurowane konto pocztowe."
        case .missingPDF:
            return "Nie udało się wygenerować PDF faktury."
        case .missingXML:
            return "Faktura nie ma zapisanego dokumentu XML."
        }
    }
}

/// Przekazanie faktury do wysyłki e-mail przez systemowe okno tworzenia
/// wiadomości (NSSharingService — aplikacja Mail). Załączniki (PDF/XML)
/// są zapisywane do katalogu tymczasowego pod czytelnymi nazwami.
@MainActor
public enum InvoiceEmailService {

    /// Otwiera okno nowej wiadomości z adresatem, tematem, treścią
    /// i wybranymi załącznikami. Zwraca sterowanie po przekazaniu do Mail —
    /// samą wysyłkę użytkownik zatwierdza w oknie wiadomości.
    public static func compose(
        invoice: Invoice,
        recipient: String,
        subject: String,
        body: String,
        includePDF: Bool,
        includeXML: Bool
    ) throws {
        guard let service = NSSharingService(named: .composeEmail) else {
            throw InvoiceEmailError.composeUnavailable
        }

        var items: [Any] = [body]
        let baseName = InvoiceEmailComposer.attachmentBaseName(for: invoice)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KsefiarzEmail-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if includePDF {
            guard let pdfData = InvoicePDFGenerator.pdfData(for: invoice) else {
                throw InvoiceEmailError.missingPDF
            }
            let url = directory.appending(path: "\(baseName).pdf")
            try pdfData.write(to: url)
            items.append(url)
        }
        if includeXML {
            guard let xml = invoice.rawXmlContent, !xml.isEmpty else {
                throw InvoiceEmailError.missingXML
            }
            let url = directory.appending(path: "\(baseName).xml")
            try Data(xml.utf8).write(to: url)
            items.append(url)
        }

        service.recipients = recipient.isEmpty ? [] : [recipient]
        service.subject = subject
        guard service.canPerform(withItems: items) else {
            throw InvoiceEmailError.composeUnavailable
        }
        service.perform(withItems: items)
    }
}
