import AppKit
import Foundation
import SwiftUI

extension InvoicePDFBranding {
    /// Kolor SwiftUI wyliczany ze zwalidowanego zapisu konfiguracji.
    static func color(hex: String) -> Color {
        let normalized = normalizedHex(hex) ?? defaultPrimaryHex
        let value = UInt64(normalized.dropFirst(), radix: 16) ?? 0
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Przygotowuje logo do trwałego zapisu w ustawieniach i kopii zapasowej.
/// Obraz jest skalowany do rozsądnego rozmiaru i kodowany jako PNG, aby duże
/// pliki źródłowe nie powiększały bez potrzeby UserDefaults i każdego PDF-a.
@MainActor
public enum PDFBrandingLogoProcessor {
    public static let maximumSourceBytes = 10 * 1_024 * 1_024
    public static let maximumDimension: CGFloat = 1_200

    public static func normalizedPNG(from data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maximumSourceBytes,
              let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        // Przypisanie `current` nie korzysta ze stosu save/restore AppKit.
        // Jawne odtworzenie zapobiega przejęciu kontekstu późniejszego PDF-a.
        NSGraphicsContext.current = previousContext
        return bitmap.representation(using: .png, properties: [:])
    }
}
