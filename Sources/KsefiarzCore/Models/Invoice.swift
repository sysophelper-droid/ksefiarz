import Foundation
import SwiftData

/// Trwały stan wysyłki faktury sprzedażowej do KSeF.
public enum KSeFSubmissionStatus: String, Codable, CaseIterable, Sendable {
    case local
    /// Wystawiona w trybie offline24 — czeka w kolejce na dosłanie do KSeF
    /// (termin: następny dzień roboczy po dacie wystawienia).
    case offlinePending = "offline"
    case processing
    case accepted
    case rejected

    public var displayName: String {
        switch self {
        case .local: return "Lokalna"
        case .offlinePending: return "Offline24 — oczekuje na dosłanie"
        case .processing: return "Przetwarzana przez KSeF"
        case .accepted: return "Przyjęta przez KSeF"
        case .rejected: return "Odrzucona przez KSeF"
        }
    }
}

/// Model faktury przechowywany lokalnie w bazie SwiftData.
///
/// Obejmuje zarówno faktury sprzedażowe (wystawiane przez nas),
/// jak i zakupowe (pobierane z KSeF — wystawione na nasz NIP).
@Model
public final class Invoice {

    /// Powód wystawienia dokumentu w trybie offline — od niego zależy
    /// termin dosłania do KSeF (tabela trybów w docs CIRFMF: tryby-offline).
    public enum OfflineReason: String, Codable, CaseIterable, Sendable {
        /// Świadomy wybór podatnika (art. 106nda) — dosłanie do następnego
        /// dnia roboczego po dacie wystawienia. RawValue "" obsługuje
        /// dokumenty zapisane przed wprowadzeniem pola.
        case offline24 = ""
        /// Niedostępność KSeF ogłoszona komunikatem (art. 106nh) —
        /// dosłanie do następnego dnia roboczego po jej zakończeniu.
        case unavailability = "niedostepnosc"
        /// Awaria KSeF ogłoszona komunikatem (art. 106nf) — dosłanie
        /// do 7 dni roboczych od jej zakończenia.
        case failure = "awaria"

        public var displayName: String {
            switch self {
            case .offline24: return "Offline24"
            case .unavailability: return "Offline — niedostępność KSeF"
            case .failure: return "Tryb awaryjny — awaria KSeF"
            }
        }

        /// Opis terminu dosłania (do prezentacji przy braku znanej daty
        /// zakończenia zdarzenia).
        public var deadlineDescription: String {
            switch self {
            case .offline24:
                return "następny dzień roboczy po dacie wystawienia"
            case .unavailability:
                return "następny dzień roboczy po zakończeniu niedostępności"
            case .failure:
                return "7 dni roboczych od zakończenia awarii"
            }
        }
    }

    /// Rodzaj faktury — sprzedażowa lub zakupowa.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case sales = "sprzedaz"
        case purchase = "zakup"

        public var displayName: String {
            switch self {
            case .sales: return "Sprzedaż"
            case .purchase: return "Zakup"
            }
        }
    }

    /// Unikalny identyfikator lokalny.
    @Attribute(.unique) public var id: UUID

    /// Unikalny numer identyfikacyjny nadany przez system KSeF (nil, jeśli faktura nie została jeszcze wysłana).
    public var ksefId: String?

    /// Numer własny faktury (np. FV/2026/06/001).
    public var invoiceNumber: String

    /// Data wystawienia.
    public var issueDate: Date

    /// Dane sprzedawcy.
    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String = ""

    /// Dane nabywcy.
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String = ""

    /// Kwoty: netto, VAT, brutto.
    public var netAmount: Double
    public var vatAmount: Double
    public var grossAmount: Double

    /// Status opłacenia — domyślnie `false` (do opłacenia).
    public var isPaid: Bool

    /// Termin płatności (opcjonalny).
    public var paymentDueDate: Date?

    /// Forma płatności (kod słownika FA(2): 1-gotówka … 6-przelew) — patrz `PaymentForm`.
    public var paymentFormRaw: String?

    /// Numer rachunku bankowego do płatności (NrRB z faktury).
    public var paymentBankAccount: String?

    /// Data zapłaty (DataZaplaty), jeśli faktura była opłacona przy wystawieniu.
    public var paymentDate: Date?

    /// Flaga ukrycia faktury nieuprawnionej / nie do rozliczenia — domyślnie `false`.
    /// Ukryte faktury nie są uwzględniane w rozliczeniach ani statystykach.
    public var isArchivedOrHidden: Bool

    /// Oryginalny dokument XML e-Faktury (FA(2), FA(3) lub FA_RR(1)).
    public var rawXmlContent: String?

    /// Rodzaj dokumentu, np. VAT, KOR, ZAL, VAT_RR albo KOR_VAT_RR.
    public var documentTypeRaw: String = "VAT"

    /// Dane faktury korygowanej (tylko dla dokumentów KOR).
    public var correctionReason: String?
    public var correctedInvoiceNumber: String?
    public var correctedInvoiceKsefId: String?
    public var correctedInvoiceIssueDate: Date?

    /// Numer referencyjny sesji KSeF, w której wysłano fakturę —
    /// potrzebny do pobrania UPO.
    public var ksefSessionReference: String?

    /// Numer referencyjny faktury w sesji — osobny od docelowego numeru KSeF.
    /// Jest dostępny od chwili przyjęcia przesyłki i służy do odpytywania
    /// o wynik przetwarzania.
    public var ksefInvoiceReference: String? = nil

    /// Surowy stan wysyłki. Pusty oznacza rekord sprzed wprowadzenia pełnego
    /// cyklu statusów; wtedy stan jest wyprowadzany z istniejących numerów.
    public var ksefSubmissionStatusRaw: String = ""

    /// Ostatni kod i opis zwrócony przez endpoint statusu faktury.
    public var ksefStatusCode: Int? = nil
    public var ksefStatusDescription: String? = nil
    public var ksefLastCheckedAt: Date? = nil
    public var ksefAcceptedAt: Date? = nil

    /// Środowisko, do którego wysłano dokument. Puste dla starszych rekordów.
    public var ksefEnvironmentRaw: String = ""

    /// UPO pobrane automatycznie po przyjęciu faktury. Przechowujemy XML,
    /// aby można go było wyeksportować także bez połączenia z siecią.
    public var upoXmlContent: String? = nil

    /// Uwagi na fakturze (dopisek pod pozycjami) — w XML: Stopka/Informacje/
    /// StopkaFaktury. Wartość domyślna obowiązkowa (migracja bazy).
    public var notes: String = ""

    /// Waluta faktury (KodWaluty); kwoty faktury są w tej walucie.
    public var currency: String = "PLN"
    /// Kurs PLN dla waluty obcej (0 = nie dotyczy) — do pól P_14_xW
    /// i przeliczeń statystyk.
    public var exchangeRate: Double = 0
    /// Mechanizm podzielonej płatności (Adnotacje P_18A = 1).
    public var splitPayment: Bool = false
    /// Data dokonania dostawy / otrzymania zapłaty (P_6) — dla ZAL data
    /// otrzymania zaliczki.
    public var saleDate: Date?
    /// Numery KSeF faktur zaliczkowych rozliczanych dokumentem ROZ
    /// (rozdzielone znakiem nowej linii — SwiftData nie lubi tablic w atrybutach).
    public var advanceInvoiceRefsRaw: String = ""
    /// Procedura marży (Adnotacje/PMarzy): "" = brak, "2" = biura podróży,
    /// "3_1" = towary używane, "3_2" = dzieła sztuki, "3_3" = antyki.
    public var marginProcedureRaw: String = ""

    /// Samofakturowanie (Adnotacje P_17 = 1, art. 106d ust. 1 ustawy o VAT) —
    /// faktura wystawiona przez NABYWCĘ w imieniu i na rzecz sprzedawcy.
    /// Dla zakupów: my (nabywca) wystawiliśmy dokument w imieniu dostawcy;
    /// dla sprzedaży: dokument wystawił w naszym imieniu nasz klient.
    /// Wartość domyślna obowiązkowa (lekka migracja istniejącej bazy).
    public var isSelfInvoicing: Bool = false

    /// Załącznik FA(3) (element Zalacznik) — bloki danych zserializowane
    /// do JSON (`[FA3AttachmentBlock]`); "" = brak załącznika.
    public var attachmentJSON: String = ""

    /// Data przekazania faktury do wysyłki e-mailem (nil = nie wysyłano).
    public var emailSentAt: Date? = nil
    /// Adres, na który przekazano fakturę e-mailem.
    public var emailSentTo: String = ""

    /// Kategoria kosztu (tylko zakupy) — grupuje wydatki w raportach.
    /// Pusta = „Bez kategorii”. Wartość domyślna obowiązkowa (migracja bazy).
    public var costCategory: String = ""

    /// Lokalne metadane KPiR. Nie zmieniają treści faktury ani dokumentu KSeF;
    /// pozwalają księgowo zaklasyfikować dokument według wzoru obowiązującego
    /// od 2026 r. Puste wartości oznaczają automatyczne wyprowadzenie z faktury.
    public var isExcludedFromKPiR: Bool = false
    public var kpirColumnRaw: String = ""
    public var kpirEventDate: Date? = nil
    public var kpirDescription: String = ""
    public var kpirNotes: String = ""
    /// Kwota w PLN przyjęta do KPiR; nil = kwota netto przeliczona kursem
    /// faktury. Umożliwia ujęcie części kosztu albo VAT niepodlegającego odliczeniu.
    public var kpirAmountOverride: Double? = nil
    /// Część kosztu wykazywana dodatkowo informacyjnie w kolumnie 18 (B+R).
    public var kpirResearchDevelopmentCost: Double = 0

    /// Lokalne metadane ryczałtu (ewidencja przychodów). Dotyczą wyłącznie
    /// sprzedaży; nie zmieniają treści faktury ani dokumentu KSeF. Puste
    /// wartości oznaczają automatyczne wyprowadzenie (stawka domyślna
    /// z ustawień, data i kwota z faktury). Wartości domyślne obowiązkowe
    /// (lekka migracja bazy).
    public var isExcludedFromRyczalt: Bool = false
    /// Stawka ryczałtu (rawValue `RyczaltRate`, np. „8.5”); "" = stawka domyślna.
    public var ryczaltRateRaw: String = ""
    /// Data dokonania zapisu w ewidencji; nil = data uzyskania przychodu.
    public var ryczaltEntryDate: Date? = nil
    /// Data uzyskania przychodu przyjęta do ewidencji; nil = data z faktury.
    public var ryczaltEventDate: Date? = nil
    /// Kwota przychodu w PLN; nil = kwota netto przeliczona kursem faktury.
    public var ryczaltAmountOverride: Double? = nil
    /// Uwagi ewidencji przychodów (kol. 17 wzoru).
    public var ryczaltNotes: String = ""

    /// Dokument wystawiony w trybie offline (offline24 / niedostępność /
    /// awaria). Przy dosyłaniu do KSeF wysyłany jest DOKŁADNIE zapisany XML
    /// (`rawXmlContent`) — jego skrót jest częścią kodów QR na wydruku.
    public var isOfflineMode: Bool = false
    /// Skrót SHA-256 zapisanego XML (Base64) — utrwalony w chwili wystawienia
    /// offline; wchodzi do kodów QR i pola invoiceHash przy dosyłaniu.
    public var offlineHashBase64: String = ""
    /// Powód trybu offline (rawValue `OfflineReason`); "" = offline24
    /// (dokumenty sprzed migracji i domyślny wybór podatnika).
    public var offlineReasonRaw: String = ""
    /// Data zakończenia niedostępności/awarii KSeF (komunikat MF) — od niej
    /// liczy się termin dosłania; nil = zdarzenie trwa albo nie dotyczy.
    public var offlineEventEndedAt: Date? = nil
    /// Identyfikator zdarzenia z publicznego API Latarni MF. Pozwala
    /// automatycznie powiązać komunikat kończący awarię z fakturą, bez
    /// zgadywania po dacie. `nil` oznacza wybór/daty ustawione ręcznie.
    public var offlineEventId: Int? = nil

    /// Windykacja (tylko sprzedaż) — daty odnotowanych działań ścieżki
    /// eskalacji: przypomnienie → wezwanie → nota odsetkowa → dane do EPU.
    /// Z dat wyprowadzany jest status windykacji (`collectionStage`).
    /// Wartości domyślne obowiązkowe (lekka migracja istniejącej bazy).
    public var collectionReminderAt: Date? = nil
    /// Liczba wysłanych przypomnień (miękkie ponaglenia bywają cykliczne).
    public var collectionReminderCount: Int = 0
    public var collectionDemandAt: Date? = nil
    public var collectionInterestNoteAt: Date? = nil
    public var collectionEPUAt: Date? = nil

    /// Czy dokument jest fakturą korygującą.
    public var isCorrection: Bool {
        ["KOR", "KOR_ZAL", "KOR_ROZ", "KOR_VAT_RR"].contains(documentTypeRaw)
    }

    /// Czy dokument należy do osobnej struktury FA_RR(1).
    public var isRR: Bool {
        documentTypeRaw == "VAT_RR" || documentTypeRaw == "KOR_VAT_RR"
    }

    /// Zakupowy dokument wystawiony PRZEZ NAS jako nabywcę: faktura VAT RR
    /// albo samofaktura (samofakturowanie). Taki dokument podlega pełnemu
    /// cyklowi wysyłki do KSeF jak sprzedaż (edycja/korekta/wysyłka),
    /// w odróżnieniu od zakupów pobranych z KSeF i ręcznych faktur kosztowych.
    /// Sprzedaż z adnotacją samofakturowania (wystawiona przez klienta
    /// w naszym imieniu) świadomie NIE wchodzi do tej kategorii.
    public var isSelfIssuedPurchase: Bool {
        kind == .purchase && (isRR || isSelfInvoicing)
    }

    /// Dokument, którego cyklem wysyłki do KSeF zarządza aplikacja:
    /// własna sprzedaż albo zakup wystawiony przez nas jako nabywcę (VAT RR
    /// lub samofaktura). Sprzedaż z P_17 sporządził klient w naszym imieniu,
    /// więc nie wolno proponować dla niej naszej korekty/edycji. Zwykłe
    /// zakupy są tylko pobierane z KSeF, a ręczne faktury kosztowe pozostają
    /// poza cyklem wysyłki.
    public var hasKSeFSubmissionLifecycle: Bool {
        (kind == .sales && !isSelfInvoicing) || isSelfIssuedPurchase
    }

    /// NIP kontekstu, w którym aplikacja wysyła dokument do KSeF. Dla
    /// dokumentów wystawianych przez nas jako nabywcę kontekstem jest
    /// Podmiot2; dla zwykłej sprzedaży — Podmiot1. Wartość jest używana
    /// m.in. w KODZIE II dokumentu offline.
    public var ksefSubmissionContextNIP: String {
        isSelfIssuedPurchase ? buyerNIP : sellerNIP
    }

    /// Numery KSeF faktur zaliczkowych (dokumenty ROZ) jako tablica.
    public var advanceInvoiceRefs: [String] {
        get { advanceInvoiceRefsRaw.split(separator: "\n").map(String.init) }
        set { advanceInvoiceRefsRaw = newValue.joined(separator: "\n") }
    }

    /// Efektywny stan wysyłki. Obsługuje rekordy sprzed migracji: obecność
    /// numeru KSeF oznacza dokument przyjęty, a referencji — przetwarzany.
    public var ksefSubmissionStatus: KSeFSubmissionStatus {
        get {
            if let status = KSeFSubmissionStatus(rawValue: ksefSubmissionStatusRaw) {
                return status
            }
            if ksefId != nil { return .accepted }
            if ksefInvoiceReference != nil { return .processing }
            return .local
        }
        set { ksefSubmissionStatusRaw = newValue.rawValue }
    }

    /// Czy faktura istnieje tylko lokalnie i nigdy nie została przekazana
    /// do KSeF. Dokument w toku lub odrzucony nie jest ponownie edytowalny,
    /// bo ponowna wysyłka mogłaby utworzyć duplikat.
    public var isLocalOnly: Bool {
        ksefId == nil && ksefInvoiceReference == nil && ksefSubmissionStatus == .local
    }

    /// Czy warto automatycznie ponowić sprawdzenie statusu lub pobranie UPO.
    public var needsKSeFFollowUp: Bool {
        guard ksefSessionReference != nil, ksefInvoiceReference != nil else { return false }
        return ksefSubmissionStatus == .processing
            || (ksefSubmissionStatus == .accepted && (upoXmlContent ?? "").isEmpty)
    }

    /// Powód wystawienia w trybie offline — decyduje o terminie dosłania.
    public var offlineReason: OfflineReason {
        get { OfflineReason(rawValue: offlineReasonRaw) ?? .offline24 }
        set { offlineReasonRaw = newValue.rawValue }
    }

    /// Termin dosłania dokumentu offline do KSeF (koniec dnia, 23:59:59):
    /// - offline24 — następny dzień roboczy po dacie wystawienia,
    /// - niedostępność KSeF — następny dzień roboczy po jej zakończeniu,
    /// - awaria KSeF — 7. dzień roboczy po jej zakończeniu.
    /// `nil`, gdy dokument nie czeka w kolejce albo zdarzenie jeszcze trwa
    /// (termin nieznany do czasu komunikatu MF o zakończeniu).
    public var offlineSendDeadline: Date? {
        guard isOfflineMode, ksefSubmissionStatus == .offlinePending else { return nil }
        switch offlineReason {
        case .offline24:
            return PolishBusinessCalendar.endOfNextBusinessDay(after: issueDate)
        case .unavailability:
            guard let eventEnd = offlineEventEndedAt else { return nil }
            return PolishBusinessCalendar.endOfNextBusinessDay(after: eventEnd)
        case .failure:
            guard let eventEnd = offlineEventEndedAt else { return nil }
            return PolishBusinessCalendar.endOfBusinessDay(after: eventEnd, businessDays: 7)
        }
    }

    /// Pozycje faktury (FaWiersz).
    @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
    public var lines: [InvoiceLine] = []

    /// Historia wpłat do faktury (płatności częściowe).
    @Relationship(deleteRule: .cascade, inverse: \PaymentRecord.invoice)
    public var payments: [PaymentRecord] = []

    /// Suma zarejestrowanych wpłat (w walucie faktury).
    public var paidAmount: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    /// Saldo pozostałe do zapłaty. Faktura oznaczona jako opłacona ma saldo 0
    /// niezależnie od historii wpłat (znacznik „opłacona” jest nadrzędny —
    /// starsze rekordy i formy „z góry” nie mają wpisów wpłat).
    public var outstandingAmount: Double {
        isPaid ? 0 : max(0, grossAmount - paidAmount)
    }

    /// Częściowo opłacona: są wpłaty, ale saldo nie zostało domknięte.
    public var isPartiallyPaid: Bool {
        !isPaid && paidAmount > 0.005
    }

    /// Wpłaty od najnowszej.
    public var sortedPayments: [PaymentRecord] {
        payments.sorted { $0.date > $1.date }
    }

    /// Surowa wartość rodzaju faktury — przechowywana jako String,
    /// aby można było jej używać w makrze #Predicate (SwiftData).
    public var kindRaw: String

    /// Wygodny dostęp do rodzaju faktury jako enum.
    public var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .purchase }
        set { kindRaw = newValue.rawValue }
    }

    /// Forma płatności jako enum (jeśli znana).
    public var paymentForm: PaymentForm? {
        get { paymentFormRaw.flatMap(PaymentForm.init(rawValue:)) }
        set { paymentFormRaw = newValue?.rawValue }
    }

    /// Pozycje posortowane po numerze wiersza.
    public var sortedLines: [InvoiceLine] {
        lines.sorted { $0.index < $1.index }
    }

    public init(
        id: UUID = UUID(),
        ksefId: String? = nil,
        invoiceNumber: String,
        issueDate: Date,
        sellerName: String,
        sellerNIP: String,
        sellerAddress: String = "",
        buyerName: String,
        buyerNIP: String,
        buyerAddress: String = "",
        netAmount: Double,
        vatAmount: Double,
        grossAmount: Double,
        isPaid: Bool = false,
        paymentDueDate: Date? = nil,
        paymentForm: PaymentForm? = nil,
        paymentBankAccount: String? = nil,
        paymentDate: Date? = nil,
        isArchivedOrHidden: Bool = false,
        rawXmlContent: String? = nil,
        documentType: String = "VAT",
        correctionReason: String? = nil,
        correctedInvoiceNumber: String? = nil,
        correctedInvoiceKsefId: String? = nil,
        correctedInvoiceIssueDate: Date? = nil,
        ksefSessionReference: String? = nil,
        ksefInvoiceReference: String? = nil,
        ksefSubmissionStatus: KSeFSubmissionStatus? = nil,
        ksefStatusCode: Int? = nil,
        ksefStatusDescription: String? = nil,
        ksefLastCheckedAt: Date? = nil,
        ksefAcceptedAt: Date? = nil,
        ksefEnvironmentRaw: String = "",
        upoXmlContent: String? = nil,
        notes: String = "",
        currency: String = "PLN",
        exchangeRate: Double = 0,
        splitPayment: Bool = false,
        saleDate: Date? = nil,
        advanceInvoiceRefs: [String] = [],
        marginProcedure: String = "",
        isSelfInvoicing: Bool = false,
        kind: Kind = .purchase
    ) {
        self.id = id
        self.ksefId = ksefId
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.sellerName = sellerName
        self.sellerNIP = sellerNIP
        self.sellerAddress = sellerAddress
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.buyerAddress = buyerAddress
        self.netAmount = netAmount
        self.vatAmount = vatAmount
        self.grossAmount = grossAmount
        self.isPaid = isPaid
        self.paymentDueDate = paymentDueDate
        self.paymentFormRaw = paymentForm?.rawValue
        self.paymentBankAccount = paymentBankAccount
        self.paymentDate = paymentDate
        self.isArchivedOrHidden = isArchivedOrHidden
        self.rawXmlContent = rawXmlContent
        self.documentTypeRaw = documentType
        self.correctionReason = correctionReason
        self.correctedInvoiceNumber = correctedInvoiceNumber
        self.correctedInvoiceKsefId = correctedInvoiceKsefId
        self.correctedInvoiceIssueDate = correctedInvoiceIssueDate
        self.ksefSessionReference = ksefSessionReference
        self.ksefInvoiceReference = ksefInvoiceReference
        self.ksefSubmissionStatusRaw = ksefSubmissionStatus?.rawValue ?? ""
        self.ksefStatusCode = ksefStatusCode
        self.ksefStatusDescription = ksefStatusDescription
        self.ksefLastCheckedAt = ksefLastCheckedAt
        self.ksefAcceptedAt = ksefAcceptedAt
        self.ksefEnvironmentRaw = ksefEnvironmentRaw
        self.upoXmlContent = upoXmlContent
        self.notes = notes
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.splitPayment = splitPayment
        self.saleDate = saleDate
        self.advanceInvoiceRefsRaw = advanceInvoiceRefs.joined(separator: "\n")
        self.marginProcedureRaw = marginProcedure
        self.isSelfInvoicing = isSelfInvoicing
        self.kindRaw = kind.rawValue
    }

    /// Etap windykacji — najdalszy odnotowany krok ścieżki eskalacji.
    public var collectionStage: DebtCollectionStage {
        DebtCollectionEngine.stage(for: self)
    }

    /// Czy faktura jest zaległa (nieopłacona i po terminie płatności) na wskazany moment.
    public func isOverdue(asOf date: Date = .now) -> Bool {
        guard !isPaid, let due = paymentDueDate else { return false }
        return due < date
    }

    /// Wygodny skrót — zaległość względem chwili bieżącej.
    public var isOverdue: Bool { isOverdue(asOf: .now) }
}

// MARK: - Mapowanie z danych pobranych z KSeF

public extension Invoice {
    /// Tworzy fakturę na podstawie danych sparsowanych z dokumentu FA(2).
    /// Znacznik „Zaplacono” z faktury ustawia status opłacenia.
    ///
    /// Uwaga: pozycje (relacja SwiftData) należy uzupełnić po wstawieniu
    /// do kontekstu — metodą `applyDetails(from:)`.
    convenience init(from data: FA2InvoiceData, kind: Kind) {
        self.init(
            ksefId: data.ksefId,
            invoiceNumber: data.invoiceNumber,
            issueDate: data.issueDate,
            sellerName: data.sellerName,
            sellerNIP: data.sellerNIP,
            sellerAddress: data.sellerAddress,
            buyerName: data.buyerName,
            buyerNIP: data.buyerNIP,
            buyerAddress: data.buyerAddress,
            netAmount: data.netAmount,
            vatAmount: data.vatAmount,
            grossAmount: data.grossAmount,
            isPaid: data.isPaidMarker,
            paymentDueDate: data.paymentDueDate,
            paymentForm: data.paymentForm.flatMap(PaymentForm.init(rawValue:)),
            paymentBankAccount: data.paymentBankAccount,
            paymentDate: data.paymentDate,
            rawXmlContent: data.rawXML,
            documentType: data.documentType,
            correctionReason: data.correction?.reason,
            correctedInvoiceNumber: data.correction?.originalNumber,
            correctedInvoiceKsefId: data.correction?.originalKsefNumber,
            correctedInvoiceIssueDate: data.correction?.originalIssueDate,
            ksefSubmissionStatus: data.ksefId == nil ? nil : .accepted,
            notes: data.notes,
            currency: data.currency,
            splitPayment: data.splitPayment,
            saleDate: data.saleDate,
            isSelfInvoicing: data.isSelfInvoicing,
            kind: kind
        )
    }

    /// Uzupełnia/odświeża szczegóły faktury danymi z dokumentu FA(2)
    /// (adresy, pozycje, dane płatności, XML). Nie nadpisuje decyzji
    /// użytkownika: statusu „opłacona” nie cofa, ukrycia nie zmienia.
    func applyDetails(from data: FA2InvoiceData) {
        sellerName = data.sellerName.isEmpty ? sellerName : data.sellerName
        sellerAddress = data.sellerAddress
        buyerName = data.buyerName.isEmpty ? buyerName : data.buyerName
        buyerAddress = data.buyerAddress
        if data.netAmount != 0 || data.grossAmount != 0 {
            netAmount = data.netAmount
            vatAmount = data.vatAmount
            grossAmount = data.grossAmount
        }
        if let due = data.paymentDueDate { paymentDueDate = due }
        if let form = data.paymentForm { paymentFormRaw = form }
        if let account = data.paymentBankAccount { paymentBankAccount = account }
        if let paid = data.paymentDate { paymentDate = paid }
        // Znacznik „Zaplacono” może tylko ustawić status — nigdy go nie cofa.
        if data.isPaidMarker { isPaid = true }
        if !data.rawXML.isEmpty { rawXmlContent = data.rawXML }
        if let number = data.ksefId {
            ksefId = number
            ksefSubmissionStatus = .accepted
        }
        documentTypeRaw = data.documentType
        if let correction = data.correction {
            correctionReason = correction.reason
            correctedInvoiceNumber = correction.originalNumber
            correctedInvoiceKsefId = correction.originalKsefNumber
            correctedInvoiceIssueDate = correction.originalIssueDate
        }

        if !data.notes.isEmpty { notes = data.notes }
        currency = data.currency
        splitPayment = data.splitPayment
        isSelfInvoicing = data.isSelfInvoicing
        if let sale = data.saleDate { saleDate = sale }
        if !data.attachments.isEmpty { attachmentJSON = data.attachments.encodedJSON() }

        // Pozycje budujemy od nowa z dokumentu.
        lines = data.lines.map { line in
            InvoiceLine(
                index: line.index,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu,
                gtu: line.gtu,
                procedure: line.procedure,
                ossRate: line.ossRate,
                rrQuality: line.rrQuality
            )
        }
    }
}
