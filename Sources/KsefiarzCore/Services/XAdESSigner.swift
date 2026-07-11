import Foundation
import Security
import CryptoKit

/// Podpis XAdES-BES (enveloped) dokumentu AuthTokenRequest — uwierzytelnienie
/// w KSeF 2.0 certyfikatem (KSeF typu 1, kwalifikowanym albo self-signed na
/// środowisku testowym).
///
/// Kanonikalizacja (exclusive C14N) jest wykonywana ręcznie: dokument budujemy
/// sami, bajt po bajcie, dokładnie w postaci kanonicznej — elementy bez białych
/// znaków, atrybuty w kolejności kanonicznej, deklaracje przestrzeni nazw
/// dokładnie tam, gdzie umieściłby je algorytm exc-c14n. Dzięki temu skróty
/// liczone są z tych samych bajtów, które zobaczy weryfikator.
public enum XAdESSigner {

    static let authNamespace = "http://ksef.mf.gov.pl/auth/token/2.0"
    static let dsNamespace = "http://www.w3.org/2000/09/xmldsig#"
    static let xadesNamespace = "http://uri.etsi.org/01903/v1.3.2#"
    static let signatureId = "ksefiarz-signature"
    static let signedPropertiesId = "ksefiarz-signed-properties"

    /// Buduje i podpisuje dokument AuthTokenRequest dla podanego wyzwania
    /// i kontekstu NIP. Zwraca kompletny XML gotowy do POST /auth/xades-signature.
    public static func signAuthTokenRequest(
        challenge: String,
        nip: String,
        certificate: KSeFCertificate,
        signingTime: Date = .now
    ) throws -> String {
        guard let info = certificate.info else {
            throw KSeFError.encryptionFailed("Nie udało się odczytać pól certyfikatu do podpisu XAdES.")
        }
        let privateKey = try certificate.privateKey()

        let document = unsignedDocument(challenge: challenge, nip: nip)
        let signedProperties = canonicalSignedProperties(
            certificateDER: certificate.certificateDER,
            issuerName: info.issuerName,
            serialDecimal: info.serialNumberDecimal,
            signingTime: signingTime
        )
        let signedInfo = canonicalSignedInfo(
            documentDigest: sha256Base64(document),
            signedPropertiesDigest: sha256Base64(signedProperties),
            keyType: certificate.keyType
        )
        let signatureValue = try X509Builder.signSHA256(
            Data(signedInfo.utf8),
            privateKey: privateKey,
            keyType: certificate.keyType
        )

        let signature = signatureElement(
            signedInfo: signedInfo,
            signatureValue: signatureValue.base64EncodedString(),
            certificateBase64: certificate.certificateDER.base64EncodedString(),
            signedProperties: signedProperties
        )

        // Podpis enveloped — ostatnie dziecko elementu głównego.
        let closingTag = "</AuthTokenRequest>"
        let signedDocument = document.replacingOccurrences(of: closingTag, with: signature + closingTag)
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + signedDocument
    }

    // MARK: Fragmenty dokumentu (postać kanoniczna)

    /// Dokument bez podpisu — jednocześnie wejście skrótu referencji URI=""
    /// (transformata enveloped usuwa podpis, a exc-c14n zostawia dokładnie
    /// tę postać: jedyna deklaracja to domyślna przestrzeń nazw na korzeniu).
    static func unsignedDocument(challenge: String, nip: String) -> String {
        "<AuthTokenRequest xmlns=\"\(authNamespace)\">"
            + "<Challenge>\(escape(challenge))</Challenge>"
            + "<ContextIdentifier><Nip>\(escape(nip))</Nip></ContextIdentifier>"
            + "<SubjectIdentifierType>certificateSubject</SubjectIdentifierType>"
            + "</AuthTokenRequest>"
    }

    /// SignedProperties w postaci kanonicznej (exc-c14n) — identyczny ciąg
    /// trafia do dokumentu, więc skrót referencji zgadza się z weryfikacją.
    /// Deklaracje xmlns:ds na elementach ds:* są wymagane przez exc-c14n
    /// (żaden przodek wewnątrz kanonikalizowanego poddrzewa ich nie wnosi).
    static func canonicalSignedProperties(
        certificateDER: Data,
        issuerName: String,
        serialDecimal: String,
        signingTime: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let time = formatter.string(from: signingTime)
        let certDigest = sha256Base64(certificateDER)

        return "<xades:SignedProperties xmlns:xades=\"\(xadesNamespace)\" Id=\"\(signedPropertiesId)\">"
            + "<xades:SignedSignatureProperties>"
            + "<xades:SigningTime>\(time)</xades:SigningTime>"
            + "<xades:SigningCertificate>"
            + "<xades:Cert>"
            + "<xades:CertDigest>"
            + "<ds:DigestMethod xmlns:ds=\"\(dsNamespace)\" Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"></ds:DigestMethod>"
            + "<ds:DigestValue xmlns:ds=\"\(dsNamespace)\">\(certDigest)</ds:DigestValue>"
            + "</xades:CertDigest>"
            + "<xades:IssuerSerial>"
            + "<ds:X509IssuerName xmlns:ds=\"\(dsNamespace)\">\(escape(issuerName))</ds:X509IssuerName>"
            + "<ds:X509SerialNumber xmlns:ds=\"\(dsNamespace)\">\(serialDecimal)</ds:X509SerialNumber>"
            + "</xades:IssuerSerial>"
            + "</xades:Cert>"
            + "</xades:SigningCertificate>"
            + "</xades:SignedSignatureProperties>"
            + "</xades:SignedProperties>"
    }

    /// Algorytm podpisu w SignedInfo zależnie od rodzaju klucza.
    static func signatureMethod(for keyType: KSeFKeyType) -> String {
        switch keyType {
        case .rsa: return "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
        case .ec: return "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
        }
    }

    /// SignedInfo w postaci kanonicznej (exc-c14n) — dane wejściowe podpisu.
    static func canonicalSignedInfo(
        documentDigest: String,
        signedPropertiesDigest: String,
        keyType: KSeFKeyType = .rsa
    ) -> String {
        "<ds:SignedInfo xmlns:ds=\"\(dsNamespace)\">"
            + "<ds:CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></ds:CanonicalizationMethod>"
            + "<ds:SignatureMethod Algorithm=\"\(signatureMethod(for: keyType))\"></ds:SignatureMethod>"
            + "<ds:Reference URI=\"\">"
            + "<ds:Transforms>"
            + "<ds:Transform Algorithm=\"http://www.w3.org/2000/09/xmldsig#enveloped-signature\"></ds:Transform>"
            + "<ds:Transform Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></ds:Transform>"
            + "</ds:Transforms>"
            + "<ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"></ds:DigestMethod>"
            + "<ds:DigestValue>\(documentDigest)</ds:DigestValue>"
            + "</ds:Reference>"
            + "<ds:Reference Type=\"http://uri.etsi.org/01903#SignedProperties\" URI=\"#\(signedPropertiesId)\">"
            + "<ds:Transforms>"
            + "<ds:Transform Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></ds:Transform>"
            + "</ds:Transforms>"
            + "<ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"></ds:DigestMethod>"
            + "<ds:DigestValue>\(signedPropertiesDigest)</ds:DigestValue>"
            + "</ds:Reference>"
            + "</ds:SignedInfo>"
    }

    /// Kompletny element ds:Signature. SignedInfo w dokumencie nie powtarza
    /// deklaracji xmlns:ds (dziedziczy ją z ds:Signature) — weryfikator i tak
    /// kanonikalizuje SignedInfo od nowa, dokładając deklarację na wierzchołku.
    private static func signatureElement(
        signedInfo: String,
        signatureValue: String,
        certificateBase64: String,
        signedProperties: String
    ) -> String {
        let inlineSignedInfo = signedInfo.replacingOccurrences(
            of: "<ds:SignedInfo xmlns:ds=\"\(dsNamespace)\">",
            with: "<ds:SignedInfo>"
        )
        return "<ds:Signature xmlns:ds=\"\(dsNamespace)\" Id=\"\(signatureId)\">"
            + inlineSignedInfo
            + "<ds:SignatureValue>\(signatureValue)</ds:SignatureValue>"
            + "<ds:KeyInfo><ds:X509Data><ds:X509Certificate>\(certificateBase64)</ds:X509Certificate></ds:X509Data></ds:KeyInfo>"
            + "<ds:Object>"
            + "<xades:QualifyingProperties xmlns:xades=\"\(xadesNamespace)\" Target=\"#\(signatureId)\">"
            + signedProperties
            + "</xades:QualifyingProperties>"
            + "</ds:Object>"
            + "</ds:Signature>"
    }

    // MARK: Pomocnicze

    static func sha256Base64(_ string: String) -> String {
        KSeFCrypto.sha256Base64(Data(string.utf8))
    }

    static func sha256Base64(_ data: Data) -> String {
        KSeFCrypto.sha256Base64(data)
    }

    /// Ucieczka znaków specjalnych XML w węzłach tekstowych.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
