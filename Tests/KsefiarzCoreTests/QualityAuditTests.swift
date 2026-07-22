import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Audyt jakości — 20 usprawnień")
@MainActor
struct QualityAuditTests {

    private func invoice(
        number: String = "FV/2026/07/001",
        kind: Invoice.Kind = .sales,
        sellerName: String = "Sprzedawca",
        sellerNIP: String = "9999999999",
        buyerName: String = "Nabywca",
        buyerNIP: String = "5260250274",
        gross: Double = 123,
        currency: String = "PLN",
        exchangeRate: Double = 0,
        hidden: Bool = false
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-10")!,
            sellerName: sellerName,
            sellerNIP: sellerNIP,
            buyerName: buyerName,
            buyerNIP: buyerNIP,
            netAmount: gross,
            vatAmount: 0,
            grossAmount: gross,
            isArchivedOrHidden: hidden,
            currency: currency,
            exchangeRate: exchangeRate,
            kind: kind
        )
    }

    // MARK: 1–10 — wyszukiwanie i raporty

    @Test("[01] Wyszukiwanie faktur ignoruje polskie znaki diakrytyczne")
    func invoiceSearchFoldsDiacritics() {
        let matching = invoice(buyerName: "Żółw Świętokrzyski")
        let other = invoice(number: "FV/2", buyerName: "Inna Firma")

        let result = InvoiceFilter.apply([other, matching], status: .all, searchText: "zolw swietokrzyski")

        #expect(result.map(\.id) == [matching.id])
    }

    @Test("[02] Wyszukiwanie NIP ignoruje myślniki i ukośniki zapytania")
    func invoiceSearchNormalizesTaxIdentifier() {
        let matching = invoice(buyerNIP: "5260250274")
        let other = invoice(number: "FV/2", buyerNIP: "5260250275")

        #expect(InvoiceFilter.apply(
            [other, matching], status: .all, searchText: "526-025-02-74"
        ).map(\.id) == [matching.id])
        #expect(InvoiceFilter.apply(
            [other, matching], status: .all, searchText: "526/025/02/74"
        ).map(\.id) == [matching.id])
    }

    @Test("[03] Tokeny wyszukiwania mogą pasować do różnych pól faktury")
    func invoiceSearchMatchesAcrossFields() {
        let matching = invoice(number: "FV/2026/07/001", buyerName: "ACME Kraków")
        let other = invoice(number: "FV/2026/07/002", buyerName: "ACME Kraków")

        let result = InvoiceFilter.apply(
            [other, matching], status: .all, searchText: "acme 001"
        )

        #expect(result.map(\.id) == [matching.id])
    }

    @Test("[04] Wszystkie raporty pomijają ukryte dokumenty wewnątrz silnika")
    func reportsExcludeHiddenInvoices() {
        let visibleSale = invoice(number: "S/1", buyerName: "Jawny", buyerNIP: "")
        visibleSale.lines = [InvoiceLine(index: 1, name: "Jawna usługa", netAmount: 100)]
        let hiddenSale = invoice(
            number: "S/2", buyerName: "Ukryty", buyerNIP: "", gross: 10_000, hidden: true
        )
        hiddenSale.lines = [InvoiceLine(index: 1, name: "Ukryta usługa", netAmount: 10_000)]
        let hiddenPurchase = invoice(number: "Z/1", kind: .purchase, gross: 20_000, hidden: true)
        hiddenPurchase.costCategory = "Tajny koszt"

        #expect(ReportsEngine.topContractors(in: [visibleSale, hiddenSale]).map(\.name) == ["Jawny"])
        #expect(ReportsEngine.revenueByProduct(in: [visibleSale, hiddenSale]).map(\.name) == ["Jawna usługa"])
        #expect(ReportsEngine.costsByCategory(in: [hiddenPurchase]).isEmpty)
        #expect(CostCategories.used(in: [hiddenPurchase]).isEmpty)
    }

    @Test("[05] Kontrahenci bez NIP są grupowani mimo różnej pisowni i odstępów")
    func reportNormalizesContractorNames() {
        let first = invoice(number: "S/1", buyerName: "Żółw  Sp. z o.o.", buyerNIP: "", gross: 100)
        let second = invoice(number: "S/2", buyerName: " zolw sp. Z O.O.\n", buyerNIP: "", gross: 50)

        let groups = ReportsEngine.topContractors(in: [first, second])

        #expect(groups.count == 1)
        #expect(groups.first?.name == "Żółw Sp. z o.o.")
        #expect(groups.first?.invoiceCount == 2)
        #expect(groups.first?.grossPLN == 150)

        let numericName = invoice(
            number: "S/3", buyerName: "5260250274", buyerNIP: "", gross: 25
        )
        let sameDigitsAsNIP = invoice(
            number: "S/4", buyerName: "Firma z NIP", buyerNIP: "5260250274", gross: 20
        )
        let identityGroups = ReportsEngine.topContractors(in: [numericName, sameDigitsAsNIP])
        #expect(identityGroups.count == 2)
        #expect(Set(identityGroups.map(\.id)).count == 2)
    }

    @Test("[06] Produkty są grupowane mimo różnej pisowni i białych znaków")
    func reportNormalizesProductNames() {
        let first = invoice(number: "S/1")
        first.lines = [InvoiceLine(index: 1, name: "Usługa  doradcza", quantity: 1, netAmount: 100)]
        let second = invoice(number: "S/2")
        second.lines = [InvoiceLine(index: 1, name: " usluga DORADCZA\n", quantity: 2, netAmount: 200)]

        let groups = ReportsEngine.revenueByProduct(in: [first, second])

        #expect(groups.count == 1)
        #expect(groups.first?.name == "Usługa doradcza")
        #expect(groups.first?.quantity == 3)
        #expect(groups.first?.netPLN == 300)
    }

    @Test("[07] Kategorie kosztów są grupowane mimo różnej pisowni i odstępów")
    func reportNormalizesCostCategories() {
        let first = invoice(number: "Z/1", kind: .purchase, gross: 100)
        first.costCategory = "Sprzęt  IT"
        let second = invoice(number: "Z/2", kind: .purchase, gross: 50)
        second.costCategory = " sprzet it\n"

        let groups = ReportsEngine.costsByCategory(in: [first, second])

        #expect(groups.count == 1)
        #expect(groups.first?.category == "Sprzęt IT")
        #expect(groups.first?.invoiceCount == 2)
        #expect(groups.first?.grossPLN == 150)
        #expect(CostCategories.used(in: [first, second]) == ["Sprzęt IT"])
    }

    @Test("[08] Ujemne limity raportów zwracają pustą listę")
    func reportNegativeLimitsAreSafe() {
        let value = invoice()
        value.lines = [InvoiceLine(index: 1, name: "Usługa", netAmount: 100)]

        #expect(ReportsEngine.topContractors(in: [value], limit: -1).isEmpty)
        #expect(ReportsEngine.revenueByProduct(in: [value], limit: -10).isEmpty)
    }

    @Test("[09] Ujemny limit wyszukiwarki globalnej zwraca pustą listę")
    func globalSearchNegativeLimitIsSafe() {
        let item = GlobalSearchEngine.Item(
            kind: .contractor, id: "1", title: "ACME", subtitle: "", keywords: []
        )

        #expect(GlobalSearchEngine.search("acme", in: [item], limit: -1).isEmpty)
    }

    @Test("[10] Ujemna retencja raportów miesięcznych daje pustą historię")
    func monthlyReportNegativeRetentionIsSafe() {
        #expect(MonthlyReportEngine.prune(sent: ["2026-05", "2026-06"], keep: -1).isEmpty)
    }

    // MARK: 11–20 — daty, dane finansowe i odporność wejścia

    @Test("[11] Termin płatności obejmuje cały wskazany dzień")
    func invoiceIsNotOverdueOnDueDate() {
        let value = invoice()
        let due = FA2Format.dateFormatter.date(from: "2026-07-10")!
        value.paymentDueDate = due
        let sameDayNoon = due.addingTimeInterval(12 * 60 * 60)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: due)!

        #expect(!value.isOverdue(asOf: sameDayNoon))
        #expect(value.isOverdue(asOf: nextDay))
    }

    @Test("[12] Dzisiejszy termin pozostaje w najbliższych płatnościach")
    func dashboardIncludesDueToday() {
        let due = FA2Format.dateFormatter.date(from: "2026-07-10")!
        let value = invoice(number: "DZISIAJ")
        value.paymentDueDate = due

        let metrics = DashboardMetrics(
            invoices: [value], now: due.addingTimeInterval(16 * 60 * 60), dueSoonDays: 0
        )

        #expect(metrics.dueSoonDays == 0)
        #expect(metrics.dueSoonInvoices.map(\.invoiceNumber) == ["DZISIAJ"])
        #expect(metrics.overdueCount == 0)

        let analytics = DashboardAnalytics(
            invoices: [value], periodInvoices: [value],
            now: due.addingTimeInterval(16 * 60 * 60)
        )
        #expect(analytics.aging[0].receivables == 123)
        #expect(analytics.aging[1].receivables == 0)
    }

    @Test("[13] Analityka Kokpitu samodzielnie pomija ukryte dokumenty")
    func dashboardAnalyticsExcludesHiddenInvoices() {
        let hiddenSale = invoice(number: "UKRYTA-S", gross: 1_000, hidden: true)
        hiddenSale.vatAmount = 230
        hiddenSale.grossAmount = 1_230
        hiddenSale.paymentDueDate = FA2Format.dateFormatter.date(from: "2026-07-01")!
        hiddenSale.payments = [PaymentRecord(
            amount: 100,
            date: FA2Format.dateFormatter.date(from: "2026-07-05")!
        )]
        let hiddenPurchase = invoice(
            number: "UKRYTA-Z", kind: .purchase, gross: 2_000, hidden: true
        )
        hiddenPurchase.vatAmount = 460
        hiddenPurchase.grossAmount = 2_460
        hiddenPurchase.paymentDueDate = FA2Format.dateFormatter.date(from: "2026-07-02")!
        hiddenPurchase.payments = [PaymentRecord(
            amount: 200,
            date: FA2Format.dateFormatter.date(from: "2026-07-06")!
        )]
        let hiddenPreviousSale = invoice(number: "UKRYTA-PS", gross: 300, hidden: true)
        hiddenPreviousSale.issueDate = FA2Format.dateFormatter.date(from: "2026-06-10")!
        hiddenPreviousSale.vatAmount = 69
        let hiddenPreviousPurchase = invoice(
            number: "UKRYTA-PZ", kind: .purchase, gross: 400, hidden: true
        )
        hiddenPreviousPurchase.issueDate = FA2Format.dateFormatter.date(from: "2026-06-11")!
        let now = FA2Format.dateFormatter.date(from: "2026-07-20")!

        let analytics = DashboardAnalytics(
            invoices: [hiddenSale, hiddenPurchase, hiddenPreviousSale, hiddenPreviousPurchase],
            periodInvoices: [hiddenSale, hiddenPurchase],
            now: now
        )

        #expect(analytics.vatDue == 0)
        #expect(analytics.vatInput == 0)
        #expect(analytics.cashFlow.allSatisfy { $0.inflow == 0 && $0.outflow == 0 })
        #expect(analytics.currentMonth.salesGross == 0)
        #expect(analytics.currentMonth.purchasesGross == 0)
        #expect(analytics.currentMonth.vatDue == 0)
        #expect(analytics.previousMonth.salesGross == 0)
        #expect(analytics.previousMonth.purchasesGross == 0)
        #expect(analytics.previousMonth.vatDue == 0)
        #expect(analytics.aging.allSatisfy { $0.receivables == 0 && $0.payables == 0 })
    }

    @Test("[14] Kod PLN jest normalizowany w modelach i operacjach finansowych")
    func financialAggregatesNormalizePLN() {
        let value = invoice(currency: " pln\n", exchangeRate: 4)
        value.vatAmount = 25
        let now = FA2Format.dateFormatter.date(from: "2026-07-31")!

        #expect(CurrencyCode.normalized(" pln\n") == "PLN")
        #expect(value.currency == "PLN")
        let draft = InvoiceDraft(
            invoiceNumber: "FV/1", issueDate: now,
            sellerName: "Sprzedawca", sellerNIP: "9999999999",
            buyerName: "Nabywca", buyerNIP: "5260250274",
            currency: " eur\n"
        )
        #expect(draft.currency == "EUR")
        let proformaDraft = ProformaDraft(
            proformaNumber: "PF/1", issueDate: now,
            sellerName: "Sprzedawca", sellerNIP: "9999999999",
            buyerName: "Nabywca", currency: " usd\n"
        )
        #expect(proformaDraft.currency == "USD")
        let proforma = Proforma(
            proformaNumber: "PF/1", issueDate: now,
            sellerName: "Sprzedawca", sellerNIP: "9999999999",
            buyerName: "Nabywca", netAmount: 100, vatAmount: 23,
            grossAmount: 123, currency: " gbp\n"
        )
        #expect(proforma.currency == "GBP")

        // Symulacja rekordu ze starszej bazy SwiftData, materializowanego bez
        // wywołania bieżącego inicjalizatora modelu.
        value.currency = " pln\n"
        #expect(DashboardMetrics(invoices: [value], now: now).salesAwaitingGross == 123)
        #expect(DashboardAnalytics(
            invoices: [value], periodInvoices: [value], now: now
        ).vatDue == 25)
        #expect(MonthlyReportEngine.summary(
            invoices: [value],
            periodStart: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            asOf: now
        ).missingRateCount == 0)
        var jpkWarnings: [String] = []
        #expect(JPKV7Generator.amountInPLN(
            123, invoice: value, warnings: &jpkWarnings
        ) == 123)
        #expect(jpkWarnings.isEmpty)
        let waproXML = (try? WaproXMLExporter.export(invoices: [value], generatedAt: now))
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(waproXML?.contains("<SYM_WAL>PLN</SYM_WAL>") == true)

        var legacyDraft = draft
        legacyDraft.vatAmount = 23
        legacyDraft.grossAmount = 23
        legacyDraft.currency = " pln\n"
        #expect(!InvoiceValidator.validate(legacyDraft).contains(.missingExchangeRate))
    }

    @Test("[15] Nowa linia nie spełnia wymaganych pól ręcznego zakupu")
    func manualPurchaseRejectsNewlineOnlyFields() {
        let draft = ManualPurchaseDraft(
            documentNumber: "\n\t", sellerName: "\r\n", netAmount: 100
        )

        let errors = draft.validate()

        #expect(errors.contains(.emptyDocumentNumber))
        #expect(errors.contains(.emptySellerName))
    }

    @Test("[16] Ręczny zakup zapisuje kanoniczne pola i pusty rachunek jako nil")
    func manualPurchaseNormalizesPersistedFields() {
        let draft = ManualPurchaseDraft(
            documentNumber: " FZ/1\n",
            sellerName: " Dostawca\n",
            sellerTaxID: " DE123456789\n",
            sellerAddress: " Berlin\n",
            buyerName: " Moja Firma\n",
            buyerNIP: " 5260250274\n",
            netAmount: 100,
            currency: " pln\n",
            paymentBankAccount: " \n",
            costCategory: " Sprzęt IT\n"
        )

        #expect(draft.validate().isEmpty)
        let saved = draft.makeInvoice()
        #expect(saved.invoiceNumber == "FZ/1")
        #expect(saved.sellerName == "Dostawca")
        #expect(saved.sellerNIP == "DE123456789")
        #expect(saved.sellerAddress == "Berlin")
        #expect(saved.buyerName == "Moja Firma")
        #expect(saved.buyerNIP == "5260250274")
        #expect(saved.currency == "PLN")
        #expect(saved.paymentBankAccount == nil)
        #expect(saved.costCategory == "Sprzęt IT")

        let edited = invoice(kind: .purchase)
        draft.apply(to: edited)
        #expect(edited.invoiceNumber == "FZ/1")
        #expect(edited.sellerName == "Dostawca")
        #expect(edited.sellerNIP == "DE123456789")
        #expect(edited.sellerAddress == "Berlin")
        #expect(edited.buyerName == "Moja Firma")
        #expect(edited.buyerNIP == "5260250274")
        #expect(edited.currency == "PLN")
        #expect(edited.paymentBankAccount == nil)
        #expect(edited.costCategory == "Sprzęt IT")
    }

    @Test("[17] Proforma z białym numerem faktury nie jest rozliczona")
    func proformaConversionNumberIsTrimmed() {
        let proforma = Proforma(
            proformaNumber: "PF/1",
            issueDate: .now,
            sellerName: "Sprzedawca",
            sellerNIP: "5260250274",
            buyerName: "Nabywca",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            convertedInvoiceNumber: "\n\t"
        )

        #expect(!proforma.isConverted)
        proforma.markConverted(toInvoiceNumber: " FV/1\n")
        #expect(proforma.isConverted)
        #expect(proforma.convertedInvoiceNumber == "FV/1")
    }

    @Test("[18] Dekodowanie form płatności przycina odstępy")
    func prepaidFormsDecodeTrimsValues() {
        let decoded = PaymentFormPolicy.decode(
            " \(PaymentForm.cash.rawValue), \(PaymentForm.transfer.rawValue) ,\n"
        )

        #expect(decoded == [PaymentForm.cash.rawValue, PaymentForm.transfer.rawValue])
    }

    @Test("[19] Pole CSV ze znakiem CR jest ujmowane w cudzysłowy")
    func invoiceCSVQuotesCarriageReturn() {
        let value = invoice(buyerName: "Pierwsza\rDruga")

        let csv = InvoiceCSVExporter.csv(for: [value])

        #expect(csv.contains("\"Pierwsza\rDruga\""))
    }

    @Test("[20] Księga płatności odrzuca niedodatnie i nieskończone kwoty")
    func paymentLedgerRejectsInvalidAmounts() {
        let value = invoice(gross: 100)

        #expect(PaymentLedger.register(amount: 0, on: value) == nil)
        #expect(PaymentLedger.register(amount: -10, on: value) == nil)
        #expect(PaymentLedger.register(amount: .nan, on: value) == nil)
        #expect(PaymentLedger.register(amount: .infinity, on: value) == nil)
        #expect(value.payments.isEmpty)
        #expect(!value.isPaid)

        let zeroTransaction = BankTransaction(
            date: .now, amount: 0, title: "Zapłata FV/2026/07/001"
        )
        let proposals = PaymentMatcher.proposals(
            transactions: [zeroTransaction], invoices: [value]
        )
        #expect(proposals.first?.invoiceID == value.id)
        #expect(PaymentMatcher.apply(proposals, invoices: [value]) == 0)
        #expect(value.payments.isEmpty)
        #expect(!value.isPaid)

        #expect(PaymentLedger.register(amount: 100, on: value) != nil)
        #expect(value.isPaid)
    }
}
