import Foundation
import Testing
@testable import KsefiarzCore

// Testy nazw prezentacyjnych (displayName / id / icon) oraz akcesorów
// enumów modeli i filtrów. Każdy `case` musi mieć niepustą, jednoznaczną
// etykietę — iteracja po `allCases` pokrywa wszystkie gałęzie `switch`.

@Suite("Etykiety filtrów list i zakresów")
struct FilterDisplayNamesTests {

    @Test("DocumentTypeFilter — każdy rodzaj ma unikalną etykietę i id")
    func documentTypeFilter() {
        let names = DocumentTypeFilter.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == DocumentTypeFilter.allCases.count)
        #expect(DocumentTypeFilter.allCases.allSatisfy { $0.id == $0.rawValue })
    }

    @Test("DocumentTypeFilter.apply — filtruje po rodzaju, wariant all przepuszcza wszystko")
    func documentTypeApply() {
        let vat = makeTestInvoice(number: "FV/1")
        vat.documentTypeRaw = "VAT"
        let zal = makeTestInvoice(number: "FV/2")
        zal.documentTypeRaw = "ZAL"
        let kor = makeTestInvoice(number: "FV/3")
        kor.documentTypeRaw = "KOR_ZAL"
        let all = [vat, zal, kor]

        #expect(DocumentTypeFilter.all.apply(to: all).count == 3)
        #expect(DocumentTypeFilter.vat.apply(to: all) == [vat])
        #expect(DocumentTypeFilter.zal.apply(to: all) == [zal])
        #expect(DocumentTypeFilter.corrections.apply(to: all) == [kor])
        #expect(DocumentTypeFilter.roz.apply(to: all).isEmpty)
        #expect(DocumentTypeFilter.upr.apply(to: all).isEmpty)
    }

    @Test("DisplayDateFilter — etykiety i id")
    func displayDateFilter() {
        for filter in DisplayDateFilter.allCases {
            #expect(!filter.displayName.isEmpty)
            #expect(filter.id == filter.rawValue)
        }
    }

    @Test("DateRangeMode — etykiety i id")
    func dateRangeMode() {
        for mode in DateRangeMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(mode.id == mode.rawValue)
        }
    }

    @Test("PaymentStatusFilter i KSeFSyncFilter — etykiety i id")
    func invoiceFilters() {
        for filter in PaymentStatusFilter.allCases {
            #expect(!filter.displayName.isEmpty)
            #expect(filter.id == filter.rawValue)
        }
        for filter in KSeFSyncFilter.allCases {
            #expect(!filter.displayName.isEmpty)
            #expect(filter.id == filter.rawValue)
        }
    }
}

@Suite("Etykiety i akcesory enumów modeli")
struct ModelEnumDisplayNamesTests {

    @Test("PaymentRecord.Source — etykieta i setter przez source")
    func paymentRecordSource() {
        for source in PaymentRecord.Source.allCases {
            #expect(!source.displayName.isEmpty)
        }
        let record = PaymentRecord(amount: 100, date: .now)
        #expect(record.source == .manual)
        record.source = .bankImport
        #expect(record.source == .bankImport)
        #expect(record.sourceRaw == PaymentRecord.Source.bankImport.rawValue)
    }

    @Test("SyncRun.Operation — etykieta i ikona; Trigger — etykieta")
    func syncRunEnums() {
        for op in SyncRun.Operation.allCases {
            #expect(!op.displayName.isEmpty)
            #expect(!op.icon.isEmpty)
        }
        for trigger in SyncRun.Trigger.allCases {
            #expect(!trigger.displayName.isEmpty)
        }
    }

    @Test("RecurrenceUnit — etykieta; RecurringInvoice.unit setter")
    func recurrenceUnit() {
        for unit in RecurrenceUnit.allCases {
            #expect(!unit.displayName.isEmpty)
        }
        let preset = InvoicePreset(draft: makeSampleDraft())
        let schedule = RecurringInvoice(name: "Abonament", preset: preset, unit: .month)
        #expect(schedule.unit == .month)
        schedule.unit = .year
        #expect(schedule.unit == .year)
        #expect(schedule.recurrenceUnitRaw == RecurrenceUnit.year.rawValue)
    }

    @Test("InvoiceTemplate.preset — setter koduje szablon do danych")
    func invoiceTemplatePresetSetter() {
        let preset = InvoicePreset(draft: makeSampleDraft())
        let template = InvoiceTemplate(name: "Szablon", preset: preset)
        var updated = preset
        updated.sellerName = "Nowy Sprzedawca"
        template.preset = updated
        #expect(template.preset?.sellerName == "Nowy Sprzedawca")
        // Nil nie nadpisuje istniejących danych (guard).
        template.preset = nil
        #expect(template.preset?.sellerName == "Nowy Sprzedawca")
    }

    @Test("Product.ProductType — etykieta, id i setter type")
    func productType() {
        for type in Product.ProductType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(type.id == type.rawValue)
        }
        let product = Product()
        #expect(product.type == .goods)
        product.type = .service
        #expect(product.type == .service)
        #expect(product.typeRaw == Product.ProductType.service.rawValue)
    }

    @Test("BankAccount.displayName — z etykietą i bez")
    func bankAccountDisplayName() {
        let bare = BankAccount()
        bare.accountNumber = "PL61109010140000071219812874"
        #expect(bare.displayName == bare.accountNumber)

        let labeled = BankAccount()
        labeled.label = "Firmowy PLN"
        labeled.accountNumber = "PL61109010140000071219812874"
        #expect(labeled.displayName == "Firmowy PLN (2874)")
    }

    @Test("Contractor.displayName — jedno- i dwuwierszowa nazwa")
    func contractorDisplayName() {
        let single = Contractor()
        single.name = "ACME Sp. z o.o."
        #expect(single.displayName == "ACME Sp. z o.o.")

        let twoLines = Contractor()
        twoLines.name = "ACME"
        twoLines.nameLine2 = "Oddział Kraków"
        #expect(twoLines.displayName == "ACME Oddział Kraków")
    }

    @Test("Invoice — etykiety statusu wysyłki i termin trybu offline")
    func invoiceSubmissionAndOfflineLabels() {
        for status in KSeFSubmissionStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
        for reason in Invoice.OfflineReason.allCases {
            #expect(!reason.displayName.isEmpty)
            #expect(!reason.deadlineDescription.isEmpty)
        }
    }

    @Test("Invoice — settery advanceInvoiceRefs i kind")
    func invoiceRefsAndKindSetters() {
        let invoice = makeTestInvoice()
        invoice.advanceInvoiceRefs = ["KSEF-1", "KSEF-2"]
        #expect(invoice.advanceInvoiceRefsRaw == "KSEF-1\nKSEF-2")
        #expect(invoice.advanceInvoiceRefs == ["KSEF-1", "KSEF-2"])

        #expect(invoice.kind == .purchase)
        invoice.kind = .sales
        #expect(invoice.kind == .sales)
        #expect(invoice.kindRaw == Invoice.Kind.sales.rawValue)
    }

    @Test("InvoiceLine — VATRate, PaymentForm etykiety i id")
    func invoiceLineEnums() {
        for rate in VATRate.allCases {
            #expect(!rate.displayName.isEmpty)
            #expect(rate.id == rate.rawValue)
        }
        for form in PaymentForm.allCases {
            #expect(!form.displayName.isEmpty)
            #expect(!form.englishName.isEmpty)
            #expect(form.id == form.rawValue)
        }
    }
}

/// Wspólny szkic faktury do budowy presetów w testach etykiet.
func makeSampleDraft() -> InvoiceDraft {
    InvoiceDraft(
        invoiceNumber: "FV/1/2026",
        issueDate: FA2Format.dateFormatter.date(from: "2026-06-12")!,
        sellerName: "Sprzedawca",
        sellerNIP: "5260250274",
        sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
        buyerName: "Nabywca",
        buyerNIP: "1111111111",
        lines: [InvoiceLineDraft(name: "Pozycja", quantity: 1, unitNetPrice: 100)]
    )
}
