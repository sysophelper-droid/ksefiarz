import Foundation

/// Polski kalendarz dni roboczych — wyznaczanie terminu dosłania faktur
/// offline24 do KSeF (następny dzień roboczy po dacie wystawienia).
/// Dni wolne: soboty, niedziele i ustawowe święta (z ruchomymi: Poniedziałek
/// Wielkanocny i Boże Ciało; Wigilia jest dniem wolnym od 2025 r.).
public enum PolishBusinessCalendar {

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current
        return calendar
    }

    /// Niedziela Wielkanocna danego roku (algorytm Meeusa/Butchera).
    static func easterSunday(year: Int) -> DateComponents {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return DateComponents(year: year, month: month, day: day)
    }

    /// Święta ustawowo wolne od pracy w danym roku jako pary (miesiąc, dzień).
    static func holidays(year: Int) -> Set<[Int]> {
        var days: Set<[Int]> = [
            [1, 1],   // Nowy Rok
            [1, 6],   // Trzech Króli
            [5, 1],   // Święto Pracy
            [5, 3],   // Konstytucja 3 Maja
            [8, 15],  // Wniebowzięcie NMP
            [11, 1],  // Wszystkich Świętych
            [11, 11], // Święto Niepodległości
            [12, 25], // Boże Narodzenie
            [12, 26], // drugi dzień świąt
        ]
        if year >= 2025 {
            days.insert([12, 24]) // Wigilia — wolna od 2025 r.
        }
        let easter = easterSunday(year: year)
        let calendar = Self.calendar
        if let easterDate = calendar.date(from: easter) {
            // Poniedziałek Wielkanocny (+1) i Boże Ciało (+60).
            for offset in [1, 60] {
                if let date = calendar.date(byAdding: .day, value: offset, to: easterDate) {
                    let components = calendar.dateComponents([.month, .day], from: date)
                    days.insert([components.month!, components.day!])
                }
            }
        }
        return days
    }

    /// Czy wskazany dzień jest dniem roboczym (pn–pt poza świętami).
    public static func isBusinessDay(_ date: Date) -> Bool {
        let calendar = Self.calendar
        let weekday = calendar.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false } // niedziela, sobota
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return !holidays(year: components.year!).contains([components.month!, components.day!])
    }

    /// Pierwszy dzień roboczy PO wskazanej dacie.
    public static func nextBusinessDay(after date: Date) -> Date {
        let calendar = Self.calendar
        var day = calendar.startOfDay(for: date)
        repeat {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        } while !isBusinessDay(day)
        return day
    }

    /// Koniec (23:59:59) następnego dnia roboczego — termin dosłania
    /// dokumentu offline24 do KSeF.
    public static func endOfNextBusinessDay(after date: Date) -> Date {
        let day = nextBusinessDay(after: date)
        return Self.calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day)!
    }

    /// Koniec (23:59:59) N-tego dnia roboczego PO wskazanej dacie —
    /// np. termin dosłania po awarii KSeF to 7. dzień roboczy od jej
    /// zakończenia (art. 106nf ustawy o VAT).
    public static func endOfBusinessDay(after date: Date, businessDays: Int) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<max(1, businessDays) {
            day = nextBusinessDay(after: day)
        }
        return Self.calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day)!
    }
}
