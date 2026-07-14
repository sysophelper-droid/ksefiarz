import Foundation
import PDFKit

/// Łączy wydruki wielu faktur w jeden dokument PDF, zachowując kolejność
/// przekazaną przez listę (zaznaczenie albo wszystkie widoczne dokumenty).
@MainActor
public enum BatchInvoicePDFBuilder {

    public struct Result {
        public let data: Data
        public let invoiceCount: Int
        public let pageCount: Int
    }

    /// Generuje jeden PDF. Pusty wybór albo błąd któregokolwiek wydruku
    /// zwraca `nil`, aby użytkownik nie dostał niekompletnego pliku bez wiedzy.
    public static func makePDF(invoices: [Invoice]) -> Result? {
        guard !invoices.isEmpty else { return nil }
        let combined = PDFDocument()

        for invoice in invoices {
            guard
                let data = InvoicePDFGenerator.pdfData(for: invoice),
                let source = PDFDocument(data: data),
                source.pageCount > 0
            else { return nil }

            for index in 0..<source.pageCount {
                guard let page = source.page(at: index)?.copy() as? PDFPage else { return nil }
                combined.insert(page, at: combined.pageCount)
            }
        }

        guard let data = combined.dataRepresentation(), combined.pageCount > 0 else { return nil }
        return Result(data: data, invoiceCount: invoices.count, pageCount: combined.pageCount)
    }
}
