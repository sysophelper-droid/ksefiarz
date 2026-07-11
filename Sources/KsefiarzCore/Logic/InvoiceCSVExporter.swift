import Foundation

/// Eksport listy faktur do pliku CSV (separator „;” — zgodny z polskim
/// Excelem/Numbers) — np. do przekazania księgowości.
public enum InvoiceCSVExporter {

    /// Nagłówek pliku CSV.
    static let header = [
        "Numer", "Numer KSeF", "Rodzaj", "Data wystawienia", "Termin płatności",
        "Sprzedawca", "NIP sprzedawcy", "Nabywca", "NIP nabywcy",
        "Netto", "VAT", "Brutto", "Status", "Forma płatności", "Rachunek",
    ].joined(separator: ";")

    /// Generuje zawartość CSV dla podanych faktur.
    public static func csv(for invoices: [Invoice]) -> String {
        var rows = [header]
        for invoice in invoices {
            rows.append([
                field(invoice.invoiceNumber),
                field(invoice.ksefId ?? ""),
                field(invoice.kind.displayName),
                FA2Format.dateFormatter.string(from: invoice.issueDate),
                invoice.paymentDueDate.map(FA2Format.dateFormatter.string(from:)) ?? "",
                field(invoice.sellerName),
                field(invoice.sellerNIP),
                field(invoice.buyerName),
                field(invoice.buyerNIP),
                decimal(invoice.netAmount),
                decimal(invoice.vatAmount),
                decimal(invoice.grossAmount),
                invoice.isPaid ? "opłacona" : (invoice.isOverdue ? "zaległa" : "do opłacenia"),
                field(invoice.paymentForm?.displayName ?? ""),
                field(invoice.paymentBankAccount ?? ""),
            ].joined(separator: ";"))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Kwoty z przecinkiem dziesiętnym (konwencja polskiego arkusza).
    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Pole CSV — cudzysłowy wokół wartości zawierających separator,
    /// cudzysłów lub nową linię.
    private static func field(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
