import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Kalendarz i prognoza podatkowa")
struct TaxCalendarEngineTests {
    private var calendar: Calendar {
        PolishBusinessCalendar.calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func invoice(
        number: String,
        kind: Invoice.Kind,
        date: Date,
        net: Double,
        vat: Double
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: date,
            sellerName: kind == .sales ? "Moja Firma" : "Dostawca",
            sellerNIP: kind == .sales ? "1111111111" : "5260250274",
            sellerAddress: "ul. Sprzedawcy 1",
            buyerName: kind == .sales ? "Odbiorca" : "Moja Firma",
            buyerNIP: kind == .sales ? "5260250274" : "1111111111",
            buyerAddress: "ul. Nabywcy 2",
            netAmount: net,
            vatAmount: vat,
            grossAmount: net + vat,
            kind: kind
        )
    }

    private func snapshot(
        invoices: [Invoice] = [],
        taxForm: TaxForm = .kpir,
        method: KPiRIncomeTaxMethod = .scale,
        incomeCycle: TaxSettlementCycle = .monthly,
        vatCycle: TaxSettlementCycle = .monthly,
        isActiveVATPayer: Bool = true,
        now: Date
    ) -> TaxCalendarEngine.Snapshot {
        TaxCalendarEngine.snapshot(
            invoices: invoices,
            taxForm: taxForm,
            defaultRyczaltRate: .r8_5,
            incomeTaxMethod: method,
            incomeTaxCycle: incomeCycle,
            vatCycle: vatCycle,
            isActiveVATPayer: isActiveVATPayer,
            now: now,
            calendar: calendar
        )
    }

    @Test("Nieznane ustawienia wracają do bezpiecznych wartości miesięcznych i skali")
    func settingsFallbacks() {
        #expect(TaxSettlementCycle.resolve("monthly") == .monthly)
        #expect(TaxSettlementCycle.resolve("quarterly") == .quarterly)
        #expect(TaxSettlementCycle.resolve("inne") == .monthly)
        #expect(KPiRIncomeTaxMethod.resolve("linear") == .linear)
        #expect(KPiRIncomeTaxMethod.resolve("inne") == .scale)
        #expect(TaxSettlementCycle.quarterly.displayName == "Kwartalnie")
        #expect(TaxSettlementCycle.monthly.id == "monthly")
        #expect(KPiRIncomeTaxMethod.scale.displayName.contains("12%"))
        #expect(KPiRIncomeTaxMethod.linear.id == "linear")
        #expect(BackupService.currentVersion == 13)
        #expect(BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.numberPatternPRO))
        #expect(BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.numberPatternSF))
        #expect(BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.kpirIncomeTaxMethod))
        #expect(BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.incomeTaxSettlementCycle))
        #expect(BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.vatSettlementCycle))
        #expect(BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.isActiveVATPayer))
    }

    @Test("JPK i VAT za czerwiec przesuwają się z soboty 25 lipca na poniedziałek")
    func weekendDeadlineShift() throws {
        let result = snapshot(now: date(2026, 7, 13))
        let zus = try #require(result.deadlines.first { $0.kind == .zus })
        let pit = try #require(result.deadlines.first { $0.kind == .incomeTax })
        let jpk = try #require(result.deadlines.first { $0.kind == .jpk })
        let vat = try #require(result.deadlines.first { $0.kind == .vat })

        #expect(calendar.isDate(zus.dueDate, inSameDayAs: date(2026, 7, 20)))
        #expect(calendar.isDate(pit.dueDate, inSameDayAs: date(2026, 7, 20)))
        #expect(calendar.isDate(jpk.dueDate, inSameDayAs: date(2026, 7, 27)))
        #expect(calendar.isDate(vat.dueDate, inSameDayAs: date(2026, 7, 27)))
        #expect(jpk.period.months == [6])
        #expect(jpk.period.label == "czerwiec 2026")
    }

    @Test("Po terminie silnik pokazuje kolejny miesiąc")
    func deadlineMovesForward() throws {
        let result = snapshot(now: date(2026, 7, 28))
        let jpk = try #require(result.deadlines.first { $0.kind == .jpk })
        #expect(calendar.isDate(jpk.dueDate, inSameDayAs: date(2026, 8, 25)))
        #expect(jpk.period.months == [7])
    }

    @Test("JPK pozostaje miesięczny, a kwartalny VAT wskazuje zakończony kwartał")
    func quarterlyVATAndMonthlyJPK() throws {
        let result = snapshot(vatCycle: .quarterly, now: date(2026, 8, 10))
        let jpk = try #require(result.deadlines.first { $0.kind == .jpk })
        let vat = try #require(result.deadlines.first { $0.kind == .vat })

        #expect(jpk.period.months == [7])
        #expect(calendar.isDate(jpk.dueDate, inSameDayAs: date(2026, 8, 25)))
        #expect(vat.period.months == [7, 8, 9])
        #expect(vat.period.label == "3 kwartał 2026")
        #expect(calendar.isDate(vat.dueDate, inSameDayAs: date(2026, 10, 26)))
        #expect(result.forecast.vatPeriod.months == [7, 8, 9])
    }

    @Test("Prognoza VAT liczy bieżący okres w PLN i pomija ukryte dokumenty")
    func vatForecast() {
        let sale = invoice(number: "S/1", kind: .sales, date: date(2026, 7, 2), net: 1_000, vat: 230)
        let purchase = invoice(number: "Z/1", kind: .purchase, date: date(2026, 7, 3), net: 400, vat: 92)
        purchase.currency = "EUR"
        purchase.exchangeRate = 4
        let hidden = invoice(number: "X", kind: .sales, date: date(2026, 7, 4), net: 10_000, vat: 2_300)
        hidden.isArchivedOrHidden = true
        let june = invoice(number: "S/VI", kind: .sales, date: date(2026, 6, 30), net: 500, vat: 115)

        let forecast = snapshot(
            invoices: [sale, purchase, hidden, june],
            now: date(2026, 7, 13)
        ).forecast

        #expect(forecast.outputVAT == 230)
        #expect(forecast.inputVAT == 368)
        #expect(forecast.vatBalance == -138)
        #expect(forecast.vatApplies)
    }

    @Test("Podatnik zwolniony nie dostaje terminów ani kwot JPK i VAT")
    func vatExemption() {
        let sale = invoice(number: "ZW", kind: .sales, date: date(2026, 7, 2), net: 1_000, vat: 230)
        let result = snapshot(
            invoices: [sale],
            isActiveVATPayer: false,
            now: date(2026, 7, 13)
        )

        #expect(result.deadlines.map(\.kind).contains(.jpk) == false)
        #expect(result.deadlines.map(\.kind).contains(.vat) == false)
        #expect(result.forecast.vatApplies == false)
        #expect(result.forecast.outputVAT == 0)
        #expect(result.forecast.vatBalance == 0)
    }

    @Test("VAT RR nie jest automatycznie odliczany w prognozie VAT")
    func vatRRIsNotDeducted() {
        let purchase = invoice(
            number: "RR/1", kind: .purchase, date: date(2026, 7, 3),
            net: 1_000, vat: 70
        )
        purchase.documentTypeRaw = "VAT_RR"

        let forecast = snapshot(invoices: [purchase], now: date(2026, 7, 13)).forecast
        #expect(forecast.inputVAT == 0)
        #expect(forecast.warnings.contains { $0.contains("VAT RR") })
    }

    @Test("Skala PIT liczy przyrost podatku narastająco po przekroczeniu progu")
    func progressivePITForecast() {
        let january = invoice(number: "S/I", kind: .sales, date: date(2026, 1, 10), net: 100_000, vat: 0)
        let july = invoice(number: "S/VII", kind: .sales, date: date(2026, 7, 10), net: 30_000, vat: 0)

        let forecast = snapshot(
            invoices: [january, july],
            method: .scale,
            now: date(2026, 7, 13)
        ).forecast

        #expect(forecast.incomeTaxBase == 130_000)
        // 14 000 zł podatku narastająco minus 8 400 zł do końca czerwca.
        #expect(forecast.incomeTax == 5_600)
        #expect(forecast.incomeTaxLabel.contains("skala"))
    }

    @Test("Podatek liniowy uwzględnia dochód po kosztach bieżącego miesiąca")
    func linearPITForecast() {
        let sale = invoice(number: "S", kind: .sales, date: date(2026, 7, 2), net: 10_000, vat: 2_300)
        let cost = invoice(number: "Z", kind: .purchase, date: date(2026, 7, 3), net: 2_000, vat: 460)

        let forecast = snapshot(
            invoices: [sale, cost],
            method: .linear,
            now: date(2026, 7, 13)
        ).forecast

        #expect(forecast.incomeTaxBase == 8_000)
        #expect(forecast.incomeTax == 1_520)
        #expect(forecast.incomeTaxLabel.contains("liniowy"))
    }

    @Test("Strata w KPiR nie tworzy prognozowanej zaliczki")
    func lossDoesNotCreateAdvance() {
        let sale = invoice(number: "S", kind: .sales, date: date(2026, 7, 2), net: 1_000, vat: 230)
        let cost = invoice(number: "Z", kind: .purchase, date: date(2026, 7, 3), net: 2_000, vat: 460)
        let forecast = snapshot(invoices: [sale, cost], now: date(2026, 7, 13)).forecast
        #expect(forecast.incomeTaxBase == 0)
        #expect(forecast.incomeTax == 0)
    }

    @Test("Ryczałt sumuje własne stawki faktur w bieżącym kwartale")
    func ryczaltForecast() {
        let first = invoice(number: "R/1", kind: .sales, date: date(2026, 7, 2), net: 1_000, vat: 230)
        first.ryczaltRateRaw = RyczaltRate.r8_5.rawValue
        let second = invoice(number: "R/2", kind: .sales, date: date(2026, 8, 2), net: 2_000, vat: 460)
        second.ryczaltRateRaw = RyczaltRate.r12.rawValue

        let forecast = snapshot(
            invoices: [first, second],
            taxForm: .ryczalt,
            incomeCycle: .quarterly,
            vatCycle: .quarterly,
            now: date(2026, 8, 10)
        ).forecast

        #expect(forecast.incomeTaxPeriod.months == [7, 8, 9])
        #expect(forecast.incomeTaxBase == 3_000)
        #expect(forecast.incomeTax == 325)
        #expect(forecast.incomeTaxLabel.contains("Ryczałt"))
    }

    @Test("Metadane rodzajów terminów mają polskie etykiety i ikony")
    func deadlineMetadata() {
        #expect(TaxCalendarEngine.DeadlineKind.allCases.count == 4)
        #expect(TaxCalendarEngine.DeadlineKind.jpk.title.contains("JPK"))
        #expect(!TaxCalendarEngine.DeadlineKind.vat.systemImage.isEmpty)
        let result = snapshot(now: date(2026, 7, 13))
        #expect(result.deadlines.first { $0.kind == .jpk }?.id == "jpk")
    }
}
