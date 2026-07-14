import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Globalna wyszukiwarka ⌘K — normalizacja, ranking i mapowanie (F3)")
struct GlobalSearchEngineTests {

    private func item(
        kind: GlobalSearchEngine.Kind = .contractor,
        id: String = UUID().uuidString,
        title: String,
        subtitle: String = "",
        keywords: [String] = []
    ) -> GlobalSearchEngine.Item {
        GlobalSearchEngine.Item(
            kind: kind, id: id, title: title, subtitle: subtitle, keywords: keywords
        )
    }

    // MARK: Normalizacja

    @Test("Normalizacja składa polskie znaki diakrytyczne, w tym ł")
    func normalizationFoldsDiacritics() {
        #expect(GlobalSearchEngine.normalized("Żółw Świętokrzyski ŁĄKA") == "zolw swietokrzyski laka")
        #expect(GlobalSearchEngine.normalized("faktura") == "faktura")
    }

    @Test("Zapytanie bez diakrytyków znajduje tytuł z diakrytykami")
    func diacriticInsensitiveMatch() {
        let items = [item(title: "Żółw Sp. z o.o."), item(title: "Inna firma")]
        let results = GlobalSearchEngine.search("zolw", in: items)
        #expect(results.map(\.title) == ["Żółw Sp. z o.o."])
    }

    // MARK: Ranking

    @Test("Każdy wyraz zapytania musi pasować — brak trafienia dyskwalifikuje")
    func allTokensMustMatch() {
        let items = [
            item(title: "ACME Warszawa"),
            item(title: "ACME Kraków"),
        ]
        let results = GlobalSearchEngine.search("acme kraków", in: items)
        #expect(results.map(\.title) == ["ACME Kraków"])
    }

    @Test("Prefiks tytułu wygrywa z trafieniem w środku tytułu i w słowach kluczowych")
    func rankingOrder() {
        let items = [
            item(id: "keyword", title: "Inna nazwa", keywords: ["faktura"]),
            item(id: "infix", title: "Stara faktura"),
            item(id: "prefix", title: "Faktura testowa"),
        ]
        let results = GlobalSearchEngine.search("faktura", in: items)
        #expect(results.map(\.id) == ["prefix", "infix", "keyword"])
    }

    @Test("Puste zapytanie nie zwraca wyników, a limit ogranicza listę")
    func emptyQueryAndLimit() {
        let items = (1...5).map { item(title: "Firma \($0)") }
        #expect(GlobalSearchEngine.search("", in: items).isEmpty)
        #expect(GlobalSearchEngine.search("   ", in: items).isEmpty)
        #expect(GlobalSearchEngine.search("firma", in: items, limit: 3).count == 3)
    }

    @Test("Tabulatory i nowe linie rozdzielają wyrazy zapytania")
    func allWhitespaceSeparatesTokens() {
        let items = [
            item(title: "ACME Kraków"),
            item(title: "ACME Warszawa"),
        ]
        let results = GlobalSearchEngine.search("acme\n\tkraków", in: items)
        #expect(results.map(\.title) == ["ACME Kraków"])
        #expect(GlobalSearchEngine.search("\n\t", in: items).isEmpty)
    }

    @Test("Kontrahent jest znajdowany po NIP ze słów kluczowych")
    func contractorFoundByNIP() {
        let contractor = Contractor()
        contractor.name = "Kontrahent S.A."
        contractor.nip = "5260250274"
        contractor.city = "Warszawa"
        let mapped = GlobalSearchEngine.item(for: contractor)
        let results = GlobalSearchEngine.search("5260250274", in: [mapped])
        #expect(results.count == 1)
        #expect(results.first?.title == "Kontrahent S.A.")
    }

    // MARK: Mapowanie modeli

    @Test("Pozycja faktury sprzedaży: numer w tytule, nabywca i kwota w podtytule")
    func invoiceMapping() {
        let invoice = Invoice(
            ksefId: "1111111111-20260711-AAAAAAAAAAAA-AA",
            invoiceNumber: "FV/7/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            kind: .sales
        )
        let mapped = GlobalSearchEngine.item(for: invoice)
        #expect(mapped.kind == .invoice)
        #expect(mapped.title == "FV/7/2026")
        #expect(mapped.subtitle == "Sprzedaż · Kontrahent S.A. · 123.00 PLN · 2026-07-01")
        #expect(mapped.keywords.contains("1111111111-20260711-AAAAAAAAAAAA-AA"))
        #expect(mapped.keywords.contains("5260250274"))
        // Wyszukanie po numerze KSeF trafia w tę fakturę.
        let results = GlobalSearchEngine.search("AAAAAAAAAAAA", in: [mapped])
        #expect(results.count == 1)
    }

    @Test("Pozycja faktury zakupu pokazuje sprzedawcę jako drugą stronę")
    func purchaseMappingShowsSeller() {
        let invoice = Invoice(
            invoiceNumber: "K/1/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
            sellerName: "Dostawca Sp. j.",
            sellerNIP: "5260250274",
            buyerName: "Moja Firma",
            buyerNIP: "1111111111",
            netAmount: 10,
            vatAmount: 2.3,
            grossAmount: 12.3,
            kind: .purchase
        )
        let mapped = GlobalSearchEngine.item(for: invoice)
        #expect(mapped.subtitle.hasPrefix("Zakup · Dostawca Sp. j."))
    }

    @Test("Pozycja proformy ma numer w tytule i nabywcę w podtytule")
    func proformaMapping() {
        let proforma = Proforma(
            proformaNumber: "PF/1/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-05")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Klient Detaliczny",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123
        )
        let mapped = GlobalSearchEngine.item(for: proforma)
        #expect(mapped.kind == .proforma)
        #expect(mapped.title == "PF/1/2026")
        #expect(mapped.subtitle == "Proforma · Klient Detaliczny · 123.00 PLN · 2026-07-05")
    }
}
