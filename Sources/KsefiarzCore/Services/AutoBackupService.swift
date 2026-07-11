import Foundation

/// Automatyczna kopia zapasowa przy starcie aplikacji: jeden plik JSON
/// dziennie w katalogu kopii + rotacja starych plików według ustawień.
/// Dotyczy wyłącznie plików automatycznych (prefiks nazwy) — ręcznych
/// eksportów użytkownika nigdy nie usuwa.
public enum AutoBackupService {

    /// Tryb rotacji starych kopii.
    public enum RotationMode: String, CaseIterable, Identifiable, Sendable {
        /// Zachowaj N najnowszych kopii.
        case keepCount = "count"
        /// Zachowaj kopie z ostatnich N dni.
        case keepDays = "days"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .keepCount: return "liczba kopii"
            case .keepDays: return "dni wstecz"
            }
        }
    }

    /// Prefiks nazw plików automatycznych — rotacja nie dotyka innych plików.
    static let filePrefix = "ksefiarz-auto-"

    /// Domyślny katalog kopii automatycznych.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(
            path: "Ksefiarz/Backups", directoryHint: .isDirectory
        )
    }

    /// Nazwa pliku kopii dziennej (jedna kopia na dzień).
    static func fileName(for date: Date) -> String {
        "\(filePrefix)\(FA2Format.dateFormatter.string(from: date)).json"
    }

    /// Zapisuje dzisiejszą kopię (jeśli jeszcze nie istnieje) i rotuje stare.
    /// `data` jest wywoływane tylko, gdy zapis jest potrzebny.
    /// Zwraca `true`, gdy utworzono nowy plik kopii.
    @discardableResult
    public static func performIfNeeded(
        directory: URL,
        mode: RotationMode,
        keepCount: Int,
        keepDays: Int,
        now: Date = .now,
        data: () throws -> Data
    ) throws -> Bool {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let target = directory.appending(path: fileName(for: now))
        var written = false
        if !fileManager.fileExists(atPath: target.path) {
            try data().write(to: target, options: .atomic)
            written = true
        }
        try rotate(in: directory, mode: mode, keepCount: keepCount, keepDays: keepDays, now: now)
        return written
    }

    /// Usuwa stare kopie automatyczne według trybu rotacji.
    /// Data kopii pochodzi z nazwy pliku (sortowanie leksykalne = chronologiczne).
    static func rotate(
        in directory: URL,
        mode: RotationMode,
        keepCount: Int,
        keepDays: Int,
        now: Date = .now
    ) throws {
        let fileManager = FileManager.default
        let autoBackups = try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(filePrefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // najnowsze najpierw

        let toDelete: [URL]
        switch mode {
        case .keepCount:
            toDelete = Array(autoBackups.dropFirst(max(1, keepCount)))
        case .keepDays:
            let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, keepDays), to: now)!
            toDelete = autoBackups.filter { url in
                guard let date = date(fromFileName: url.lastPathComponent) else { return false }
                return date < cutoff
            }
        }
        for url in toDelete {
            try fileManager.removeItem(at: url)
        }
    }

    /// Odczytuje datę kopii z nazwy pliku automatycznego.
    static func date(fromFileName name: String) -> Date? {
        guard name.hasPrefix(filePrefix), name.hasSuffix(".json") else { return nil }
        let day = name.dropFirst(filePrefix.count).dropLast(".json".count)
        return FA2Format.dateFormatter.date(from: String(day))
    }
}
