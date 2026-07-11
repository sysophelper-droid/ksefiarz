# Ksefiarz

Natywna aplikacja desktopowa na macOS (14+ Sonoma) do zarządzania fakturami,
integracji z Krajowym Systemem e-Faktur (KSeF) oraz wewnętrznego rozliczania płatności.

**Stos:** Swift 5.10+ (async/await) · SwiftUI (NavigationSplitView, Dark Mode) · SwiftData · URLSession

## Uruchomienie

```bash
./Scripts/build-app.sh  # buduje natywny bundle dist/Ksefiarz.app (release)
open dist/Ksefiarz.app  # uruchomienie; instalacja: przeciągnij do /Applications

swift run Ksefiarz      # alternatywnie: uruchomienie deweloperskie z CLI
swift test              # uruchomienie testów jednostkowych
```

Projekt można też otworzyć bezpośrednio w Xcode (`open Package.swift`)
i uruchomić schemat **Ksefiarz**. Bundle jest podpisany ad-hoc — do dystrybucji
poza własny komputer potrzebny jest podpis Developer ID i notaryzacja.

## Struktura projektu

```
Sources/
├── KsefiarzApp/
│   └── InvoiceApp.swift          # punkt wejścia, konfiguracja .modelContainer
└── KsefiarzCore/
    ├── Models/
    │   ├── Invoice.swift         # model SwiftData (ksefId, kwoty, isPaid, isArchivedOrHidden…)
    │   ├── InvoiceDraft.swift    # szkic i przenośna migawka szablonu
    │   └── InvoiceAutomation.swift # szablony i harmonogramy SwiftData
    ├── Services/
    │   ├── KSeFService.swift     # API KSeF 2.0: uwierzytelnienie, pobieranie i wysyłka faktur
    │   ├── KSeFCrypto.swift      # RSA-OAEP (SHA-256), AES-256-CBC, SHA-256
    │   ├── FA2XML.swift          # generator i parser uproszczonej struktury FA(2)
    │   └── InvoiceValidator.swift# walidacja pól + suma kontrolna NIP
    ├── Logic/
    │   ├── InvoiceFilter.swift   # filtrowanie list (status płatności, wyszukiwarka)
    │   ├── DashboardMetrics.swift# agregaty Kokpitu (ukryte faktury pomijane)
    │   └── InvoiceAutomationEngine.swift # duplikaty i terminy cykli
    └── Views/
        ├── MainContentView.swift # NavigationSplitView + pasek boczny
        ├── DashboardView.swift   # Kokpit: podsumowania, płatności na 7 dni
        ├── InvoiceListView.swift # listy zakupów/sprzedaży, swipe/menu, badge
        ├── InvoiceDetailView.swift # szczegóły + podgląd surowego XML
        ├── NewInvoiceView.swift  # formularz wystawiania faktury z walidacją
        ├── InvoiceAutomationView.swift # szablony, cykle i kolejka zatwierdzeń
        ├── HiddenInvoicesView.swift # archiwum „Nieuprawnione / Ukryte”
        └── SettingsView.swift    # NIP, token KSeF, środowisko
Tests/KsefiarzCoreTests/          # 249 testów (Swift Testing) — model, parser, usługa, kryptografia, logika
```

## Funkcje

- **Integracja z KSeF 2.0** — pełny, produkcyjny przepływ API v2
  (`api-test`/`api-demo`/`api.ksef.mf.gov.pl`): uwierzytelnienie certyfikatem
  lub tokenem, pobieranie faktur zakupowych (metadane + oryginalny XML),
  wystawianie faktur w sesji interaktywnej z obowiązkowym szyfrowaniem AES-256-CBC.
- **Uwierzytelnianie certyfikatem KSeF (preferowane)** — podpis XAdES-BES
  dokumentu AuthTokenRequest wykonywany w całości lokalnie (własna
  kanonikalizacja i podpis RSA/ECDSA, bez zewnętrznych bibliotek).
  Certyfikat typu 1 można uzyskać wprost z aplikacji (wniosek CSR przez API;
  klucz prywatny nigdy nie opuszcza komputera) albo zaimportować z pliku
  `.p12`/PEM (RSA-2048 i EC P-256) — np. pozyskany w Aplikacji Podatnika.
  Aplikacja pilnuje ważności (ostrzeżenie 30 dni przed wygaśnięciem),
  a przy niepowodzeniu loguje się zapasowo tokenem KSeF (tokeny mają
  przestać działać z końcem 2026 r.).
- **Tryb offline24** — świadome wystawianie faktur bez połączenia z KSeF
  (art. 106nda) oraz automatyczne przejście w offline przy braku sieci.
  Dokument dostaje utrwalony skrót SHA-256 i trafia do kolejki dosłania
  (termin: następny dzień roboczy — polski kalendarz świąt); aplikacja
  dosyła zapisany XML bajt w bajt automatycznie co minutę, a w szczegółach
  jest przycisk „Doślij teraz” i widoczny termin z alarmem po przekroczeniu.
- **Kody QR na wydrukach** — każdy PDF faktury z numerem KSeF zawiera
  KOD I (link weryfikacyjny `qr.ksef.mf.gov.pl` z numerem KSeF w podpisie);
  dokumenty offline24 dostają KOD I z etykietą „OFFLINE” oraz KOD II
  „CERTYFIKAT” podpisany certyfikatem KSeF typu 2 (RSASSA-PSS/ECDSA).
- **Pełny status wysyłki** — faktura sprzedażowa rozróżnia stan lokalny,
  przetwarzanie, przyjęcie i odrzucenie. Numer referencyjny przesyłki jest
  przechowywany osobno od numeru KSeF; aplikacja automatycznie ponawia
  sprawdzenie co minutę, zapisuje kod i opis odpowiedzi, a po przyjęciu
  uzupełnia numer KSeF oraz pobiera UPO. Status można też sprawdzić ręcznie
  w szczegółach, a listę filtrować według każdego stanu.
- **Pełne dane faktur** — adresy stron, pozycje (FaWiersz) z jednostkami,
  ilościami i stawkami VAT (23/8/5/0/zw), sumy per stawka (P_13_x/P_14_x),
  forma płatności, numer rachunku, termin i znacznik „Zaplacono”
  (faktury opłacone gotówką/kartą przy wystawieniu są automatycznie
  oznaczane jako opłacone). Generowany XML zawiera komplet elementów
  wymaganych przez XSD FA(2) (Adres, Adnotacje, RodzajFaktury).
- **Synchronizacja dwukierunkowa** — pobieranie faktur zakupowych (Subject2)
  i sprzedażowych (Subject1); ponowna synchronizacja uzupełnia szczegóły
  wcześniej pobranych faktur bez nadpisywania decyzji użytkownika.
- **Zakres importu** — w Ustawieniach: bieżący/poprzedni miesiąc, 3 miesiące
  lub własny zakres dat; ogranicza pobieranie z KSeF (limit API: 3 miesiące
  na zapytanie). Kokpit i każda lista mają niezależne filtry okresu
  wyświetlania (zapamiętywane osobno).
- **Synchronizacja automatyczna** — w Ustawieniach: pobranie faktur
  (sprzedaż + zakup) przy starcie aplikacji oraz cykliczne pobieranie
  w wybranym interwale (15 min – 8 godz.), dopóki aplikacja działa.
  Oba tryby używają zakresu importu z Ustawień i działają **wyłącznie na
  środowisku produkcyjnym** (na testowym synchronizuj ręcznie z listy).
  Czas ostatniej udanej synchronizacji widać na dole paska bocznego.
- **Automatyczna kopia zapasowa** — raz dziennie przy starcie pełna kopia
  (faktury + słowniki + ustawienia) zapisuje się do
  `~/Library/Application Support/Ksefiarz/Backups/` z konfigurowalną
  rotacją: liczba przechowywanych kopii albo liczba dni wstecz.
- **Eksport** — zapis oryginalnego XML e-Faktury, generowanie PDF
  z klasycznym układem faktury (z kwotą słownie; długie faktury dzielone
  na wiele stron z numeracją) oraz eksport widocznej listy faktur do CSV
  (format zgodny z polskim Excelem).
- **Numeracja per rodzaj dokumentu** — każdy rodzaj (VAT/ZAL/ROZ/UPR/korekty)
  może mieć w Ustawieniach własny wzorzec i niezależną serię numeracji;
  na listach faktur dostępny jest filtr rodzaju dokumentu.
- **Standardy fakturowania** — automatyczna numeracja według konfigurowalnego
  wzorca ({RRRR}/{MM}/{N…} w Ustawieniach), wybór kontrahenta z historii,
  kwota słownie po polsku.
- **Szablony i faktury cykliczne** — istniejącą fakturę sprzedażową można
  zduplikować (zawsze z nowym numerem i datami), a dane formularza zapisać
  jako wielokrotnie używany szablon. Z szablonu można utworzyć harmonogram
  tygodniowy, miesięczny lub roczny z własnym terminem płatności. Sekcja
  „Szablony i cykle” pokazuje dokumenty oczekujące; każdy otwiera pełny
  formularz do podglądu i edycji. Harmonogram przesuwa się dopiero po ręcznym
  zapisie lub wysłaniu — aplikacja nigdy nie wysyła cyklicznej faktury do KSeF
  bez wyraźnego zatwierdzenia. Szablony i harmonogramy obejmuje kopia zapasowa.
- **Słowniki** (sekcja w pasku bocznym) — trzy kartoteki przyspieszające
  wystawianie faktur: **kontrahenci** (dane ogólne, adres, kontakt; możliwość
  pobrania nazwy i adresu z wykazu podatników VAT — „Białej listy” — po numerze
  NIP), **towary i usługi** (typ, jednostka, SKU/EAN, CN/PKWiU, GTU,
  załącznik 15, cenniki netto/brutto) oraz **rachunki bankowe** (identyfikator,
  numer, bank, SWIFT, waluta, rachunek VAT). Dane słowników są wyłącznie
  podstawiane do faktury — kontrahenta i pozycje nadal można wpisać ręcznie,
  a po wybraniu ze słownika zmienić cenę, jednostkę, stawkę VAT i CN/PKWiU.
  Słowniki wchodzą w skład kopii zapasowej.
- **Uwagi na fakturze** — pole pod pozycjami na dowolny dopisek (np. podstawa
  zwolnienia z VAT); trafia do XML (stopka faktury) i na wydruk PDF.
- **Schemat FA(3)** — wystawiane faktury są generowane w bieżącej schemie
  FA(3) (zweryfikowane end-to-end na środowisku testowym KSeF); parser
  czyta dokumenty FA(2) i FA(3).
- **Faktury zaliczkowe i rozliczeniowe** — rodzaj dokumentu (VAT/ZAL/ROZ)
  do wyboru przy wystawianiu; ZAL z datą otrzymania zaliczki (P_6),
  ROZ ze wskazaniem numerów KSeF rozliczanych zaliczek.
- **Waluty obce** — faktura w EUR/USD/GBP/CHF i in. z kursem PLN
  (VAT przeliczany do pól P_14_xW zgodnie z art. 106e ust. 11 ustawy o VAT);
  przycisk „NBP" pobiera kurs średni z ostatniego dnia roboczego przed datą
  wystawienia/sprzedaży (art. 31a), z możliwością ręcznej korekty;
  statystyki Kokpitu przeliczają kwoty walutowe po kursie z faktury.
- **Korekty zaliczek i procedury szczególne** — korekta faktury ZAL/ROZ
  generuje KOR_ZAL/KOR_ROZ; faktury uproszczone (UPR); procedury marży
  (biura podróży, towary używane, dzieła sztuki, antyki — Adnotacje/PMarzy)
  oraz oznaczenia procedur pozycji (WSTO_EE, IED, TT_D, I_42…).
- **Split payment (MPP)** — przełącznik na fakturze (Adnotacje P_18A);
  pozycja ze słownika oznaczona „załącznik 15” podpowiada włączenie MPP.
- **Biała lista** — przycisk „Sprawdź rachunek na białej liście”
  w szczegółach faktury zakupowej weryfikuje rachunek sprzedawcy
  w wykazie podatników VAT (istotne przy przelewach powyżej 15 000 zł).
- **Powiadomienia** — systemowe powiadomienie o nowych fakturach zakupowych
  pobranych przez synchronizację (wyłączane w Ustawieniach).
- **Faktury korygujące** — „Wystaw korektę” w szczegółach faktury sprzedażowej:
  dokument KOR z danymi faktury korygowanej (DaneFaKorygowanej), pozycjami
  wyrażającymi różnicę (kwoty ujemne dozwolone) i przyczyną korekty.
- **UPO** — automatyczne pobieranie i lokalne przechowywanie Urzędowego
  Poświadczenia Odbioru (XML) po przyjęciu faktury; w szczegółach można
  ponowić pobranie lub wyeksportować zapisany dokument także bez sieci.
- **Płatności** — oznaczanie „Opłacona / Do opłacenia” gestem (swipe w prawo),
  z menu kontekstowego i z widoku szczegółów; znaczniki: zielony (opłacona),
  pomarańczowy (do opłacenia), czerwony (zaległa); dane do przelewu
  (rachunek z faktury) z kopiowaniem jednym kliknięciem. W Ustawieniach
  konfigurowalna polityka form płatności: formy „opłacone z góry”
  (domyślnie gotówka/karta/bon/mobilna) oznaczają fakturę jako opłaconą
  od razu, formy odroczone (np. przelew) trafiają do „Do opłacenia”.
- **Obsługa listy** — pojedyncze kliknięcie zaznacza, podwójne otwiera
  szczegóły; zaznaczanie wielu faktur (⌘/⇧) z akcjami zbiorczymi
  w menu kontekstowym: oznacz jako opłacone/nieopłacone, ukryj (zakupy).
  Ten sam wzorzec działa na liście najbliższych płatności w Kokpicie —
  szczegóły faktury otwierają się bez przechodzenia do listy zakupów.
- **Ochrona przed nadużyciami** — „Ukryj fakturę (Nieuprawniony zakup)”
  (swipe w lewo, tylko faktury zakupowe): faktura znika z rozliczeń
  i statystyk, trafia do sekcji „Nieuprawnione / Ukryte”, skąd można ją
  przywrócić; ukryta faktura nie zostanie ponownie zaimportowana z KSeF.

- **Faktury lokalne (robocze)** — „Zapisz lokalnie” tworzy fakturę bez wysyłki
  do KSeF (etykieta „Lokalna” + filtr na liście sprzedaży). Taką fakturę można
  edytować, usunąć lub wysłać do KSeF później; faktury wysłane do KSeF są
  niezmienialne — korekta zamiast edycji (to dokument urzędowy).
- **Kopia zapasowa** — w Ustawieniach: eksport wszystkich faktur (z pozycjami
  i XML) oraz ustawień do jednego pliku JSON i import na innym komputerze
  bez ponownego pobierania z KSeF (duplikaty pomijane automatycznie).

## Gdzie przechowywane są dane

Wszystkie dane pozostają lokalnie na Twoim komputerze:

| Dane | Lokalizacja |
| --- | --- |
| Baza aplikacji (SwiftData/SQLite): faktury, pozycje, statusy wysyłki, surowe XML i UPO, szablony i harmonogramy | `~/Library/Application Support/Ksefiarz/Ksefiarz.store` (+ pliki `-wal`, `-shm`) |
| Ustawienia: dane firmy, środowisko, numeracja, filtry | `~/Library/Preferences/pl.itkrak.ksefiarz.plist` |
| **Token KSeF** | pęk kluczy macOS (Keychain), pozycja `pl.itkrak.ksefiarz` |
| **Certyfikaty KSeF (typ 1 i 2) z kluczami prywatnymi** | pęk kluczy macOS, pozycje `ksef.cert.*` w usłudze `pl.itkrak.ksefiarz` (osobno per środowisko) |
| Eksporty (XML / PDF / CSV / UPO / kopia zapasowa) | lokalizacja wybrana w panelu zapisu |

🔐 **Token KSeF** jest przechowywany w systemowym pęku kluczy (Keychain) —
zaszyfrowany przez system i niedostępny dla innych procesów bez Twojej zgody.
Każde środowisko (produkcja/demo/test) ma osobny token — przełączenie
środowiska w Ustawieniach nie kasuje pozostałych tokenów.
Przy pierwszym uruchomieniu po starszej wersji token jest automatycznie
przenoszony z pliku ustawień do pęku kluczy i usuwany z preferencji.
Kopia zapasowa (JSON) **nie zawiera tokenu** — po przeniesieniu na inny
komputer wpisz go ręcznie w Ustawieniach. Ponieważ aplikacja jest podpisana
ad-hoc, po każdej aktualizacji macOS może jednorazowo zapytać o zgodę na
dostęp do pęku kluczy — kliknij „Zezwól”. W razie potrzeby token można
w każdej chwili unieważnić w Aplikacji Podatnika KSeF i wygenerować nowy.

Przenosiny na inny komputer: użyj „Kopii zapasowej” w Ustawieniach
(eksport → import). Alternatywnie można ręcznie skopiować oba pliki
z tabeli powyżej.

## Uwagi produkcyjne

- Bundle jest podpisany ad-hoc; dystrybucja poza własny komputer wymaga
  podpisu Developer ID i notaryzacji. Sygnatura zmienia się przy każdym
  wydaniu, więc dostęp do tokenu w pęku kluczy może po aktualizacji
  wymagać jednorazowego potwierdzenia („Zezwól”).
- Generator FA(3) obsługuje praktyczny podzbiór schemy: faktury VAT,
  korygujące (KOR), zaliczkowe (ZAL), rozliczeniowe (ROZ), waluty obce
  i MPP; poza zakresem są m.in. procedury szczególne (marża, OSS),
  faktury UPR oraz korekty zaliczek (KOR_ZAL/KOR_ROZ).
