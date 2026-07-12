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
    │   ├── KSeFPermissionsService.swift # API permissions: nadawanie/odbieranie/przegląd uprawnień
    │   ├── KSeFCrypto.swift      # RSA-OAEP (SHA-256), AES-256-CBC, SHA-256
    │   ├── FA2XML.swift          # generator i parser uproszczonej struktury FA(2)
    │   └── InvoiceValidator.swift# walidacja pól + suma kontrolna NIP/PESEL
    ├── Logic/
    │   ├── InvoiceFilter.swift   # filtrowanie list (status płatności, wyszukiwarka)
    │   ├── DashboardMetrics.swift# agregaty Kokpitu (ukryte faktury pomijane)
    │   ├── PermissionsEngine.swift # walidacja i normalizacja uprawnień KSeF
    │   └── InvoiceAutomationEngine.swift # duplikaty i terminy cykli
    └── Views/
        ├── MainContentView.swift # NavigationSplitView + pasek boczny
        ├── DashboardView.swift   # Kokpit: podsumowania, płatności na 7 dni
        ├── InvoiceListView.swift # listy zakupów/sprzedaży, swipe/menu, badge
        ├── InvoiceDetailView.swift # szczegóły + podgląd surowego XML
        ├── NewInvoiceView.swift  # formularz wystawiania faktury z walidacją
        ├── PermissionsView.swift # sekcja „Uprawnienia” + arkusz nadawania
        ├── InvoiceAutomationView.swift # szablony, cykle i kolejka zatwierdzeń
        ├── HiddenInvoicesView.swift # archiwum „Nieuprawnione / Ukryte”
        └── SettingsView.swift    # NIP, token KSeF, środowisko
Tests/KsefiarzCoreTests/          # 400 testów (Swift Testing) — model, parser, usługa, kryptografia, logika
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
- **Automatyczne odnowienie certyfikatów** — na ok. 30 dni przed końcem
  ważności aplikacja sama składa wniosek o nowy certyfikat (typ 1 i typ 2)
  i podmienia go w pęku kluczy, zanim stary przestanie działać. Odnowienie
  loguje się wciąż ważnym certyfikatem typu 1 (typ 1 odnawia się nim samym,
  póki jeszcze ważny; typ 2 — o ile istnieje ważny typ 1), więc po wygaśnięciu
  typu 1 nowy trzeba zaimportować ręcznie. Próba jest podejmowana najwyżej raz
  na certyfikat na dobę, a nieudana nie narusza dotychczasowego certyfikatu;
  o wyniku informuje powiadomienie. Przełącznik w Ustawieniach → KSeF.
- **Zarządzanie uprawnieniami KSeF** — sekcja „Uprawnienia” pozwala nadać
  po NIP innej firmie (np. biuru rachunkowemu) dostęp do wystawiania i/lub
  przeglądania faktur (z opcją dalszego delegowania), osobie fizycznej
  (po NIP lub PESEL) wybrany zestaw uprawnień do pracy w KSeF, a także
  uprawnienia podmiotowe (samofakturowanie, przedstawiciel podatkowy,
  faktury RR/PEF). Nadane dostępy są prezentowane na dwóch listach
  (uprawnienia do pracy w KSeF oraz podmiotowe) i można je stamtąd odebrać.
  Operacje na uprawnieniach są w API asynchroniczne — aplikacja czeka na
  potwierdzenie (`/permissions/operations/{ref}`), więc wynik jest
  jednoznaczny. Wymaga poświadczeń z prawem zarządzania uprawnieniami
  (właściciel NIP). Zweryfikowane na mockach; na produkcji nie modyfikuje
  się uprawnień w testach (polityka „tylko odczyt na żywo”).
- **Tryby offline (offline24 / niedostępność / awaria)** — świadome
  wystawianie faktur bez połączenia z KSeF oraz automatyczne przejście
  w offline przy braku sieci. Dokument dostaje utrwalony skrót SHA-256
  i trafia do kolejki dosłania; aplikacja dosyła zapisany XML bajt w bajt
  automatycznie co minutę, a w szczegółach jest przycisk „Doślij teraz”
  i widoczny termin z alarmem po przekroczeniu. Tryb wybiera się przy
  wystawianiu (i można doprecyzować w szczegółach do czasu dosłania):
  **offline24** (art. 106nda) — dosłanie do następnego dnia roboczego;
  **niedostępność KSeF** (art. 106nh, komunikat MF) — następny dzień
  roboczy po jej zakończeniu; **awaria KSeF** (art. 106nf, komunikat MF) —
  7 dni roboczych od jej zakończenia (datę zakończenia wpisuje się
  w szczegółach; do tego czasu termin prezentowany jest opisowo).
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
- **Ikona w pasku menu** — przy zegarze systemowym: status ostatniej
  synchronizacji, liczba oczekujących i zaległych dosłań offline (czerwony
  trójkąt po przekroczeniu terminu), wysyłki w toku oraz szybkie
  „Pobierz z KSeF” (domknięcie wysyłek + import sprzedaży i zakupów);
  działa też przy zamkniętym oknie głównym („Otwórz Ksefiarza” wraca
  do aplikacji). Przełącznik w Ustawieniach → Synchronizacja.
- **Centrum synchronizacji** (sekcja „Synchronizacja” w pasku bocznym) —
  osobne stany zakupów, sprzedaży i wysyłek (kolejka offline24, statusy
  przesyłek, UPO), historia przebiegów (ostatnie 200) z liczbą pobranych
  dokumentów, wyzwalaczem (ręczna/przy starcie/automatyczna/ponowienie)
  i komunikatami błędów oraz przycisk „Ponów” dla nieudanej operacji.
- **Automatyczna kopia zapasowa** — raz dziennie przy starcie pełna kopia
  (faktury + słowniki + ustawienia) zapisuje się do
  `~/Library/Application Support/Ksefiarz/Backups/` z konfigurowalną
  rotacją: liczba przechowywanych kopii albo liczba dni wstecz.
- **Eksport** — zapis oryginalnego XML e-Faktury, generowanie PDF
  z klasycznym układem faktury (z kwotą słownie; długie faktury dzielone
  na wiele stron z numeracją) oraz eksport widocznej listy faktur do CSV
  (format zgodny z polskim Excelem).
- **Dwujęzyczny PDF (PL/EN)** — dla kontrahentów zagranicznych: wariant
  wydruku z etykietami w obu językach („Sprzedawca / Seller”, „Do zapłaty /
  Total due”…, angielskie nazwy form płatności). Wybór w menu „Eksportuj
  PDF” w szczegółach faktury i przełącznikiem w arkuszu e-mail; kontrahent
  z włączonym polem „Dokumenty dwujęzyczne (PL/EN)” w słowniku dostaje ten
  wariant automatycznie.
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
- **Procedura OSS (dział XII rozdz. 6a)** — pozycja faktury może mieć stawkę
  podatku od wartości dodanej państwa konsumpcji (pole „OSS %” w formularzu):
  do XML trafia P_12_XII zamiast polskiej stawki, a sumy do P_13_5/P_14_5;
  do tego oznaczenia procedur pozycji (WSTO_EE, IED…).
- **Załączniki do faktur (FA(3))** — sekcja „Załącznik” w formularzu:
  bloki danych z nagłówkiem, parami metadanych (wymagana min. jedna — XSD),
  akapitami tekstu i prostą tabelą (nagłówki i wiersze rozdzielane znakiem |);
  element Zalacznik w XML, odczyt i podgląd w szczegółach faktury.
  ⚠️ Wystawianie faktur z załącznikiem wymaga wcześniejszego zgłoszenia
  w e-Urzędzie Skarbowym.
- **Wysyłanie faktur e-mailem** — „Wyślij e-mailem” w szczegółach faktury
  sprzedażowej i menu listy: adresat podpowiadany ze słownika kontrahentów
  (pole „E-mail do faktur”, potem adres ogólny), edytowalny temat i treść,
  załączniki PDF i XML; wiadomość otwiera się w aplikacji Mail, a na
  fakturze zapisywana jest data i adres przekazania do wysyłki. Szablon
  treści po polsku albo po angielsku (przełącznik języka w arkuszu;
  angielski podpowiadany dla kontrahentów z dokumentami dwujęzycznymi).
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
- **Faktury kosztowe spoza KSeF** — „Dodaj zakup” na liście zakupów:
  ręczne wprowadzanie dokumentów, których nie ma w KSeF (faktury
  zagraniczne, paragony z NIP) dla pełnego obrazu VAT i przepływów.
  Formularz z NIP/VAT ID (może być pusty), kwotami netto/VAT (brutto
  wyliczane), walutą z kursem NBP, kategorią kosztu i płatnością.
  Takie dokumenty mają odznakę „Spoza KSeF” i — w odróżnieniu od zakupów
  pobranych z KSeF — można je edytować i usuwać.
- **Raporty sprzedaży i kosztów** (sekcja „Raporty” w pasku bocznym) —
  top kontrahenci sprzedaży (wykres + tabela: liczba faktur, netto,
  brutto), przychody per towar/usługa (z pozycji faktur) oraz koszty per
  kategoria (netto/VAT/brutto z sumami). Kategorię kosztu przypisuje się
  w szczegółach faktury zakupowej (podpowiedzi z listy typowych i już
  użytych) albo przy ręcznym dodawaniu zakupu. Kwoty w PLN po kursie
  z faktury; okres analizy wybierany jak w Kokpicie.
- **Rozbudowany Kokpit** — oprócz podsumowań kwot i najbliższych płatności:
  VAT należny/naliczony/saldo w analizowanym okresie, wykres przepływów
  pieniężnych z ostatnich 6 miesięcy (wg ewidencji wpłat), struktura wiekowa
  nieopłaconych należności i zobowiązań (przed terminem, 1–30, 31–60, 61–90,
  ponad 90 dni — po saldzie z uwzględnieniem wpłat częściowych) oraz
  porównanie bieżącego i poprzedniego miesiąca (sprzedaż, zakupy,
  VAT należny, zmiana %). Kwoty walutowe po kursie z faktury.
- **Powiadomienia** — systemowe powiadomienia o nowych fakturach zakupowych
  z synchronizacji oraz o terminach: płatność wypadająca dziś lub jutro
  (należności i zobowiązania, z kwotą pozostałą do zapłaty) i termin
  dosłania dokumentu offline do KSeF (dziś / po terminie). Każde
  powiadomienie najwyżej raz dziennie na fakturę; oba rodzaje wyłączane
  w Ustawieniach.
- **Faktury korygujące** — „Wystaw korektę” w szczegółach faktury sprzedażowej:
  dokument KOR z danymi faktury korygowanej (DaneFaKorygowanej), pozycjami
  wyrażającymi różnicę (kwoty ujemne dozwolone) i przyczyną korekty.
- **UPO** — automatyczne pobieranie i lokalne przechowywanie Urzędowego
  Poświadczenia Odbioru (XML) po przyjęciu faktury; w szczegółach można
  ponowić pobranie lub wyeksportować zapisany dokument także bez sieci.
- **Eksport JPK_V7M** — ewidencja VAT wybranego miesiąca (sprzedaż
  z podziałem na stawki, oznaczenia GTU i procedur z pozycji; zakupy jako
  pozostałe nabycia) z częścią deklaracyjną VAT-7 (kwoty w pełnych złotych,
  do wpłaty / do przeniesienia). Plik zgodny z oficjalną XSD JPK_V7M(2);
  arkusz pokazuje podsumowanie i listę pozycji do ręcznej weryfikacji
  (m.in. pozycje OSS rozliczane poza JPK, procedura marży, brak kursu).
- **Wezwania do zapłaty i noty odsetkowe** — dla dłużników z zaległymi
  fakturami (kandydaci ze struktury wiekowej Kokpitu): wybór faktur,
  odsetki naliczane od salda według konfigurowalnej stopy rocznej
  (domyślnie odsetki za opóźnienie w transakcjach handlowych), PDF
  z tabelą zaległości i sumami per waluta, zapis do pliku albo wysyłka
  e-mailem na adres ze słownika kontrahentów.
- **Paczka dla księgowości** — eksport wybranego okresu (miesiąc albo
  własny zakres dat) do jednego pliku ZIP: zestawienia CSV osobno dla
  sprzedaży i zakupu, oryginalne dokumenty XML, wydruki PDF oraz
  `raport.txt` z sumami per waluta i listą braków (dokumenty niewysłane
  do KSeF, odrzucone, bez UPO, bez XML, offline w kolejce, brak NIP
  nabywcy). Faktury ukryte nie wchodzą do paczki. Archiwum ZIP powstaje
  w całości w aplikacji (bez zależności zewnętrznych).
- **Ewidencja płatności** — historia wpłat na każdej fakturze: płatności
  częściowe, saldo pozostałe do zapłaty, znacznik „Częściowo” na listach.
  Pełne pokrycie kwoty brutto oznacza fakturę jako opłaconą automatycznie;
  ręczne decyzje pozostają nadrzędne. **Import wyciągu bankowego (MT940)**
  — standardowy format eksportu polskich banków (obsługa kodowań
  Windows-1250/Latin-2) — z automatycznymi propozycjami dopasowania:
  po numerze faktury w tytule przelewu (zaznaczane od razu) albo po zgodnej
  kwocie salda (do świadomego potwierdzenia); wpływy trafiają na faktury
  sprzedażowe, wypływy na zakupowe, a księgowanie następuje wyłącznie po
  zatwierdzeniu. Historia wpłat wchodzi w skład kopii zapasowej.
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

## Licencja

Projekt jest udostępniany na licencji [Apache License 2.0](LICENSE).
Możesz go używać, modyfikować i rozpowszechniać (także komercyjnie),
zachowując informację o licencji; licencja udziela też jawnej licencji
patentowej od kontrybutorów.
