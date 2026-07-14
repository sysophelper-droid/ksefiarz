import Foundation

/// Etap windykacji faktury sprzedażowej — wyprowadzany z działań
/// odnotowanych na fakturze. Ścieżka eskalacji:
/// przypomnienie → wezwanie do zapłaty → nota odsetkowa → dane do EPU.
public enum DebtCollectionStage: Int, CaseIterable, Comparable, Sendable {
    case none = 0
    case reminded = 1
    case demanded = 2
    case interestNoted = 3
    case epuPrepared = 4

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .none: return "Bez działań"
        case .reminded: return "Przypomnienie wysłane"
        case .demanded: return "Wezwanie wysłane"
        case .interestNoted: return "Nota odsetkowa wystawiona"
        case .epuPrepared: return "Dane do EPU przygotowane"
        }
    }
}

/// Działanie windykacyjne odnotowywane na fakturze.
public enum DebtCollectionAction: String, CaseIterable, Sendable {
    case reminder = "przypomnienie"
    case demand = "wezwanie"
    case interestNote = "nota"
    case epu = "epu"

    public var displayName: String {
        switch self {
        case .reminder: return "Przypomnienie o płatności"
        case .demand: return "Wezwanie do zapłaty"
        case .interestNote: return "Nota odsetkowa"
        case .epu: return "Dane do pozwu EPU (e-sąd)"
        }
    }

    /// Etap, na który przechodzi faktura po odnotowaniu działania.
    public var stage: DebtCollectionStage {
        switch self {
        case .reminder: return .reminded
        case .demand: return .demanded
        case .interestNote: return .interestNoted
        case .epu: return .epuPrepared
        }
    }
}

/// Sugerowany następny krok windykacji z krótkim uzasadnieniem.
public struct DebtCollectionSuggestion: Equatable, Sendable {
    public let action: DebtCollectionAction
    public let reason: String
}

/// Progi czasowe eskalacji (dni kalendarzowe). Wartości domyślne są
/// zachowawcze — użytkownik może eskalować wcześniej ręcznie, silnik tylko
/// podpowiada moment kolejnego kroku.
public struct DebtCollectionPolicy: Equatable, Sendable {
    /// Wezwanie sugerowane, gdy zaległość trwa co najmniej tyle dni…
    public var demandAfterDaysOverdue: Int
    /// …i od przypomnienia minęło co najmniej tyle dni.
    public var demandAfterReminderDays: Int
    /// Nota odsetkowa sugerowana tyle dni po wezwaniu bez zapłaty.
    public var noteAfterDemandDays: Int
    /// Dane do EPU sugerowane tyle dni po nocie bez zapłaty.
    public var epuAfterNoteDays: Int

    public init(
        demandAfterDaysOverdue: Int = 14,
        demandAfterReminderDays: Int = 7,
        noteAfterDemandDays: Int = 14,
        epuAfterNoteDays: Int = 14
    ) {
        self.demandAfterDaysOverdue = demandAfterDaysOverdue
        self.demandAfterReminderDays = demandAfterReminderDays
        self.noteAfterDemandDays = noteAfterDemandDays
        self.epuAfterNoteDays = epuAfterNoteDays
    }
}

/// Ścieżka windykacji należności: status z odnotowanych działań, sugestia
/// kolejnego kroku eskalacji oraz przygotowanie danych do pozwu
/// w elektronicznym postępowaniu upominawczym (EPU, e-sad.gov.pl).
/// Czysta logika — dokumenty (PDF/e-mail) tworzą widoki i generatory.
public enum DebtCollectionEngine {

    // MARK: Status windykacji

    /// Etap windykacji faktury — najdalszy odnotowany krok eskalacji.
    public static func stage(for invoice: Invoice) -> DebtCollectionStage {
        if invoice.collectionEPUAt != nil { return .epuPrepared }
        if invoice.collectionInterestNoteAt != nil { return .interestNoted }
        if invoice.collectionDemandAt != nil { return .demanded }
        if invoice.collectionReminderAt != nil { return .reminded }
        return .none
    }

    /// Odnotowuje działanie windykacyjne na fakturach. Daty wcześniejszych
    /// etapów nie są modyfikowane; ponowne przypomnienie aktualizuje datę
    /// i licznik (miękkie ponaglenia bywają cykliczne).
    public static func record(
        _ action: DebtCollectionAction,
        on invoices: [Invoice],
        at date: Date = .now
    ) {
        for invoice in invoices {
            switch action {
            case .reminder:
                invoice.collectionReminderAt = date
                invoice.collectionReminderCount += 1
            case .demand:
                invoice.collectionDemandAt = date
            case .interestNote:
                invoice.collectionInterestNoteAt = date
            case .epu:
                invoice.collectionEPUAt = date
            }
        }
    }

    /// Sugeruje następny krok eskalacji dla zaległej faktury sprzedażowej.
    /// `nil`, gdy faktura nie podlega windykacji (opłacona, ukryta, przed
    /// terminem, zakup) albo ścieżka jest wyczerpana (EPU przygotowane).
    public static func suggestion(
        for invoice: Invoice,
        asOf: Date = .now,
        policy: DebtCollectionPolicy = DebtCollectionPolicy()
    ) -> DebtCollectionSuggestion? {
        guard invoice.kind == .sales,
              !invoice.isArchivedOrHidden,
              !invoice.isPaid,
              invoice.outstandingAmount > 0,
              let due = invoice.paymentDueDate, due < asOf else { return nil }
        let overdueDays = PaymentDemandEngine.daysOverdue(dueDate: due, asOf: asOf)

        switch stage(for: invoice) {
        case .none:
            return DebtCollectionSuggestion(
                action: .reminder,
                reason: "Faktura po terminie (\(overdueDays) dni) — zacznij od miękkiego przypomnienia."
            )
        case .reminded:
            guard overdueDays >= policy.demandAfterDaysOverdue,
                  let reminded = invoice.collectionReminderAt,
                  daysBetween(reminded, and: asOf) >= policy.demandAfterReminderDays
            else { return nil }
            return DebtCollectionSuggestion(
                action: .demand,
                reason: "Przypomnienie bez zapłaty, zaległość \(overdueDays) dni — czas na formalne wezwanie do zapłaty."
            )
        case .demanded:
            guard let demanded = invoice.collectionDemandAt,
                  daysBetween(demanded, and: asOf) >= policy.noteAfterDemandDays
            else { return nil }
            return DebtCollectionSuggestion(
                action: .interestNote,
                reason: "Wezwanie bez zapłaty od \(daysBetween(demanded, and: asOf)) dni — nalicz odsetki notą odsetkową."
            )
        case .interestNoted:
            guard let noted = invoice.collectionInterestNoteAt,
                  daysBetween(noted, and: asOf) >= policy.epuAfterNoteDays
            else { return nil }
            return DebtCollectionSuggestion(
                action: .epu,
                reason: "Polubowna windykacja wyczerpana — przygotuj dane do pozwu EPU (e-sąd)."
            )
        case .epuPrepared:
            return nil
        }
    }

    /// Pełne dni kalendarzowe między datami (początek dnia → początek dnia).
    static func daysBetween(_ from: Date, and to: Date) -> Int {
        let calendar = Calendar.current
        return max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: from),
            to: calendar.startOfDay(for: to)
        ).day ?? 0)
    }

    // MARK: Dane do pozwu EPU (e-sąd)

    /// Kwalifikacja pozycji do pozwu EPU. Poza pozwem zostają roszczenia
    /// w walucie obcej (formularz e-sądu przyjmuje kwoty w złotych) oraz
    /// wymagalne dawniej niż 3 lata przed dniem pozwu (art. 505(29a) KPC —
    /// w EPU można dochodzić roszczeń wymagalnych w okresie trzech lat
    /// przed dniem wniesienia pozwu).
    public static func epuEligibleItems(
        from items: [PaymentDemandItem],
        asOf: Date = .now
    ) -> (eligible: [PaymentDemandItem], omissions: [(invoiceNumber: String, reason: String)]) {
        var eligible: [PaymentDemandItem] = []
        var omissions: [(invoiceNumber: String, reason: String)] = []
        for item in items {
            if let reason = epuOmissionReason(
                currency: item.currency,
                dueDate: item.dueDate,
                asOf: asOf
            ) {
                omissions.append((item.invoiceNumber, reason))
            } else {
                eligible.append(item)
            }
        }
        return (eligible, omissions)
    }

    /// Faktury spełniające techniczne kryteria EPU używane przy
    /// odnotowaniu przygotowania pozwu. Dzięki temu faktura pokazana na
    /// liście pominięć (waluta obca / ponad 3 lata) nie dostaje fałszywego
    /// statusu „EPU przygotowane”. Pozostałe warunki (sprzedaż, saldo,
    /// widoczność) zapewnia widok windykacji przed wywołaniem tej funkcji.
    public static func epuEligibleInvoices(
        from invoices: [Invoice],
        asOf: Date = .now
    ) -> [Invoice] {
        invoices.filter { invoice in
            guard let dueDate = invoice.paymentDueDate else { return false }
            return epuOmissionReason(
                currency: invoice.currency,
                dueDate: dueDate,
                asOf: asOf
            ) == nil
        }
    }

    /// Powód wyłączenia wspólny dla pozycji pozwu i odpowiadających im
    /// faktur. Porównujemy początki dni, żeby roszczenie dokładnie na
    /// granicy trzech lat nie wypadało z EPU tylko dlatego, że pozew jest
    /// przygotowywany później niż o północy.
    private static func epuOmissionReason(
        currency: String,
        dueDate: Date,
        asOf: Date
    ) -> String? {
        if currency != "PLN" {
            return "waluta \(currency) — pozew EPU obejmuje kwoty w złotych"
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: asOf)
        let threeYearsAgo = calendar.date(byAdding: .year, value: -3, to: today) ?? today
        if calendar.startOfDay(for: dueDate) < threeYearsAgo {
            return "roszczenie wymagalne ponad 3 lata temu — poza zakresem EPU (art. 505(29a) KPC)"
        }
        return nil
    }

    /// Wartość przedmiotu sporu: suma należności głównych (bez odsetek —
    /// art. 20 KPC), zaokrąglona w górę do pełnego złotego (art. 126(1) § 3 KPC).
    public static func epuDisputeValue(of items: [PaymentDemandItem]) -> Int {
        // Kwoty faktur są groszowe, ale model przechowuje je jako Double.
        // Sumowanie Double przed ceil potrafi zmienić dokładne 988,00 na
        // 988,0000000000001 i zawyżyć WPS o złotówkę. Najpierw zamieniamy
        // każdą pozycję na grosze, potem wykonujemy arytmetykę całkowitą.
        let totalCents = items.reduce(Int64(0)) { result, item in
            result + Int64((item.outstanding * 100).rounded())
        }
        guard totalCents > 0 else { return 0 }
        return Int((totalCents + 99) / 100)
    }

    /// Opłata od pozwu w EPU: czwarta część opłaty z art. 13 ustawy
    /// o kosztach sądowych w sprawach cywilnych, nie mniej niż 30 zł
    /// (art. 19 ust. 2 pkt 2). Opłata z art. 13: do 20 000 zł widełki stałe,
    /// powyżej — 5% WPS, maks. 100 000 zł (nowelizacja od 23.09.2025).
    /// Końcówki zaokrąglane w górę do pełnego złotego (art. 21).
    public static func epuCourtFee(disputeValue: Int) -> Int {
        guard disputeValue > 0 else { return 0 }
        let fullFee: Int
        switch disputeValue {
        case ...500: fullFee = 30
        case ...1500: fullFee = 100
        case ...4000: fullFee = 200
        case ...7500: fullFee = 400
        case ...10_000: fullFee = 500
        case ...15_000: fullFee = 750
        case ...20_000: fullFee = 1000
        default: fullFee = min(100_000, Int((Double(disputeValue) * 0.05).rounded(.up)))
        }
        let quarter = Int((Double(fullFee) / 4).rounded(.up))
        return max(30, quarter)
    }

    /// Dane stron pozwu EPU.
    public struct EPUParties: Equatable, Sendable {
        public var claimantName: String
        public var claimantNIP: String
        public var claimantAddress: String
        public var claimantBankAccount: String
        public var defendantName: String
        public var defendantNIP: String
        public var defendantAddress: String

        public init(
            claimantName: String,
            claimantNIP: String,
            claimantAddress: String,
            claimantBankAccount: String,
            defendantName: String,
            defendantNIP: String,
            defendantAddress: String
        ) {
            self.claimantName = claimantName
            self.claimantNIP = claimantNIP
            self.claimantAddress = claimantAddress
            self.claimantBankAccount = claimantBankAccount
            self.defendantName = defendantName
            self.defendantNIP = defendantNIP
            self.defendantAddress = defendantAddress
        }
    }

    /// Ostrzeżenia do danych EPU — jawne braki, które użytkownik powinien
    /// uzupełnić przed złożeniem pozwu.
    public static func epuWarnings(
        parties: EPUParties,
        items: [PaymentDemandItem],
        demandSentAt: Date?
    ) -> [String] {
        var warnings: [String] = []
        if demandSentAt == nil {
            warnings.append(
                "Brak odnotowanego wezwania do zapłaty. Pozew musi zawierać informację, "
                + "czy strony podjęły próbę polubownego rozwiązania sporu "
                + "(art. 187 § 1 pkt 3 KPC) — wyślij najpierw wezwanie."
            )
        }
        if parties.claimantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Brak nazwy powoda — uzupełnij dane firmy w Ustawieniach.")
        }
        if parties.claimantNIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Brak NIP powoda — uzupełnij dane firmy w Ustawieniach.")
        }
        if parties.claimantAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Brak adresu powoda — uzupełnij dane firmy w Ustawieniach.")
        }
        if parties.defendantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Brak nazwy pozwanego — uzupełnij dane kontrahenta.")
        }
        if parties.defendantAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(
                "Brak adresu pozwanego — uzupełnij go w słowniku kontrahentów "
                + "(pozew wymaga adresu do doręczeń)."
            )
        }
        if parties.defendantNIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Brak NIP pozwanego — e-sąd wymaga identyfikatora pozwanego przedsiębiorcy.")
        }
        if items.isEmpty {
            warnings.append("Brak roszczeń kwalifikujących się do EPU.")
        }
        return warnings
    }

    private static let epuDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter
    }()

    /// Tekst z kompletem danych do przepisania do formularza pozwu na
    /// e-sad.gov.pl. EPU nie przyjmuje załączników — dowody wyłącznie
    /// wskazuje się w treści pozwu.
    public static func epuText(
        parties: EPUParties,
        items: [PaymentDemandItem],
        demandSentAt: Date?,
        omissions: [(invoiceNumber: String, reason: String)] = [],
        date: Date = .now
    ) -> String {
        let format = epuDateFormatter
        let disputeValue = epuDisputeValue(of: items)
        let fee = epuCourtFee(disputeValue: disputeValue)
        var lines: [String] = []

        lines.append("DANE DO POZWU — ELEKTRONICZNE POSTĘPOWANIE UPOMINAWCZE (EPU)")
        lines.append("Przygotowano: \(format.string(from: date)) (Ksefiarz). "
            + "Dane do przepisania do formularza pozwu na e-sad.gov.pl.")
        lines.append("Sąd: Sąd Rejonowy Lublin-Zachód w Lublinie, VI Wydział Cywilny "
            + "(właściwy dla wszystkich pozwów EPU).")
        lines.append("")

        lines.append("POWÓD (wierzyciel):")
        lines.append("  Nazwa: \(parties.claimantName)")
        lines.append("  NIP: \(parties.claimantNIP)")
        if !parties.claimantAddress.isEmpty {
            lines.append("  Adres: \(parties.claimantAddress)")
        }
        if !parties.claimantBankAccount.isEmpty {
            lines.append("  Rachunek do zapłaty zasądzonych kwot: \(parties.claimantBankAccount)")
        }
        lines.append("")

        lines.append("POZWANY (dłużnik):")
        lines.append("  Nazwa: \(parties.defendantName)")
        if !parties.defendantNIP.isEmpty {
            lines.append("  NIP: \(parties.defendantNIP)")
        }
        if !parties.defendantAddress.isEmpty {
            lines.append("  Adres: \(parties.defendantAddress)")
        }
        lines.append("")

        lines.append("WARTOŚĆ PRZEDMIOTU SPORU: \(disputeValue) zł")
        lines.append("  (suma należności głównych bez odsetek — art. 20 KPC; "
            + "zaokrąglona w górę do pełnego złotego — art. 126(1) § 3 KPC)")
        lines.append("OPŁATA OD POZWU: \(fee) zł")
        lines.append("  (1/4 opłaty z art. 13 ustawy o kosztach sądowych w sprawach cywilnych, "
            + "nie mniej niż 30 zł — art. 19 ust. 2 pkt 2; płatna elektronicznie przy wnoszeniu pozwu)")
        lines.append("")

        lines.append("ROSZCZENIA:")
        for (index, item) in items.enumerated() {
            let overdueFrom = Calendar.current.date(
                byAdding: .day, value: 1, to: item.dueDate
            ) ?? item.dueDate
            lines.append("  \(index + 1). Kwota: \(FA2Format.amount(item.outstanding)) zł "
                + "z odsetkami ustawowymi za opóźnienie w transakcjach handlowych "
                + "od dnia \(format.string(from: overdueFrom)) do dnia zapłaty")
            lines.append("     Tytuł: faktura nr \(item.invoiceNumber) "
                + "z dnia \(format.string(from: item.issueDate)), "
                + "termin płatności \(format.string(from: item.dueDate))")
        }
        lines.append("")

        lines.append("DOWODY (w EPU dowodów nie załącza się — wskazuje się je w pozwie):")
        for (index, item) in items.enumerated() {
            lines.append("  \(index + 1). Faktura nr \(item.invoiceNumber) "
                + "z dnia \(format.string(from: item.issueDate))")
        }
        if let demandSentAt {
            lines.append("  \(items.count + 1). Wezwanie do zapłaty "
                + "z dnia \(format.string(from: demandSentAt))")
        }
        lines.append("")

        lines.append("UZASADNIENIE (propozycja):")
        var justification = "  Powód w ramach prowadzonej działalności gospodarczej wykonał na rzecz "
            + "pozwanego świadczenia udokumentowane wskazanymi fakturami. Pozwany nie uregulował "
            + "należności w terminach płatności określonych na fakturach."
        if let demandSentAt {
            justification += " Pismem z dnia \(format.string(from: demandSentAt)) powód wezwał "
                + "pozwanego do dobrowolnej zapłaty — bezskutecznie (próba polubownego "
                + "rozwiązania sporu, art. 187 § 1 pkt 3 KPC)."
        }
        lines.append(justification)

        if !omissions.isEmpty {
            lines.append("")
            lines.append("POZA POZWEM (do dochodzenia osobno):")
            for omission in omissions {
                lines.append("  • \(omission.invoiceNumber) — \(omission.reason)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
