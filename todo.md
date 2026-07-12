# Ksefiarz — TODO / backlog

Śledzenie zadań projektu. Zrealizowane oznaczaj `[x]`, otwarte `[ ]`.
Zasady pracy i wiedza projektowa są w `CLAUDE.md` — tu tylko zadania.

## Otwarte

- [ ] Pierwsza produkcyjna wysyłka faktury („Wystaw i wyślij" na środowisku
  produkcyjnym — ścieżka zweryfikowana e2e na środowisku testowym 12.06.2026).
- [ ] Developer ID + notaryzacja — dopiero przy dystrybucji poza własny
  komputer (decyzja: na sam koniec). Usunie też pytanie o pęk kluczy po
  każdym wydaniu (ad-hoc zmienia sygnaturę).

### Rekomendowane rozszerzenia (sesja 12.07.2026)

- [ ] Automatyczne odnowienie certyfikatu KSeF: wniosek o nowy certyfikat
  (typ 1 i 2) przed wygaśnięciem starego, podmiana w pęku kluczy.
- [ ] Zarządzanie uprawnieniami KSeF: nadawanie/odbieranie uprawnień
  (np. biuro rachunkowe po NIP) i przegląd dostępów — API permissions.
- [ ] Ikona w pasku menu (menu bar extra): status synchronizacji, liczba
  zaległych i oczekujących dosłań, szybkie „Pobierz z KSeF”.
- [ ] Raporty sprzedaży i kosztów: top kontrahenci, przychody per
  towar/usługa, koszty per kategoria (wymaga tagów/kategorii na zakupach).
- [ ] Faktury kosztowe spoza KSeF: ręczne dodawanie zakupów (faktury
  zagraniczne, paragony z NIP) dla pełnego obrazu VAT i przepływów.
- [ ] Dwujęzyczny PDF (PL/EN) dla kontrahentów zagranicznych + angielski
  szablon treści e-mail.

## Zrealizowane

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
- [x] Rozbudowana ewidencja płatności (11.07.2026): historia wpłat
  (PaymentRecord) z płatnościami częściowymi i saldem, automatyczne
  oznaczenie opłacenia przy pełnym pokryciu (ręczne decyzje nadrzędne),
  import wyciągów MT940 (kodowania PL) i propozycje dopasowań przelewów
  (numer faktury w tytule / zgodna kwota salda) zatwierdzane przez
  użytkownika; wpłaty w kopii zapasowej.
