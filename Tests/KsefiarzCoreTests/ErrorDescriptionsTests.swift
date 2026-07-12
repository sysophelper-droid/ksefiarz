import Foundation
import Testing
@testable import KsefiarzCore

// Opisy błędów (LocalizedError.errorDescription) prezentowane użytkownikowi.
// Każdy komunikat musi być niepusty, a przy błędach z wartością powiązaną —
// zawierać tę wartość (indeks pozycji, kod waluty, szczegóły usługi).

@Suite("Opisy błędów walidacji i usług")
struct ErrorDescriptionsTests {

    @Test("InvoiceValidationError — wszystkie warianty mają niepusty opis")
    func invoiceValidationErrors() {
        let cases: [InvoiceValidationError] = [
            .emptyInvoiceNumber, .emptySellerName, .emptySellerAddress,
            .emptyBuyerName, .invalidSellerNIP, .invalidBuyerNIP,
            .nonPositiveNetAmount, .negativeVatAmount, .amountsMismatch,
            .emptyLineName(2), .nonPositiveLineQuantity(3), .negativeLinePrice(4),
            .emptyCorrectedInvoiceNumber, .missingExchangeRate,
            .missingAdvanceInvoiceRefs, .duplicateInvoiceNumber("FV/1/2026"),
            .invalidLineOSSRate(5), .attachmentMissingMetadata(1),
            .attachmentTooManyParagraphs(2), .attachmentInvalidTable(3),
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
        // Wartości powiązane trafiają do komunikatu.
        #expect(InvoiceValidationError.emptyLineName(7).errorDescription?.contains("7") == true)
        #expect(InvoiceValidationError.duplicateInvoiceNumber("FV/42")
            .errorDescription?.contains("FV/42") == true)
        #expect(InvoiceValidationError.invalidLineOSSRate(9)
            .errorDescription?.contains("9") == true)
        #expect(InvoiceValidationError.attachmentInvalidTable(4)
            .errorDescription?.contains("4") == true)
    }

    @Test("ManualPurchaseValidationError — opisy wszystkich wariantów")
    func manualPurchaseErrors() {
        let cases: [ManualPurchaseValidationError] = [
            .emptyDocumentNumber, .emptySellerName, .zeroAmount, .missingExchangeRate,
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("NBPExchangeRateService.RateError — opisy z kodem waluty i szczegółami")
    func nbpRateErrors() {
        #expect(NBPExchangeRateService.RateError.unsupportedCurrency("XYZ")
            .errorDescription?.contains("XYZ") == true)
        #expect(NBPExchangeRateService.RateError.noRateAvailable
            .errorDescription?.isEmpty == false)
        #expect(NBPExchangeRateService.RateError.serviceError("HTTP 500")
            .errorDescription?.contains("HTTP 500") == true)
    }

    @Test("ContractorLookupService.LookupError — opisy z detalami usługi")
    func contractorLookupErrors() {
        #expect(ContractorLookupService.LookupError.invalidNIP
            .errorDescription?.isEmpty == false)
        #expect(ContractorLookupService.LookupError.notFound
            .errorDescription?.isEmpty == false)
        #expect(ContractorLookupService.LookupError.serviceError("timeout")
            .errorDescription?.contains("timeout") == true)
    }

    @Test("InvoiceEmailError — opisy wszystkich wariantów")
    func invoiceEmailErrors() {
        let cases: [InvoiceEmailError] = [.composeUnavailable, .missingPDF, .missingXML]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
