import Foundation

/// Minimalny koder i czytnik ASN.1 DER — wystarczający do zbudowania
/// wniosku CSR (PKCS#10), certyfikatu self-signed (środowisko testowe)
/// oraz odczytu pól certyfikatu (wystawca, numer seryjny) na potrzeby
/// podpisu XAdES. Nie jest to ogólna biblioteka ASN.1.
enum ASN1DER {

    // MARK: Kodowanie

    /// Koduje długość w formacie DER (krótka lub długa forma).
    static func length(_ count: Int) -> Data {
        precondition(count >= 0)
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    /// Element o podanym tagu i zawartości.
    static func tagged(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + length(content.count) + content
    }

    /// SEQUENCE (0x30).
    static func sequence(_ elements: [Data]) -> Data {
        tagged(0x30, elements.reduce(Data(), +))
    }

    /// SET (0x31).
    static func set(_ elements: [Data]) -> Data {
        tagged(0x31, elements.reduce(Data(), +))
    }

    /// INTEGER z surowych bajtów big-endian (dokłada wiodące zero,
    /// gdy najstarszy bit jest ustawiony — liczby są nieujemne).
    static func integer(rawBytes: Data) -> Data {
        var bytes = Data(rawBytes.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = Data([0]) }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: bytes.startIndex)
        }
        return tagged(0x02, bytes)
    }

    static func integer(_ value: Int) -> Data {
        precondition(value >= 0)
        var bytes: [UInt8] = []
        var v = value
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return integer(rawBytes: Data(bytes))
    }

    /// OBJECT IDENTIFIER z tekstowej postaci kropkowej (np. "2.5.4.97").
    static func objectIdentifier(_ oid: String) -> Data {
        let parts = oid.split(separator: ".").compactMap { UInt64($0) }
        precondition(parts.count >= 2, "OID musi mieć co najmniej dwa człony")
        var content: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for part in parts.dropFirst(2) {
            var encoded: [UInt8] = [UInt8(part & 0x7F)]
            var value = part >> 7
            while value > 0 {
                encoded.insert(UInt8(0x80 | (value & 0x7F)), at: 0)
                value >>= 7
            }
            content.append(contentsOf: encoded)
        }
        return tagged(0x06, Data(content))
    }

    static func utf8String(_ string: String) -> Data {
        tagged(0x0C, Data(string.utf8))
    }

    static func printableString(_ string: String) -> Data {
        tagged(0x13, Data(string.utf8))
    }

    static func bitString(_ data: Data) -> Data {
        // Prefiks 0x00 — liczba nieużywanych bitów w ostatnim bajcie.
        tagged(0x03, Data([0]) + data)
    }

    static func octetString(_ data: Data) -> Data {
        tagged(0x04, data)
    }

    static func null() -> Data {
        Data([0x05, 0x00])
    }

    static func boolean(_ value: Bool) -> Data {
        Data([0x01, 0x01, value ? 0xFF : 0x00])
    }

    /// UTCTime (RRMMDDGGMMSSZ) — format dat ważności certyfikatów do 2049 r.
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }

    /// Element context-specific constructed [n] (np. [0] rozszerzenia w TBS).
    static func contextTag(_ number: UInt8, _ content: Data) -> Data {
        tagged(0xA0 | number, content)
    }

    // MARK: Odczyt

    /// Pojedynczy element ASN.1: tag, zawartość i całkowita długość w bajtach.
    struct Element {
        let tag: UInt8
        let content: Data
        let totalLength: Int
    }

    /// Czyta element od wskazanego miejsca. Zwraca nil przy błędnej strukturze.
    static func readElement(_ data: Data, at offset: Int = 0) -> Element? {
        let bytes = Data(data)  // normalizacja indeksów (Data bywa slice'em)
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[offset]
        var lengthByte = Int(bytes[offset + 1])
        var headerLength = 2
        var contentLength = lengthByte
        if lengthByte & 0x80 != 0 {
            let lengthOfLength = lengthByte & 0x7F
            guard lengthOfLength > 0, offset + 2 + lengthOfLength <= bytes.count else { return nil }
            contentLength = 0
            for i in 0..<lengthOfLength {
                contentLength = (contentLength << 8) | Int(bytes[offset + 2 + i])
            }
            headerLength = 2 + lengthOfLength
        }
        lengthByte = contentLength
        guard offset + headerLength + contentLength <= bytes.count else { return nil }
        let content = bytes.subdata(in: (offset + headerLength)..<(offset + headerLength + contentLength))
        return Element(tag: tag, content: content, totalLength: headerLength + contentLength)
    }

    /// Rozkłada zawartość elementu konstruowanego na listę elementów potomnych.
    static func children(of content: Data) -> [Element] {
        var result: [Element] = []
        var offset = 0
        while offset < content.count, let element = readElement(content, at: offset) {
            result.append(element)
            offset += element.totalLength
        }
        return result
    }

    /// Zamienia bajty big-endian nieujemnej liczby na zapis dziesiętny —
    /// numery seryjne certyfikatów przekraczają zakres Int64.
    static func decimalString(fromBigEndian bytes: Data) -> String {
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                let value = Int(digits[i]) * 256 + carry
                digits[i] = UInt8(value % 10)
                carry = value / 10
            }
            while carry > 0 {
                digits.append(UInt8(carry % 10))
                carry /= 10
            }
        }
        return String(digits.reversed().map { Character(UnicodeScalar(UInt8(48 + $0))) })
    }
}
