import Foundation

/// Treść kodu QR polecenia przelewu w standardzie **2D ZBP** (Rekomendacja
/// Związku Banków Polskich). Klient skanuje kod aplikacją banku i płaci
/// bez ręcznego przepisywania rachunku, kwoty i tytułu.
///
/// Format to dziewięć pól rozdzielonych znakiem `|` (potok):
/// `NIP | KodKraju | NrRachunku | Kwota | NazwaOdbiorcy | Tytuł | Rez1 | Rez2 | Rez3`,
/// gdzie:
/// - **NIP** — 10 cyfr NIP odbiorcy (opcjonalny; przy niepoprawnym pusty),
/// - **KodKraju** — dwuliterowy kod kraju odbiorcy (np. `PL`),
/// - **NrRachunku** — 26 cyfr NRB (bez prefiksu `PL` i separatorów),
/// - **Kwota** — kwota w GROSZACH, wyrównana zerami do min. 6 cyfr (`%06d`),
/// - **NazwaOdbiorcy** — maks. 20 znaków,
/// - **Tytuł** — maks. 32 znaki,
/// - **Rez1–3** — pola rezerwowe (puste).
///
/// Całość nie może przekroczyć 160 znaków. Standard obejmuje wyłącznie
/// krajowe przelewy w PLN — dla innych walut kod nie powstaje.
///
/// To czysta logika (bez rysowania) z testami; obraz QR rysuje
/// `QRCodeRenderer`, a osadza go `InvoicePDFGenerator`.
public enum PaymentQRCode {

    /// Separator pól standardu 2D ZBP.
    public static let fieldSeparator = "|"
    /// Maksymalna długość całego łańcucha kodu.
    public static let maxTotalLength = 160
    /// Maksymalna długość nazwy odbiorcy.
    public static let nameMaxLength = 20
    /// Maksymalna długość tytułu przelewu.
    public static let titleMaxLength = 32
    /// Wymagana długość numeru rachunku (NRB).
    public static let bankAccountLength = 26
    /// Minimalna liczba cyfr pola kwoty (zera wiodące).
    public static let amountMinDigits = 6

    /// Czy kod QR płatności ma być rysowany na wydruku faktury. Ustawienie
    /// jest domyślnie WŁĄCZONE — funkcja ma wartość dopiero, gdy odbiorca
    /// może dzięki niej zapłacić, więc nie zaśmieca dokumentów, na których
    /// i tak się nie pojawi (waluta obca, brak rachunku, faktura opłacona).
    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppSettingsKeys.pdfPaymentQR) as? Bool ?? true
    }

    /// Buduje treść kodu 2D ZBP z danych pojedynczego przelewu. Zwraca `nil`,
    /// gdy przelewu nie da się poprawnie zakodować (waluta inna niż PLN,
    /// kwota niedodatnia, brak poprawnego 26-cyfrowego rachunku, pusta nazwa
    /// lub tytuł, albo przekroczenie 160 znaków).
    public static func zbpTransferContent(
        recipientName: String,
        recipientNIP: String,
        bankAccount: String,
        amount: Double,
        currency: String,
        title: String,
        countryCode: String = "PL"
    ) -> String? {
        // Standard 2D ZBP to krajowy przelew w złotych — kwota w groszach.
        guard currency.trimmingCharacters(in: .whitespaces).uppercased() == "PLN" else { return nil }

        let account = normalizedBankAccount(bankAccount)
        guard account.count == bankAccountLength else { return nil }

        let name = truncated(recipientName, to: nameMaxLength)
        guard !name.isEmpty else { return nil }

        let paymentTitle = truncated(title, to: titleMaxLength)
        guard !paymentTitle.isEmpty else { return nil }

        let grosze = Int((amount * 100).rounded())
        guard grosze > 0 else { return nil }
        // `%ld` (long) — na 64-bitowym macOS `%d` odczytałby tylko 32 bity,
        // psując pole kwoty dla dużych faktur (grosze > Int32.max ≈ 21,4 mln zł).
        let amountField = String(format: "%0\(amountMinDigits)ld", grosze)

        let fields = [
            normalizedNIP(recipientNIP), // NIP odbiorcy (opcjonalny)
            normalizedCountry(countryCode),
            account,
            amountField,
            name,
            paymentTitle,
            "", "", "", // rezerwacje 1–3
        ]
        let content = fields.joined(separator: fieldSeparator)
        guard content.count <= maxTotalLength else { return nil }
        return content
    }

    /// Wariant z faktury. Kod płatności powstaje wyłącznie dla WŁASNEJ
    /// sprzedaży — to nasza firma jest odbiorcą przelewu, więc kupujący płaci
    /// nam. Kwota to saldo pozostałe do zapłaty (`outstandingAmount`), dzięki
    /// czemu faktura opłacona (saldo 0) nie dostaje kodu, a częściowo
    /// opłacona — kod na kwotę brakującą. Odbiorcą jest sprzedawca, a tytułem
    /// numer faktury.
    public static func zbpTransferContent(for invoice: Invoice) -> String? {
        guard invoice.kind == .sales else { return nil }
        return zbpTransferContent(
            recipientName: invoice.sellerName,
            recipientNIP: invoice.sellerNIP,
            bankAccount: invoice.paymentBankAccount ?? "",
            amount: invoice.outstandingAmount,
            currency: invoice.currency,
            title: invoice.invoiceNumber
        )
    }

    // MARK: - Normalizacje pól

    /// Numer rachunku do 26 cyfr: usuwa spacje, prefiks `PL` i pozostałe znaki.
    static func normalizedBankAccount(_ value: String) -> String {
        var text = value.uppercased()
        if text.hasPrefix("PL") { text.removeFirst(2) }
        return String(text.filter(\.isNumber))
    }

    /// NIP do dokładnie 10 cyfr (bez prefiksu `PL` i kresek); w przeciwnym
    /// razie pusty — pole jest opcjonalne, więc niepełny NIP go nie psuje.
    static func normalizedNIP(_ value: String) -> String {
        var text = value.uppercased()
        if text.hasPrefix("PL") { text.removeFirst(2) }
        let digits = String(text.filter(\.isNumber))
        return digits.count == 10 ? digits : ""
    }

    /// Dwuliterowy kod kraju (wielkie litery) albo pusty.
    static func normalizedCountry(_ value: String) -> String {
        let letters = value.uppercased().filter(\.isLetter)
        return letters.count == 2 ? String(letters) : ""
    }

    /// Przycina po przycięciu białych znaków do zadanego limitu.
    static func truncated(_ value: String, to limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}
