import Foundation
import Security
import CoreImage

/// Linki weryfikacyjne i kody QR wizualizacji faktur KSeF 2.0.
///
/// KOD I (weryfikacja faktury) — wymagany na każdej wizualizacji faktury;
/// etykieta pod kodem: numer KSeF (gdy nadany) albo napis „OFFLINE”.
/// KOD II (poświadczenie wystawcy, etykieta „CERTYFIKAT”) — wymagany
/// wyłącznie na dokumentach wystawionych w trybie offline; podpisywany
/// kluczem certyfikatu KSeF typu 2 (Offline).
public enum KSeFVerificationLink {

    /// Host bramki weryfikacyjnej QR dla środowiska.
    public static func qrHost(for environment: KSeFEnvironment) -> String {
        switch environment {
        case .test: return "qr-test.ksef.mf.gov.pl"
        case .demo: return "qr-demo.ksef.mf.gov.pl"
        case .production: return "qr.ksef.mf.gov.pl"
        }
    }

    /// Base64URL (bez dopełnienia) — format skrótu w linkach QR.
    public static func base64URL(fromBase64 base64: String) -> String {
        base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Data wystawienia w formacie linku KOD I (DD-MM-RRRR).
    static func linkDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        formatter.timeZone = TimeZone(identifier: "Europe/Warsaw")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// KOD I: `https://{host}/invoice/{NIP}/{DD-MM-RRRR}/{skrót Base64URL}`.
    /// - Parameter xmlHashBase64: skrót SHA-256 pliku XML faktury w Base64
    ///   (dokładnie tych bajtów, które są/będą wysłane do KSeF).
    public static func invoiceURL(
        environment: KSeFEnvironment,
        sellerNIP: String,
        issueDate: Date,
        xmlHashBase64: String
    ) -> String {
        "https://\(qrHost(for: environment))/invoice/\(sellerNIP)/\(linkDate(issueDate))/\(base64URL(fromBase64: xmlHashBase64))"
    }

    /// KOD II: `https://{host}/certificate/Nip/{kontekst}/{NIP}/{seryjny}/{skrót}/{podpis}`.
    /// Podpisywany jest URL bez `https://` i bez segmentu podpisu; podpis:
    /// RSA → RSASSA-PSS (SHA-256, MGF1, sól 32 B), EC → ECDSA P1363 (R‖S).
    public static func certificateURL(
        environment: KSeFEnvironment,
        contextNip: String,
        sellerNIP: String,
        certificate: KSeFCertificate,
        xmlHashBase64: String
    ) throws -> String {
        let path = "\(qrHost(for: environment))/certificate/Nip/\(contextNip)/\(sellerNIP)/\(certificate.serialNumberHex)/\(base64URL(fromBase64: xmlHashBase64))"
        let signature = try sign(Data(path.utf8), with: certificate)
        return "https://\(path)/\(base64URL(fromBase64: signature.base64EncodedString()))"
    }

    /// Podpis treści KODU II kluczem certyfikatu offline.
    static func sign(_ data: Data, with certificate: KSeFCertificate) throws -> Data {
        let privateKey = try certificate.privateKey()
        switch certificate.keyType {
        case .rsa:
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePSSSHA256,
                data as CFData,
                &error
            ) else {
                let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
                throw KSeFError.encryptionFailed("Podpis RSASSA-PSS nie powiódł się: \(details)")
            }
            return signature as Data
        case .ec:
            return try X509Builder.signSHA256(data, privateKey: privateKey, keyType: .ec)
        }
    }
}

/// Rysowanie kodów QR (CoreImage) do osadzenia na wydruku PDF.
public enum QRCodeRenderer {

    /// Generuje obraz QR dla podanego tekstu; `scale` mnoży rozmiar modułu.
    public static func image(for text: String, scale: CGFloat = 8) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
