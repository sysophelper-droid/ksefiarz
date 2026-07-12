import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import KsefiarzCore

@Suite("Branding wydruku PDF")
@MainActor
struct InvoicePDFBrandingTests {

    private func salesInvoice(sellerNIP: String = "5260250274") -> Invoice {
        let invoice = Invoice(
            invoiceNumber: "FV/BRAND/1",
            issueDate: Date(timeIntervalSince1970: 1_782_864_000),
            sellerName: "Studio Północ Sp. z o.o.",
            sellerNIP: sellerNIP,
            sellerAddress: "ul. Morska 8, 80-001 Gdańsk",
            buyerName: "Klient S.A.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Testowa 2, 00-001 Warszawa",
            netAmount: 1_000,
            vatAmount: 230,
            grossAmount: 1_230,
            paymentDueDate: Date(timeIntervalSince1970: 1_784_073_600),
            paymentForm: .transfer,
            kind: .sales
        )
        invoice.lines = [
            InvoiceLine(
                index: 1, name: "Projekt identyfikacji wizualnej", unit: "usł.",
                quantity: 1, unitNetPrice: 1_000, netAmount: 1_000,
                vatRate: "23", vatAmount: 230
            ),
        ]
        return invoice
    }

    @Test("Kolory są normalizowane do zapisu #RRGGBB")
    func normalizacjaKolorow() {
        #expect(InvoicePDFBranding.normalizedHex(" 1e4d6b ") == "#1E4D6B")
        #expect(InvoicePDFBranding.normalizedHex("#aBc123") == "#ABC123")
        #expect(InvoicePDFBranding.normalizedHex("12345") == nil)
        #expect(InvoicePDFBranding(normalizedPrimary: "nie-kolor").primaryColorHex == InvoicePDFBranding.defaultPrimaryHex)
    }

    @Test("Branding obejmuje własną sprzedaż, ale nie obce faktury kosztowe")
    func zakresBrandingu() {
        let branding = InvoicePDFBranding(isEnabled: true, companyNIP: "526-025-02-74")
        #expect(branding.applies(to: salesInvoice()))
        #expect(!branding.applies(to: salesInvoice(sellerNIP: "9999999999")))
        #expect(!InvoicePDFBranding(companyNIP: "5260250274").applies(to: salesInvoice()))
    }

    @Test("VAT RR używa brandingu firmy będącej nabywcą i wystawcą dokumentu")
    func brandingVATRR() {
        let invoice = salesInvoice(sellerNIP: "9999999999")
        invoice.documentTypeRaw = "VAT_RR"
        invoice.buyerNIP = "5260250274"
        let branding = InvoicePDFBranding(isEnabled: true, companyNIP: "5260250274")

        #expect(branding.applies(to: invoice))
    }

    @Test("Konfiguracja odczytuje logo, kolory i stopkę z ustawień")
    func odczytUstawien() throws {
        let suite = "InvoicePDFBrandingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let logo = Data([0, 1, 2, 3])
        defaults.set(true, forKey: AppSettingsKeys.pdfBrandingEnabled)
        defaults.set("5260250274", forKey: AppSettingsKeys.nip)
        defaults.set(logo.base64EncodedString(), forKey: AppSettingsKeys.pdfBrandingLogo)
        defaults.set("#112233", forKey: AppSettingsKeys.pdfBrandingPrimaryColor)
        defaults.set("#AABBCC", forKey: AppSettingsKeys.pdfBrandingAccentColor)
        defaults.set("  Stopka firmy  ", forKey: AppSettingsKeys.pdfBrandingFooter)

        let branding = InvoicePDFBranding.current(defaults: defaults)

        #expect(branding.isEnabled)
        #expect(branding.logoData == logo)
        #expect(branding.primaryColorHex == "#112233")
        #expect(branding.accentColorHex == "#AABBCC")
        #expect(branding.footer == "Stopka firmy")
    }

    @Test("Logo jest skalowane i kodowane jako PNG")
    func normalizacjaLogo() throws {
        let source = NSImage(size: CGSize(width: 2_000, height: 500))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 2_000, height: 500)).fill()
        source.unlockFocus()
        let tiff = try #require(source.tiffRepresentation)

        let png = try #require(PDFBrandingLogoProcessor.normalizedPNG(from: tiff))
        let normalized = try #require(NSBitmapImageRep(data: png))

        #expect(normalized.pixelsWide == 1_200)
        #expect(normalized.pixelsHigh == 300)
        #expect(PDFBrandingLogoProcessor.normalizedPNG(from: Data()) == nil)
    }

    @Test("PDF zawiera własną stopkę i kolory marki")
    func renderBrandingu() throws {
        let branding = InvoicePDFBranding(
            isEnabled: true,
            companyNIP: "5260250274",
            logoData: try makeTestLogo(),
            primaryColorHex: "#C2185B",
            accentColorHex: "#00A6A6",
            footer: "Studio Północ • studio.example • +48 58 000 00 00"
        )
        let data = try #require(InvoicePDFGenerator.pdfData(
            for: salesInvoice(), branding: branding
        ))
        if let snapshotPath = ProcessInfo.processInfo.environment["KSEF_PDF_SNAPSHOT_PATH"] {
            try data.write(to: URL(fileURLWithPath: snapshotPath))
        }
        let document = try #require(PDFDocument(data: data))
        let text = try #require(document.string)

        #expect(text.contains("Studio Północ • studio.example • +48 58 000 00 00"))
        #expect(data.count > 10_000)
    }

    @Test("Obca faktura nie otrzymuje stopki firmy użytkownika")
    func bezBrandinguNaZakupie() throws {
        let branding = InvoicePDFBranding(
            isEnabled: true,
            companyNIP: "5260250274",
            footer: "NIE DLA DOSTAWCY"
        )
        let data = try #require(InvoicePDFGenerator.pdfData(
            for: salesInvoice(sellerNIP: "9999999999"), branding: branding
        ))

        #expect(PDFDocument(data: data)?.string?.contains("NIE DLA DOSTAWCY") == false)
    }

    @Test("Własna stopka jest drukowana na każdej stronie długiej faktury")
    func stopkaNaKazdejStronie() throws {
        let invoice = salesInvoice()
        invoice.lines = (1...15).map {
            InvoiceLine(
                index: $0, name: "Pozycja projektu \($0)", quantity: 1,
                unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23
            )
        }
        let branding = InvoicePDFBranding(
            isEnabled: true, companyNIP: "5260250274", footer: "STOPKA WIELOSTRONICOWA"
        )

        let data = try #require(InvoicePDFGenerator.pdfData(for: invoice, branding: branding))
        let document = try #require(PDFDocument(data: data))

        #expect(document.pageCount == 2)
        for index in 0..<document.pageCount {
            #expect(document.page(at: index)?.string?.contains("STOPKA WIELOSTRONICOWA") == true)
        }
    }

    private func makeTestLogo() throws -> Data {
        let image = NSImage(size: CGSize(width: 300, height: 120))
        image.lockFocus()
        NSColor(calibratedRed: 0, green: 0.65, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 300, height: 120),
                     xRadius: 24, yRadius: 24).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        return try #require(PDFBrandingLogoProcessor.normalizedPNG(from: tiff))
    }
}

private extension InvoicePDFBranding {
    /// Skrót używany wyłącznie do sprawdzenia walidacji wartości inicjalizatora.
    init(normalizedPrimary: String) {
        self.init(primaryColorHex: normalizedPrimary)
    }
}
