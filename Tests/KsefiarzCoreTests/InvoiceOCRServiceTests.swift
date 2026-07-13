import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import KsefiarzCore

@Suite("OCR faktur kosztowych — odczyt PDF z warstwą tekstową")
struct InvoiceOCRServiceTests {

    /// Tworzy plik PDF z warstwą tekstową (Core Text) — jak faktura
    /// wygenerowana elektronicznie, w odróżnieniu od skanu-bitmapy.
    private func makeTextPDF(lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw InvoiceOCRError.unreadableFile
        }
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for (idx, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 40, y: 800 - CGFloat(idx) * 20)
            CTLineDraw(ctLine, context)
        }
        context.endPDFPage()
        context.closePDF()
        return url
    }

    @Test("PDF z warstwą tekstową jest czytany wprost (bez OCR) i parsowany")
    func textLayerPDF() async throws {
        let url = try makeTextPDF(lines: [
            "Faktura VAT nr FV/77/2026",
            "Data wystawienia: 10.07.2026",
            "Do zaplaty: 615,00 PLN",
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try await InvoiceOCRService.recognizeTextLines(at: url)
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("FV/77/2026"))
        #expect(joined.contains("615,00"))

        let extraction = InvoiceOCRParser.parse(lines: lines)
        #expect(extraction.documentNumber == "FV/77/2026")
        #expect(extraction.grossAmount == 615.00)
        #expect(extraction.currency == "PLN")
        #expect(extraction.issueDate == FA2Format.dateFormatter.date(from: "2026-07-10"))
    }

    /// Rysuje linie tekstu na białej bitmapie — syntetyczny „skan” faktury
    /// do testów prawdziwej ścieżki Vision.
    private func makeScanImage(lines: [String]) throws -> CGImage {
        let width = 1200
        let height = 400 + lines.count * 60
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw InvoiceOCRError.unreadableFile }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        for (idx, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 80, y: height - 200 - idx * 60)
            CTLineDraw(ctLine, context)
        }
        guard let image = context.makeImage() else { throw InvoiceOCRError.unreadableFile }
        return image
    }

    private func writeJPEG(
        _ image: CGImage,
        to url: URL,
        orientation: Int? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.jpeg" as CFString, 1, nil
        ) else { throw InvoiceOCRError.unreadableFile }
        let properties = orientation.map {
            [kCGImagePropertyOrientation: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw InvoiceOCRError.unreadableFile
        }
    }

    /// Treść syntetycznego skanu — bez polskich znaków, bo dobór języków
    /// Vision zależy od systemu; parser i tak jest na to odporny.
    private static let scanLines = [
        "Faktura VAT nr FV/123/2026",
        "Data wystawienia: 10.07.2026",
        "Sprzedawca: ACME Sp. z o.o.",
        "NIP: 5261040828",
        "Do zaplaty: 1230,00 PLN",
    ]

    @Test("Obraz PNG przechodzi przez prawdziwy OCR Vision i jest parsowany")
    func visionOCRFromImage() async throws {
        let image = try makeScanImage(lines: Self.scanLines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).png")
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try await InvoiceOCRService.recognizeTextLines(at: url)
        let extraction = InvoiceOCRParser.parse(lines: lines)
        #expect(extraction.documentNumber == "FV/123/2026")
        #expect(extraction.issueDate == FA2Format.dateFormatter.date(from: "2026-07-10"))
        #expect(extraction.sellerTaxID == "5261040828")
        #expect(extraction.grossAmount == 1230.00)
    }

    @Test("PDF-skan (obraz bez warstwy tekstowej) przechodzi przez OCR Vision")
    func visionOCRFromScannedPDF() async throws {
        let image = try makeScanImage(lines: Self.scanLines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox) // sam obraz — zero tekstu w warstwie
        context.endPDFPage()
        context.closePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try await InvoiceOCRService.recognizeTextLines(at: url)
        let extraction = InvoiceOCRParser.parse(lines: lines)
        #expect(extraction.documentNumber == "FV/123/2026")
        #expect(extraction.sellerTaxID == "5261040828")
        #expect(extraction.grossAmount == 1230.00)
    }

    @Test("Wczytanie zdjęcia stosuje orientację EXIF przed OCR")
    func imageOrientationIsApplied() throws {
        let image = try makeScanImage(lines: ["Test"])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).jpg")
        try writeJPEG(image, to: url, orientation: 6) // obrót o 90° w prawo
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try #require(InvoiceOCRService.loadCGImage(from: url))
        #expect(loaded.width == image.height)
        #expect(loaded.height == image.width)
    }

    @Test("Duży obraz jest zmniejszany do limitu 4000 px przed OCR")
    func largeImageIsDownsampled() throws {
        let width = 5000
        let height = 100
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).jpg")
        try writeJPEG(image, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try #require(InvoiceOCRService.loadCGImage(from: url))
        #expect(max(loaded.width, loaded.height) == 4000)
    }

    @Test("Plik niebędący PDF ani obrazem zgłasza czytelny błąd")
    func unreadableFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).txt")
        try Data("to nie jest faktura".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: InvoiceOCRError.self) {
            _ = try await InvoiceOCRService.recognizeTextLines(at: url)
        }
    }

    @Test("Komunikaty błędów OCR są po polsku i niepuste")
    func errorDescriptions() {
        for error in [InvoiceOCRError.unreadableFile, .emptyDocument, .noTextRecognized] {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
