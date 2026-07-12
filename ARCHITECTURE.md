# Ksefiarz — architektura i wiedza o systemie

Dokumentacja techniczna projektu: mapa modułów, fakty o API KSeF 2.0, zasady
generowania schemy FA(3), lokalizacje danych i znane ograniczenia. To jest
**wiedza referencyjna** — zasady pracy i decyzje projektowe są w `CLAUDE.md`,
a backlog w `todo.md`.

Ksefiarz to natywna aplikacja macOS (SwiftUI + SwiftData, Swift Package) do
zarządzania fakturami z pełną integracją z **KSeF 2.0** (produkcyjne API,
prawdziwa kryptografia).

## Mapa modułów

```
Sources/KsefiarzApp/InvoiceApp.swift   # @main, ModelContainer, AppDelegate (ikona, migracja defaults)
Sources/KsefiarzCore/
  Models/      Invoice (@Model) + InvoiceLine + PaymentRecord (relacje; wpłaty
               przypisywać PO context.insert jak pozycje), InvoiceDraft
               (+ init(from: Invoice)), ManualPurchaseDraft (zakupy spoza
               KSeF: walidacja + makeInvoice/apply; Invoice.isManualPurchase
               = zakup bez ksefId, edytowalny/usuwalny;
               Invoice.costCategory — kategoria kosztu do raportów;
               lokalne pola kpir* + isExcludedFromKPiR — klasyfikacja
               podatkowa bez modyfikowania treści dokumentu KSeF),
               słowniki: Contractor (+ prefersBilingualDocuments — PDF
               PL/EN i angielski e-mail), Product,
               BankAccount (@Model, dane tylko PODSTAWIANE do faktur —
               pola faktury zawsze edytowalne ręcznie), SyncRun (@Model,
               historia przebiegów Centrum synchronizacji), FA3Attachment
               (bloki załącznika FA(3); na fakturze jako JSON
               w Invoice.attachmentJSON)
  Services/    KSeFService (API 2.0), KSeFCrypto, FA2XML (generator+parser), InvoiceValidator,
               BackupService (format v8 obejmuje metadane KPiR),
               FileExportService (NSSave/OpenPanel), InvoicePDFGenerator (+ kody QR,
               opcjonalny branding własnych dokumentów: logo, dwa kolory,
               stopka na każdej stronie),
               TokenStore (token w pęku kluczy), ContractorLookupService (Biała
               lista VAT, wl-api.mf.gov.pl — publiczne, bez klucza),
               kryptografia certyfikatów: ASN1DER (koder/czytnik DER —
               czytnik utwardzony na niezaufane wejście: odrzuca długości
               przepełniające Int / przekraczające bufor),
               X509Builder (CSR PKCS#10, self-signed, podpisy RSA/EC),
               XAdESSigner (AuthTokenRequest, ręczna kanonikalizacja exc-c14n),
               KSeFCertificateStore (pęk kluczy), KSeFCertificateService
               (enrollment API), KSeFCertificateImporter (.p12/PEM;
               certyfikat + klucz jawny lub zaszyfrowany PKCS#8),
               PKCS8EncryptedKey (odszyfrowanie ENCRYPTED PRIVATE KEY —
               PBES2: PBKDF2 HMAC-SHA1/224/256/384/512 + AES-128/192/256-CBC),
               KSeFPermissionsService (rozszerzenie KSeFService — nadawanie,
               odbieranie i przegląd uprawnień KSeF; API permissions),
               KSeFQRCode (linki weryfikacyjne KOD I/II + render QR),
               InvoiceEmailService (okno wiadomości Mail przez
               NSSharingService; załączniki PDF/XML z katalogu tymczasowego),
               InvoicePDFGenerator ma wariant dwujęzyczny
               (pdfData(for:bilingual:branding:), etykiety w InvoicePDFLabels);
               PDFBrandingLogoProcessor skaluje importowane logo do maks.
               1200 px i koduje PNG przed zapisem Base64 w UserDefaults,
               SyncActivity (współdzielony stan synchronizacji: pasek
               boczny + ikona w pasku menu; QuickSyncRunner — ręczne
               „Pobierz z KSeF” z paska menu; MainWindowOpener — most do
               openWindow dla ikony w pasku menu),
               MenuBarController (ikona w pasku menu jako AppKit NSStatusItem,
               NIE scena SwiftUI MenuBarExtra — patrz „Decyzje” w CLAUDE.md;
               @MainActor, uruchamiany z InvoiceApp.init() i
               MainContentView.onAppear, reużywa
               MenuBarStatus/SyncActivity/QuickSyncRunner; przełącznik
               ksef.menuBarExtra dodaje/usuwa ikonę na żywo — obserwacja
               UserDefaults.didChangeNotification)
  Logic/       InvoiceFilter, KSeFSyncFilter, DashboardMetrics, DateRangeResolver,
               DisplayDateFilter, InvoiceNumberGenerator, AmountInWords, InvoiceCSVExporter,
               PaymentFormPolicy, InvoicePDFBranding (czysta konfiguracja,
               normalizacja #RRGGBB i reguła zastosowania tylko do własnej
               sprzedaży; VAT RR po NIP nabywcy),
               InvoiceSyncEngine (wspólny sync: ręczny,
               przy starcie i cykliczny — automatyka w MainContentView),
               PolishBusinessCalendar (dni robocze/święta — terminy trybów
               offline), OfflineQueueEngine (kolejka dosłań offline),
               DeadlineNotificationEngine (powiadomienia o terminach
               płatności i dosłań; dedup po kluczach z datą w UserDefaults),
               SyncCenter (rejestracja przebiegów SyncRun, stany operacji,
               wspólne domykanie wysyłek: kolejka offline + statusy + UPO),
               PaymentLedger (wpłaty częściowe/saldo — jedyne miejsce zmian
               historii wpłat), MT940Parser (wyciągi bankowe),
               PaymentMatcher (propozycje dopasowań przelewów),
               ZipWriter (archiwum ZIP bez zależności; AccountingPackageBuilder
               w Services — paczka dla księgowości),
               InvoiceEmailComposer (adresat ze słownika po NIP — invoiceEmail
               przed email; domyślny temat/treść), DashboardAnalytics
               (przepływy z PaymentRecord, VAT okresu, wiekowanie sald,
               porównania miesięczne), JPKV7Generator (JPK_V7M i JPK_V7K
               — enum JPKV7Variant; automatyczny wybór schemy (2) do stycznia
               2026 lub (3) od lutego 2026; ewidencja + deklaracja VAT-7/
               VAT-7K; wydanie (3) z NrKSeF albo OFF/BFK/DI; V7K kwartalny —
               deklaracja tylko w pliku ostatniego miesiąca kwartału, za cały
               kwartał, z elementem Kwartal; OSS poza JPK, ostrzeżenia
               o uproszczeniach),
               VATUEGenerator (informacja podsumowująca VAT-UE(5) zgodna
               z XSD crd.gov.pl/wzor/2021/01/12/10293 — WDT/część C,
               WNT/część D, usługi UE/część E z danych faktur; kontrahent
               UE po prefiksie kraju w numerze VAT, towar/usługa z CN/PKWiU,
               kwoty w pełnych złotych per kontrahent; import usług i OSS
               poza VAT-UE),
               PaymentDemandEngine (odsetki od salda, pozycje wezwań;
               PDF w Services/PaymentDemandPDFGenerator),
               KPiREngine (ewidencja KPiR według wzoru od 2026 r.:
               kolumny 1–19, klasyfikacja faktur do kol. 9/10/12–15,
               przeliczenie PLN, podsumowania okresu i KPiRCSVExporter;
               ukryte faktury zawsze pomijane),
               ReportsEngine (raporty: top kontrahenci, przychody per
               towar/usługa, koszty per kategoria; CostCategories —
               podpowiedzi kategorii), MenuBarStatus (liczniki dosłań
               i opisy dla ikony w pasku menu), CertificateRenewalEngine
               (+ CertificateRenewalCoordinator — automatyczne odnowienie
               certyfikatów przed wygaśnięciem: typ 1 odnawia się wciąż
               ważnym typem 1, typ 2 wymaga ważnego typu 1; dedup jednej
               próby na dobę, zapis w pęku kluczy tylko przy sukcesie;
               wpięte w MainContentView, przełącznik ksef.autoRenewCertificates),
               PermissionsEngine (czysta logika uprawnień: budowa żądań
               grant/revoke z formularza, walidacja NIP, normalizacja
               wyników zapytań do widoku, polskie etykiety zakresów)
  Views/       MainContentView (NavigationSplitView), InvoiceListView, InvoiceDetailView,
               NewInvoiceView (nowa/edycja/korekta), NewPurchaseView (zakup
               spoza KSeF), ReportsView (sekcja Raporty), DashboardView,
               SettingsView (zakładka Firma: import/podgląd logo,
               ColorPicker koloru głównego i akcentu, własna stopka PDF),
               HiddenInvoicesView,
               PermissionsView (sekcja Uprawnienia — nadawanie/odbieranie
               i przegląd dostępów KSeF),
               KPiRView (tabela, edycja lokalnej klasyfikacji i CSV),
               JPKExportView i VATUEExportView (eksport ewidencji VAT
               z menu „Ewidencje” na listach faktur),
               DictionariesView (+ ContractorsView/ProductsView/BankAccountsView)
Tests/KsefiarzCoreTests/               # Swift Testing (#expect/#require), nazwy PO POLSKU
Scripts/build-app.sh                   # składanie bundla .app
```

## KPiR (wzór od 2026 r.)

- Źródłem układu jest rozporządzenie Ministra Finansów i Gospodarki
  z 6 września 2025 r. (Dz.U. 2025 poz. 1299), obowiązujące od 1.01.2026:
  <https://eli.gov.pl/eli/DU/2025/1299/ogl>.
- Wpis jest wyprowadzany z widocznej faktury. Data to lokalna korekta KPiR,
  następnie data sprzedaży, a na końcu data wystawienia. Kwota domyślna to
  netto w PLN (`DashboardAnalytics.inPLN`); ręczne `kpirAmountOverride`
  pozwala uwzględnić częściowy koszt lub nieodliczalny VAT.
- Sprzedaż domyślnie trafia do kolumny 9, a zakup do 15. Użytkownik może
  wybrać właściwą kolumnę 9/10 albo 12–15. Kolumny 11 i 16 są wyliczane;
  kolumna 18 przechowuje informacyjną część B+R, kolumna 19 — uwagi.
- Gdy kontrahent ma identyfikator podatkowy (kol. 5), eksport pozostawia
  nazwę i adres (kol. 6–7) puste zgodnie z objaśnieniami wzoru.
- `isExcludedFromKPiR` jest niezależne od ukrycia. Dokumenty ukryte są
  bezwarunkowo pomijane; wykluczone można roboczo pokazać i przywrócić.
- CSV jest pełnym, 19-kolumnowym eksportem roboczym, nie strukturą
  JPK_PKPIR. Metadane KPiR są objęte `BackupService` od wersji 8.

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
  logowanie), `Offline` (typ 2, tylko KOD II QR). Ważność 2 lata. Pobrany
  z KSeF certyfikat to plik `.crt` (PEM, klucz publiczny EC P-256 lub RSA)
  wraz z OSOBNYM, zaszyfrowanym kluczem prywatnym w PKCS#8
  (`ENCRYPTED PRIVATE KEY`, PBES2) — import wymaga hasła do klucza.
- Uprawnienia (API permissions): operacje grant/revoke są ASYNCHRONICZNE —
  zwracają HTTP 202 `{referenceNumber}`, status przez GET
  `/permissions/operations/{ref}` → `status.code == 200` (sukces) lub `400+`
  (błąd), analogicznie do pollingu auth/enrollment. Nadawanie:
  `/permissions/entities/grants` (podmiot po NIP — np. biuro rachunkowe;
  zakresy InvoiceRead/InvoiceWrite + canDelegate),
  `/permissions/persons/grants` (osoba po NIP/PESEL/odcisku; 7 zakresów),
  `/permissions/authorizations/grants` (uprawnienia podmiotowe: SelfInvoicing,
  TaxRepresentative, RRInvoicing, PefInvoicing — pojedyncze). Odbieranie:
  DELETE `/permissions/common/grants/{permissionId}` (osoby/podmioty) oraz
  DELETE `/permissions/authorizations/grants/{permissionId}` (podmiotowe).
  Przegląd: POST `/permissions/query/persons/grants` (queryType
  `PermissionsGrantedInCurrentContext` zwraca uprawnienia nadane w kontekście —
  osobom i podmiotom) oraz POST `/permissions/query/authorizations/grants`
  (queryType `Granted`/`Received`); stronicowanie `pageOffset`/`pageSize`.
  Zarządzanie uprawnieniami wymaga zakresu `CredentialsManage`, przegląd —
  `CredentialsRead` (właściciel NIP ma oba); token dostępowy wystarcza
  (nie trzeba XAdES).
- Tryby offline: zwykła sesja interaktywna z `offlineMode: true` w żądaniu
  wysyłki (WSPÓLNA flaga dla wszystkich trybów — API nie rozróżnia);
  dosyłany XML musi być BAJT W BAJT tym, z którego policzono skrót
  do kodów QR (stąd `Invoice.offlineHashBase64` + wysyłka `rawXmlContent`
  przez `sendInvoiceXML`, nigdy ponowna generacja). Terminy dosłania
  (`Invoice.OfflineReason`, tabela w docs CIRFMF tryby-offline.md):
  offline24 (art. 106nda) — następny dzień roboczy po dacie wystawienia;
  niedostępność (art. 106nh) — następny dzień roboczy po jej zakończeniu;
  awaria (art. 106nf) — 7 dni roboczych od jej zakończenia. Daty końca
  zdarzenia NIE ma w API (komunikaty w BIP MF) — wpisuje ją użytkownik
  (`offlineEventEndedAt`); do tego czasu termin jest nieznany (nil).
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

Fakty o API/schemie weryfikuj u źródła (OpenAPI
`https://api-test.ksef.mf.gov.pl/docs/v2/openapi.json`, XSD z CIRFMF/ksef-api,
docs CIRFMF/ksef-docs) — nie zgaduj pól.

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
OSS (dział XII rozdz. 6a): pozycja z `ossRate` dostaje P_12_XII (TProcentowy,
do 6 miejsc) ZAMIAST P_12, a jej sumy idą do sekwencji P_13_5+P_14_5
(między blokiem taksówek P_13_4 a P_13_6_1); pozycje OSS nie wchodzą do sum
polskich stawek. Pozycja: kod z kropkami→PKWiU, same cyfry→CN (między P_7
a P_8A); GTU po P_12/P_12_XII.
Uwagi faktury → Stopka/Informacje/StopkaFaktury (po elemencie Fa).
Załącznik → element Zalacznik jako OSTATNI element Faktura (po Stopce):
BlokDanych{ZNaglowek?, MetaDane+ (min. 1 para — XSD!), Tekst?/Akapit×10,
Tabela*(Opis?, TNaglowek/Kol Typ="txt"/NKom, Wiersz+/WKom, Suma?/SKom)};
wysyłka faktur z załącznikiem wymaga zgłoszenia w e-US. Wygenerowany
dokument OSS+załącznik zweryfikowany oficjalną XSD (xmllint, 12.07.2026).
Korekty (KOR): kwoty to RÓŻNICA (mogą być ujemne); wybór NrKSeF=1 +
NrKSeFFaKorygowanej albo NrKSeFN=1. Parser jest odporny na przestrzenie nazw
(wyszukiwanie po nazwach lokalnych) — czyta FA(2) i FA(3).

## VAT-UE(5) — informacja podsumowująca

Osobna ewidencja (poza JPK_V7M), składana do e-Deklaracji. Źródło prawdy:
oficjalna XSD `http://crd.gov.pl/wzor/2021/01/12/10293/` (importy: etd
`.../2020/03/11/eD/DefinicjeTypy/`, kue `.../2021/01/04/eD/KodyUE/`).
Struktura (kolejność XSD): root `Deklaracja` → `Naglowek` (KodFormularza
`kodSystemowy="VAT-UE (5)" wersjaSchemy="2-0E"`=VAT-UE, WariantFormularza=5,
Rok, Miesiac, **CelZlozenia=1 na stałe** — brak wariantu korekty w schemie,
KodUrzedu) → `Podmiot1 rola="Podatnik"` z **etd:OsobaNiefizyczna{etd:NIP,
etd:PelnaNazwa}** (typ TPodmiotDowolnyBezAdresu3, BEZ Email/REGON;
elementy kwalifikowane prefiksem etd) → `PozycjeSzczegolowe` → `Pouczenie`=1.
Sekcje w PozycjeSzczegolowe (każda Grupa minOccurs=0, unbounded; klucz
unikalności = kraj+numer+flaga): **Grupa1** WDT/część C
{P_Da kraj, P_Db nr VAT, P_Dc kwota (TKwotaC, pełne złote, ≤12 cyfr),
**P_Dd=1 wymagane** — flaga transakcji trójstronnej}; **Grupa2** WNT/część D
{P_Na, P_Nb, P_Nc, **P_Nd=1**}; **Grupa3** usługi/część E {P_Ua, P_Ub, P_Uc —
bez flagi}; Grupa4 (call-off stock) NIE generowana (brak modelu danych).

## JPK_V7M / JPK_V7K — ewidencja VAT z deklaracją

Generator `JPKV7Generator` obsługuje dwa warianty (`JPKV7Variant`): miesięczny
(**JPK_V7M**) i kwartalny (**JPK_V7K** — mały podatnik / VAT kwartalny). To
osobne schematy XSD. Wydanie jest dobierane automatycznie do okresu:
- od lutego 2026 r. V7M(3): namespace `.../2025/12/19/14090/`, VAT-7(23);
  V7K(3): namespace `.../2025/12/19/14089/`, VAT-7K(17), element `Kwartal`;
- od stycznia 2022 r. do stycznia 2026 r. zachowane są historyczne V7M(2)
  (`.../11148`, VAT-7(22)) i V7K(2) (`.../11149`, VAT-7K(16)).

W wydaniu (3) każdy wiersz ewidencji zawiera wymagany wybór: `NrKSeF`, jeśli
faktura ma już numer, `OFF` dla faktury wystawionej podczas awarii KSeF bez
numeru, `DI` dla offline24/niedostępności bez numeru albo `BFK` dla pozostałej
faktury elektronicznej/papierowej wystawionej poza KSeF. Po nadaniu numeru KSeF
ma on pierwszeństwo przed znacznikiem trybu wystawienia.

Reguła składania V7K (broszura MF): ewidencję składa się co miesiąc, a część
deklaracyjną raz na kwartał — **wyłącznie w pliku ostatniego miesiąca kwartału**
(3/6/9/12). Wtedy `Ewidencja` = dane tylko tego miesiąca (`inPeriod`, jak V7M),
a `Deklaracja` = **sumy całego kwartału** (`quarterMonths` → 3 miesiące). Dla
miesięcy 1. i 2. kwartału generator emituje sam blok `Ewidencja` (bez
`Deklaracja`) i dokłada ostrzeżenie. `JPKV7Result` rozdziela kwoty ewidencji
(miesiąc: `outputVAT`/`inputVAT`) od kwot deklaracji (kwartał dla V7K:
`declarationOutputVAT`/`declarationInputVAT`, `amountDue`/`excessCarried`,
flaga `hasDeclaration`). Warianty (2) i (3) zweryfikowane oficjalnymi XSD
(xmllint, 12.07.2026). Uproszczenia jak w V7M (OSS poza JPK, zakupy jako
pozostałe nabycia, okres po dacie sprzedaży/wystawienia).
Kody krajów: `TKodKrajuUE` (towary) i `TKodKrajuUEUslugi` (usługi, bez XI);
Grecja = **EL**, Irlandia Płn. **XI tylko dla towarów**, PL wykluczone.
Stary słownik XSD nadal technicznie zawiera GB, ale generator pomija Wielką
Brytanię po Brexicie. Numer VAT bez prefiksu kraju (TNrVatUE, 1–12 znaków).
Kwalifikacja z faktury: kontrahent UE po prefiksie kraju (buyerNIP sprzedaż /
sellerNIP zakup; same cyfry = krajowy, GR→EL); towar vs usługa po kodzie
pozycji (CN=towar, PKWiU z kropkami=usługa), a dla sprzedaży dodatkowo po
stawce 0%. Brak kodu i sprzedaż z inną stawką są pomijane z ostrzeżeniem;
kwoty per kontrahent, zaokrąglenie do złotych. **Import usług** (zakup usług
z UE) i **procedura OSS** świadomie POZA VAT-UE (tylko JPK_V7 / procedura
unijna). Wygenerowany dokument (WDT+WNT+usługi, EL, XI) zweryfikowany
oficjalną XSD (xmllint, 12.07.2026).

## Gdzie przechowywane są dane

- Baza: `~/Library/Application Support/Ksefiarz/Ksefiarz.store` (SQLite/SwiftData).
  ⚠️ Nigdy nie używaj domyślnej ścieżki SwiftData (`default.store`) — to plik
  współdzielony między procesami; 12.06.2026 migracja schematu wykonana przez
  `com.apple.icloudmailagent` skasowała w nim wszystkie faktury.
- Ustawienia: `~/Library/Preferences/pl.itkrak.ksefiarz.plist`.
- Token KSeF: pęk kluczy (generic password `pl.itkrak.ksefiarz` / `ksef.token`).
  Tokeny per środowisko: produkcja `ksef.token`, pozostałe `ksef.token.<env>`
  (patrz `TokenStore.account(forEnvironment:)`).
- Certyfikaty KSeF: pęk kluczy `ksef.cert.auth`/`ksef.cert.offline`
  (+ sufiks środowiska) — JSON z certyfikatem DER i kluczem prywatnym
  (`KSeFCertificateStore.account(type:environmentRaw:)`).
- Kopia zapasowa/eksporty: pliki wybierane przez użytkownika (bez tokenu).

Podgląd bazy (tylko odczyt):
`sqlite3 -readonly ~/Library/Application\ Support/Ksefiarz/Ksefiarz.store`.

## Znane ograniczenia

- Na produkcji pierwszy certyfikat KSeF trzeba zaimportować z pliku
  (pozyskany np. w Aplikacji Podatnika) — wniosek z aplikacji wymaga
  wcześniejszego zalogowania podpisem, a to na produkcji umożliwia dopiero
  ważny certyfikat typu 1.
- Wysyłka faktury przeszła e2e na środowisku `test` w schemie FA(3)
  (LiveSendTests, 12.06.2026: numer KSeF + UPO); na produkcji jeszcze
  nigdy nie wykonana.
- Nadawanie/odbieranie uprawnień jest przetestowane wyłącznie na mockach
  (środowisko użytkownika to produkcja — polityka „tylko odczyt na żywo"
  zabrania modyfikacji uprawnień w testach na żywym API).
- Wysyłka e-mail otwiera okno wiadomości w Mail (NSSharingService) —
  aplikacja zapisuje moment PRZEKAZANIA do Mail, nie potwierdzenie wysyłki.
- Bundle podpisany ad-hoc (dystrybucja wymaga Developer ID + notaryzacji).
