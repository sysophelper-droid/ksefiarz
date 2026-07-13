import Foundation
import Testing
@testable import KsefiarzCore

@Suite("PaymentQRCode — kod płatności 2D ZBP")
struct PaymentQRCodeTests {

    // MARK: - Budowa łańcucha z danych przelewu

    @Test("Pełny łańcuch: 9 pól rozdzielonych | w kolejności standardu 2D ZBP")
    func fullString() throws {
        let content = try #require(PaymentQRCode.zbpTransferContent(
            recipientName: "Firma",
            recipientNIP: "5260250274",
            bankAccount: "12 3456 7890 1234 5678 9012 3456",
            amount: 1230,
            currency: "PLN",
            title: "FV/2026/07/001"
        ))
        #expect(content == "5260250274|PL|12345678901234567890123456|123000|Firma|FV/2026/07/001|||")

        // Dokładnie dziewięć pól (osiem separatorów).
        let fields = content.components(separatedBy: "|")
        #expect(fields.count == 9)
        #expect(fields[0] == "5260250274")   // NIP
        #expect(fields[1] == "PL")           // kod kraju
        #expect(fields[2] == "12345678901234567890123456") // NRB
        #expect(fields[3] == "123000")       // kwota w groszach
        #expect(fields[4] == "Firma")        // nazwa odbiorcy
        #expect(fields[5] == "FV/2026/07/001") // tytuł
        #expect(fields[6] == "" && fields[7] == "" && fields[8] == "") // rezerwacje
    }

    @Test("Rachunek: usuwa spacje i prefiks PL, zostawia 26 cyfr")
    func accountNormalization() {
        #expect(PaymentQRCode.normalizedBankAccount("PL 12 3456 7890 1234 5678 9012 3456")
            == "12345678901234567890123456")
        #expect(PaymentQRCode.normalizedBankAccount("12345678901234567890123456").count == 26)
    }

    @Test("Rachunek o innej długości niż 26 cyfr → brak kodu")
    func invalidAccount() {
        // 25 cyfr — za krótki.
        #expect(PaymentQRCode.zbpTransferContent(
            recipientName: "Firma", recipientNIP: "", bankAccount: "1234567890123456789012345",
            amount: 100, currency: "PLN", title: "FV/1"
        ) == nil)
        // Pusty rachunek.
        #expect(PaymentQRCode.zbpTransferContent(
            recipientName: "Firma", recipientNIP: "", bankAccount: "",
            amount: 100, currency: "PLN", title: "FV/1"
        ) == nil)
    }

    @Test("NIP: prefiks PL i kreski usuwane; niepoprawny (≠10 cyfr) → pusty")
    func nipNormalization() {
        #expect(PaymentQRCode.normalizedNIP("PL526-025-02-74") == "5260250274")
        #expect(PaymentQRCode.normalizedNIP("123") == "")       // za krótki
        #expect(PaymentQRCode.normalizedNIP("12345678901") == "") // za długi
        // Niepoprawny NIP daje pole puste, ale kod dalej powstaje.
        let content = PaymentQRCode.zbpTransferContent(
            recipientName: "Firma", recipientNIP: "123", bankAccount: "12345678901234567890123456",
            amount: 100, currency: "PLN", title: "FV/1"
        )
        #expect(content?.hasPrefix("|PL|") == true)
    }

    @Test("Kwota w groszach: min. 6 cyfr z zerami wiodącymi i zaokrąglenie")
    func amountFormatting() {
        // 99,99 zł → 9999 gr → 6 cyfr z zerem wiodącym.
        let a = PaymentQRCode.zbpTransferContent(
            recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 99.99, currency: "PLN", title: "T"
        )
        #expect(a?.components(separatedBy: "|")[3] == "009999")

        // 12 345,67 zł → 1 234 567 gr → pole rośnie ponad 6 cyfr.
        let b = PaymentQRCode.zbpTransferContent(
            recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 12_345.67, currency: "PLN", title: "T"
        )
        #expect(b?.components(separatedBy: "|")[3] == "1234567")

        // Duża kwota powyżej Int32.max w groszach (25 mln zł → 2,5 mld gr):
        // regresja formatu %ld — z %d pole kwoty byłoby przekłamane.
        let c = PaymentQRCode.zbpTransferContent(
            recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 25_000_000, currency: "PLN", title: "T"
        )
        #expect(c?.components(separatedBy: "|")[3] == "2500000000")
    }

    @Test("Kwota niedodatnia → brak kodu")
    func nonPositiveAmount() {
        for amount in [0.0, -5.0] {
            #expect(PaymentQRCode.zbpTransferContent(
                recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
                amount: amount, currency: "PLN", title: "T"
            ) == nil)
        }
    }

    @Test("Waluta inna niż PLN → brak kodu (standard to przelew krajowy)")
    func onlyPLN() {
        #expect(PaymentQRCode.zbpTransferContent(
            recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 100, currency: "EUR", title: "T"
        ) == nil)
        // PLN pisane małymi/spacją — dalej akceptowane.
        #expect(PaymentQRCode.zbpTransferContent(
            recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 100, currency: " pln ", title: "T"
        ) != nil)
    }

    @Test("Nazwa odbiorcy przycięta do 20 znaków, tytuł do 32")
    func truncation() throws {
        let content = try #require(PaymentQRCode.zbpTransferContent(
            recipientName: "Przedsiębiorstwo Handlowo-Usługowe ABCDEF",
            recipientNIP: "",
            bankAccount: "12345678901234567890123456",
            amount: 100,
            currency: "PLN",
            title: "Zapłata za fakturę numer FV/2026/07/0001 z dnia 13 lipca"
        ))
        let fields = content.components(separatedBy: "|")
        #expect(fields[4].count == 20)
        #expect(fields[5].count == 32)
    }

    @Test("Pusta nazwa lub pusty tytuł → brak kodu")
    func emptyMandatoryFields() {
        #expect(PaymentQRCode.zbpTransferContent(
            recipientName: "   ", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 100, currency: "PLN", title: "T"
        ) == nil)
        #expect(PaymentQRCode.zbpTransferContent(
            recipientName: "F", recipientNIP: "", bankAccount: "12345678901234567890123456",
            amount: 100, currency: "PLN", title: "  "
        ) == nil)
    }

    @Test("Kod kraju: niepoprawny → pusty, domyślnie PL")
    func countryNormalization() {
        #expect(PaymentQRCode.normalizedCountry("pl") == "PL")
        #expect(PaymentQRCode.normalizedCountry("POL") == "")
        #expect(PaymentQRCode.normalizedCountry("") == "")
    }

    // MARK: - Wariant z faktury

    private func salesInvoice(
        account: String? = "12345678901234567890123456",
        gross: Double = 1230,
        currency: String = "PLN",
        isPaid: Bool = false,
        kind: Invoice.Kind = .sales
    ) -> Invoice {
        Invoice(
            invoiceNumber: "FV/2026/07/001",
            issueDate: Date(timeIntervalSince1970: 1_782_864_000),
            sellerName: "Studio Północ",
            sellerNIP: "5260250274",
            buyerName: "Klient S.A.",
            buyerNIP: "1111111111",
            netAmount: 1000, vatAmount: 230, grossAmount: gross,
            isPaid: isPaid,
            paymentBankAccount: account,
            currency: currency,
            kind: kind
        )
    }

    @Test("Faktura sprzedaży z rachunkiem: kod na saldo, odbiorcą sprzedawca")
    func salesInvoiceProducesCode() throws {
        let content = try #require(PaymentQRCode.zbpTransferContent(for: salesInvoice()))
        #expect(content == "5260250274|PL|12345678901234567890123456|123000|Studio Północ|FV/2026/07/001|||")
    }

    @Test("Faktura zakupu → brak kodu (odbiorcą przelewu jest dostawca, nie my)")
    func purchaseInvoiceNoCode() {
        #expect(PaymentQRCode.zbpTransferContent(for: salesInvoice(kind: .purchase)) == nil)
    }

    @Test("Faktura bez rachunku → brak kodu")
    func salesWithoutAccount() {
        #expect(PaymentQRCode.zbpTransferContent(for: salesInvoice(account: nil)) == nil)
    }

    @Test("Faktura opłacona (saldo 0) → brak kodu")
    func paidInvoiceNoCode() {
        #expect(PaymentQRCode.zbpTransferContent(for: salesInvoice(isPaid: true)) == nil)
    }

    @Test("Faktura w walucie obcej → brak kodu")
    func foreignCurrencyInvoiceNoCode() {
        #expect(PaymentQRCode.zbpTransferContent(for: salesInvoice(currency: "EUR")) == nil)
    }

    @Test("Częściowa wpłata: kwota kodu to saldo pozostałe do zapłaty")
    func partialPaymentUsesOutstanding() throws {
        let invoice = salesInvoice(gross: 1230)
        invoice.payments = [PaymentRecord(amount: 230, date: .now)]
        // Saldo = 1230 - 230 = 1000 zł → 100000 gr.
        let content = try #require(PaymentQRCode.zbpTransferContent(for: invoice))
        #expect(content.components(separatedBy: "|")[3] == "100000")
    }

    // MARK: - Ustawienie

    @Test("Ustawienie domyślnie włączone, można wyłączyć")
    func enabledSetting() {
        let defaults = UserDefaults(suiteName: "test.paymentQR.\(UUID().uuidString)")!
        #expect(PaymentQRCode.isEnabled(defaults: defaults) == true) // domyślnie ON
        defaults.set(false, forKey: AppSettingsKeys.pdfPaymentQR)
        #expect(PaymentQRCode.isEnabled(defaults: defaults) == false)
        defaults.set(true, forKey: AppSettingsKeys.pdfPaymentQR)
        #expect(PaymentQRCode.isEnabled(defaults: defaults) == true)
    }
}

@Suite("InvoicePDFGenerator — kod QR płatności na wydruku")
@MainActor
struct InvoicePDFPaymentQRTests {

    private func salesInvoice(account: String? = "12345678901234567890123456") -> Invoice {
        let invoice = Invoice(
            invoiceNumber: "FV/PAY/1",
            issueDate: .now,
            sellerName: "Sprzedawca", sellerNIP: "5260250274",
            buyerName: "Nabywca", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            paymentBankAccount: account,
            kind: .sales
        )
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa", unit: "usł.", quantity: 1,
                        unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23),
        ]
        return invoice
    }

    @Test("Faktura lokalna sprzedaży z rachunkiem dostaje sam kod płatności (bez KSeF)")
    func localSalesGetsPaymentOnly() {
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: salesInvoice(), offlineCertificate: nil, paymentEnabled: true
        )
        #expect(codes?.payment != nil)
        #expect(codes?.verification == nil) // brak numeru KSeF i nie offline
        #expect(codes?.verificationLabel == "")
    }

    @Test("Wyłączone ustawienie: brak kodu płatności (i brak sekcji QR, gdy nic więcej)")
    func disabledSettingSkipsPayment() {
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: salesInvoice(), offlineCertificate: nil, paymentEnabled: false
        )
        #expect(codes == nil)
    }

    @Test("Faktura sprzedaży bez rachunku i bez KSeF: brak sekcji QR")
    func noAccountNoKSeFNoSection() {
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: salesInvoice(account: nil), offlineCertificate: nil, paymentEnabled: true
        )
        #expect(codes == nil)
    }

    @Test("PDF z kodem płatności generuje się (paginacja z rezerwą miejsca)")
    func pdfRendersWithPaymentQR() throws {
        let pdf = InvoicePDFGenerator.pdfData(for: salesInvoice())
        #expect(pdf != nil)
        #expect((pdf?.count ?? 0) > 1000)
    }
}
