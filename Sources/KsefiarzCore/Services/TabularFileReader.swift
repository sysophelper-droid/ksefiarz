import Foundation

public enum TabularFileReaderError: LocalizedError, Equatable {
    case unsupportedFormat
    case unreadableFile
    case fileTooLarge
    case emptyFile
    case invalidCSVEncoding
    case invalidWorkbook(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Obsługiwane są pliki CSV, TSV i Excel (.xlsx)."
        case .unreadableFile:
            return "Nie można odczytać wybranego pliku."
        case .fileTooLarge:
            return "Plik lub arkusz jest zbyt duży (limit 64 MB)."
        case .emptyFile:
            return "Plik nie zawiera tabeli z nagłówkami i danymi."
        case .invalidCSVEncoding:
            return "Nie rozpoznano kodowania pliku tekstowego (obsługiwane: UTF-8, UTF-16 i Windows-1250)."
        case let .invalidWorkbook(reason):
            return "Nie można odczytać skoroszytu Excel: \(reason)"
        }
    }
}

/// Czytnik plików wejściowych importu. CSV jest parsowany bez zależności,
/// a XLSX jako standardowy pakiet Office Open XML — czytany wyłącznie z
/// wymaganych wpisów przez systemowy `unzip`, bez rozpakowywania obcych ścieżek.
public enum TabularFileReader {
    private static let maximumSize = 64 * 1024 * 1024

    public static func read(url: URL) throws -> TabularSheet {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv", "tsv", "txt":
            return try readDelimited(url: url, forcedDelimiter: ext == "tsv" ? "\t" : nil)
        case "xlsx":
            return try XLSXReader.read(url: url)
        default:
            throw TabularFileReaderError.unsupportedFormat
        }
    }

    public static func parseCSV(_ text: String, name: String = "CSV", delimiter: Character? = nil) throws -> TabularSheet {
        let rows = CSVParser.parse(text, delimiter: delimiter ?? CSVParser.detectDelimiter(in: text))
        return try normalizedSheet(name: name, rows: rows)
    }

    private static func readDelimited(url: URL, forcedDelimiter: Character?) throws -> TabularSheet {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            throw TabularFileReaderError.unreadableFile
        }
        guard size.intValue <= maximumSize else { throw TabularFileReaderError.fileTooLarge }
        guard let data = try? Data(contentsOf: url) else { throw TabularFileReaderError.unreadableFile }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1250)
        }
        guard let text else {
            throw TabularFileReaderError.invalidCSVEncoding
        }
        return try parseCSV(text, name: url.deletingPathExtension().lastPathComponent, delimiter: forcedDelimiter)
    }

    fileprivate static func normalizedSheet(name: String, rows: [[String]]) throws -> TabularSheet {
        var rows = rows
        while let first = rows.first, first.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.removeFirst()
        }
        while let last = rows.last, last.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.removeLast()
        }
        guard rows.count >= 2, let header = rows.first, header.contains(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw TabularFileReaderError.emptyFile
        }
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { row in row + Array(repeating: "", count: max(0, width - row.count)) }
        if !rows[0].isEmpty {
            rows[0][0] = rows[0][0].replacingOccurrences(of: "\u{FEFF}", with: "")
        }
        return TabularSheet(name: name, rows: rows)
    }
}

private enum CSVParser {
    static func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [";", ",", "\t"]
        let sample = String(text.replacingOccurrences(of: "\r\n", with: "\n").prefix(16_384))
        var counts = Dictionary(uniqueKeysWithValues: candidates.map { ($0, [Int]()) })
        var current = Dictionary(uniqueKeysWithValues: candidates.map { ($0, 0) })
        var quoted = false
        var lines = 0
        var index = sample.startIndex
        while index < sample.endIndex {
            let character = sample[index]
            let next = sample.index(after: index)
            if character == "\"" {
                if quoted, next < sample.endIndex, sample[next] == "\"" {
                    index = sample.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if !quoted {
                if candidates.contains(character) { current[character, default: 0] += 1 }
                if character == "\n" {
                    candidates.forEach { counts[$0, default: []].append(current[$0, default: 0]) }
                    current = Dictionary(uniqueKeysWithValues: candidates.map { ($0, 0) })
                    lines += 1
                    if lines >= 8 { break }
                }
            }
            index = next
        }
        if lines == 0 || current.values.contains(where: { $0 > 0 }) {
            candidates.forEach { counts[$0, default: []].append(current[$0, default: 0]) }
        }
        // Nagłówek jest najlepszym sygnałem: przecinki dziesiętne w danych
        // nie mogą wygrać ze średnikiem rozdzielającym kolumny.
        return candidates.max {
            let left = counts[$0]?.first ?? 0
            let right = counts[$1]?.first ?? 0
            if left != right { return left < right }
            return (counts[$0]?.reduce(0, +) ?? 0) < (counts[$1]?.reduce(0, +) ?? 0)
        } ?? ";"
    }

    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        func finishField() {
            row.append(field)
            field = ""
        }
        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        field.append("\"")
                        index = text.index(after: nextIndex)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else if character == "\"", field.isEmpty {
                quoted = true
            } else if character == delimiter {
                finishField()
            } else if character == "\n" {
                finishRow()
            } else {
                field.append(character)
            }
            index = nextIndex
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }
}

// MARK: - Excel / Office Open XML

private enum XLSXReader {
    static func read(url: URL) throws -> TabularSheet {
        let archive = XLSXArchive(url: url)
        let workbookData = try archive.requiredEntry("xl/workbook.xml")
        let relationshipsData = try archive.requiredEntry("xl/_rels/workbook.xml.rels")
        let workbook = try WorkbookXML.parse(workbookData)
        let relationships = try RelationshipsXML.parse(relationshipsData)
        guard let sheet = workbook.sheets.first,
              let target = relationships[sheet.relationshipID] else {
            throw TabularFileReaderError.invalidWorkbook("brak pierwszego arkusza")
        }
        let sheetPath = normalizedSheetPath(target)
        let sharedStrings = (try? archive.optionalEntry("xl/sharedStrings.xml"))
            .flatMap { try? SharedStringsXML.parse($0) } ?? []
        let cellStyles = (try? archive.optionalEntry("xl/styles.xml"))
            .flatMap { try? StylesXML.parse($0) } ?? []
        let rows = try SheetXML.parse(
            try archive.requiredEntry(sheetPath),
            sharedStrings: sharedStrings,
            cellStyles: cellStyles,
            uses1904Dates: workbook.uses1904Dates
        )
        return try TabularFileReader.normalizedSheet(name: sheet.name, rows: rows)
    }

    private static func normalizedSheetPath(_ target: String) -> String {
        var target = target.replacingOccurrences(of: "\\", with: "/")
        if target.hasPrefix("/") { target.removeFirst() }
        if !target.hasPrefix("xl/") { target = "xl/\(target)" }
        let components = target.split(separator: "/").reduce(into: [Substring]()) { result, part in
            if part == ".." { if !result.isEmpty { result.removeLast() } }
            else if part != "." { result.append(part) }
        }
        return components.joined(separator: "/")
    }
}

private struct XLSXArchive {
    let url: URL

    func requiredEntry(_ path: String) throws -> Data {
        guard let data = try optionalEntry(path) else {
            throw TabularFileReaderError.invalidWorkbook("brak wpisu \(path)")
        }
        return data
    }

    func optionalEntry(_ path: String) throws -> Data? {
        let listing = try run(arguments: ["-l", url.path, path])
        guard listing.status == 0 else { return nil }
        let listingText = String(decoding: listing.output, as: UTF8.self)
        let size = listingText.split(separator: "\n").compactMap { line -> Int? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.last == Substring(path), let first = parts.first else { return nil }
            return Int(first)
        }.first
        guard let size else { return nil }
        guard size <= 64 * 1024 * 1024 else { throw TabularFileReaderError.fileTooLarge }

        let result = try run(arguments: ["-p", url.path, path])
        guard result.status == 0 else { return nil }
        guard result.output.count <= 64 * 1024 * 1024 else { throw TabularFileReaderError.fileTooLarge }
        return result.output
    }

    private func run(arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() }
        catch { throw TabularFileReaderError.unreadableFile }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}

private final class WorkbookXML: NSObject, XMLParserDelegate {
    struct Sheet { var name: String; var relationshipID: String }
    var sheets: [Sheet] = []
    var uses1904Dates = false

    static func parse(_ data: Data) throws -> WorkbookXML {
        let delegate = WorkbookXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TabularFileReaderError.invalidWorkbook("uszkodzony workbook.xml")
        }
        return delegate
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "workbookPr" || elementName.hasSuffix(":workbookPr") {
            uses1904Dates = ["1", "true"].contains(attributeDict["date1904"]?.lowercased() ?? "")
        }
        if elementName == "sheet" || elementName.hasSuffix(":sheet"),
           let name = attributeDict["name"],
           let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] {
            sheets.append(.init(name: name, relationshipID: relationshipID))
        }
    }
}

private final class RelationshipsXML: NSObject, XMLParserDelegate {
    var relationships: [String: String] = [:]

    static func parse(_ data: Data) throws -> [String: String] {
        let delegate = RelationshipsXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TabularFileReaderError.invalidWorkbook("uszkodzony plik relacji")
        }
        return delegate.relationships
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship" || elementName.hasSuffix(":Relationship"),
              let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        relationships[id] = target
    }
}

private final class SharedStringsXML: NSObject, XMLParserDelegate {
    var values: [String] = []
    private var current = ""
    private var capturesText = false

    static func parse(_ data: Data) throws -> [String] {
        let delegate = SharedStringsXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TabularFileReaderError.invalidWorkbook("uszkodzona tabela tekstów")
        }
        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { capturesText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { capturesText = false }
        if elementName == "si" { values.append(current) }
    }
}

private final class StylesXML: NSObject, XMLParserDelegate {
    struct CellStyle {
        var isDate: Bool
        var zeroPadWidth: Int?
    }

    private var customFormats: [Int: String] = [:]
    private var cellStyles: [CellStyle] = []
    private var insideCellFormats = false

    static func parse(_ data: Data) throws -> [CellStyle] {
        let delegate = StylesXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TabularFileReaderError.invalidWorkbook("uszkodzone style")
        }
        return delegate.cellStyles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "numFmt", let id = attributeDict["numFmtId"].flatMap(Int.init),
           let code = attributeDict["formatCode"] {
            customFormats[id] = code
        } else if elementName == "cellXfs" {
            insideCellFormats = true
        } else if elementName == "xf", insideCellFormats,
                  let id = attributeDict["numFmtId"].flatMap(Int.init) {
            let code = customFormats[id]
            cellStyles.append(.init(
                isDate: Self.isDateFormat(id: id, code: code),
                zeroPadWidth: Self.zeroPadWidth(code: code)
            ))
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "cellXfs" { insideCellFormats = false }
    }

    private static func isDateFormat(id: Int, code: String?) -> Bool {
        if (14...22).contains(id) || (27...36).contains(id) || (45...47).contains(id) || (50...58).contains(id) {
            return true
        }
        guard var code = code?.lowercased() else { return false }
        code = code.replacingOccurrences(of: #"\\."#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        return code.contains("yy") || code.contains("dd")
    }

    private static func zeroPadWidth(code: String?) -> Int? {
        guard let code else { return nil }
        let plain = code.trimmingCharacters(in: .whitespaces)
        guard !plain.isEmpty, plain.allSatisfy({ $0 == "0" }) else { return nil }
        return plain.count
    }
}

private final class SheetXML: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let cellStyles: [StylesXML.CellStyle]
    private let uses1904Dates: Bool
    private var rows: [[String]] = []
    private var currentRow: [String] = []
    private var cellColumn = 0
    private var nextColumn = 0
    private var cellType = ""
    private var cellStyle: Int?
    private var cellValue = ""
    private var capturesValue = false

    init(sharedStrings: [String], cellStyles: [StylesXML.CellStyle], uses1904Dates: Bool) {
        self.sharedStrings = sharedStrings
        self.cellStyles = cellStyles
        self.uses1904Dates = uses1904Dates
    }

    static func parse(_ data: Data, sharedStrings: [String], cellStyles: [StylesXML.CellStyle], uses1904Dates: Bool) throws -> [[String]] {
        let delegate = SheetXML(sharedStrings: sharedStrings, cellStyles: cellStyles, uses1904Dates: uses1904Dates)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw TabularFileReaderError.invalidWorkbook("uszkodzony arkusz")
        }
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            currentRow = []
            nextColumn = 0
        } else if elementName == "c" {
            cellColumn = attributeDict["r"].map(Self.columnIndex) ?? nextColumn
            nextColumn = cellColumn + 1
            cellType = attributeDict["t"] ?? ""
            cellStyle = attributeDict["s"].flatMap(Int.init)
            cellValue = ""
        } else if elementName == "v" || (elementName == "t" && cellType == "inlineStr") {
            capturesValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesValue { cellValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" { capturesValue = false }
        if elementName == "c" {
            while currentRow.count <= cellColumn { currentRow.append("") }
            currentRow[cellColumn] = resolvedCellValue()
        } else if elementName == "row" {
            rows.append(currentRow)
        }
    }

    private func resolvedCellValue() -> String {
        switch cellType {
        case "s":
            guard let index = Int(cellValue), sharedStrings.indices.contains(index) else { return "" }
            return sharedStrings[index]
        case "b": return cellValue == "1" ? "tak" : "nie"
        case "inlineStr", "str", "e": return cellValue
        default:
            guard let number = Double(cellValue) else { return cellValue }
            if let style = cellStyle, cellStyles.indices.contains(style) {
                if cellStyles[style].isDate {
                    return Self.excelDate(number, uses1904Dates: uses1904Dates)
                }
                if let width = cellStyles[style].zeroPadWidth, number.rounded() == number {
                    return String(format: "%0*lld", width, Int64(number))
                }
            }
            return number.rounded() == number ? String(format: "%.0f", number) : String(number)
        }
    }

    private static func columnIndex(_ reference: String) -> Int {
        var result = 0
        for scalar in reference.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(0, result - 1)
    }

    private static func excelDate(_ serial: Double, uses1904Dates: Bool) -> String {
        let reference = uses1904Dates
            ? Date(timeIntervalSince1970: -2_082_844_800) // 1904-01-01 UTC
            : Date(timeIntervalSince1970: -2_209_075_200) // 1899-12-31 UTC
        // Excel zachowuje historyczny, fikcyjny 29.02.1900 (serial 60).
        // Dla późniejszych dat odejmujemy ten jeden nieistniejący dzień.
        let correctedSerial = !uses1904Dates && serial >= 60 ? serial - 1 : serial
        let date = reference.addingTimeInterval(correctedSerial * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = serial.truncatingRemainder(dividingBy: 1) == 0
            ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
