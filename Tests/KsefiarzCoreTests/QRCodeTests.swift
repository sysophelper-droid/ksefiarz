import Foundation
import Security
import CryptoKit
import Testing
@testable import KsefiarzCore

@Suite("KSeFVerificationLink — linki weryfikacyjne kodów QR")
struct KSeFVerificationLinkTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: 12)
        components.timeZone = TimeZone(identifier: "Europe/Warsaw")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("KOD I odtwarza przykład z oficjalnej dokumentacji (kody-qr.md)")
    func kod1MatchesDocsExample() throws {
        // Skrót z przykładu: Base64URL "UtQp9Gpc51y-u3xApZjIjgkpZ01js-J8KflSPW8WzIE".
        let hashData = try #require(Data(
            base64Encoded: "UtQp9Gpc51y+u3xApZjIjgkpZ01js+J8KflSPW8WzIE="
        ))
        let url = KSeFVerificationLink.invoiceURL(
            environment: .test,
            sellerNIP: "1111111111",
            issueDate: date(2026, 2, 1),
            xmlHashBase64: hashData.base64EncodedString()
        )
        #expect(url == "https://qr-test.ksef.mf.gov.pl/invoice/1111111111/01-02-2026/UtQp9Gpc51y-u3xApZjIjgkpZ01js-J8KflSPW8WzIE")
    }

    @Test("Hosty QR per środowisko (produkcja bez sufiksu)")
    func hosts() {
        #expect(KSeFVerificationLink.qrHost(for: .production) == "qr.ksef.mf.gov.pl")
        #expect(KSeFVerificationLink.qrHost(for: .demo) == "qr-demo.ksef.mf.gov.pl")
        #expect(KSeFVerificationLink.qrHost(for: .test) == "qr-test.ksef.mf.gov.pl")
    }

    @Test("Base64URL: zamiana +/ na -_ i zrzucenie dopełnienia")
    func base64URL() {
        #expect(KSeFVerificationLink.base64URL(fromBase64: "ab+cd/ef==") == "ab-cd_ef")
        #expect(KSeFVerificationLink.base64URL(fromBase64: "UtQp9Gpc51y+u3xApZjIjgkpZ01js+J8KflSPW8WzIE=")
            == "UtQp9Gpc51y-u3xApZjIjgkpZ01js-J8KflSPW8WzIE")
    }

    @Test("KOD II (RSA): struktura URL i podpis RSASSA-PSS weryfikowalny kluczem certyfikatu")
    func kod2RSA() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Offline"), .countryName("PL")],
            privateKey: key
        )
        let certificate = KSeFCertificate(
            certificateDER: der,
            privateKeyDER: try X509Builder.exportPrivateKey(key)
        )
        let hashBase64 = KSeFCrypto.sha256Base64(Data("faktura".utf8))
        let url = try KSeFVerificationLink.certificateURL(
            environment: .production,
            contextNip: "1111111111",
            sellerNIP: "1111111111",
            certificate: certificate,
            xmlHashBase64: hashBase64
        )

        let expectedPath = "qr.ksef.mf.gov.pl/certificate/Nip/1111111111/1111111111/\(certificate.serialNumberHex)/\(KSeFVerificationLink.base64URL(fromBase64: hashBase64))"
        #expect(url.hasPrefix("https://\(expectedPath)/"))

        // Ostatni segment to podpis PSS ścieżki (bez https:// i bez podpisu).
        let signatureSegment = String(url.split(separator: "/").last!)
        var base64 = signatureSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        let signature = try #require(Data(base64Encoded: base64))
        #expect(signature.count == 256) // RSA-2048

        let publicKey = try #require(SecKeyCopyPublicKey(key))
        #expect(SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePSSSHA256,
            Data(expectedPath.utf8) as CFData, signature as CFData, nil
        ))
    }

    @Test("KOD II (EC): podpis ECDSA P1363 (R‖S, 64 bajty) weryfikowalny przez CryptoKit")
    func kod2EC() throws {
        let key = try X509Builder.generateECKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Offline EC"), .countryName("PL")],
            privateKey: key,
            keyType: .ec
        )
        let certificate = KSeFCertificate(
            certificateDER: der,
            privateKeyDER: try X509Builder.exportPrivateKey(key),
            keyType: .ec
        )
        let hashBase64 = KSeFCrypto.sha256Base64(Data("faktura-ec".utf8))
        let url = try KSeFVerificationLink.certificateURL(
            environment: .test,
            contextNip: "2222222222",
            sellerNIP: "2222222222",
            certificate: certificate,
            xmlHashBase64: hashBase64
        )
        let signatureSegment = String(url.split(separator: "/").last!)
        var base64 = signatureSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        let signature = try #require(Data(base64Encoded: base64))
        #expect(signature.count == 64) // P-256: R‖S po 32 bajty

        let signedPath = String(url.dropFirst("https://".count).dropLast(signatureSegment.count + 1))
        let publicKeyData = try #require(SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil)) as Data
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        #expect(publicKey.isValidSignature(ecdsa, for: Data(signedPath.utf8)))
    }

    @Test("Renderer QR tworzy obraz dla linku")
    func qrImage() {
        let image = QRCodeRenderer.image(for: "https://qr.ksef.mf.gov.pl/invoice/1/01-01-2026/abc")
        #expect(image != nil)
        #expect((image?.width ?? 0) > 100)
    }
}

@Suite("InvoicePDFGenerator — kody QR na wizualizacji")
@MainActor
struct InvoicePDFQRTests {

    private func makeInvoice(ksefId: String?, offline: Bool) -> Invoice {
        let xml = "<Faktura>test-qr</Faktura>"
        let invoice = Invoice(
            ksefId: ksefId,
            invoiceNumber: "FV/QR/1",
            issueDate: .now,
            sellerName: "A", sellerNIP: "1111111111",
            buyerName: "B", buyerNIP: "2222222222",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            rawXmlContent: xml,
            ksefSubmissionStatus: offline ? .offlinePending : (ksefId != nil ? .accepted : .local),
            ksefEnvironmentRaw: "test",
            kind: .sales
        )
        if offline {
            invoice.isOfflineMode = true
            invoice.offlineHashBase64 = KSeFCrypto.sha256Base64(Data(xml.utf8))
        }
        return invoice
    }

    private func makeOfflineCertificate() throws -> KSeFCertificate {
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Offline"), .countryName("PL")],
            privateKey: key
        )
        return KSeFCertificate(certificateDER: der, privateKeyDER: try X509Builder.exportPrivateKey(key))
    }

    @Test("Faktura z numerem KSeF: KOD I z numerem w etykiecie, bez KODU II")
    func onlineInvoice() {
        let ksefNumber = "1111111111-20260711-AAAAAAAAAAAA-AA"
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: makeInvoice(ksefId: ksefNumber, offline: false),
            offlineCertificate: nil
        )
        #expect(codes != nil)
        #expect(codes?.verificationLabel == ksefNumber)
        #expect(codes?.certificate == nil)
        #expect(codes?.certificateNote == nil)
    }

    @Test("Dokument offline: KOD I z etykietą OFFLINE i KOD II z certyfikatem typu 2")
    func offlineInvoiceWithCertificate() throws {
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: makeInvoice(ksefId: nil, offline: true),
            offlineCertificate: try makeOfflineCertificate()
        )
        #expect(codes?.verificationLabel == "OFFLINE")
        #expect(codes?.certificate != nil)
        #expect(codes?.certificateNote == nil)
    }

    @Test("Dokument offline bez certyfikatu typu 2 dostaje ostrzeżenie zamiast KODU II")
    func offlineInvoiceWithoutCertificate() {
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: makeInvoice(ksefId: nil, offline: true),
            offlineCertificate: nil
        )
        #expect(codes?.verificationLabel == "OFFLINE")
        #expect(codes?.certificate == nil)
        #expect(codes?.certificateNote?.isEmpty == false)
    }

    @Test("Faktura lokalna (bez KSeF, nie offline) nie dostaje kodów QR")
    func localInvoice() {
        let codes = InvoicePDFGenerator.makeQRCodes(
            for: makeInvoice(ksefId: nil, offline: false),
            offlineCertificate: nil
        )
        #expect(codes == nil)
    }

    @Test("PDF dokumentu offline generuje się z kodami QR (paginacja z rezerwą)")
    func pdfRenders() throws {
        let invoice = makeInvoice(ksefId: nil, offline: true)
        let pdf = InvoicePDFGenerator.pdfData(for: invoice)
        #expect(pdf != nil)
        #expect((pdf?.count ?? 0) > 1000)
    }
}
