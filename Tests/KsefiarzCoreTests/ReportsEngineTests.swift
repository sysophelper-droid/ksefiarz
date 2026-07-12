import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

@Suite("Raporty — top kontrahenci, przychody per towar, koszty per kategoria")
@MainActor
struct ReportsEngineTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Invoice.self, configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeInvoice(
        number: String,
        kind: Invoice.Kind = .sales,
        buyerName: String = "Nabywca",
        buyerNIP: String = "1111111111",
        sellerName: String = "Sprzedawca",
        net: Double = 100,
        vat: Double = 23,
        currency: String = "PLN",
        exchangeRate: Double = 0,
        category: String = ""
    ) -> Invoice {
        let invoice = Invoice(
            invoiceNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: sellerName, sellerNIP: "9999999999",
            buyerName: buyerName, buyerNIP: buyerNIP,
            netAmount: net, vatAmount: vat, grossAmount: net + vat,
            currency: currency,
            exchangeRate: exchangeRate,
            kind: kind
        )
        invoice.costCategory = category
        return invoice
    }

    // MARK: Top kontrahenci

    @Test("Kontrahenci grupowani po NIP (myślniki ignorowane), sortowanie po brutto")
    func topContractorsGrouping() {
        let invoices = [
            makeInvoice(number: "S/1", buyerName: "Alfa", buyerNIP: "111-111-11-11", net: 100, vat: 23),
            makeInvoice(number: "S/2", buyerName: "Alfa Sp. z o.o.", buyerNIP: "1111111111", net: 200, vat: 46),
            makeInvoice(number: "S/3", buyerName: "Beta", buyerNIP: "2222222222", net: 1000, vat: 230),
        ]
        let top = ReportsEngine.topContractors(in: invoices)

        #expect(top.count == 2)
        #expect(top[0].name == "Beta")
        #expect(top[0].grossPLN == 1230)
        #expect(top[1].nip == "1111111111")
        #expect(top[1].invoiceCount == 2)
        #expect(top[1].netPLN == 300)
        #expect(top[1].grossPLN == 369)
    }

    @Test("Zakupy nie wchodzą do rankingu kontrahentów; walutowe po kursie faktury")
    func topContractorsKindAndCurrency() {
        let invoices = [
            makeInvoice(number: "S/1", buyerNIP: "1111111111", net: 100, vat: 0,
                        currency: "EUR", exchangeRate: 4.0),
            makeInvoice(number: "Z/1", kind: .purchase, buyerNIP: "1111111111", net: 999, vat: 0),
        ]
        let top = ReportsEngine.topContractors(in: invoices)

        #expect(top.count == 1)
        #expect(top[0].netPLN == 400)
    }

    @Test("Kontrahent bez NIP grupowany po nazwie; limit przycina ranking")
    func topContractorsFallbackAndLimit() {
        let invoices = [
            makeInvoice(number: "S/1", buyerName: "Osoba Prywatna", buyerNIP: "", net: 50, vat: 0),
            makeInvoice(number: "S/2", buyerName: "osoba prywatna", buyerNIP: "", net: 50, vat: 0),
            makeInvoice(number: "S/3", buyerName: "Beta", buyerNIP: "2222222222", net: 1000, vat: 0),
        ]
        let top = ReportsEngine.topContractors(in: invoices, limit: 1)

        #expect(top.count == 1)
        #expect(top[0].name == "Beta")

        let all = ReportsEngine.topContractors(in: invoices)
        #expect(all.count == 2)
        #expect(all[1].invoiceCount == 2) // obie faktury bez NIP zgrupowane po nazwie
    }

    // MARK: Przychody per towar/usługa

    @Test("Pozycje grupowane po nazwie bez wielkości liter, kwoty w PLN")
    func revenueByProduct() throws {
        let context = try makeContext()
        let sale = makeInvoice(number: "S/1", net: 300, vat: 69)
        let saleEUR = makeInvoice(number: "S/2", net: 100, vat: 0, currency: "EUR", exchangeRate: 4.0)
        context.insert(sale)
        context.insert(saleEUR)
        sale.lines = [
            InvoiceLine(index: 1, name: "Usługa IT", quantity: 2, netAmount: 200),
            InvoiceLine(index: 2, name: "Licencja", quantity: 1, netAmount: 100),
        ]
        saleEUR.lines = [
            InvoiceLine(index: 1, name: "usługa it", quantity: 1, netAmount: 100),
        ]

        let revenue = ReportsEngine.revenueByProduct(in: [sale, saleEUR])

        #expect(revenue.count == 2)
        #expect(revenue[0].name == "Usługa IT")
        #expect(revenue[0].quantity == 3)
        #expect(revenue[0].netPLN == 200 + 400) // pozycja EUR po kursie 4,0
        #expect(revenue[1].name == "Licencja")
        #expect(revenue[1].netPLN == 100)
    }

    @Test("Pozycje zakupów i pozycje bez nazwy są pomijane")
    func revenueSkipsPurchasesAndEmptyNames() throws {
        let context = try makeContext()
        let purchase = makeInvoice(number: "Z/1", kind: .purchase)
        let sale = makeInvoice(number: "S/1")
        context.insert(purchase)
        context.insert(sale)
        purchase.lines = [InvoiceLine(index: 1, name: "Toner", netAmount: 100)]
        sale.lines = [InvoiceLine(index: 1, name: "   ", netAmount: 50)]

        #expect(ReportsEngine.revenueByProduct(in: [purchase, sale]).isEmpty)
    }

    // MARK: Koszty per kategoria

    @Test("Koszty grupowane po kategorii; pusta kategoria to „Bez kategorii”")
    func costsByCategory() {
        let invoices = [
            makeInvoice(number: "Z/1", kind: .purchase, net: 100, vat: 23, category: "Paliwo i transport"),
            makeInvoice(number: "Z/2", kind: .purchase, net: 50, vat: 11.5, category: "Paliwo i transport"),
            makeInvoice(number: "Z/3", kind: .purchase, net: 10, vat: 2.3, category: "  "),
            makeInvoice(number: "S/1", kind: .sales, net: 999, vat: 0, category: "Paliwo i transport"),
        ]
        let costs = ReportsEngine.costsByCategory(in: invoices)

        #expect(costs.count == 2)
        #expect(costs[0].category == "Paliwo i transport")
        #expect(costs[0].invoiceCount == 2)
        #expect(costs[0].netPLN == 150)
        #expect(costs[0].vatPLN == 34.5)
        #expect(costs[0].grossPLN == 184.5)
        #expect(costs[1].category == CostCategories.none)
        #expect(costs[1].invoiceCount == 1)
    }

    @Test("Lista użytych kategorii jest unikalna, bez pustych i posortowana")
    func usedCategories() {
        let invoices = [
            makeInvoice(number: "Z/1", kind: .purchase, category: "Paliwo i transport"),
            makeInvoice(number: "Z/2", kind: .purchase, category: "Biuro"),
            makeInvoice(number: "Z/3", kind: .purchase, category: "Paliwo i transport"),
            makeInvoice(number: "Z/4", kind: .purchase, category: ""),
        ]
        #expect(CostCategories.used(in: invoices) == ["Biuro", "Paliwo i transport"])
    }
}
