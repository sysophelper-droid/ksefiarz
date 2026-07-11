import Foundation

/// Minimalny zapis archiwum ZIP (metoda „store”, bez kompresji) — bez
/// zależności zewnętrznych. Wystarczający dla paczki księgowej: PDF-y są
/// już skompresowane, a XML/CSV są małe. Nazwy plików kodowane w UTF-8
/// (flaga bitu 11 — poprawne polskie znaki w macOS/Windows).
public struct ZipWriter {

    private struct Entry {
        let fileName: Data
        let crc32: UInt32
        let size: UInt32
        let offset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private var output = Data()
    private var entries: [Entry] = []

    public init() {}

    /// Dodaje plik pod wskazaną ścieżką wewnątrz archiwum (separator „/”).
    public mutating func addFile(path: String, data: Data, date: Date = .now) {
        let name = Data(path.utf8)
        let crc = Self.crc32(data)
        let (dosTime, dosDate) = Self.dosDateTime(from: date)
        let offset = UInt32(output.count)

        // Local file header.
        output.append(le32(0x04034B50))
        output.append(le16(20))            // wersja wymagana: 2.0
        output.append(le16(1 << 11))       // flaga: nazwy w UTF-8
        output.append(le16(0))             // metoda: store
        output.append(le16(dosTime))
        output.append(le16(dosDate))
        output.append(le32(crc))
        output.append(le32(UInt32(data.count)))
        output.append(le32(UInt32(data.count)))
        output.append(le16(UInt16(name.count)))
        output.append(le16(0))             // extra length
        output.append(name)
        output.append(data)

        entries.append(Entry(
            fileName: name, crc32: crc, size: UInt32(data.count),
            offset: offset, dosTime: dosTime, dosDate: dosDate
        ))
    }

    /// Zamyka archiwum (central directory + end record) i zwraca bajty ZIP.
    public func finalized() -> Data {
        var archive = output
        let directoryOffset = UInt32(archive.count)

        for entry in entries {
            archive.append(le32(0x02014B50))
            // Wersja twórcy: górny bajt = system Unix (3) — bez tego unzip
            // ignoruje flagę UTF-8 i przekłamuje polskie znaki w nazwach.
            archive.append(le16(3 << 8 | 20))
            archive.append(le16(20))       // wersja wymagana
            archive.append(le16(1 << 11))  // UTF-8
            archive.append(le16(0))        // store
            archive.append(le16(entry.dosTime))
            archive.append(le16(entry.dosDate))
            archive.append(le32(entry.crc32))
            archive.append(le32(entry.size))
            archive.append(le32(entry.size))
            archive.append(le16(UInt16(entry.fileName.count)))
            archive.append(le16(0))        // extra
            archive.append(le16(0))        // comment
            archive.append(le16(0))        // disk
            archive.append(le16(0))        // internal attrs
            // Atrybuty zewnętrzne: uniksowy tryb zwykłego pliku 0644
            // (przy twórcy Unix zerowe atrybuty dawałyby chmod 000).
            archive.append(le32(UInt32(0o100644) << 16))
            archive.append(le32(entry.offset))
            archive.append(entry.fileName)
        }

        let directorySize = UInt32(archive.count) - directoryOffset
        archive.append(le32(0x06054B50))
        archive.append(le16(0))            // disk
        archive.append(le16(0))            // disk z katalogiem
        archive.append(le16(UInt16(entries.count)))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le32(directorySize))
        archive.append(le32(directoryOffset))
        archive.append(le16(0))            // komentarz
        return archive
    }

    // MARK: Pomocnicze

    private func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// CRC-32 (IEEE 802.3, odwrócony wielomian 0xEDB88320) — wymagany
    /// przez format ZIP.
    static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Data/czas w formacie MS-DOS (lokalna strefa — konwencja ZIP).
    static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let year = max(1980, parts.year ?? 1980)
        let dosDate = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        let dosTime = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        return (dosTime, dosDate)
    }
}
