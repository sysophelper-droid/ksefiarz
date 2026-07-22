import Foundation
import Testing
@testable import KsefiarzCore

@Suite("ElixirPaymentExporter — paczka przelewów do banku")
@MainActor
struct ElixirPaymentExporterTests {

    private let sourceAccount = "49114020040000330200112177"
    private let recipientAccount = "61109010140000071219812874"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func purchase(
        number: String = "FV/1",
        gross: Double = 123,
        vat: Double = 23,
        splitPayment: Bool = false
    ) -> Invoice {
        let invoice = Invoice(
            invoiceNumber: number,
            issueDate: date(2026, 7, 1),
            sellerName: "Dostawca Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Dostawcza 7, Warszawa",
            buyerName: "Moja Firma",
            buyerNIP: "1111111111",
            netAmount: gross - vat,
            vatAmount: vat,
            grossAmount: gross,
            paymentDueDate: date(2026, 7, 15),
            paymentForm: .transfer,
            paymentBankAccount: recipientAccount,
            splitPayment: splitPayment,
            kind: .purchase
        )
        return invoice
    }

    private func options(
        date: Date? = nil,
        sourceAccount: String? = nil,
        sourceName: String = "Moja Firma",
        encoding: ElixirPaymentExporter.TextEncoding = .utf8
    ) -> ElixirPaymentExporter.Options {
        .init(
            sourceAccount: sourceAccount ?? self.sourceAccount,
            sourceName: sourceName,
            sourceAddress: "ul. Własna 1, Kraków",
            executionDate: date ?? self.date(2026, 7, 15),
            encoding: encoding
        )
    }

    private func transfer(from invoice: Invoice) throws -> ElixirPaymentExporter.Transfer {
        try #require(ElixirPaymentExporter.prepare(invoices: [invoice]).transfers.first)
    }

    /// Minimalny parser rekordu CSV: uwzględnia przecinki wewnątrz
    /// cudzysłowów (potrzebne dla kwoty VAT w komunikacie MPP).
    private func fields(from record: String) -> [String] {
        var result: [String] = []
        var field = ""
        var isQuoted = false
        for character in record {
            if character == "\"" {
                isQuoted.toggle()
            } else if character == "," && !isQuoted {
                result.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        result.append(field)
        return result
    }

    @Test("Zwykły przelew ma dokładnie 16 pól Elixir-O i zakończenie CRLF")
    func ordinaryTransferExactRecord() throws {
        let transfer = try transfer(from: purchase())
        let data = try ElixirPaymentExporter.data(
            for: [transfer],
            options: options(),
            today: date(2026, 7, 13),
            calendar: calendar
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text == "110,20260715,12300,11402004,0,\"49114020040000330200112177\",\"61109010140000071219812874\",\"Moja Firma|ul. Własna 1 Kraków\",\"Dostawca Sp. z o.o.|ul. Dostawcza 7 Warszawa\",0,10901014,\"FV/1\",\"\",\"\",\"51\",\"\"\r\n")
        #expect(fields(from: String(text.dropLast(2))).count == 16)
    }

    @Test("MPP używa kodu 53 i struktury VAT/IDC/INV łamanej do 35 znaków")
    func splitPaymentRecord() throws {
        let invoice = purchase(number: "FV/MPP/1", splitPayment: true)
        invoice.sellerNIP = "PL 526-025-02-74"
        let transfer = try transfer(from: invoice)
        let data = try ElixirPaymentExporter.data(
            for: [transfer],
            options: options(),
            today: date(2026, 7, 13),
            calendar: calendar
        )
        let text = try #require(String(data: data, encoding: .utf8))
        let record = String(text.dropLast(2))
        let fields = fields(from: record)

        #expect(fields.count == 16)
        #expect(fields[14] == "53")
        #expect(fields[11].replacingOccurrences(of: "|", with: "")
            == "/VAT/23,00/IDC/5260250274/INV/FV/MPP/1")
        #expect(fields[11].split(separator: "|", omittingEmptySubsequences: false)
            .allSatisfy { $0.count <= 35 })
    }

    @Test("Płatność częściowa eksportuje saldo i proporcjonalną podpowiedź VAT MPP")
    func partialSplitPayment() throws {
        let invoice = purchase(splitPayment: true)
        PaymentLedger.register(amount: 61.50, on: invoice)

        let transfer = try transfer(from: invoice)
        #expect(abs(transfer.amount - 61.50) < 0.001)
        #expect(abs((transfer.vatAmount ?? 0) - 11.50) < 0.001)

        let data = try ElixirPaymentExporter.data(
            for: [transfer],
            options: options(),
            today: date(2026, 7, 13),
            calendar: calendar
        )
        let text = try #require(String(data: data, encoding: .utf8))
        let parsed = fields(from: String(text.dropLast(2)))
        #expect(parsed[2] == "6150")
        #expect(parsed[11].replacingOccurrences(of: "|", with: "").contains("/VAT/11,50/"))
    }

    @Test("Przygotowanie odrzuca sprzedaż, ukryte, opłacone, walutowe i błędne dane płatności")
    func preparationRejections() {
        let valid = purchase(number: "OK")

        let sale = purchase(number: "SPRZEDAŻ")
        sale.kind = .sales

        let hidden = purchase(number: "UKRYTA")
        hidden.isArchivedOrHidden = true

        let paid = purchase(number: "OPŁACONA")
        paid.isPaid = true

        let foreign = purchase(number: "EUR")
        foreign.currency = "EUR"

        let missingAccount = purchase(number: "BEZ-RACHUNKU")
        missingAccount.paymentBankAccount = nil

        let badAccount = purchase(number: "ZŁY-NRB")
        badAccount.paymentBankAccount = "62109010140000071219812874"

        let badMPP = purchase(number: "ZŁY-MPP", splitPayment: true)
        badMPP.sellerNIP = "1234567890"

        let result = ElixirPaymentExporter.prepare(invoices: [
            valid, sale, hidden, paid, foreign, missingAccount, badAccount, badMPP,
        ])

        #expect(result.transfers.map(\.invoiceNumber) == ["OK"])
        #expect(result.rejections.count == 7)
        #expect(result.rejections.map(\.reason).contains { $0.contains("wyłącznie faktury zakupowe") })
        #expect(result.rejections.map(\.reason).contains { $0.contains("ukryta") })
        #expect(result.rejections.map(\.reason).contains { $0.contains("salda") })
        #expect(result.rejections.map(\.reason).contains { $0.contains("PLN") })
        #expect(result.rejections.filter { $0.reason.contains("rachunku NRB") }.count == 2)
        #expect(result.rejections.map(\.reason).contains { $0.contains("poprawnego NIP") })
    }

    @Test("Surowy kod PLN ze starszej bazy nie odrzuca przelewu")
    func legacyRawPLNIsAccepted() {
        let invoice = purchase(number: "LEGACY-PLN")
        invoice.currency = " pln\n"

        let result = ElixirPaymentExporter.prepare(invoices: [invoice])

        #expect(result.transfers.map(\.invoiceNumber) == ["LEGACY-PLN"])
        #expect(result.rejections.isEmpty)
    }

    @Test("NRB jest normalizowany i sprawdzany sumą kontrolną modulo 97")
    func nrbValidation() {
        #expect(ElixirPaymentExporter.normalizedNRB("PL 49-1140-2004-0000-3302-0011-2177")
            == sourceAccount)
        #expect(ElixirPaymentExporter.isValidNRB(sourceAccount))
        #expect(ElixirPaymentExporter.isValidNRB("PL \(recipientAccount)"))
        #expect(!ElixirPaymentExporter.isValidNRB("50114020040000330200112177"))
        #expect(!ElixirPaymentExporter.isValidNRB("49X14020040000330200112177"))
        #expect(!ElixirPaymentExporter.isValidNRB("123"))
        #expect(ElixirPaymentExporter.bankRoutingNumber(from: sourceAccount) == "11402004")
    }

    @Test("Walidacja generatora chroni rachunek źródłowy, nazwę, datę i pustą paczkę")
    func generatorValidation() throws {
        let transfer = try transfer(from: purchase())

        #expect(throws: ElixirPaymentExporter.ExportError.noTransfers) {
            try ElixirPaymentExporter.data(
                for: [], options: options(), today: date(2026, 7, 13), calendar: calendar
            )
        }
        #expect(throws: ElixirPaymentExporter.ExportError.tooManyTransfers(51)) {
            try ElixirPaymentExporter.data(
                for: Array(repeating: transfer, count: 51), options: options(),
                today: date(2026, 7, 13), calendar: calendar
            )
        }
        #expect(throws: ElixirPaymentExporter.ExportError.invalidSourceAccount) {
            try ElixirPaymentExporter.data(
                for: [transfer], options: options(sourceAccount: "123"),
                today: date(2026, 7, 13), calendar: calendar
            )
        }
        #expect(throws: ElixirPaymentExporter.ExportError.missingSourceName) {
            try ElixirPaymentExporter.data(
                for: [transfer], options: options(sourceName: "  "),
                today: date(2026, 7, 13), calendar: calendar
            )
        }
        #expect(throws: ElixirPaymentExporter.ExportError.executionDateInPast) {
            try ElixirPaymentExporter.data(
                for: [transfer], options: options(date: date(2026, 7, 12)),
                today: date(2026, 7, 13), calendar: calendar
            )
        }
    }

    @Test("Generator odrzuca błędną kwotę VAT MPP oraz kwoty poza limitem")
    func transferAmountValidation() throws {
        var split = try transfer(from: purchase(splitPayment: true))
        split.vatAmount = 124

        #expect(throws: ElixirPaymentExporter.ExportError.invalidTransfer(
            invoiceNumber: "FV/1",
            reason: "kwota VAT MPP musi być dodatnia, nie większa od przelewu i mieścić się w limicie 10 cyfr"
        )) {
            try ElixirPaymentExporter.data(
                for: [split], options: options(), today: date(2026, 7, 13), calendar: calendar
            )
        }

        let excessiveVAT = ElixirPaymentExporter.Transfer(
            id: UUID(),
            invoiceNumber: "FV/MPP/LIMIT",
            recipientName: "Dostawca",
            recipientAddress: "Warszawa",
            recipientNIP: "5260250274",
            recipientAccount: recipientAccount,
            amount: 10_000_000_001,
            vatAmount: 10_000_000_000,
            usesSplitPayment: true
        )
        #expect(throws: ElixirPaymentExporter.ExportError.invalidTransfer(
            invoiceNumber: "FV/MPP/LIMIT",
            reason: "kwota VAT MPP musi być dodatnia, nie większa od przelewu i mieścić się w limicie 10 cyfr"
        )) {
            try ElixirPaymentExporter.data(
                for: [excessiveVAT], options: options(),
                today: date(2026, 7, 13), calendar: calendar
            )
        }

        let tooLarge = purchase(gross: Double(ElixirPaymentExporter.maxAmountInCents) / 100 + 1)
        let preparation = ElixirPaymentExporter.prepare(invoices: [tooLarge])
        #expect(preparation.transfers.isEmpty)
        #expect(preparation.rejections.first?.reason.contains("przekracza limit") == true)
    }

    @Test("Polskie znaki przechodzą przez wszystkie oferowane kodowania")
    func encodingsRoundTrip() throws {
        let invoice = purchase()
        invoice.sellerName = "Zażółć Gęślą Jaźń"
        let transfer = try transfer(from: invoice)

        for encoding in ElixirPaymentExporter.TextEncoding.allCases {
            let data = try ElixirPaymentExporter.data(
                for: [transfer], options: options(encoding: encoding),
                today: date(2026, 7, 13), calendar: calendar
            )
            let foundation: String.Encoding
            switch encoding {
            case .utf8: foundation = .utf8
            case .windows1250: foundation = .windowsCP1250
            case .isoLatin2: foundation = .isoLatin2
            }
            let decoded = try #require(String(data: data, encoding: foundation))
            #expect(decoded.contains("Zażółć Gęślą Jaźń"))
        }
    }

    @Test("Znaki sterujące nie wstrzykują rekordu ani pól, a tekst mieści się w 4×35")
    func sanitizationAndLimits() throws {
        let invoice = purchase(number: "FV|1\r\n110,ATAK")
        invoice.sellerName = String(repeating: "Bardzo długa nazwa odbiorcy ", count: 8) + "\"|\r\n"
        invoice.sellerAddress = String(repeating: "Długi adres ", count: 12)
        let transfer = try transfer(from: invoice)
        let data = try ElixirPaymentExporter.data(
            for: [transfer], options: options(),
            today: date(2026, 7, 13), calendar: calendar
        )
        let text = try #require(String(data: data, encoding: .utf8))
        let records = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let parsed = fields(from: try #require(records.first))

        #expect(records.count == 1)
        #expect(parsed.count == 16)
        #expect(parsed[8].split(separator: "|", omittingEmptySubsequences: false).count <= 4)
        #expect(parsed[8].split(separator: "|", omittingEmptySubsequences: false)
            .allSatisfy { $0.count <= 35 })
        #expect(!parsed[11].contains("\r") && !parsed[11].contains("\n"))
    }
}
