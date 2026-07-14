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
    │   ├── KSeFAnonymousAccessService.swift # publiczne pobranie po numerze KSeF + danych
    │   ├── KSeFPermissionsService.swift # API permissions: nadawanie/odbieranie/przegląd uprawnień
    │   ├── KSeFCrypto.swift      # RSA-OAEP (SHA-256), AES-256-CBC, SHA-256
    │   ├── FA2XML.swift          # generator FA(3) i parser FA(2)/FA(3)/FA_RR(1)
    │   ├── FARRXML.swift         # generator VAT RR i dobór schemy sesji KSeF
    │   ├── InvoiceValidator.swift# walidacja pól + suma kontrolna NIP/PESEL
    │   ├── BatchInvoicePDFBuilder.swift # wiele faktur w jednym PDF / wydruku
    │   ├── TabularFileReader.swift # odczyt CSV/TSV/XLSX do wspólnej tabeli
    │   └── BulkImportService.swift # zapis planu importu do SwiftData
    ├── Logic/
    │   ├── AnonymousInvoiceImportEngine.swift # parser + deduplikacja anonimowego zakupu
    │   ├── InvoiceFilter.swift   # filtrowanie list (status płatności, wyszukiwarka)
    │   ├── DashboardMetrics.swift# agregaty Kokpitu (ukryte faktury pomijane)
    │   ├── PermissionsEngine.swift # walidacja i normalizacja uprawnień KSeF
    │   ├── InvoiceAutomationEngine.swift # duplikaty i terminy cykli
    │   ├── ElixirPaymentExporter.swift # walidacja i eksport paczki przelewów .pli
    │   ├── WaproXMLExporter.swift # dokumenty do importu w WAPRO Kaper/Fakir
    │   ├── KPiREngine.swift       # KPiR 2026: klasyfikacja, sumy i CSV 1–19
    │   ├── RyczaltEngine.swift    # ryczałt 2026: stawki, przychód i CSV 1–17
    │   ├── JPKV7VATRRPolicy.swift # art. 116: kwalifikacja VAT RR po zapłacie/zwrocie
    │   ├── ContractorHistory.swift # salda i scoring płatniczy kontrahenta
    │   └── BulkImportEngine.swift  # mapowanie, walidacja i deduplikacja importu
    └── Views/
        ├── MainContentView.swift # NavigationSplitView + pasek boczny
        ├── DashboardView.swift   # Kokpit: podsumowania, płatności na 7 dni
        ├── InvoiceListView.swift # listy zakupów/sprzedaży, swipe/menu, badge
        ├── AnonymousInvoiceImportView.swift # arkusz pobrania zakupu bez logowania
        ├── InvoiceDetailView.swift # szczegóły + podgląd surowego XML
        ├── NewInvoiceView.swift  # formularz wystawiania faktury z walidacją
        ├── PermissionsView.swift # sekcja „Uprawnienia” + arkusz nadawania
        ├── ContractorVerificationView.swift # karta weryfikacji kontrahenta (krajowa)
        ├── VIESVerificationView.swift # karta weryfikacji VAT-UE (kontrahent UE)
        ├── ContractorHistoryView.swift # dokumenty, salda i terminowość kontrahenta
        ├── BankTransferExportView.swift # zakupowe przelewy Elixir-O / MPP
        ├── InvoiceAutomationView.swift # szablony, cykle i kolejka zatwierdzeń
        ├── HiddenInvoicesView.swift # archiwum „Nieuprawnione / Ukryte”
        ├── BulkImportView.swift  # kreator importu CSV/Excel z podglądem
        └── SettingsView.swift    # NIP, token KSeF, środowisko
Tests/KsefiarzCoreTests/          # Swift Testing — model, parser, usługa, kryptografia, logika
```

## Funkcje

- **Integracja z KSeF 2.0** — pełny, produkcyjny przepływ API v2
  (`api-test`/`api-demo`/`api.ksef.mf.gov.pl`): uwierzytelnienie certyfikatem
  lub tokenem, pobieranie faktur zakupowych (metadane + oryginalny XML),
  wystawianie faktur w sesji interaktywnej z obowiązkowym szyfrowaniem AES-256-CBC.
- **Anonimowe pobranie pojedynczej faktury** — na liście zakupów pod „+”
  znajduje się akcja „Pobierz po numerze KSeF…”. Pozwala wciągnąć fakturę,
  która nie pojawiła się w zwykłej synchronizacji, po podaniu numeru KSeF,
  numeru faktury sprzedawcy, identyfikatora i nazwy nabywcy oraz kwoty brutto.
  Aplikacja korzysta z publicznej bramki MF właściwej dla wybranego środowiska
  (`qr-test` / `qr-demo` / `qr.ksef.mf.gov.pl`), więc operacja nie wymaga
  tokenu, certyfikatu ani logowania i niczego nie zapisuje w KSeF. Pobrany
  oryginalny XML przechodzi przez ten sam parser i scalanie co synchronizacja:
  dokument trafia do zakupów, duplikat po numerze KSeF nie powstaje (także gdy
  wcześniejsza faktura jest ukryta), a ręczny znacznik „Opłacona” nie jest
  cofany.
- **Wysyłka wsadowa (sesja batch/ZIP)** — przycisk „Wyślij wsadowo do KSeF”
  na liście sprzedaży (oraz akcja zbiorcza w menu kontekstowym zaznaczenia)
  wysyła wiele lokalnych dokumentów jedną paczką ZIP zamiast pojedynczych
  sesji interaktywnych — do migracji z innego systemu (np. po imporcie
  CSV/Excel) i nadrabiania zaległości. Arkusz pokazuje kwalifikujące się
  dokumenty (lokalne, jeszcze nie przekazane do KSeF — także samofaktury
  i VAT RR; FA(3) i FA_RR(1) idą w osobnych sesjach), prosi o potwierdzenie
  z nazwą środowiska i po przetworzeniu paczki pokazuje wynik per dokument
  (numer KSeF / odrzucenie / w toku). Statusy są korelowane po skrócie
  SHA-256 dokumentu (zalecenie MF), UPO pobierane wspólną ścieżką, a sesje
  przetwarzane dłużej domyka automatyczna synchronizacja. Dokument, którego
  paczka nie dostarczyła (błąd całej sesji), wraca do stanu lokalnego i można
  go wysłać ponownie. Przepływ zweryfikowany e2e na środowisku testowym KSeF
  (paczka 3 faktur → 3 numery KSeF + UPO).
- **Faktury VAT RR (rolnik ryczałtowy)** — w formularzu wystawiania można
  wybrać dokument VAT RR, wskazać dostawcę–rolnika, klasę/jakość produktu
  rolnego oraz stawkę zryczałtowanego zwrotu 7% (lub historyczną 6,5%).
  Aplikacja poprawnie odwraca role stron (rolnik jest dostawcą, firma
  użytkownika nabywcą), zapisuje dokument jako zakup i generuje osobną,
  oficjalną strukturę `FA_RR (1)` (`1-1E`, namespace z 6.03.2026), a sesję
  KSeF otwiera z `formCode` `FA_RR`. Obsługiwane są również korekty
  `KOR_VAT_RR`, odczyt pobranego XML, tryby offline oraz osobny wzorzec
  numeracji RR w Ustawieniach. Funkcja wymaga wcześniejszego uprawnienia
  `RRInvoicing`; specyfikacja: [struktura logiczna FA_RR(1)](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/struktura-logiczna-fa_rr/).
- **Samofakturowanie (wystawianie faktur w imieniu dostawcy)** — przełącznik
  „Samofakturowanie” w formularzu wystawiania (oraz wejście „Wystaw
  samofakturę” pod „+” na liście zakupów) wystawia zwykłą fakturę FA(3)
  z adnotacją `P_17 = 1` (art. 106d ustawy o VAT), w której sprzedawcą
  (Podmiot1) jest dostawca, a nabywcą (Podmiot2) firma użytkownika. Dokument
  jest zapisywany jako **zakup** (koszt w KPiR, VAT naliczony w JPK), ale ma
  pełny cykl wysyłki do KSeF jak sprzedaż: edycja/usuwanie póki lokalny,
  wysyłka we własnym kontekście firmy, statusy, UPO, tryby offline i korekty
  (korekta dziedziczy adnotację i role stron). Wysyłka wymaga uprawnienia
  podmiotowego `SelfInvoicing`, które dostawca nadaje firmie użytkownika
  w swoim KSeF — relację weryfikuje KSeF przy przyjęciu pliku. Osobna seria
  numeracji samofaktur w Ustawieniach (pusty wzorzec dziedziczy serię VAT);
  na PDF drukowana jest wymagana adnotacja „samofakturowanie”, a rachunek
  płatności to rachunek dostawcy. Faktury sprzedaży pobrane z KSeF
  z adnotacją P_17 (wystawione przez klienta w imieniu użytkownika) dostają
  znacznik „Samofakturowanie” na liście i w szczegółach, ale pozostają
  dokumentami tylko do odczytu — ich korektę wystawia klient, który sporządził
  fakturę pierwotną w ramach umowy o samofakturowaniu.
- **Faktury proforma** — osobna sekcja „Faktury proforma" na dokumenty
  handlowe, które **nie idą do KSeF** i nie wchodzą do rozliczeń podatkowych
  (proforma nie jest fakturą VAT). Wystawianie z lekkiego formularza (NIP
  nabywcy opcjonalny — np. konsument), wydruk PDF „Faktura PROFORMA" z adnotacją
  i kodem QR płatności, wysyłka e-mailem. Po zapłacie jednym kliknięciem
  **„Konwertuj na fakturę VAT"** — otwiera formularz faktury wypełniony danymi
  proformy (numer z serii VAT); po wystawieniu proforma zostaje oznaczona jako
  rozliczona, a potwierdzony status zapłaty jest przenoszony na fakturę.
  Kurs waluty obcej trzeba uzupełnić dla daty nowej faktury. Osobna numeracja
  (wzorzec `PF/…`) i objęcie kopią zapasową.
- **Uwierzytelnianie certyfikatem KSeF (preferowane)** — podpis XAdES-BES
  dokumentu AuthTokenRequest wykonywany w całości lokalnie (własna
  kanonikalizacja i podpis RSA/ECDSA, bez zewnętrznych bibliotek).
  Certyfikat typu 1 można uzyskać wprost z aplikacji (wniosek CSR przez API;
  klucz prywatny nigdy nie opuszcza komputera) albo zaimportować z pliku
  `.p12`/PEM (RSA-2048 i EC P-256) — np. pozyskany w Aplikacji Podatnika.
  Obsługiwany jest też format wydawany przez KSeF: certyfikat `.crt` z osobnym,
  zaszyfrowanym kluczem prywatnym (PKCS#8 `ENCRYPTED PRIVATE KEY`, PBES2 —
  PBKDF2 + AES-CBC) — aplikacja prosi wtedy o hasło do klucza.
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
- **Weryfikacja kontrahenta** — karta „Zweryfikuj” (menu kontekstowe listy
  kontrahentów oraz przycisk w edytorze) łączy trzy sprawdzenia: poprawność
  NIP (suma kontrolna), status w Wykazie podatników VAT (Biała lista:
  czynny / zwolniony / niezarejestrowany) oraz — gdy podane są poświadczenia
  KSeF — relację uprawnień w KSeF (czy kontrahent nadał Twojej firmie
  uprawnienie podmiotowe, np. samofakturowanie). Werdykt oznaczony wagą
  (OK / informacja / ostrzeżenie / błąd). Uwaga: KSeF nie ma pojęcia
  „aktywnego konta” — faktura trafia do odbiorcy po jego NIP automatycznie,
  więc karta weryfikuje status VAT i relację uprawnień, a nie „aktywację
  konta” (której w KSeF nie ma).
- **Weryfikacja VAT-UE (VIES)** — dla kontrahentów unijnych (pole „Prefiks UE”
  ustawione na kraj inny niż PL) ta sama akcja „Zweryfikuj” otwiera kartę VIES
  zamiast krajowej: sprawdza w systemie VIES Komisji Europejskiej, czy numer
  VAT-UE jest aktywny do transakcji wewnątrzwspólnotowych (bez aktywnego numeru
  nabywcy nie zastosujesz stawki 0% do WDT). Gdy w Ustawieniach jest podany NIP
  Twojej firmy, aplikacja próbuje pobrać z VIES **numer potwierdzenia zapytania**
  (dowód sprawdzenia do celów należytej staranności). Publiczne API, bez klucza.
  Niepoprawny lub odrzucony przez VIES NIP firmy nie blokuje anonimowego
  sprawdzenia kontrahenta.
- **Historia kontrahenta** — ze słownika kontrahentów można otworzyć jedną
  kartę z wszystkimi widocznymi dokumentami sprzedaży i zakupu, przejść
  podwójnym kliknięciem do szczegółów faktury oraz sprawdzić należności,
  zobowiązania i saldo netto osobno dla każdej waluty. Karta pokazuje średni
  czas pełnej zapłaty oraz scoring terminowości odbiorcy (bardzo dobra / dobra /
  wymaga uwagi / słaba). Ocena dotyczy wyłącznie sprzedaży — terminowość
  zakupów opisuje zachowanie naszej firmy — i nie zgaduje daty zapłaty z
  samego ręcznego znacznika. Uwzględnia natomiast otwarte faktury po terminie;
  dokumenty ukryte są pomijane tak jak w pozostałych statystykach.
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
  7 dni roboczych od jej zakończenia. Aplikacja co minutę odczytuje publiczne,
  niewymagające logowania API **Latarni KSeF** Ministerstwa Finansów. Przy
  aktywnej przerwie lub awarii pokazuje treść komunikatu i przycisk użycia
  właściwego trybu; po komunikacie kończącym sama uzupełnia termin faktur
  powiązanych z tym zdarzeniem. Datę nadal można wpisać ręcznie — ręczna
  decyzja odłącza dokument od automatycznej aktualizacji. Zaplanowane przerwy
  są sygnalizowane z wyprzedzeniem do 7 dni. Gdy Latarnia jest nieosiągalna,
  formularz jawnie ostrzega, że tryb trzeba zweryfikować ręcznie. Awaria
  całkowita nie jest błędnie mapowana na zwykły offline: aplikacja blokuje
  wystawienie ustrukturyzowanego dokumentu do późniejszego dosłania, bo ten
  odrębny tryb podlega innym zasadom.
- **Kody QR na wydrukach** — każdy PDF faktury z numerem KSeF zawiera
  KOD I (link weryfikacyjny `qr.ksef.mf.gov.pl` z numerem KSeF w podpisie);
  dokumenty offline24 dostają KOD I z etykietą „OFFLINE” oraz KOD II
  „CERTYFIKAT” podpisany certyfikatem KSeF typu 2 (RSASSA-PSS/ECDSA).
- **Kod QR płatności (standard 2D ZBP)** — na własnych fakturach sprzedaży
  drukowany jest kod „Zapłać (QR)” zgodny z Rekomendacją Związku Banków
  Polskich: odbiorca skanuje go aplikacją banku, a rachunek, kwota i tytuł
  uzupełniają się automatycznie. Kod pojawia się tylko dla faktur w PLN
  z podanym rachunkiem i niezerowym saldem (kwota = pozostałe do zapłaty;
  faktura opłacona kodu nie dostaje). Przełącznik w Ustawieniach → Firma
  („Drukuj kod QR płatności na fakturach”, domyślnie włączony); niezależny
  od kodu weryfikacyjnego KSeF. Pole nazwy odbiorcy w standardzie ma tylko
  20 znaków — gdy pełna nazwa firmy się nie mieści, można podać własny,
  czytelny skrót („Nazwa odbiorcy na kodzie QR”); puste pole skraca nazwę
  automatycznie na granicy słowa. Kod wymaga poprawnego NIP firmy; znaki
  spoza rekomendacji ZBP są bezpiecznie normalizowane, aby nie uszkodzić
  struktury danych przelewu.
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
  wymaganych przez XSD FA(3) (Adres, Adnotacje, RodzajFaktury).
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
- **Globalna wyszukiwarka ⌘K** — paleta „Szukaj wszędzie…” (menu Edycja
  albo skrót ⌘K, działa też po zamknięciu okna głównego): jedno pole
  przeszukuje faktury sprzedaży i zakupu (numer, kontrahent, NIP, numer
  KSeF), proformy, kontrahentów ze słownika, ustawienia oraz sekcje
  aplikacji — bez polskich znaków też trafia („zolw” znajdzie „Żółw”).
  Enter otwiera najlepszy wynik: dokument w szczegółach, kontrahenta na
  karcie historii, ustawienie we właściwej zakładce z podświetlonym
  wierszem, sekcję w pasku bocznym. Faktury ukryte nie pojawiają się
  w wynikach (ta sama ochrona co w statystykach).
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
  z kwotą słownie (długie faktury są dzielone na wiele stron z numeracją),
  eksport widocznej listy faktur do CSV (format zgodny z polskim Excelem),
  wspólny PDF/druk wielu dokumentów oraz WAPRO XML dla księgowości.
- **Logo i branding PDF** — w Ustawieniach → Firma można włączyć logo,
  wybrać kolor główny i akcent oraz wpisać własną stopkę drukowaną na każdej
  stronie. Logo jest automatycznie skalowane, a konfiguracja trafia do kopii
  zapasowej. Branding obejmuje wyłącznie dokumenty własnej firmy (dla VAT RR:
  firmy jako nabywcy/wystawcy), więc pobrane faktury kosztowe nie dostają
  omyłkowo obcego znaku. Dokumenty samofakturowania (P_17) są wyłączone
  w obie strony: samofaktura jest formalnie fakturą dostawcy, a sprzedaż
  z tą adnotacją wystawił klient.
- **Dwujęzyczny PDF (PL/EN)** — dla kontrahentów zagranicznych: wariant
  wydruku z etykietami w obu językach („Sprzedawca / Seller”, „Do zapłaty /
  Total due”…, angielskie nazwy form płatności). Wybór w menu „Eksportuj
  PDF” w szczegółach faktury i przełącznikiem w arkuszu e-mail; kontrahent
  z włączonym polem „Dokumenty dwujęzyczne (PL/EN)” w słowniku dostaje ten
  wariant automatycznie.
- **Numeracja per rodzaj dokumentu** — każdy rodzaj (VAT/ZAL/ROZ/UPR/VAT RR/
  samofaktury/korekty) może mieć w Ustawieniach własny wzorzec i niezależną
  serię numeracji; na listach faktur dostępny jest filtr rodzaju dokumentu.
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
- **Import wsadowy CSV/Excel** — przycisk „Import CSV/Excel” w sekcji
  „Słowniki” otwiera kreator masowego importu **kontrahentów, towarów/usług
  albo faktur**. Obsługiwane są CSV/TSV (UTF-8, UTF-16 i Windows-1250;
  separator `;`, `,` lub tabulator) oraz pierwszy arkusz skoroszytu `.xlsx`.
  Nagłówki typowych eksportów Fakturowni i katalogu produktów wFirmy są
  dopasowywane automatycznie, a każdą kolumnę można przypisać ręcznie — dzięki
  temu działa też dowolny własny układ. Bilans przed zapisem pokazuje poprawne
  rekordy, duplikaty, błędy i ostrzeżenia oraz próbkę źródła. Powtarzane wiersze
  tej samej faktury stają się jej pozycjami; poprawne rekordy można wczytać
  mimo błędów w innych wierszach. Duplikaty nie nadpisują bazy (kontrahent:
  identyfikator podatkowy; produkt: SKU/EAN/nazwa; faktura: numer KSeF oraz
  rodzaj+numer+NIP-y stron), przy czym sprawdzane są również faktury ukryte.
  Faktura z numerem KSeF jest zapisywana jako przyjęta, bez numeru — jako
  lokalna. Stary binarny format `.xls` nie jest obsługiwany: z Fakturowni użyj
  opcji „Eksport do CSV”, a plik Excela zapisz jako `.xlsx`.
- **Uwagi na fakturze** — pole pod pozycjami na dowolny dopisek (np. podstawa
  zwolnienia z VAT); trafia do XML (stopka faktury) i na wydruk PDF.
- **Schemat FA(3)** — wystawiane faktury są generowane w bieżącej schemie
  FA(3) (zweryfikowane end-to-end na środowisku testowym KSeF); parser
  czyta dokumenty FA(2), FA(3) i osobną strukturę FA_RR(1).
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
- **Konfigurowalne szablony e-mail** — Ustawienia → E-mail: edytowalne
  wzory tematu i treści (osobno PL i EN) dla wysyłki faktury, proformy
  oraz automatycznych przypomnień przed i po terminie. Symbole
  `{numer}`, `{data}`, `{kwota}`, `{saldo}`, `{termin}`, `{rachunek}`,
  `{ksef}`, `{sprzedawca}`, `{nabywca}`, `{dni_po_terminie}` są
  podstawiane danymi dokumentu; wiersz, którego wszystkie symbole są
  puste (np. „Termin płatności: {termin}.” bez terminu), znika
  z wiadomości. Puste/przywrócone pole wraca do wbudowanego wzoru;
  własne szablony wchodzą do kopii zapasowej.
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
- **OCR faktur kosztowych (macOS Vision)** — przycisk „Wczytaj ze skanu /
  PDF (OCR)” w formularzu zakupu spoza KSeF (plik można też upuścić na
  okno): skan/zdjęcie (PNG, JPEG, TIFF, HEIC) albo PDF papierowej faktury
  jest rozpoznawany natywnie na komputerze (Vision, bez zależności
  zewnętrznych i bez wysyłania danych) i wstępnie wypełnia formularz —
  numer dokumentu, daty, sprzedawca z NIP/VAT ID i adresem (NIP walidowany
  sumą kontrolną, NIP własnej firmy pomijany), kwoty netto/VAT/brutto,
  waluta, rachunek NRB (walidacja IBAN), termin i forma płatności.
  PDF z warstwą tekstową czytany jest wprost (bez strat OCR); rozpoznane
  dane zawsze wymagają weryfikacji przed zapisem.
- **Raporty sprzedaży i kosztów** (sekcja „Raporty” w pasku bocznym) —
  top kontrahenci sprzedaży (wykres + tabela: liczba faktur, netto,
  brutto), przychody per towar/usługa (z pozycji faktur) oraz koszty per
  kategoria (netto/VAT/brutto z sumami). Kategorię kosztu przypisuje się
  w szczegółach faktury zakupowej (podpowiedzi z listy typowych i już
  użytych) albo przy ręcznym dodawaniu zakupu. Kwoty w PLN po kursie
  z faktury; okres analizy wybierany jak w Kokpicie.
- **Ewidencja podatku dochodowego — KPiR albo ryczałt** — w Ustawieniach →
  Firma wybierasz formę opodatkowania (zasady ogólne / podatek liniowy → KPiR
  albo ryczałt od przychodów ewidencjonowanych). Nie można prowadzić obu naraz —
  w pasku bocznym pojawia się tylko wybrana ewidencja.
  - **KPiR — Księga Przychodów i Rozchodów** — zgodna z 19-kolumnowym wzorem
    obowiązującym od 2026 r. Automatycznie ujmuje widoczne faktury sprzedażowe
    i zakupowe, przelicza kwoty walutowe na PLN, pokazuje przychód, koszty
    i dochód dla miesiąca lub roku oraz pozwala skorygować lokalną klasyfikację:
    datę zdarzenia, opis, kolumnę 9/10/12–15, kwotę podatkową, koszt B+R
    (kol. 18), uwagi i wykluczenie z księgi. Eksport CSV zawiera pełne kolumny
    1–19, w tym numer KSeF. CSV jest materiałem roboczym do weryfikacji
    księgowej — nie jest plikiem JPK_PKPIR.
  - **Ewidencja przychodów (ryczałt)** — zgodna z 17-kolumnowym wzorem od 2026 r.
    (Dz.U. 2025 poz. 1294) z podziałem na stawki 17%, 15%, 14%, 12,5%, 12%, 10%,
    8,5%, 5,5% i 3%. Obejmuje wyłącznie sprzedaż, przelicza kwoty walutowe na PLN,
    pokazuje przychód i szacowany ryczałt (bez odliczeń składek) łącznie oraz per
    stawka. Domyślną stawkę ustawiasz raz, a na każdym wpisie możesz ją nadpisać
    — podobnie datę wpisu, datę uzyskania przychodu, kwotę i uwagi (kol. 17).
    Eksport CSV zawiera pełne kolumny 1–17, w tym numer KSeF i identyfikator
    kontrahenta, oraz wiersz sumy przychodów per stawka.
  - We wszystkich ewidencjach faktury ukryte nigdy nie wchodzą do zestawienia,
    a lokalna klasyfikacja podatkowa wchodzi do kopii zapasowej.
- **Kalendarz i prognoza podatkowa** — Kokpit pokazuje cztery najbliższe
  obowiązki: ZUS/DRA i zaliczkę PIT (standardowo do 20. dnia), miesięczny
  JPK_V7 oraz płatność VAT (do 25. dnia). Terminy przypadające w weekend lub
  święto są przesuwane na pierwszy dzień roboczy. JPK pozostaje miesięczny
  także przy kwartalnym VAT; cykl VAT i PIT/ryczałtu ustawia się w
  Ustawieniach → Firma. Podatnik zwolniony z VAT może wyłączyć te dwa
  obowiązki i prognozę VAT.
  Prognoza bieżącego miesiąca albo kwartału pokazuje saldo VAT oraz szacowany
  PIT: dla KPiR według skali 12%/32% z kwotą zmniejszającą albo liniowo 19%,
  a dla ryczałtu według stawek przypisanych do wpisów. Kwoty są robocze —
  opierają się na fakturach i lokalnej klasyfikacji, bez składek
  ZUS/zdrowotnej, ulg, innych źródeł, proporcji VAT i faktycznie wpłaconych
  zaliczek; przed zapłatą wymagają weryfikacji księgowej.
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
- **Eksport JPK_V7M / JPK_V7K** — ewidencja VAT wybranego miesiąca (sprzedaż
  z podziałem na stawki, oznaczenia GTU i procedur z pozycji; zakupy jako
  pozostałe nabycia) z częścią deklaracyjną VAT-7/VAT-7K (kwoty w pełnych
  złotych, do wpłaty / do przeniesienia). W arkuszu wybierasz wariant:
  **miesięczny** (JPK_V7M) albo **kwartalny** (JPK_V7K — mały podatnik / VAT
  kwartalny), gdzie ewidencję składa się co miesiąc, a deklarację raz na
  kwartał — powstaje ona tylko w pliku ostatniego miesiąca kwartału i obejmuje
  sumy całego kwartału. Dla okresów od lutego 2026 r. generator stosuje
  aktualne schemy JPK_V7M(3)/JPK_V7K(3), w tym numer KSeF albo wymagany
  znacznik OFF/BFK/DI; dla wcześniejszych okresów od 2022 r. zachowuje
  historyczne schemy (2). Pliki są zgodne z oficjalnymi XSD;
  arkusz pokazuje podsumowanie i listę pozycji do ręcznej weryfikacji
  (m.in. pozycje OSS rozliczane poza JPK, procedura marży, brak kursu).
  Faktury **VAT RR** są zakupem nabywcy: po zapisaniu pełnej zapłaty w historii
  wpłat (albo przy dacie zapłaty z dokumentu), formie przelewu i rachunku
  rolnika generator ujmuje je w okresie zapłaty z `DokumentZakupu=VAT_RR`,
  wartością w `K_42` i zryczałtowanym zwrotem w `K_43`. Częściowa lub
  nieudokumentowana zapłata jest bezpiecznie pomijana z ostrzeżeniem; korekta
  zmniejszająca wymaga daty bankowego zwrotu przez rolnika. Przed wysyłką
  trzeba potwierdzić związek nabycia ze sprzedażą opodatkowaną oraz prawidłowe
  wskazanie faktury/numeru KSeF na dowodzie płatności (art. 116 ustawy o VAT).
- **Eksport VAT-UE** — informacja podsumowująca za wybrany miesiąc
  (obok JPK_V7M/V7K w menu „Ewidencje”): wewnątrzwspólnotowe dostawy towarów
  (WDT, część C), nabycia towarów (WNT, część D) i świadczenie usług UE
  (część E) na podstawie faktur. Kontrahent UE rozpoznawany po prefiksie
  kraju w numerze VAT (Grecja jako „EL”, Irlandia Płn. „XI” tylko dla
  towarów; GB pomijane po Brexicie), towar vs usługa z kodu CN/PKWiU
  pozycji, a sprzedaż dodatkowo po stawce 0%; dane niejednoznaczne są
  pomijane z ostrzeżeniem. Kwoty w pełnych
  złotych sumowane per kontrahent. Plik zgodny z oficjalną XSD VAT-UE(5)
  (zweryfikowany xmllint); arkusz pokazuje zestawienia i ostrzeżenia
  (import usług i procedura OSS pozostają poza VAT-UE).
- **Eksport JPK_FA (na żądanie)** — pełny JPK faktur VAT w strukturze
  JPK_FA(4), przekazywany wyłącznie na wezwanie organu podatkowego
  (kontrola, czynności sprawdzające, postępowanie; art. 193a Ordynacji
  podatkowej). Obejmuje **wyłącznie wystawione faktury sprzedaży** z pełnymi
  pozycjami — bez zakupów, bez samofaktur wystawionych w imieniu dostawców
  (trafiają do JPK_FA dostawcy) i bez faktur VAT RR (osobna struktura
  JPK_FA_RR). Zakres pliku wyznaczają daty wystawienia dopasowane do
  wezwania; kwoty pozostają w walucie faktury, a podatek przeliczony na
  złote trafia do pól P_14_xW. Historyczne stawki oraz oznaczenia `oo`/`np`
  z zaimportowanych pozycji są mapowane do właściwych pól JPK_FA. Faktury
  zaliczkowe i ich korekty prezentują pozycje w węźle Zamowienie,
  rozliczające (ROZ) wykazują numery faktur
  zaliczkowych, korekty wchodzą kwotami różnicy. Arkusz (menu „Ewidencje”)
  wymaga prawidłowego NIP i strukturalnego adresu podmiotu (wymóg XSD —
  osobne pola województwo/powiat/gmina itd., zapamiętywane w ustawieniach) i pokazuje
  sumy kontrolne oraz ostrzeżenia; nie pozwala zapisać dokumentu bez
  obowiązkowych wierszy faktur. Plik zgodny z oficjalną XSD
  Schemat_JPK_FA(4)_v1-0 (zweryfikowany xmllint). JPK na żądanie nie
  podlega korekcie i nie przekazuje się go e-mailem (Klient JPK WEB albo
  nośnik danych).
- **Ścieżka windykacji** — dla dłużników z zaległymi fakturami (kandydaci
  ze struktury wiekowej Kokpitu, wejście też z menu listy sprzedaży) pełna
  eskalacja: **przypomnienie o płatności** (miękkie pismo bez odsetek) →
  **wezwanie do zapłaty** (odsetki od salda według konfigurowalnej stopy
  rocznej — domyślnie odsetki za opóźnienie w transakcjach handlowych) →
  **nota odsetkowa** → **dane do pozwu EPU** (e-sąd). Pisma powstają jako
  PDF z tabelą zaległości i sumami per waluta — do zapisu albo wysyłki
  e-mailem na adres ze słownika kontrahentów. Dane do EPU to komplet do
  przepisania do formularza na e-sad.gov.pl: strony, wartość przedmiotu
  sporu (bez odsetek, zaokrąglona w górę), wyliczona opłata od pozwu
  (1/4 opłaty z art. 13 uksc, min. 30 zł), roszczenia z odsetkami „od dnia
  następnego po terminie do dnia zapłaty”, lista dowodów i propozycja
  uzasadnienia; roszczenia w walucie obcej i wymagalne ponad 3 lata temu są
  jawnie wyłączane. Każdy utworzony dokument jest odnotowywany na fakturze —
  **status windykacji** (znacznik na liście sprzedaży i sekcja w
  szczegółach) pokazuje osiągnięty etap, a aplikacja podpowiada następny
  krok eskalacji.
- **Automatyczne przypomnienia e-mail o płatnościach** — cykliczne miękkie
  ponaglenia do kontrahentów: uprzedzenie na kilka dni przed terminem
  i powtarzane co N dni ponaglenia po terminie (dni konfigurowalne
  w Ustawieniach → Faktury; funkcja domyślnie wyłączona). Wiadomości
  (PL, a dla kontrahentów dwujęzycznych EN) zawierają saldo pozostałe do
  zapłaty, termin i rachunek; adresat pochodzi ze słownika kontrahentów.
  Dostarczanie przez aplikację Mail w dwóch trybach: **szkice** w Wersjach
  roboczych do przejrzenia i wysłania ręcznie albo **automatyczna wysyłka**
  — pierwsze użycie prosi o systemową zgodę na sterowanie Mail, a wynik
  przebiegu podsumowuje powiadomienie. Formalne wezwanie do zapłaty
  wstrzymuje miękkie przypomnienia danej faktury; faktury bez adresu
  e-mail są raportowane w dziennym powiadomieniu z numerami dokumentów,
  nie po cichu pomijane.
- **Miesięczny raport e-mail** — Ustawienia → E-mail (funkcja domyślnie
  wyłączona): na początku każdego miesiąca aplikacja przygotowuje
  podsumowanie zamkniętego miesiąca — liczba i kwoty sprzedaży
  (netto/VAT/brutto), zakupy, saldo VAT oraz stan należności na dzień
  raportu (w tym po terminie). Kwoty w PLN po kursie z faktury; pozycje
  walutowe bez kursu są jawnie policzone w ostrzeżeniu. Adresat własny
  albo (puste pole) e-mail podatnika z ustawień JPK; dostarczanie przez
  aplikację Mail jako szkic do przejrzenia albo automatyczna wysyłka.
  Jeden raport na miesiąc (pamięć zaraportowanych okresów); raport jest
  poglądowy i nie zastępuje ewidencji księgowej.
- **Paczka dla księgowości** — eksport wybranego okresu (miesiąc albo
  własny zakres dat) do jednego pliku ZIP: zestawienia CSV osobno dla
  sprzedaży i zakupu, oryginalne dokumenty XML, wydruki PDF oraz
  `raport.txt` z sumami per waluta i listą braków (dokumenty niewysłane
  do KSeF, odrzucone, bez UPO, bez XML, offline w kolejce, brak NIP
  nabywcy). Faktury ukryte nie wchodzą do paczki. Archiwum ZIP powstaje
  w całości w aplikacji (bez zależności zewnętrznych).
- **Eksport do WAPRO Kaper/Fakir** — menu „Dokumenty” na liście zapisuje
  zaznaczone faktury, a bez zaznaczenia wszystkie widoczne, jako jeden plik
  WAPRO XML (`MAGIK_EKSPORT`, wersja 4.3.2; maks. 999 dokumentów). Plik zawiera
  kartotekę kontrahentów, sprzedaż/zakup i korekty, pozycje, rejestr VAT,
  wartości walutowe i kurs, formę płatności, MPP, numer KSeF oraz kody
  GTU/procedur. Import w WAPRO zaczyna się od „Narzędzia → Import dokumentów”
  po zdefiniowaniu źródła WAPRO XML; dokumenty należy najpierw sprawdzić
  w buforze. Brak kursu PLN lub pozycji nie jest ukrywany — po zapisie
  aplikacja pokazuje ostrzeżenia. Format oparto na
  [publicznej specyfikacji WAPRO](https://wapro.pl/dokumentacja-erp/desktop/docs/finanse-i-ksiegowosc/informacje-uzupelniajace/kh-99.010-specyfikacja-pliku-XML/)
  i [instrukcji importu WAPRO Kaper](https://wapro.pl/dokumentacja-erp/desktop/docs/ksiega-podatkowa/narzedzia-i-moduly/kp-90.20.005-import-dokumentow/).
- **Zbiorczy PDF i druk** — to samo menu „Dokumenty” oraz menu kontekstowe
  multiselectu łączą wydruki zaznaczonych (albo wszystkich widocznych)
  faktur w jeden PDF, zachowując kolejność listy i wszystkie strony każdej
  faktury. Plik można zapisać lub od razu przekazać do systemowego okna
  drukowania macOS. Faktury ukryte nie pojawiają się na liście, więc nie są
  przypadkiem dołączane.
- **Przelewy do banku (Elixir-O)** — z listy zakupów można wyeksportować
  zaznaczone faktury (albo wszystkie widoczne) do pliku `.pli` importowanego
  jako paczka przelewów w polskiej bankowości. Arkusz wybiera rachunek
  zleceniodawcy, datę i kodowanie (UTF-8, Windows-1250 lub ISO-8859-2),
  pokazuje pominięte dokumenty i kontroluje NRB wraz z sumą kontrolną.
  Eksport obejmuje wyłącznie widoczne, nieopłacone zakupy w PLN z poprawnym
  rachunkiem sprzedawcy; kwotą jest pozostałe saldo. MPP tworzy komunikat
  `/VAT/…/IDC/…/INV/…` (kod `53`), z edytowalną kwotą VAT — przy płatności
  częściowej aplikacja podpowiada ją proporcjonalnie. Dla zgodności z bankami
  jedna paczka ma maksymalnie 50 dyspozycji. Plik zawsze trzeba sprawdzić
  i autoryzować w banku; samo zapisanie **nie oznacza faktur jako opłaconych**.
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
  w menu kontekstowym: oznacz jako opłacone/nieopłacone, ukryj (zakupy),
  eksportuj do WAPRO XML albo zapisz/drukuj jako jeden PDF.
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
| Baza aplikacji (SwiftData/SQLite): faktury, pozycje, statusy wysyłki, surowe XML i UPO, faktury proforma, szablony i harmonogramy | `~/Library/Application Support/Ksefiarz/Ksefiarz.store` (+ pliki `-wal`, `-shm`) |
| Ustawienia: dane firmy, branding PDF (w tym pomniejszone logo), środowisko, numeracja, filtry | `~/Library/Preferences/pl.itkrak.ksefiarz.plist` |
| **Token KSeF** | pęk kluczy macOS (Keychain), pozycja `pl.itkrak.ksefiarz` |
| **Certyfikaty KSeF (typ 1 i 2) z kluczami prywatnymi** | pęk kluczy macOS, pozycje `ksef.cert.*` w usłudze `pl.itkrak.ksefiarz` (osobno per środowisko) |
| Eksporty (XML / WAPRO XML / PDF / zbiorczy PDF / CSV / UPO / kopia zapasowa) | lokalizacja wybrana w panelu zapisu |

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
