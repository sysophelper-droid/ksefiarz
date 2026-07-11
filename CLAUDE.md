# Ksefiarz — przewodnik dla Claude Code

Natywna aplikacja macOS (SwiftUI + SwiftData, Swift Package) do zarządzania
fakturami z pełną integracją z **KSeF 2.0** (produkcyjne API, prawdziwa
kryptografia). Język projektu: **polski** — UI, komentarze, komunikaty błędów,
nazwy testów. Kod w trybie języka Swift 5 (`.swiftLanguageMode(.v5)`).

## Komendy

```bash
swift build                  # kompilacja (debug)
swift test                   # WSZYSTKIE testy muszą przechodzić przed oddaniem zmiany
./Scripts/build-app.sh       # natywny bundle → dist/Ksefiarz.app (release, icns, ad-hoc codesign)
open dist/Ksefiarz.app       # uruchomienie aplikacji
swift run Ksefiarz           # uruchomienie deweloperskie (bez bundla)
```

Testy integracyjne na żywo (opcjonalne, wyłącznie odczyt; poświadczenia
użytkownika z UserDefaults aplikacji):

```bash
KSEF_LIVE_NIP="$(defaults read pl.itkrak.ksefiarz ksef.nip)" \
KSEF_LIVE_TOKEN="$(security find-generic-password -s pl.itkrak.ksefiarz -a ksef.token -w)" \
KSEF_LIVE_ENV="$(defaults read pl.itkrak.ksefiarz ksef.environment)" \
swift test --filter LiveKSeFIntegrationTests
```

⚠️ Środowisko użytkownika to **production** — testy na żywo mogą tylko czytać
(auth, query metadanych, pobieranie XML/UPO). **Nigdy nie wysyłaj faktur na
produkcję**; wysyłkę testuj na mockach albo na środowisku `test`.

Podgląd bazy (tylko odczyt): `sqlite3 -readonly ~/Library/Application\ Support/Ksefiarz/Ksefiarz.store`.

Token dla środowiska testowego (self-signed XAdES, działa wyłącznie na `test`;
wymaga venv z `signxml requests cryptography lxml`):

```bash
python3 Scripts/get-test-token.py --nip <NIP>
```

Wysyłka e2e na środowisku testowym (jedyna dozwolona wysyłka na żywo):

```bash
KSEF_LIVE_SEND=1 KSEF_LIVE_ENV=test KSEF_LIVE_NIP=<NIP> \
KSEF_LIVE_TOKEN=<token testowy> swift test --filter LiveSendTests
```

Tokeny per środowisko w pęku kluczy: produkcja `ksef.token`,
pozostałe `ksef.token.<env>` (patrz `TokenStore.account(forEnvironment:)`).
Certyfikaty KSeF analogicznie: `ksef.cert.auth`/`ksef.cert.offline`
(+ sufiks środowiska) — JSON z certyfikatem DER i kluczem prywatnym
(`KSeFCertificateStore.account(type:environmentRaw:)`).

Test na żywo uwierzytelnienia certyfikatem (self-signed, tylko `test`;
wykonuje też pełny wniosek o certyfikat KSeF):

```bash
KSEF_LIVE_NIP=<NIP> KSEF_LIVE_ENV=test swift test --filter LiveCertificateAuthTests
```

Weryfikacja kodów QR e2e na bramce qr-test (wysyła dokument offline na
środowisko testowe; NIP może być fikcyjny, np. 9999999999):

```bash
KSEF_LIVE_SEND=1 KSEF_LIVE_ENV=test KSEF_LIVE_NIP=9999999999 \
  swift test --filter LiveQRVerificationTests
```

## Architektura

```
Sources/KsefiarzApp/InvoiceApp.swift   # @main, ModelContainer, AppDelegate (ikona, migracja defaults)
Sources/KsefiarzCore/
  Models/      Invoice (@Model) + InvoiceLine + PaymentRecord (relacje; wpłaty
               przypisywać PO context.insert jak pozycje), InvoiceDraft
               (+ init(from: Invoice)), słowniki: Contractor, Product,
               BankAccount (@Model, dane tylko PODSTAWIANE do faktur —
               pola faktury zawsze edytowalne ręcznie)
  Services/    KSeFService (API 2.0), KSeFCrypto, FA2XML (generator+parser), InvoiceValidator,
               BackupService, FileExportService (NSSave/OpenPanel), InvoicePDFGenerator (+ kody QR),
               TokenStore (token w pęku kluczy), ContractorLookupService (Biała
               lista VAT, wl-api.mf.gov.pl — publiczne, bez klucza),
               kryptografia certyfikatów: ASN1DER (koder/czytnik DER),
               X509Builder (CSR PKCS#10, self-signed, podpisy RSA/EC),
               XAdESSigner (AuthTokenRequest, ręczna kanonikalizacja exc-c14n),
               KSeFCertificateStore (pęk kluczy), KSeFCertificateService
               (enrollment API), KSeFCertificateImporter (.p12/PEM),
               KSeFQRCode (linki weryfikacyjne KOD I/II + render QR)
  Logic/       InvoiceFilter, KSeFSyncFilter, DashboardMetrics, DateRangeResolver,
               DisplayDateFilter, InvoiceNumberGenerator, AmountInWords, InvoiceCSVExporter,
               PaymentFormPolicy, InvoiceSyncEngine (wspólny sync: ręczny,
               przy starcie i cykliczny — automatyka w MainContentView),
               PolishBusinessCalendar (dni robocze/święta — terminy offline24),
               OfflineQueueEngine (kolejka dosłań offline24),
               PaymentLedger (wpłaty częściowe/saldo — jedyne miejsce zmian
               historii wpłat), MT940Parser (wyciągi bankowe),
               PaymentMatcher (propozycje dopasowań przelewów)
  Views/       MainContentView (NavigationSplitView), InvoiceListView, InvoiceDetailView,
               NewInvoiceView (nowa/edycja/korekta), DashboardView, SettingsView, HiddenInvoicesView,
               DictionariesView (+ ContractorsView/ProductsView/BankAccountsView)
Tests/KsefiarzCoreTests/               # Swift Testing (#expect/#require), nazwy PO POLSKU
Scripts/build-app.sh                   # składanie bundla .app
```

Zasada: **logika domenowa w Logic/Services jako czyste funkcje/typy z testami**;
widoki tylko spinają logikę z SwiftUI. Klucze ustawień wyłącznie przez
`AppSettingsKeys` (@AppStorage).

## API KSeF 2.0 — fakty krytyczne

- Hosty: `https://api{-test,-demo,}.ksef.mf.gov.pl/api/v2` (enum `KSeFEnvironment`).
- Auth tokenem: challenge → RSA-OAEP(SHA-256) na `token|timestampMs` kluczem
  publicznym MF (z `/security/public-key-certificates`, usage `KsefTokenEncryption`)
  → `/auth/ksef-token` → polling `/auth/{ref}` do `status.code == 200` →
  `/auth/token/redeem` → Bearer JWT.
- Auth certyfikatem (preferowana; fail-back do tokenu): challenge → podpisany
  XAdES-BES `AuthTokenRequest` (ns `http://ksef.mf.gov.pl/auth/token/2.0`,
  `SubjectIdentifierType=certificateSubject`) → POST `/auth/xades-signature`
  (Content-Type `application/xml`) → polling → redeem. XAdESSigner emituje
  dokument w postaci kanonicznej (exc-c14n) bajt w bajt — NIE formatować XML.
  Środowisko `test` akceptuje self-signed (2.5.4.97 = `VATPL-{NIP}`).
- Certyfikaty KSeF: enrollment WYMAGA auth podpisem XAdES (tokenem się nie
  da — błąd 25002); CSR musi zawierać DOKŁADNIE dane z GET
  `/certificates/enrollments/data` (25003). Typy: `Authentication` (typ 1,
  logowanie), `Offline` (typ 2, tylko KOD II QR). Ważność 2 lata.
- Offline24: zwykła sesja interaktywna z `offlineMode: true` w żądaniu
  wysyłki; dosyłany XML musi być BAJT W BAJT tym, z którego policzono skrót
  do kodów QR (stąd `Invoice.offlineHashBase64` + wysyłka `rawXmlContent`
  przez `sendInvoiceXML`, nigdy ponowna generacja). Termin dosłania:
  następny dzień roboczy po dacie wystawienia (PolishBusinessCalendar).
- Kody QR: hosty `qr{-test,-demo,}.ksef.mf.gov.pl`; KOD I
  `/invoice/{NIP}/{DD-MM-RRRR}/{skrót SHA-256 Base64URL bez dopełnienia}`;
  KOD II `/certificate/Nip/{ctx}/{NIP}/{seryjny HEX}/{skrót}/{podpis}` —
  podpisywana ścieżka bez `https://` i bez podpisu; RSA = RSASSA-PSS
  (SHA-256, sól 32 B), EC = ECDSA P1363 (R‖S).
- Wysyłka: sesja interaktywna z obowiązkowym szyfrowaniem — AES-256-CBC (PKCS7),
  klucz AES zaszyfrowany RSA-OAEP (usage `SymmetricKeyEncryption`), skróty SHA-256.
- **Limity**: 8 żądań/s oraz **16 pobrań dokumentów faktur/min**. `perform()`
  ponawia 429 z wykładniczym backoffem; synchronizacja przekazuje
  `skipDocumentsFor:` (numery KSeF z kompletem danych lokalnie), żeby nie
  marnować limitu. Zapytanie o metadane: maks. zakres 3 miesiące.
- Transport za protokołem `HTTPTransport` — testy wstrzykują `MockTransport`;
  klucz publiczny przez `publicKeyResolver` (testy generują własną parę RSA
  i ODSZYFROWUJĄ to, co wysłała usługa — utrzymuj ten wzorzec).
- UPO: `sessions/{sessionRef}/invoices/ksef/{ksefNumber}/upo` — wymaga
  `ksefSessionReference` zapisanego przy wysyłce.

## FA(3) — zasady generowania XML

Generator emituje **FA(3)** (namespace `http://crd.gov.pl/wzor/2025/06/25/13775/`,
kodSystemowy "FA (3)", wariant 3; sesja interaktywna otwierana z formCode
"FA (3)"). Źródło prawdy: oficjalna XSD (CIRFMF/ksef-api). **Kolejność
elementów musi odpowiadać sekwencji XSD** — Fa: KodWaluty, P_1, P_2, P_6?,
P_13_x/P_14_x (+P_14_xW dla waluty obcej), P_15, Adnotacje (obowiązkowe!,
P_18A: 1=MPP/2=brak), RodzajFaktury (VAT/KOR/ZAL/ROZ), [korekta:
PrzyczynaKorekty?, TypKorekty, DaneFaKorygowanej], FakturaZaliczkowa* (ROZ),
FaWiersz*, Platnosc. Podmiot1 wymaga Adres; **Podmiot2 wymaga JST i GV**
(dla zwykłych faktur oba = 2) — to nowość FA(3), wykryta na żywym API.
Stawki → pola: 23→P_13_1, 8→P_13_2, 5→P_13_3, 0→P_13_6_1, zw→P_13_7.
Pozycja: kod z kropkami→PKWiU, same cyfry→CN (między P_7 a P_8A); GTU po P_12.
Uwagi faktury → Stopka/Informacje/StopkaFaktury (po elemencie Fa).
Korekty (KOR): kwoty to RÓŻNICA (mogą być ujemne); wybór NrKSeF=1 +
NrKSeFFaKorygowanej albo NrKSeFN=1. Parser jest odporny na przestrzenie nazw
(wyszukiwanie po nazwach lokalnych) — czyta FA(2) i FA(3).

## Niezmienniki domenowe (nie łamać!)

1. **`isPaid` nigdy nie jest automatycznie cofane** — znacznik „Zaplacono”,
   `PaymentFormPolicy` (formy „z góry”) i `applyDetails` mogą status tylko
   USTAWIĆ; ręczne decyzje użytkownika są nadrzędne.
2. **Ukryta faktura (`isArchivedOrHidden`) nie wraca przy synchronizacji** —
   deduplikacja po `ksefId` sprawdza WSZYSTKIE faktury, też ukryte.
   Ukrywanie dotyczy WYŁĄCZNIE zakupów (ochrona przed nieuprawnionymi).
3. **Faktury wysłane do KSeF są niezmienialne** — edycja/usuwanie tylko dla
   `isLocalOnly` (ksefId == nil); zmiana wysłanej = korekta (KOR).
4. Statystyki (DashboardMetrics) pomijają faktury ukryte.
5. SwiftData: nowe pola modeli MUSZĄ mieć wartości domyślne (lekka migracja
   istniejącej bazy użytkownika!); pozycje (`lines`) przypisuj PO
   `context.insert(invoice)`.
6. Listy: pojedyncze kliknięcie zaznacza, podwójne otwiera szczegóły
   (`contextMenu(forSelectionType:primaryAction:)`); multiselect z akcjami
   zbiorczymi. Ten sam wzorzec obowiązuje w widgecie płatności Kokpitu
   (tam ręcznie: podświetlenie + `onTapGesture(count: 2)`).

## Proces pracy

1. Każda zmiana logiki = testy (Swift Testing, polskie nazwy `@Test("...")`).
   Po zmianach: `swift test` — komplet na zielono.
2. Fakty o API/schemie weryfikuj u źródła (OpenAPI `https://api-test.ksef.mf.gov.pl/docs/v2/openapi.json`,
   XSD z CIRFMF/ksef-api, docs CIRFMF/ksef-docs) — nie zgaduj pól.
3. Po zmianach widocznych dla użytkownika: `./Scripts/build-app.sh`,
   `pkill -x Ksefiarz; open dist/Ksefiarz.app` (użytkownik pracuje na bundlu).
4. Aktualizuj README.md (funkcje, lokalizacje danych) przy zmianach funkcjonalnych.
5. Sekrety: token KSeF leży w pęku kluczy (usługa `pl.itkrak.ksefiarz`,
   konto `ksef.token`, dostęp przez `TokenStore`/`KeychainSecretStorage`) —
   NIE loguj go, nie commituj i nie zapisuj do UserDefaults ani kopii
   zapasowych. Bundle ad-hoc zmienia sygnaturę przy każdym wydaniu — pierwszy
   dostęp do tokenu po aktualizacji może wywołać systemowe okno „Zezwól".

## Dane użytkownika

- Baza: `~/Library/Application Support/Ksefiarz/Ksefiarz.store` (SQLite/SwiftData).
  ⚠️ Nigdy nie używaj domyślnej ścieżki SwiftData (`default.store`) — to plik
  współdzielony między procesami; 12.06.2026 migracja schematu wykonana przez
  `com.apple.icloudmailagent` skasowała w nim wszystkie faktury.
- Ustawienia: `~/Library/Preferences/pl.itkrak.ksefiarz.plist`.
- Token KSeF: pęk kluczy (generic password `pl.itkrak.ksefiarz` / `ksef.token`).
- Kopia zapasowa/eksporty: pliki wybierane przez użytkownika (bez tokenu).

## Znane ograniczenia

- Na produkcji pierwszy certyfikat KSeF trzeba zaimportować z pliku
  (pozyskany np. w Aplikacji Podatnika) — wniosek z aplikacji wymaga
  wcześniejszego zalogowania podpisem, a to na produkcji umożliwia dopiero
  ważny certyfikat typu 1.

- Wysyłka faktury przeszła e2e na środowisku `test` w schemie FA(3)
  (LiveSendTests, 12.06.2026: numer KSeF + UPO); na produkcji jeszcze
  nigdy nie wykonana.
- FA(3): poza zakresem pozostają faktury OSS w pełnym wymiarze (jest tylko
  oznaczenie procedury pozycji, np. WSTO_EE/IED) oraz załączniki do faktur.
- Bundle podpisany ad-hoc (dystrybucja wymaga Developer ID + notaryzacji).

Zadania i backlog: **`todo.md`** (zrealizowane `[x]`, otwarte `[ ]`) —
aktualizuj go przy domykaniu/dodawaniu zadań; CLAUDE.md służy wyłącznie
wiedzy o projekcie i zasadom pracy.
