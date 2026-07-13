import AppKit
import Foundation
import PDFKit
import Vision

/// Błędy rozpoznawania tekstu ze skanu/PDF faktury.
public enum InvoiceOCRError: LocalizedError {
    case unreadableFile
    case emptyDocument
    case noTextRecognized

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Nie udało się odczytać pliku — obsługiwane są PDF oraz obrazy (PNG, JPEG, TIFF, HEIC)."
        case .emptyDocument:
            return "Dokument nie zawiera żadnej strony."
        case .noTextRecognized:
            return "Nie rozpoznano tekstu w dokumencie — sprawdź jakość skanu."
        }
    }
}

/// Rozpoznawanie tekstu faktury kosztowej ze skanu/PDF — natywnie przez
/// macOS Vision (bez zależności zewnętrznych). PDF z warstwą tekstową
/// czytany jest wprost przez PDFKit (szybciej i bez błędów OCR); skan
/// (obraz albo PDF bez tekstu) przechodzi przez `VNRecognizeTextRequest`.
public enum InvoiceOCRService {

    /// Limit stron PDF — faktury są krótkie, a OCR dużych dokumentów
    /// jest kosztowny; istotne pola i tak są na początku.
    public static let maxPages = 4

    /// Minimalna liczba znaków warstwy tekstowej strony PDF, przy której
    /// ufamy jej zamiast OCR (skan zapisany jako PDF ma pustą warstwę).
    static let minTextLayerCharacters = 32

    /// Docelowa gęstość renderowania strony PDF do OCR.
    private static let renderDPI: CGFloat = 300
    private static let maxRenderDimension: CGFloat = 4000

    /// Rozpoznaje linie tekstu (w kolejności czytania) z pliku PDF
    /// albo obrazu pod wskazanym adresem.
    public static func recognizeTextLines(at url: URL) async throws -> [String] {
        // Vision jest kosztowny obliczeniowo — praca poza główną kolejką.
        try await Task.detached(priority: .userInitiated) {
            try recognizeTextLinesSync(at: url)
        }.value
    }

    private static func recognizeTextLinesSync(at url: URL) throws -> [String] {
        if let pdf = PDFDocument(url: url) {
            return try recognizeLines(pdf: pdf)
        }
        if let image = loadCGImage(from: url) {
            let lines = try ocrLines(cgImage: image)
            guard !lines.isEmpty else { throw InvoiceOCRError.noTextRecognized }
            return lines
        }
        throw InvoiceOCRError.unreadableFile
    }

    // MARK: - PDF

    private static func recognizeLines(pdf: PDFDocument) throws -> [String] {
        guard pdf.pageCount > 0 else { throw InvoiceOCRError.emptyDocument }
        var lines: [String] = []
        for pageIndex in 0..<min(pdf.pageCount, maxPages) {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let textLayer = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if textLayer.filter({ !$0.isWhitespace }).count >= minTextLayerCharacters {
                lines.append(contentsOf: textLayer.components(separatedBy: .newlines))
            } else if let image = render(page: page) {
                lines.append(contentsOf: try ocrLines(cgImage: image))
            }
        }
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw InvoiceOCRError.noTextRecognized
        }
        return lines
    }

    /// Renderuje stronę PDF do bitmapy o gęstości OCR (skan bez warstwy
    /// tekstowej), z limitem wymiaru chroniącym pamięć.
    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var scale = renderDPI / 72
        let maxSide = max(bounds.width, bounds.height) * scale
        if maxSide > maxRenderDimension {
            scale *= maxRenderDimension / maxSide
        }
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - Obrazy

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Vision

    /// Rozpoznaje tekst na obrazie i zwraca linie w kolejności czytania
    /// (z góry na dół, w wierszu od lewej).
    private static func ocrLines(cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Polski + angielski, ale tylko w formie faktycznie wspieranej przez
        // Vision na tym systemie (żądanie niewspieranego języka kończy się
        // błędem `perform`); bez trafień zostaje domyślna lista systemowa.
        let wantedPrefixes = ["pl", "en"]
        if let supported = try? request.supportedRecognitionLanguages() {
            let available = wantedPrefixes.compactMap { prefix in
                supported.first { $0.hasPrefix(prefix) }
            }
            if !available.isEmpty { request.recognitionLanguages = available }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []

        // Vision zwraca współrzędne znormalizowane z początkiem w lewym
        // dolnym rogu — sortowanie od góry, w obrębie wiersza od lewej.
        // Wiersz to skwantyzowane midY (klucz, nie komparator z tolerancją —
        // ten nie byłby przechodni, a `sorted` wymaga spójnego porządku).
        let rowHeight: CGFloat = 0.012
        let sorted = observations.sorted { lhs, rhs in
            let lhsRow = ((1 - lhs.boundingBox.midY) / rowHeight).rounded(.down)
            let rhsRow = ((1 - rhs.boundingBox.midY) / rowHeight).rounded(.down)
            if lhsRow != rhsRow { return lhsRow < rhsRow }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }
    }
}
