import Foundation

/// Załącznik do faktury FA(3) — element `Zalacznik` schematu
/// (bloki danych z metadanymi, częścią tekstową i tabelami).
/// Struktura odpowiada XSD; na fakturze (`Invoice.attachmentJSON`)
/// przechowywana jako JSON.
public struct FA3AttachmentBlock: Codable, Equatable, Sendable, Identifiable {
    /// Para klucz–wartość danych opisowych (MetaDane/ZKlucz+ZWartosc).
    /// XSD wymaga co najmniej jednej pary w każdym bloku.
    public struct Meta: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var key: String
        public var value: String

        public init(id: UUID = UUID(), key: String = "", value: String = "") {
            self.id = id
            self.key = key
            self.value = value
        }

        /// Porównanie merytoryczne — identyfikator (potrzebny SwiftUI)
        /// nie decyduje o równości danych.
        public static func == (lhs: Meta, rhs: Meta) -> Bool {
            lhs.key == rhs.key && lhs.value == rhs.value
        }
    }

    /// Tabela załącznika (Tabela): nagłówek kolumn (TNaglowek/Kol/NKom,
    /// wszystkie jako typ "txt"), wiersze (Wiersz/WKom) i opcjonalne
    /// podsumowanie (Suma/SKom). Limity XSD: 20 kolumn, 1000 wierszy.
    public struct Table: Codable, Equatable, Sendable {
        public var description: String
        public var columns: [String]
        public var rows: [[String]]
        public var summary: [String]

        public init(
            description: String = "",
            columns: [String] = [],
            rows: [[String]] = [],
            summary: [String] = []
        ) {
            self.description = description
            self.columns = columns
            self.rows = rows
            self.summary = summary
        }
    }

    public var id: UUID
    /// Nagłówek bloku (ZNaglowek, do 512 znaków).
    public var header: String
    /// Dane opisowe — co najmniej jedna para (wymóg XSD).
    public var metadata: [Meta]
    /// Akapity części tekstowej (Tekst/Akapit, maks. 10 po 512 znaków).
    public var paragraphs: [String]
    /// Tabele bloku.
    public var tables: [Table]

    public init(
        id: UUID = UUID(),
        header: String = "",
        metadata: [Meta] = [Meta()],
        paragraphs: [String] = [],
        tables: [Table] = []
    ) {
        self.id = id
        self.header = header
        self.metadata = metadata
        self.paragraphs = paragraphs
        self.tables = tables
    }

    /// Porównanie merytoryczne — bez identyfikatora SwiftUI.
    public static func == (lhs: FA3AttachmentBlock, rhs: FA3AttachmentBlock) -> Bool {
        lhs.header == rhs.header
            && lhs.metadata == rhs.metadata
            && lhs.paragraphs == rhs.paragraphs
            && lhs.tables == rhs.tables
    }
}

public extension Array where Element == FA3AttachmentBlock {
    /// Serializacja do JSON przechowywanego w `Invoice.attachmentJSON`.
    func encodedJSON() -> String {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Odtworzenie z JSON — pusty/uszkodzony zapis daje pustą listę.
    static func decoded(from json: String) -> [FA3AttachmentBlock] {
        guard !json.isEmpty,
              let blocks = try? JSONDecoder().decode(
                  [FA3AttachmentBlock].self, from: Data(json.utf8)
              ) else { return [] }
        return blocks
    }
}
