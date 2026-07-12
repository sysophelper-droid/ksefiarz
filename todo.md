# Ksefiarz — TODO / backlog

Śledzenie zadań projektu. Zrealizowane oznaczaj `[x]`, otwarte `[ ]`.
Zasady pracy i wiedza projektowa są w `CLAUDE.md` — tu tylko zadania.

## Otwarte

- [ ] Pierwsza produkcyjna wysyłka faktury („Wystaw i wyślij" na środowisku
  produkcyjnym — ścieżka zweryfikowana e2e na środowisku testowym 12.06.2026).
- [ ] Developer ID + notaryzacja — dopiero przy dystrybucji poza własny
  komputer (decyzja: na sam koniec). Usunie też pytanie o pęk kluczy po
  każdym wydaniu (ad-hoc zmienia sygnaturę).

### Backlog propozycji funkcji (burza mózgów 12.07.2026)

Zaproponowane do decyzji; ⭐ = rekomendowane (największy zwrot / rozsądny
koszt, bez łamania „tylko odczyt na żywo"). Numeracja pomocnicza —
kolejność dowolna. ⚠️ operacje modyfikujące KSeF testować wyłącznie na `test`.

#### A. Zgodność / KSeF

- [ ] A3. Samofakturowanie — wystawianie faktur w imieniu dostawcy
  (uprawnienie `SelfInvoicing` już obsługiwane po stronie nadawania).
- [ ] A4. Wsadowa wysyłka do KSeF (sesja batch/ZIP) — masowa wysyłka zamiast
  pojedynczej sesji interaktywnej (migracja/zaległości). ⚠️ tylko `test`.
- [ ] A5. Anonimowy dostęp / pobranie faktury po numerze KSeF — wciągnięcie
  faktury zakupowej po numerze KSeF + danych, gdy nie przyszła synchronizacją.
- [ ] ⭐ A6. Auto-wykrywanie trybu awaryjnego KSeF — pobieranie komunikatów MF
  o niedostępności/awarii i automatyczne proponowanie trybu offline + terminu
  (dziś datę zakończenia zdarzenia wpisuje użytkownik ręcznie).
- [ ] A7. Weryfikacja kontrahenta w KSeF — sprawdzenie, czy odbiorca ma
  aktywne konto/uprawnienia w KSeF. Niszowe.

#### B. Podatki dochodowe / ewidencje

- [ ] B1. KPiR (Księga Przychodów i Rozchodów) — ewidencja dla zasad
  ogólnych/podatku liniowego, z eksportem.
- [ ] B2. Ewidencja przychodów (ryczałt) — z podziałem na stawki ryczałtu.
- [ ] ⭐ B3. Kalendarz i prognoza podatkowa — terminarz (JPK do 25., VAT,
  zaliczka PIT, ZUS) + szacunek kwot VAT/PIT do zapłaty za bieżący okres.
- [ ] B4. JPK_FA na żądanie — pełny JPK faktur (nie ewidencja), format dla
  kontroli US. Rzadkie.
- [ ] B5. Ewidencja JPK_V7 dla VAT RR — ujęcie zryczałtowanego zwrotu po
  stronie podatku naliczonego nabywcy (art. 116). Faktury VAT RR są zapisywane
  jako `kind == .purchase`, a w `salesBuckets` jest dziś jedynie defensywne
  ostrzeżenie dla stawek RR (ścieżka praktycznie nieosiągalna dla dokumentów
  RR). Wymaga własnej specyfikacji podatkowej i testów — świadomie poza
  zakresem A2 (który obejmował strukturę FA_RR(1), formularz, generator/parser
  i wysyłkę).

#### C. Płatności i windykacja

- [ ] ⭐ C1. Kod QR płatności na PDF (standard 2D ZBP) — klient skanuje i płaci
  z aplikacji banku; tanio (mamy już render QR).
- [ ] C2. Plik przelewów do banku (Elixir / przelew zbiorczy) — eksport
  zobowiązań (zakupów) do pliku importowalnego w bankowości.
- [ ] C3. Ścieżka windykacji — eskalacja: przypomnienie → wezwanie → nota →
  dane do EPU (e-sąd); status windykacji na fakturze (bazuje na wezwaniach).
- [ ] C4. Automatyczne przypomnienia e-mail przed/po terminie — cykliczne
  miękkie ponaglenia do kontrahentów (dziś powiadomienia tylko systemowe).

#### D. Kontrahenci / dane wejściowe

- [ ] ⭐ D1. OCR faktur kosztowych (macOS Vision) — skan/PDF papierowej faktury
  → dane do „zakupu spoza KSeF"; natywnie, bez zależności zewnętrznych.
- [ ] ⭐ D2. Karta / historia kontrahenta — jeden widok: wszystkie dokumenty,
  saldo, średni czas płatności, terminowość (scoring).
- [ ] D3. Weryfikacja VIES (kontrahenci UE) — sprawdzenie VAT-UE analogicznie
  do Białej listy dla krajowych.
- [ ] D4. Import wsadowy z CSV/Excel — masowy import kontrahentów, towarów,
  faktur (migracja z Fakturowni/wFirmy).

#### E. Dokumenty / wygląd

- [ ] ⭐ E1. Logo i branding na PDF — logo firmy, kolory, własna stopka
  (dziś wydruk „klasyczny", bez personalizacji).
- [ ] E2. Faktura proforma — dokument handlowy (nie idzie do KSeF),
  z konwersją proforma → właściwa faktura.
- [ ] E3. Eksport do formatów programów księgowych — struktura importowalna
  w Symfonii/Comarch/WAPRO (najlepiej pod konkretny program księgowej). Duży
  koszt, formaty zamknięte.
- [ ] E4. Wydruk wielu faktur naraz (batch PDF/druk) — jeden PDF/wydruk
  z zaznaczonych.

#### F. Skala / wielofirmowość / UX

- [ ] F1. Wielofirmowość (przełączanie kontekstu NIP) — kilka firm/NIP
  w jednej aplikacji z izolacją danych; fundament pod tryb biura rachunkowego.
  Duży koszt (dotyka modelu danych) — osobna, świadoma decyzja.
- [ ] F2. Blokada aplikacji Touch ID / hasłem — ochrona danych finansowych
  przy odejściu od biurka.
- [ ] F3. Globalna wyszukiwarka ⌘K — szybki skok do faktury/kontrahenta/
  ustawienia.
- [ ] F4. Cykliczny raport e-mail (podsumowanie miesiąca) — automatyczne
  zestawienie sprzedaż/VAT/należności na koniec okresu.
- [ ] F5. Konfigurowalne szablony e-mail — edytowalne wzory tematu/treści
  (dziś zaszyte PL/EN).

## Zrealizowane

### JPK_V7K — kwartalny wariant ewidencji VAT (12.07.2026)

- [x] B0. Generator JPK_V7K(2) obok JPK_V7M(2) — wariant kwartalny (mały
  podatnik / VAT kwartalny): ewidencja składana co miesiąc, część deklaracyjna
  raz na kwartał, wyłącznie w pliku ostatniego miesiąca kwartału (marzec,
  czerwiec, wrzesień, grudzień). Wtedy ewidencja obejmuje tylko ten miesiąc,
  a deklaracja VAT-7K(16) — sumy CAŁEGO kwartału, z elementem `Kwartal` (1–4).
  V7M i V7K to OSOBNE schematy XSD (V7M `.../11148/`, V7K `.../11149/` — różny
  namespace, kod formularza, kod i wariant deklaracji, dodatkowy `Kwartal`).
  Enum `JPKV7Variant` w `JPKV7Generator` (miesięce 1–2 kwartału → sama
  ewidencja z ostrzeżeniem; okno eksportu dobiera wariant, etykiety i nazwę
  pliku). Dokumenty (kwartalny z deklaracją oraz miesiąc-w-trakcie)
  zweryfikowane oficjalną XSD (xmllint). Nowy suite testów JPK_V7K.

### Faktury VAT RR — struktura FA_RR(1) (12.07.2026)

- [x] A2. Faktury RR (rolnik ryczałtowy): formularz VAT RR, generator i parser
  oficjalnej struktury FA_RR(1), właściwy formCode sesji, stawki zwrotu 7%/6,5%,
  korekty KOR_VAT_RR, tryby offline i osobna numeracja. Uprawnienie
  `RRInvoicing` było już obsługiwane. XML zweryfikowany z oficjalnym XSD (PR #18).

### Informacja podsumowująca VAT-UE (12.07.2026)

- [x] A1. Generator VAT-UE(5) obok JPK_V7M: WDT (część C), WNT (część D)
  i świadczenie usług UE (część E) z danych faktur. Kontrahent UE
  rozpoznawany po prefiksie kraju w numerze VAT (buyerNIP sprzedaż /
  sellerNIP zakup; GR→EL; XI tylko dla towarów; PL, GB i spoza UE pomijane),
  towar vs usługa z kodu CN/PKWiU pozycji, sprzedaż dodatkowo po stawce 0%,
  dane niejednoznaczne pomijane z ostrzeżeniem, kwoty w pełnych złotych sumowane
  per kontrahent. Import usług i procedura OSS świadomie poza VAT-UE
  (z ostrzeżeniami). Dokument zgodny z oficjalną XSD (crd.gov.pl/wzor/2021/
  01/12/10293) — zweryfikowany xmllintem. VATUEGenerator (czysta logika,
  pokrycie 99,6% linii, 23 testy) + VATUEExportView (menu „Ewidencje” na
  listach faktur). Cel złożenia na stałe = 1 (schema nie zna wariantu
  korekty); część F (call-off stock) poza zakresem.

### Pokrycie testami logiki domenowej (12.07.2026)

- [x] Domknięcie pokrycia testami `Logic/`, `Services/`, `Models/` do ~99%
  linii testowalnej logiki (Logic 99,72%; Models 100%; Services 92,86% — reszta
  to granica UI/sieć). 565 testów jednostkowych na zielono. Dopisane m.in.:
  etykiety/settery enumów, opisy błędów, ścieżki HTTP-error i guardy usług
  (przez atrapę transportu), błędne struktury krypto (X509/PKCS#8/ASN.1),
  dyspozytor uprawnień, kopie zapasowe, generatory FA(2)/JPK/PDF, import
  certyfikatu (PEM + fixture PKCS#12). Skrypt `Scripts/coverage-file.sh`.
  Świadomie poza testami jednostkowymi (granica UI/AppKit/sieć, jak `Views/`):
  `MenuBarController` (`NSStatusItem`), panele `FileExportService`,
  `InvoiceEmailService` (`NSSharingService`), sieciowy happy-path
  `QuickSyncRunner`; plus obronne guardy platformowych API (SecKey/CCCrypt),
  które nie zawodzą przy poprawnych danych.

### Specyfikacja pierwotna (sesja 11.06.2026)

- [x] Stos: Swift 5.10+/SwiftUI/SwiftData, NavigationSplitView, Dark Mode.
- [x] Model `Invoice` (+ `InvoiceLine`) z pełnym zakresem pól.
- [x] `KSeFService`: autoryzacja tokenem, pobieranie zakupów, wysyłka —
  docelowo z PRAWDZIWĄ integracją KSeF 2.0 (nie mock): RSA-OAEP, AES-256-CBC,
  produkcyjne API.
- [x] Statusy płatności (opłacona/do opłacenia/zaległa) z listy i szczegółów.
- [x] Ukrywanie faktur nieuprawnionych (sekcja Nieuprawnione/Ukryte,
  bez powrotu przy synchronizacji, poza statystykami).
- [x] Kokpit, listy sprzedaż/zakup z filtrami i wyszukiwarką, szczegóły
  z podglądem XML, Ustawienia (NIP + token).
- [x] Formularz wystawiania z walidacją; testy na zielono.

### Rozszerzenia (sesje 11–12.06.2026)

- [x] Korekty (KOR), UPO, PDF (wielostronicowy), CSV, kwota słownie,
  automatyczna numeracja, polityka form płatności.
- [x] Dedykowany plik bazy (`Ksefiarz/Ksefiarz.store`) po incydencie
  ze współdzielonym `default.store`.
- [x] Token KSeF w pęku kluczy (osobno per środowisko); kopia zapasowa
  bez tokenu.
- [x] Pierwsza wysyłka e2e na środowisku testowym (token testowy przez
  XAdES self-signed — `Scripts/get-test-token.py`).
- [x] Słowniki: kontrahenci (pobieranie danych po NIP z Białej listy),
  towary/usługi (CN/PKWiU, GTU, załącznik 15, cenniki), rachunki bankowe
  (+ domyślny dla nowych faktur).
- [x] Pole „Uwagi" na fakturze (Stopka), CN/PKWiU i GTU w pozycjach.
- [x] Synchronizacja automatyczna: przy starcie + interwałowa
  (15 min – 8 godz.), etykieta ostatniej synchronizacji, powiadomienia
  o nowych fakturach zakupowych.
- [x] Automatyczna kopia zapasowa dzienna z rotacją (liczba kopii / dni).
- [x] Migracja generatora na FA(3) (JST/GV w Podmiot2!), e2e na test.
- [x] Split payment (P_18A + podpowiedź z załącznika 15).
- [x] Faktury zaliczkowe (ZAL) i rozliczeniowe (ROZ).
- [x] Waluty obce (KodWaluty, kurs PLN, P_14_xW; przeliczenia w Kokpicie).
- [x] Weryfikacja rachunku na białej liście (endpoint `check` — obsługuje
  rachunki wirtualne).
- [x] Ustawienia z zakładkami (ikony) i wyszukiwarką ustawień.
- [x] Kursy walut z API NBP (przycisk przy polu kursu; ręczne wpisanie
  nadal możliwe; kurs z dnia poprzedzającego — art. 31a ustawy o VAT).
- [x] Korekty faktur zaliczkowych (KOR_ZAL/KOR_ROZ) i faktury UPR.
- [x] Procedury szczególne: marża (PMarzy — biura podróży / towary używane /
  dzieła sztuki / antyki) i oznaczenia procedur pozycji (WSTO_EE, IED…).
- [x] Wyszukiwarka ustawień prowadzi do pola (podświetlenie wiersza).
- [x] Automatyczna synchronizacja tylko na środowisku produkcyjnym
  (bezpiecznik przed śmieciami z testowego KSeF).
- [x] Wzorce numeracji per rodzaj dokumentu (VAT/ZAL/ROZ/UPR/KOR) —
  niezależne serie; puste pole dziedziczy wzorzec VAT.
- [x] Filtr rodzaju dokumentu na listach faktur.
- [x] „Wystaw korektę" w menu kontekstowym listy (dotąd tylko w szczegółach).
- [x] Kwoty pozycji w walucie faktury w formularzu (było: zawsze PLN).
- [x] Blokada duplikatu numeru dokumentu przy zapisie lokalnym i wysyłce
  (edycja może zachować własny numer; porównanie bez wielkości liter).
- [x] Pełny cykl statusu wysyłki KSeF: osobna referencja przesyłki i numer
  KSeF, stany lokalna/przetwarzana/przyjęta/odrzucona, automatyczne
  odpytywanie i pobieranie UPO, ręczne ponowienie oraz filtry listy.
- [x] Szablony i automatyzacja wystawiania: duplikowanie istniejącej faktury,
  zapisywanie szablonów, harmonogramy tygodniowe/miesięczne/roczne oraz
  obowiązkowy podgląd i ręczne zatwierdzenie przed zapisem lub wysyłką do KSeF.

### Rozszerzenia (sesja 12.07.2026)

- [x] Zarządzanie uprawnieniami KSeF (12.07.2026): sekcja „Uprawnienia” —
  nadawanie po NIP/PESEL uprawnień do pracy w KSeF (podmiot, np. biuro
  rachunkowe: InvoiceRead/InvoiceWrite + delegacja; osoba fizyczna: 7 zakresów)
  oraz uprawnień podmiotowych (samofakturowanie, przedstawiciel podatkowy,
  RR, PEF), przegląd nadanych dostępów i odbieranie (API permissions;
  operacje asynchroniczne z pollingiem `/permissions/operations/{ref}`).
  PermissionsEngine (walidacja NIP/PESEL, etykiety, normalizacja) +
  KSeFPermissionsService (rozszerzenie KSeFService) z pełnym pokryciem
  testami na mockach. Na produkcji nieprzetestowane na żywo (polityka
  „tylko odczyt na żywo”).
- [x] Automatyczne odnowienie certyfikatu KSeF (12.07.2026): na ~30 dni przed
  wygaśnięciem aplikacja sama składa wniosek o nowy certyfikat (typ 1 i typ 2)
  i podmienia go w pęku kluczy (CertificateRenewalEngine + Coordinator, czysta
  logika z testami; wpięcie w MainContentView — start + timer 12 h). Typ 1
  odnawia się wciąż ważnym typem 1, typ 2 — o ile typ 1 ważny; dedup jednej
  próby na certyfikat na dobę (UserDefaults), nieudana próba nie narusza
  działającego certyfikatu, powiadomienie o wyniku, przełącznik w Ustawieniach.

### Certyfikaty i offline24 (sesja 11.07.2026)

- [x] Uwierzytelnianie certyfikatem KSeF (typ 1): podpis XAdES-BES w czystym
  Swifcie (własna kanonikalizacja exc-c14n, RSA i EC P-256), preferencja
  certyfikatu z fail-backiem do tokenu, przechowywanie w pęku kluczy per
  środowisko, kontrola ważności (ostrzeżenie <30 dni). Zweryfikowane
  na żywo na środowisku testowym (auth self-signed → wniosek CSR →
  certyfikat KSeF → logowanie nim).
- [x] Wniosek o certyfikat z aplikacji (enrollment API: dane podmiotu → CSR
  PKCS#10 → polling → retrieve) oraz import z pliku .p12/PEM (PKCS#1,
  PKCS#8, SEC1; RSA-2048 i EC P-256) z walidacją pary klucz–certyfikat.
- [x] Tryb offline24: przełącznik przy wystawianiu + automatyczne przejście
  w offline przy braku sieci, kolejka dosłań (automat co 60 s + „Doślij
  teraz”), termin = następny dzień roboczy (polski kalendarz świąt,
  Wigilia od 2025), wysyłka zapisanego XML bajt w bajt z `offlineMode: true`.
- [x] Kody QR: KOD I (link weryfikacyjny, Base64URL skrótu SHA-256) na
  wszystkich PDF-ach faktur z numerem KSeF; na dokumentach offline KOD I
  z etykietą „OFFLINE” + KOD II „CERTYFIKAT” (RSASSA-PSS / ECDSA P1363
  certyfikatem typu 2); zgodność z przykładem z oficjalnej dokumentacji.
- [x] Weryfikacja kodów QR e2e na bramce `qr-test.ksef.mf.gov.pl`
  (LiveQRVerificationTests, 11.07.2026): KOD I → „Faktura znajduje się
  w KSeF”, tryb Offline, zgodność skrótu z dosłanym XML potwierdzona;
  KOD II → „Weryfikacja prawidłowa” (certyfikat, podpis, uprawnienia).
- [x] Paczka dla księgowości (11.07.2026): eksport miesiąca/zakresu do ZIP
  (własny ZipWriter bez zależności) — CSV per rodzaj, oryginalne XML,
  PDF-y i raport.txt z sumami per waluta oraz listą braków (niewysłane,
  odrzucone, bez UPO/XML, offline w kolejce, brak NIP nabywcy).
- [x] Ewidencja VAT / eksport JPK_V7M (12.07.2026): generator JPK_V7M(2)
  zgodny z oficjalną XSD (walidacja xmllint) — ewidencja sprzedaży per
  stawka z GTU i procedurami, zakupy jako pozostałe nabycia, deklaracja
  VAT-7(22) w pełnych złotych (P_51/P_62), ostrzeżenia o uproszczeniach
  (OSS poza JPK, marża, brak kursu, brak NIP → „BRAK”); arkusz eksportu
  na listach faktur.
- [x] Wezwania do zapłaty i noty odsetkowe (12.07.2026): PaymentDemandEngine
  (odsetki proste od salda, konfigurowalna stopa roczna), PDF z tabelą
  zaległości i sumami per waluta, wysyłka e-mailem (adres ze słownika);
  wejście z sekcji wiekowania Kokpitu i menu listy sprzedaży.
- [x] Powiadomienia o terminach (12.07.2026): płatność dziś/jutro
  (należności i zobowiązania, saldo w treści) oraz termin dosłania
  offline dziś/po terminie — raz dziennie na fakturę
  (DeadlineNotificationEngine, dedup w UserDefaults), przełącznik
  w Ustawieniach.
- [x] Tryby awaryjne KSeF (12.07.2026): wybór trybu przy wystawianiu
  (offline24 / niedostępność art. 106nh / awaria art. 106nf), terminy
  dosłań wg tabeli z docs CIRFMF (następny dzień roboczy / następny dzień
  roboczy od końca niedostępności / 7 dni roboczych od końca awarii),
  data zakończenia zdarzenia i zmiana trybu w szczegółach do czasu
  dosłania. Kopia zapasowa v5 (tryby offline, załącznik FA(3), OSS,
  e-mail).
- [x] Wysyłanie faktur e-mailem (12.07.2026): adresat ze słownika kontrahentów
  (adres fakturowy ma pierwszeństwo), edytowalny temat i treść, załączniki
  PDF/XML, przekazanie do aplikacji Mail (NSSharingService) oraz zapis daty
  i adresu wysłania na fakturze.
- [x] Rozbudowa Kokpitu (12.07.2026): VAT należny/naliczony/saldo w okresie,
  wykres przepływów pieniężnych z 6 miesięcy (ewidencja wpłat), struktura
  wiekowa nieopłaconych (po saldzie) i porównanie miesięczne ze zmianą %
  (DashboardAnalytics + Swift Charts).
- [x] Rozszerzenie FA(3) (12.07.2026): procedura OSS (P_12_XII w pozycji,
  sumy P_13_5/P_14_5, pole „OSS %” w formularzu) oraz załączniki do faktur
  (element Zalacznik: bloki z metadanymi, akapitami i tabelami; edytor
  w formularzu, podgląd w szczegółach). Wygenerowany dokument zweryfikowany
  oficjalną XSD FA(3) (xmllint). Wysyłka faktur z załącznikiem wymaga
  zgłoszenia w e-US — informacja w formularzu.
- [x] Centrum synchronizacji (11.07.2026): sekcja „Synchronizacja” z osobnymi
  stanami zakupów, sprzedaży i wysyłek, historią przebiegów (model SyncRun,
  ostatnie 200 wpisów) — liczba pobranych/nowych dokumentów, wyzwalacz,
  środowisko i błędy — oraz ponowieniem nieudanej operacji.
- [x] Ikona w pasku menu (12.07.2026): status synchronizacji, liczba
  oczekujących i zaległych dosłań offline (czerwony trójkąt po terminie),
  szybkie „Pobierz z KSeF” i powrót do okna aplikacji; przełącznik
  w Ustawieniach → Synchronizacja (MenuBarStatus + SyncActivity).
  - [x] NAPRAWA (12.07.2026): pierwsza wersja używała sceny SwiftUI
    `MenuBarExtra`, która na macOS 26 razem z `NavigationSplitView`
    wpadała w nieskończoną pętlę renderowania (100% CPU, zawieszenie
    aplikacji — niezależnie od przełącznika, bo scena była zawsze
    deklarowana). Przepisane na AppKit `NSStatusItem` w AppDelegate —
    bez dotykania grafu scen SwiftUI. Ta sama funkcjonalność.
- [x] Raporty sprzedaży i kosztów (12.07.2026): sekcja „Raporty” — top
  kontrahenci (wykres + tabela), przychody per towar/usługa, koszty per
  kategoria; pole `costCategory` na zakupach (edycja w szczegółach
  i przy ręcznym dodawaniu, podpowiedzi kategorii), kwoty w PLN.
- [x] Faktury kosztowe spoza KSeF (12.07.2026): „Dodaj zakup” na liście
  zakupów — faktury zagraniczne i paragony z NIP (NIP/VAT ID opcjonalny,
  kurs NBP, kategoria kosztu); odznaka „Spoza KSeF”, edycja i usuwanie
  ręcznych zakupów. Kopia zapasowa v6 (kategoria kosztu, flaga PL/EN
  kontrahenta).
- [x] Dwujęzyczny PDF (PL/EN) i angielski e-mail (12.07.2026): wariant
  wydruku z etykietami PL/EN (menu „Eksportuj PDF”, przełącznik w arkuszu
  e-mail), angielski szablon tematu i treści wiadomości; pole „Dokumenty
  dwujęzyczne (PL/EN)” w słowniku kontrahentów podpowiada oba automatycznie.
- [x] Rozbudowana ewidencja płatności (11.07.2026): historia wpłat
  (PaymentRecord) z płatnościami częściowymi i saldem, automatyczne
  oznaczenie opłacenia przy pełnym pokryciu (ręczne decyzje nadrzędne),
  import wyciągów MT940 (kodowania PL) i propozycje dopasowań przelewów
  (numer faktury w tytule / zgodna kwota salda) zatwierdzane przez
  użytkownika; wpłaty w kopii zapasowej.
