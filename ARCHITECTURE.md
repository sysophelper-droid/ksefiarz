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
               podatkowa bez modyfikowania treści dokumentu KSeF;
               pola collection* — daty działań windykacyjnych, z których
               wynika Invoice.collectionStage),
               słowniki: Contractor (+ prefersBilingualDocuments — PDF
               PL/EN i angielski e-mail), Product,
               BankAccount (@Model, dane tylko PODSTAWIANE do faktur —
               pola faktury zawsze edytowalne ręcznie), SyncRun (@Model,
               historia przebiegów Centrum synchronizacji), FA3Attachment
               (bloki załącznika FA(3); na fakturze jako JSON
               w Invoice.attachmentJSON),
               Proforma (@Model) + ProformaLine (@Model) — faktura proforma
               jako OSOBNY model (dokument handlowy poza KSeF; izolacja
               od agregacji faktur — szczegóły w sekcji „Faktura proforma"),
               ProformaDraft (+ init(from: Proforma), invoiceDraft() →
               InvoiceDraft do konwersji proformy na fakturę VAT)
  Services/    KSeFService (API 2.0), KSeFBatchService (rozszerzenie KSeFService
               o sesję wsadową batch/ZIP: otwarcie sesji, upload zaszyfrowanych
               części paczki pod adresy magazynu, zamknięcie, status sesji
               i wyniki per faktura ze stronicowaniem — szczegóły w sekcji
               „Sesja wsadowa"), KSeFCrypto, FA2XML (generator+parser), InvoiceValidator,
               KSeFAnonymousAccessService (publiczna bramka WWW MF: pobranie
               pojedynczego XML po numerze KSeF i danych identyfikujących,
               bez tokenu/certyfikatu — sekcja „Anonimowy dostęp"),
               BackupService (format v8 obejmuje metadane KPiR),
               FileExportService (NSSave/OpenPanel + systemowy druk PDF),
               InvoicePDFGenerator (+ kody QR,
               opcjonalny branding własnych dokumentów: logo, dwa kolory,
               stopka na każdej stronie), BatchInvoicePDFBuilder (PDFKit:
               scalenie kompletnych wydruków wielu faktur w kolejności listy),
               TokenStore (token w pęku kluczy), ContractorLookupService (Biała
               lista VAT, wl-api.mf.gov.pl — publiczne, bez klucza),
               VIESLookupService (weryfikacja VAT-UE kontrahentów UE, REST API
               VIES Komisji Europejskiej ec.europa.eu/taxation_customs/vies —
               publiczne, bez klucza; odpowiednik ContractorLookupService dla
               kontrahentów spoza PL),
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
               odbieranie i przegląd uprawnień KSeF; API permissions;
               receivedAuthorizations(fromNIP:) — uprawnienia podmiotowe
               otrzymane od kontrahenta, queryType=Received),
               TabularFileReader (CSV/TSV: auto-separator i kodowania PL;
               XLSX: pierwszy arkusz OOXML, shared/inline strings, liczby,
               style dat i system 1900/1904; odczyt tylko wymaganych wpisów
               przez /usr/bin/unzip, limit 64 MB), BulkImportService
               (materializacja planu + jeden zapis SwiftData; pozycje faktury
               przypisywane dopiero po context.insert),
               ContractorVerificationService (koordynator weryfikacji
               kontrahenta: Biała lista VAT + KSeF Received, izolacja awarii
               źródeł, składanie przez ContractorVerification.build),
               VIESVerificationService (koordynator weryfikacji VAT-UE:
               jedno źródło VIES, izolacja awarii, składanie przez
               VIESVerification.build; opcjonalny requesterNIP → numer
               potwierdzenia zapytania),
               KSeFAvailabilityService (publiczne API Latarni MF: `/status`
               + `/messages`, bez autoryzacji; TEST i PRD, brak mapowania
               Demo), KSeFAvailabilityMonitor (wspólny stan odświeżany co
               minutę przez MainContentView),
               KSeFQRCode (linki weryfikacyjne KOD I/II + render QR),
               InvoiceEmailService (okno wiadomości Mail przez
               NSSharingService; załączniki PDF/XML z katalogu tymczasowego),
               MailAutomationService (cicha wysyłka / szkic w Mail przez
               NSAppleScript — automatyczne przypomnienia o płatnościach;
               czysty MailAutomationScript z escapingiem testowanym
               jednostkowo; wymaga NSAppleEventsUsageDescription i zgody
               na automatyzację),
               InvoiceOCRService (rozpoznawanie tekstu skanu/PDF faktury
               kosztowej: PDF z warstwą tekstową wprost przez PDFKit,
               skan przez Vision VNRecognizeTextRequest — szczegóły
               w sekcji „OCR faktur kosztowych"),
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
               PaymentQRCode (czysta treść kodu QR płatności 2D ZBP —
               polecenie przelewu krajowego; render QRCodeRenderer,
               osadzenie InvoicePDFGenerator; szczegóły niżej),
               InvoiceSyncEngine (wspólny sync: ręczny,
               przy starcie i cykliczny — automatyka w MainContentView),
               AnonymousInvoiceImportEngine (parser pobranego XML + wspólne
               scalanie zakupu przez InvoiceSyncEngine),
               KSeFBatchPackage (czysta paczka ZIP sesji wsadowej: budowa
               archiwum, podział binarny na części ≤100 MB, limity),
               BatchSendEngine (wysyłka wsadowa: kwalifikacja lokalnych
               dokumentów, plan per schema FA(3)/FA_RR(1), oznaczanie
               wysłanych, korelacja wyników po skrócie SHA-256, domykanie
               sesji przez SyncCenter — sekcja „Sesja wsadowa"),
               PolishBusinessCalendar (dni robocze/święta — terminy trybów
               offline), OfflineQueueEngine (kolejka dosłań offline),
               KSeFAvailabilityPolicy (mapowanie MAINTENANCE/FAILURE na
               podpowiedź trybu, TOTAL_FAILURE jako osobna blokada,
               uzupełnianie końca zdarzenia po eventId),
               DeadlineNotificationEngine (powiadomienia o terminach
               płatności i dosłań; dedup po kluczach z datą w UserDefaults),
               SyncCenter (rejestracja przebiegów SyncRun, stany operacji,
               wspólne domykanie wysyłek: kolejka offline + statusy + UPO),
               PaymentLedger (wpłaty częściowe/saldo — jedyne miejsce zmian
               historii wpłat), MT940Parser (wyciągi bankowe),
               PaymentMatcher (propozycje dopasowań przelewów),
               ElixirPaymentExporter (czysty eksport paczki zobowiązań:
               walidacja NRB/MPP, 16 pól Elixir-O, kodowania tekstowe),
               WaproXMLExporter (czysty eksport dokumentów do WAPRO XML
               MAGIK_EKSPORT 4.3.2 — szczegóły w sekcji „WAPRO XML"),
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
               o uproszczeniach), JPKV7VATRRPolicy (specyfikacja art. 116:
               kwalifikacja zakupowego VAT RR po pełnej zapłacie/zwrocie,
               dowód kanału bankowego i jawne przyczyny pominięcia),
               JPKFAGenerator (JPK_FA(4) — pełny JPK faktur sprzedaży
               NA ŻĄDANIE organu podatkowego; wyłącznie sprzedaż, kwoty
               w walucie faktury, pozycje FakturaWiersz, zaliczki w węźle
               Zamowienie; zgodny z oficjalną XSD — sekcja „JPK_FA(4)"),
               VATUEGenerator (informacja podsumowująca VAT-UE(5) zgodna
               z XSD crd.gov.pl/wzor/2021/01/12/10293 — WDT/część C,
               WNT/część D, usługi UE/część E z danych faktur; kontrahent
               UE po prefiksie kraju w numerze VAT, towar/usługa z CN/PKWiU,
               kwoty w pełnych złotych per kontrahent; import usług i OSS
               poza VAT-UE),
               PaymentDemandEngine (odsetki od salda, pozycje dokumentów
               windykacyjnych — przypomnienie/wezwanie/nota/EPU;
               PDF w Services/PaymentDemandPDFGenerator),
               DebtCollectionEngine (ścieżka windykacji C3: etapy
               DebtCollectionStage z dat działań na fakturze, sugestia
               następnego kroku eskalacji, dane do pozwu EPU — WPS,
               opłata sądowa, roszczenia, dowody; sekcja „Windykacja"),
               PaymentReminderEngine (automatyczne przypomnienia e-mail
               C4: okna przed/po terminie, dedup po collectionReminderAt,
               szablony PL/EN, jawne pominięcia; dostarczanie przez
               Services/MailAutomationService),
               KPiREngine (ewidencja KPiR według wzoru od 2026 r.:
               kolumny 1–19, klasyfikacja faktur do kol. 9/10/12–15,
               przeliczenie PLN, podsumowania okresu i KPiRCSVExporter;
               ukryte faktury zawsze pomijane),
               RyczaltEngine (ewidencja przychodów — ryczałt, wzór od 2026 r.
               Dz.U. 2025 poz. 1294: enum RyczaltRate 9 stawek, tylko
               sprzedaż, przychód netto w PLN, podsumowanie i szacunek
               ryczałtu per stawka, RyczaltCSVExporter 17 kolumn + wiersz
               sumy; enum TaxForm wybiera KPiR albo ryczałt — obie
               wykluczające, AppSettingsKeys.taxForm),
               TaxCalendarEngine (najbliższe terminy ZUS/PIT/JPK/VAT z
               przesunięciem przez PolishBusinessCalendar; miesięczny lub
               kwartalny okres VAT i PIT; prognoza VAT oraz PIT dla
               KPiR — skala/liniowy — albo ryczałtu),
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
               wyników zapytań do widoku, polskie etykiety zakresów),
               ContractorVerification (czysta logika weryfikacji kontrahenta:
               klasyfikacja statusu VAT VATRegistrationStatus, model wyniku
               ContractorVerificationResult z ustaleniami i wagami
               OK/info/ostrzeżenie/krytyczne, budowa werdyktu z 3 źródeł —
               NIP, Biała lista, uprawnienia KSeF Received),
               VIESVerification (czysta logika weryfikacji VAT-UE: status
               VIESRegistrationStatus, wynik VIESVerificationResult reużywa
               wag i wierszy ustaleń karty krajowej, build() z wyniku VIES;
               euIdentity(uePrefix:identifier:) — routing UE vs krajowy,
               zbiór viesCountryCodes 27 państw UE + XI, GR→EL, PL wykluczone),
               ContractorHistory (dopasowanie dokumentów po znormalizowanym
               NIP, salda per waluta, średni czas płatności i scoring),
               InvoiceOCRParser (czysta logika wyciągania pól polskiej
               faktury z linii tekstu OCR: InvoiceOCRExtraction —
               opcjonalne pola, resolvedAmounts, applied(to:) na
               ManualPurchaseDraft; heurystyki po etykietach odporne
               na brak diakrytyków),
               ProformaValidator (czysta walidacja proformy — NIP nabywcy
               opcjonalny, walidowany gdy podany; osobny ProformaValidationError),
               BulkImportEngine (czyste mapowanie nagłówków Fakturownia/
               wFirma i układów własnych, typowanie kwot/dat/flag, walidacja,
               grupowanie pozycji faktur, deduplikacja i plan importu),
  Views/       MainContentView (NavigationSplitView), InvoiceListView, InvoiceDetailView,
               AnonymousInvoiceImportView (arkusz publicznego pobrania
               pojedynczego zakupu po danych identyfikujących),
               BatchSendView (arkusz wysyłki wsadowej — wejście z paska
               narzędzi listy sprzedaży i menu kontekstowego zaznaczenia),
               NewInvoiceView (nowa/edycja/korekta), NewPurchaseView (zakup
               spoza KSeF), ReportsView (sekcja Raporty), DashboardView,
               SettingsView (zakładka Firma: import/podgląd logo,
               ColorPicker koloru głównego i akcentu, własna stopka PDF),
               HiddenInvoicesView,
               PermissionsView (sekcja Uprawnienia — nadawanie/odbieranie
               i przegląd dostępów KSeF),
               ContractorVerificationView (karta „Weryfikacja kontrahenta” —
               status VAT z Białej listy + relacja uprawnień KSeF; z menu
               kontekstowego listy kontrahentów i z edytora kontrahenta),
               VIESVerificationView (karta „Weryfikacja VAT-UE (VIES)” dla
               kontrahentów UE — ta sama akcja „Zweryfikuj” routuje tu, gdy
               VIESVerification.euIdentity rozpozna prefiks UE; reużywa
               FindingRow oraz ikon/kolorów wag z ContractorVerificationView),
               ContractorHistoryView (jedna karta dokumentów, sald i
               terminowości; szczegóły faktury po podwójnym kliknięciu),
               KPiRView (tabela, edycja lokalnej klasyfikacji i CSV),
               RyczaltView (ewidencja przychodów: tabela ze stawką, podział
               przychodu/ryczałtu per stawka, edycja wpisu i CSV — pokazywana
               zamiast KPiRView przy formie „ryczałt”),
               JPKExportView, JPKFAExportView i VATUEExportView (eksport
               ewidencji VAT i JPK_FA na żądanie z menu „Ewidencje” na
               listach faktur),
               BankTransferExportView (wybór zakupów, rachunku źródłowego,
               daty, kodowania i kwoty VAT MPP; zapis .pli),
               InvoiceListView menu „Dokumenty" (WAPRO XML + zapis/druk
               wspólnego PDF; multiselect albo wszystkie widoczne),
               DictionariesView (+ ContractorsView/ProductsView/BankAccountsView),
               BulkImportView (kreator plik → mapowanie → bilans/podgląd →
               zapis kontrahentów, produktów albo faktur),
               ProformaListView + ProformaDetailView + NewProformaView
               (formularz z lekkim ProformaLineEditor) + ProformaEmailView
               (sekcja „Faktury proforma"; SidebarSection.proformas)
Tests/KsefiarzCoreTests/               # Swift Testing (#expect/#require), nazwy PO POLSKU
Scripts/build-app.sh                   # składanie bundla .app
```

## Import wsadowy CSV/Excel (D4)

- Punkt wejścia: `Słowniki` → `Import CSV/Excel`. Jeden kreator obsługuje
  kontrahentów, towary/usługi i faktury. Źródłem jest CSV/TSV albo pierwszy
  arkusz `.xlsx`; stary binarny `.xls` jest świadomie poza zakresem (eksport
  Fakturowni należy pobrać jako CSV, a arkusz zapisać jako XLSX).
  Źródła układów migracyjnych: [eksport CSV Fakturowni](https://pomoc.fakturownia.pl/19054671-eksport-faktur-do-csv),
  [eksport XLS z pozycjami Fakturowni](https://pomoc.fakturownia.pl/327434-jak-wyeksportowac-do-pliku-excel-lub-wydrukowac-faktury-z-wybranego-okresu)
  i [katalog produktów wFirmy](https://pomoc.wfirma.pl/-import-z-pliku-excel-i-zapis-w-formacie-csv).
- `TabularFileReader` normalizuje oba formaty do `TabularSheet`. Parser CSV
  obsługuje cytowanie RFC 4180, pola wieloliniowe, CRLF, separatory
  `;`/`,`/tab oraz UTF-8, UTF-16 i Windows-1250; BOM UTF-8 jest usuwany
  przed parsowaniem (inaczej psułby cudzysłów pierwszego pola). Czytnik XLSX
  nie rozpakuje całego archiwum: pobiera przez `/usr/bin/unzip -p` tylko
  `workbook.xml`, relacje, pierwszy arkusz oraz opcjonalne shared strings/style;
  limit zdekompresowanego wpisu to 64 MB. Elementy XML są dopasowywane po
  nazwie lokalnej, więc działają też pliki z prefiksami przestrzeni nazw
  (`<x:row>` z .NET OpenXML SDK).
- `BulkImportEngine` automatycznie mapuje popularne polskie i angielskie
  nagłówki, w tym zmienne eksportów Fakturowni oraz oficjalny układ katalogu
  wFirmy (`Nazwa`, `PKWiU`, `Jednostka`, `Cena`, `Stawka`, `Rodzaj ceny`,
  `Kod produktu`, `Typ`). Każde dopasowanie jest edytowalne w UI. Identyfikatory
  NIP/SKU/EAN pozostają tekstem; kwoty przyjmują separator polski/angielski
  oraz dopiski walut (`zł`, `PLN`, `EUR`, `USD`), a cena brutto jest przeliczana
  na netto według VAT. Typ dokumentu jest normalizowany do słownika
  `Invoice.documentTypeRaw` (np. „Faktura zaliczkowa” → `ZAL`); wartość
  nieznana daje ostrzeżenie i kod `VAT`.
- Plan jest czystym typem wartościowym. Błędny wiersz tworzy diagnostykę
  z numerem i nie usuwa poprawnych wierszy; brak mapowania pola wymaganego
  blokuje cały import. Powtarzane wiersze faktury są grupowane i tworzą jej
  pozycje. `BulkImportService` materializuje wyłącznie rekordy z planu i
  zapisuje je jednym `ModelContext.save()`.
- Deduplikacja nie nadpisuje istniejących danych: kontrahenci po
  znormalizowanym identyfikatorze podatkowym, produkty po każdym z kluczy
  SKU/EAN/nazwa, faktury jednocześnie po numerze KSeF i kluczu
  `kind + numer dokumentu + NIP sprzedawcy + NIP nabywcy`. Fetch istniejących
  faktur nie ma filtra widoczności, więc obejmuje też ukryte — import nie może
  przywrócić dokumentu ukrytego przez użytkownika.
- Import nie tworzy XML ani nie wysyła dokumentów do KSeF. Faktura z numerem
  KSeF dostaje stan `.accepted`; bez niego `.local`, więc pozostaje lokalnym
  dokumentem podlegającym zwykłym regułom edycji. `isPaid` jest ustawiane
  wyłącznie z dodatniego znacznika/data zapłaty nowego rekordu; importer nie
  modyfikuje istniejących faktur.

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

## Ewidencja przychodów (ryczałt, wzór od 2026 r.)

- Źródłem układu jest rozporządzenie Ministra Finansów i Gospodarki
  z 6 września 2025 r. (Dz.U. 2025 poz. 1294), obowiązujące od 1.01.2026.
  Kolumny 1–17: Lp., data wpisu, data uzyskania przychodu, numer KSeF, numer
  dowodu księgowego, identyfikator podatkowy kontrahenta, kol. 7–15 przychód
  wg stawki 17/15/14/12,5/12/10/8,5/5,5/3%, ogółem przychody, uwagi. Wzór NIE
  ma kolumny 2% (rzadka stawka rolna) — świadome ograniczenie.
- `TaxForm` (enum w `RyczaltEngine.swift`) wybiera formę opodatkowania: `.kpir`
  albo `.ryczalt`. Wzajemnie wykluczające — `MainContentView` pokazuje w pasku
  bocznym tylko odpowiadającą sekcję (`SidebarSection.kpir` lub `.ryczalt`),
  a po zmianie formy resetuje zaznaczenie na Kokpit. Klucz `taxForm`, domyślnie
  KPiR (zgodność z istniejącymi instalacjami).
- Ryczałt dotyczy WYŁĄCZNIE przychodów, więc `RyczaltEngine.rows` bierze tylko
  `kind == .sales`. Przychód domyślny = netto w PLN (`DashboardAnalytics.inPLN`);
  `ryczaltAmountOverride` pozwala ująć brutto (podatnik zwolniony z VAT) lub
  korektę. Stawka: `ryczaltRateRaw` na fakturze, a przy pustej — domyślna
  z ustawień (`ryczaltDefaultRate`, fallback 8,5%). Data przychodu:
  `ryczaltEventDate ?? saleDate ?? issueDate`. Osobna data wpisu (kol. 2) to
  `ryczaltEntryDate`, z fallbackiem do daty przychodu; decyduje o kolejności
  pozycji i może być skorygowana w edytorze.
- Podsumowanie liczy przychód i szacowany ryczałt (przychód × stawka) łącznie
  i per stawka; szacunek jest bez odliczeń składek ZUS/zdrowotnej (etykieta
  „szac.”). Ostrzeżenie o braku kursu waluty jak w KPiR. Ukryte i wykluczone
  (`isExcludedFromRyczalt`) pomijane; wykluczone można roboczo pokazać.
- CSV (`RyczaltCSVExporter`) to pełny 17-kolumnowy eksport roboczy z wierszem
  sumy przychodów per stawka — nie struktura JPK_EWP. Metadane ryczałtu objęte
  `BackupService` od wersji 9. Od wersji 10 kopia obejmuje też ustawienia
  prognozy: metodę PIT dla KPiR oraz cykle rozliczeń PIT/ryczałtu i VAT.

## Kalendarz i prognoza podatkowa

- `TaxCalendarEngine` jest czystym silnikiem z wstrzykiwaną datą i kalendarzem.
  Zwraca po jednym najbliższym terminie dla ZUS/DRA, zaliczki PIT, JPK_V7
  i płatności VAT. Nominalny 20. lub 25. dzień przesuwa przez
  `PolishBusinessCalendar` na pierwszy dzień roboczy.
- JPK_V7 jest zawsze miesięczny. Płatność VAT oraz zaliczka PIT/ryczałt mogą
  być miesięczne albo kwartalne (`TaxSettlementCycle`, osobne klucze
  `vatSettlementCycle` i `incomeTaxSettlementCycle`). Przełącznik
  `isActiveVATPayer` usuwa terminy JPK/VAT i zeruje prognozę u podatnika
  zwolnionego. ZUS przyjmuje termin
  20. dnia właściwy dla przedsiębiorcy / płatnika bez osobowości prawnej.
- Prognoza VAT używa tej samej daty okresu i tych samych koszyków/przeliczeń
  PLN co `JPKV7Generator`; faktury ukryte są pomijane. Wynik nie modeluje
  proporcji odliczenia, ulg ani przeniesionej nadwyżki. Faktury VAT RR nie
  są automatycznie zaliczane do podatku naliczonego (B5 pozostaje osobnym
  zadaniem), a prognoza pokazuje ostrzeżenie.
- Dla KPiR prognoza liczy podatek narastająco od dochodu roku: skala
  12% do 120 000 zł i 32% powyżej, z kwotą zmniejszającą 3 600 zł, albo
  podatek liniowy 19%. Kwota okresu jest różnicą podatku narastającego na
  koniec bieżącego i poprzedniego okresu. Dla ryczałtu używane jest
  `RyczaltEngine.summary` i stawki wpisów. Nie są odejmowane składki,
  ulgi, inne dochody ani faktycznie wpłacone zaliczki — UI jawnie oznacza
  wynik jako szacunek wymagający weryfikacji księgowej.
- Reguły terminów zweryfikowano 13.07.2026 w źródłach urzędowych:
  [JPK_VAT — podatki.gov.pl](https://www.podatki.gov.pl/podatki-firmowe/jednolity-plik-kontrolny/jpk_vat/jpk_vat),
  [ryczałt — podatki.gov.pl](https://www.podatki.gov.pl/podatki-firmowe/pit/informacje-podstawowe/co-jest-opodatkowane/opodatkowanie-ryczaltem-od-przychodow-ewidencjonowanych)
  i [terminy ZUS](https://www.zus.pl/en/firmy/rozliczenia-z-zus/dokumenty-rozliczeniowe/termin-skladania-dokumentow-i-oplacania-skladek).

## Kod QR płatności (standard 2D ZBP)

- `PaymentQRCode` (czysta logika) buduje treść polecenia przelewu krajowego
  wg Rekomendacji Związku Banków Polskich dot. kodu dwuwymiarowego („2D”).
  Format to **dziewięć pól rozdzielonych `|`** w kolejności: NIP odbiorcy
  instytucjonalnego (poprawne 10 cyfr, pole obowiązkowe) · kod kraju `PL` ·
  numer rachunku (26 cyfr NRB, bez prefiksu `PL` i separatorów) ·
  **kwota w GROSZACH**
  wyrównana zerami do min. 6 cyfr (`%06d`, rośnie dla większych kwot) ·
  nazwa odbiorcy (≤20 znaków) · tytuł (≤32 znaki) · trzy pola rezerwowe
  (puste). Całość ≤160 znaków. Nazwa i tytuł są ograniczane do zestawu
  znaków dozwolonego przez rekomendację; separator `|` i inne niedozwolone
  znaki są zastępowane spacją, aby nie zmienić struktury pól. Kolejność,
  długości oraz wymagany poziom korekcji błędów QR `L` zweryfikowano w
  [oficjalnej Rekomendacji ZBP „Standard 2D”](https://www.zbp.pl/getContentAsset/806da831-e7e0-43e8-b361-c45f922cf529/1b52933d-ceff-4d97-bee2-094d491a3634/2013-12-03_-_Rekomendacja_-_Standard_2D.pdf?language=pl).
- Standard obejmuje wyłącznie **przelewy krajowe w PLN** — dla innych walut
  kod nie powstaje (kwota jest w groszach). Kod dotyczy tylko WŁASNEJ
  sprzedaży (to nasza firma jest odbiorcą przelewu): odbiorcą jest sprzedawca,
  tytułem numer faktury, kwotą **saldo pozostałe do zapłaty**
  (`Invoice.outstandingAmount`) — faktura opłacona (saldo 0) kodu nie dostaje,
  częściowo opłacona dostaje kod na kwotę brakującą. NIP i rachunek są
  normalizowane (usuwanie spacji, kresek i prefiksu `PL`); błędny NIP lub
  rachunek blokuje kod zamiast tworzyć niezgodną treść.
  `InvoicePDFGenerator.makeQRCodes` łączy kod płatności z kodami
  weryfikacyjnymi KSeF (KOD I/II) i rezerwuje miejsce na wydruku, gdy jest
  choć jeden kod; przełącznik `AppSettingsKeys.pdfPaymentQR`
  (domyślnie włączony, w kopii zapasowej) steruje tylko kodem płatności;
  odczyt obsługuje zarówno natywny `Bool`, jak i tekstowe `"0"`/`"1"`
  odtwarzane przez istniejący format kopii.
- **Nazwa odbiorcy (20 znaków)**: pole nazwy standardu jest krótkie, więc
  pełna nazwa firmy bywa ucinana. `AppSettingsKeys.paymentQRRecipientName`
  pozwala podać własny skrót (np. „IT-KRAK”); puste = pełna nazwa sprzedawcy
  skracana przez `truncatedName` na granicy słowa (gdy zostawia ≥ połowę
  limitu), inaczej twarde ucięcie. Override wstrzykiwany do
  `zbpTransferContent(for:recipientNameOverride:)` przez `makeQRCodes`.

## Eksport dokumentów: WAPRO XML i zbiorczy PDF

- `WaproXMLExporter` generuje jeden dokument `MAGIK_EKSPORT` w wersji 4.3.2
  dla 1–999 faktur. Zakres pochodzi z listy: multiselect, a bez zaznaczenia
  wszystkie widoczne rekordy (ukryte nie są pobierane przez `@Query`). Eksport
  zachowuje kolejność wejścia i obejmuje oba kierunki (`S`/`Z`) oraz korekty
  (`KF` + numer dokumentu pierwotnego). Punktem wejścia jest menu „Dokumenty”
  w `InvoiceListView`; te same akcje są w menu kontekstowym zaznaczenia.
- Struktura ma wymagane sekcje `INFO_EKSPORTU`, `DOKUMENTY`,
  `KARTOTEKA_KONTRAHENTOW`, `KARTOTEKA_PRACOWNIKOW` i
  `KARTOTEKA_ARTYKULOW`. Kontrahenci są deduplikowani po znormalizowanym NIP,
  a bez NIP po nazwie; jedna karta może być jednocześnie odbiorcą i dostawcą.
  Dane dokumentu obejmują nagłówek, daty Clarion (dni SQL + 36163, zawsze
  w kalendarzu gregoriańskim niezależnie od ustawień systemu), wartości
  bazowe i walutowe, kurs, formę płatności mapowaną do słownika WAPRO, NRB,
  pozycje, podsumowanie VAT per stawka, MPP (kwota VAT po kursie, w PLN),
  numer KSeF oraz unikalne kody GTU/procedur. `NUMER_RACHUNKU` to `STR(26)`,
  więc trafia tam wyłącznie poprawny polski NRB (26 cyfr, bez prefiksu `PL`);
  rachunek innego kształtu, np. zagraniczny IBAN, jest pomijany zamiast
  obcinania. Napisy są ograniczane do limitów `STR(n)`, liczby używają
  kropki, a Foundation `XMLDocument` odpowiada za poprawne kodowanie UTF-8
  i escapowanie.
- Waluta obca z dodatnim `Invoice.exchangeRate` jest przeliczana do wartości
  bazowych PLN, a oryginalne kwoty trafiają do pól `*_WALUTA`. Brak kursu nie
  tworzy fałszywego przeliczenia: bazą zostaje kwota dokumentu i użytkownik
  dostaje po zapisie jawne ostrzeżenie. Tak samo raportowany jest brak pozycji
  (wtedy pozostaje nagłówek i syntetyczne podsumowanie VAT). Eksport niczego
  nie zmienia w modelach i należy importować najpierw do bufora księgowości.
- Specyfikacja źródłowa: [WAPRO — struktura XML](https://wapro.pl/dokumentacja-erp/desktop/docs/finanse-i-ksiegowosc/informacje-uzupelniajace/kh-99.010-specyfikacja-pliku-XML/)
  oraz [WAPRO Kaper — import dokumentów](https://wapro.pl/dokumentacja-erp/desktop/docs/ksiega-podatkowa/narzedzia-i-moduly/kp-90.20.005-import-dokumentow/).
  Wersja HTML ma literówkę `DBIORCA`; oficjalny PDF specyfikacji
  (`wapro.pl/doc/Specyfikacja_pliku_WAPRO_xml.pdf`) używa rzeczywistego
  elementu `ODBIORCA`, który emituje generator. `RODZAJ_POZYCJI` jest
  w specyfikacji opisane tylko jako „P – przychodowa, R – rozchodowa" bez
  glosy; generator przyjmuje odczyt księgowy (sprzedaż = `P`/przychód,
  zakup = `R`), pole jest opcjonalne, a klasyfikację dokumentu i tak
  wyznacza nagłówkowe `ZAKUP_SPRZEDAZ`. Comarch udostępnia opis własnego
  XML tylko autoryzowanym partnerom, a pomoc Symfonii opisuje Format 3.0
  bez kompletnego szablonu pól; dlatego nie generujemy formatów
  o zgadywanej strukturze.
- `BatchInvoicePDFBuilder` generuje osobny wydruk każdej faktury istniejącym
  `InvoicePDFGenerator`, po czym kopiuje wszystkie `PDFPage` do jednego
  `PDFDocument`. Błąd któregokolwiek składnika przerywa całość, aby nie zapisać
  po cichu niekompletnego zestawu — `InvoiceListView` buduje PDF przed
  otwarciem panelu i błąd budowania zgłasza alertem (nie myli się z
  anulowaniem zapisu). Gotowe dane zapisuje `FileExportService.exportData`,
  a `FileExportService.printPDF` przekazuje je do systemowego
  `NSPrintOperation` ze skalowaniem do strony i automatycznym obrotem.

## Eksport przelewów Elixir-O

- `ElixirPaymentExporter` generuje plik bez nagłówka i stopki, po jednym
  rekordzie na dyspozycję, z CRLF. Rekord ma 16 pól rozdzielonych przecinkami:
  kod `110`, data `RRRRMMDD`, kwota w groszach, bank zleceniodawcy, tryb `0`,
  NRB zleceniodawcy i odbiorcy, nazwy/adresy, bank odbiorcy, szczegóły,
  dwa pola puste, klasyfikacja (`51` zwykły / `53` MPP) i puste informacje
  Klient–Bank. Pola tekstowe są w cudzysłowach, mają najwyżej cztery wiersze
  po 35 znaków rozdzielone `|`; znaki sterujące są normalizowane. Struktura
  i limity pól zostały zweryfikowane 13.07.2026 w instrukcjach bankowych:
  [mBank — opis płatności Elixir](https://www.mbank.pl/indywidualny/konta/pytania-i-odpowiedzi/platnosci-elixir/)
  oraz [PKO BP (iPKO biznes) — struktura pliku wejściowego ELIXIR-O](https://www.pkobp.pl/media_files/f624fb66-22a9-4a90-80b0-aae09b8afd29.pdf)
  (pola 1–16: bank zleceniodawcy w polu 4, stała `0` w polach 5 i 10, bank
  odbiorcy w polu 11, szczegóły w polu 12, typ dokumentu `51`/`53` w polu 15;
  Przelew Split w polu 12 ma strukturę `/VAT/…/IDC/…/INV/…`).
- Kandydatem jest wyłącznie widoczna faktura zakupowa w PLN z dodatnim
  `outstandingAmount`, nazwą sprzedawcy i poprawnym 26-cyfrowym NRB (łącznie
  z kontrolą IBAN modulo 97). Opłacone, ukryte, walutowe i błędne dokumenty
  są jawnie pokazane jako pominięte. Kwota przelewu to saldo, nie brutto.
- MPP używa kodu `53` i pola 12 w kolejności
  `/VAT/{zł,grosze}/IDC/{NIP}/INV/{numer faktury}`. Wymaga poprawnego NIP;
  pełna faktura podpowiada pełny VAT, częściowo opłacona — VAT proporcjonalny
  do salda. Podpowiedź jest edytowalna w UI, a generator pilnuje, by VAT był
  dodatni, nie przekraczał kwoty przelewu ani limitu 10 cyfr części całkowitej.
  Znaczniki MPP nie są przecinane separatorem wierszy.
- `BankTransferExportView` bierze multiselect z listy zakupów (brak zaznaczenia
  = widoczny filtr), pozwala wybrać własny rachunek PLN ze słownika albo
  wpisać NRB, datę nie wcześniejszą niż bieżąca oraz kodowanie UTF-8,
  Windows-1250 lub ISO-8859-2. Dla wspólnej zgodności obowiązuje limit 50
  przelewów w pliku (mBank; banki korporacyjne mogą mieć inne limity).
  Eksport nie dotyka `Invoice.isPaid` ani historii wpłat — autoryzacja odbywa
  się dopiero po imporcie i weryfikacji w banku.

## Windykacja i przypomnienia o płatnościach (C3/C4)

- **Ścieżka eskalacji** (C3): przypomnienie → wezwanie do zapłaty → nota
  odsetkowa → dane do pozwu EPU. Działania są odnotowywane na fakturze
  (`collectionReminderAt`+licznik, `collectionDemandAt`,
  `collectionInterestNoteAt`, `collectionEPUAt` — wartości domyślne, lekka
  migracja; kopia zapasowa v14), a `DebtCollectionEngine.stage(for:)`
  wyprowadza z nich etap `DebtCollectionStage` (Comparable). Sugestię
  następnego kroku liczy `suggestion(for:asOf:policy:)` z progami dni
  w `DebtCollectionPolicy` (domyślnie: wezwanie ≥14 dni zaległości
  i ≥7 dni po przypomnieniu; nota 14 dni po wezwaniu; EPU 14 dni po nocie).
  Wspólny widok `PaymentDemandView` (Kokpit → „Windykacja…”, menu listy
  sprzedaży) po zapisie/wysyłce dokumentu stempluje zaznaczone faktury.
- **`PaymentDemandKind`** ma cztery przypadki w kolejności eskalacji;
  `includesInterest` (przypomnienie i EPU nie naliczają kwoty odsetek —
  PDF przypomnienia nie ma kolumny „Odsetki” ani zapowiedzi drogi sądowej),
  `collectionAction` mapuje dokument na stemplowane działanie. Dane EPU
  nie mają PDF (`PaymentDemandPDFGenerator` zwraca nil) — wynik to tekst
  do przepisania do formularza e-sad.gov.pl (zapis TXT / schowek).
- **EPU (e-sąd) — fakty prawne** (zweryfikowane 14.07.2026): opłata od
  pozwu to czwarta część opłaty z art. 13 uksc, nie mniej niż 30 zł
  (art. 19 ust. 2 pkt 2 uksc). Art. 13 po nowelizacji od 23.09.2025:
  widełki stałe do 20 000 zł (30/100/200/400/500/750/1000 zł), powyżej
  5% WPS, maks. **100 000 zł** (obniżone z 200 000). Końcówki opłat
  w górę do pełnego złotego (art. 21 uksc). WPS = suma należności głównych
  bez odsetek (art. 20 KPC), zaokrąglona w górę (art. 126(1) § 3 KPC).
  W EPU tylko roszczenia wymagalne w ostatnich 3 latach (art. 505(29a)
  KPC) i kwoty w złotych — pozycje walutowe/przedawnione silnik jawnie
  wyłącza z listą pominięć; walidacja ostrzega też o brakach danych obu
  stron i braku wcześniejszego wezwania. EPU nie przyjmuje załączników — dowody
  wyłącznie wskazuje się w pozwie; właściwy jest zawsze Sąd Rejonowy
  Lublin-Zachód w Lublinie (VI Wydział Cywilny).
- **Przypomnienia e-mail** (C4): `PaymentReminderEngine.candidates` wybiera
  widoczne, nieopłacone faktury sprzedaży z terminem — okno przed terminem
  (`daysBeforeDue`, obejmuje dzień terminu, jedno uprzedzenie na okno)
  i cykliczne ponaglenia po terminie (`repeatAfterDays`). Pamięcią doręczeń
  jest `collectionReminderAt` (wspólna z C3 — pismo PDF i e-mail liczą się
  tak samo); etap ≥ wezwanie WSTRZYMUJE miękkie przypomnienia (sprzeczny
  ton podważałby wezwanie). Brak adresu e-mail → jawne pominięcie i dzienne
  powiadomienie z numerami faktur (dedup przez
  `reminder.emails.omissionsNotifiedDay`).
  Cykl w `MainContentView` (natychmiast po starcie/włączeniu/zmianie
  konfiguracji + co 6 h, przełącznik `reminder.emails.enabled`, domyślnie
  wyłączony).
- **Automatyzacja Mail**: `MailAutomationService` wykonuje AppleScript
  (NSAppleScript, main thread) — `save theMessage` tworzy szkic w Wersjach
  roboczych, `send theMessage` wysyła; wiadomość z `visible:false` nie
  otwiera okna. Budowa skryptu jest czystą funkcją `MailAutomationScript`
  z escapingiem literałów (`\\`, `\"`, `\n`, `\r`, `\t` — AppleScript 2.0
  zna te sekwencje), więc treść wiadomości nie wstrzyknie poleceń.
  Wymaga `NSAppleEventsUsageDescription` w Info.plist (build-app.sh)
  i jednorazowej zgody TCC (Prywatność → Automatyzacja → Ksefiarz → Mail);
  odmowa = błąd `scriptFailed` — przebieg jest przerywany, a powiadomienie
  o problemie deduplikowane do jednego dziennie. Uruchomienie bez bundla
  (`swift run`) nie ma Info.plist — automat może być cicho odrzucany przez
  TCC; funkcja jest projektowana pod bundle `dist/Ksefiarz.app`.
- **Przywracanie ustawień z kopii**: JSON kopii trzyma ustawienia jako
  tekst; `BackupService.applySetting` przywraca znane klucze logiczne
  (`isActiveVATPayer`, `pdfBrandingEnabled`, `pdfPaymentQR`,
  `reminder.emails.enabled`) i liczbowe (`demand.paymentDays`,
  `reminder.emails.daysBefore/repeatDays`, `demand.interestRate`) pod
  natywnym typem — inaczej `@AppStorage` czytałby wartości domyślne.
  Pozostałe klucze zostają tekstem (NIP wygląda jak liczba, ale nim nie jest).

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
- **Samofakturowanie (A3)**: uprawnienia podmiotowe (`SelfInvoicing`,
  `RRInvoicing`, `TaxRepresentative`) NIE zmieniają kontekstu uwierzytelnienia —
  są weryfikowane **przy walidacji wysyłanego pliku faktury** („weryfikowana
  jest zależność pomiędzy podmiotem a danymi na fakturach”, ksef-docs
  uprawnienia.md; przykład w OpenAPI: „działanie w imieniu {NIP nadającego}
  w kontekście {NIP uprawnionego}”). Nabywca z uprawnieniem `SelfInvoicing`
  od dostawcy wysyła zwykłą FA(3) **we własnym kontekście** (zwykła sesja
  interaktywna, ten sam formCode), z Podmiot1 = dostawca, Podmiot2 = nabywca
  i `Adnotacje/P_17 = 1`. Podmiot3 z rolą „Wystawca faktury” jawnie NIE
  dotyczy samofakturowania („Nie dotyczy przypadku, gdy wystawcą faktury
  jest nabywca” — XSD FA(3)). Metadane zapytania o faktury mają gotową
  flagę `isSelfInvoicing` (mapowana w `KSeFInvoiceMetadata`). W aplikacji:
  `Invoice.isSelfInvoicing` (P_17), `Invoice.isSelfIssuedPurchase`
  (= zakup i (RR albo samofaktura) — dokument wystawiony przez nas jako
  nabywcę, z pełnym cyklem KSeF) oraz `Invoice.hasKSeFSubmissionLifecycle`
  (= własna sprzedaż bez P_17 albo `isSelfIssuedPurchase`; wspólne źródło
  warunków UI dla statusu, ręcznego odświeżenia, edycji i korekty). Sprzedaż
  z P_17 sporządził klient w naszym imieniu i aplikacja nie oferuje dla niej
  naszej korekty/duplikatu/edycji — korektę wystawia podmiot sporządzający
  fakturę pierwotną (oficjalne wyjaśnienie Biznes.gov.pl „Co zrobić z błędem
  na fakturze lub po zgubieniu faktury”). Wspólne pole
  `Invoice.ksefSubmissionContextNIP` wybiera Podmiot2 dla dokumentów
  `isSelfIssuedPurchase`, a Podmiot1 dla zwykłej sprzedaży. Tryb w `NewInvoiceView`
  zamienia role jak RR, ma osobną serię numeracji
  (`AppSettingsKeys.numberPatternSF`) i adnotację
  „samofakturowanie” na PDF (art. 106e ust. 1 pkt 17), wyłączony branding,
  kopia zapasowa v12. `isManualPurchase` wyklucza RR i samofaktury (lokalny,
  jeszcze niewysłany dokument nie jest ręcznym zakupem). KOD II QR dla
  dokumentów `isSelfIssuedPurchase` używa kontekstu = NIP nabywcy (nasz),
  nie NIP-u sprzedawcy z dokumentu. Nieprzetestowane na żywo (wymaga
  kontrahenta, który nadał uprawnienie; polityka „tylko odczyt na żywo”).
- **Weryfikacja kontrahenta**: KSeF 2.0 NIE ma endpointu „aktywne konto”
  podmiotu — pojęcie nie istnieje (system jest powszechny; każdy ważny NIP
  odbiera faktury po NIP automatycznie). Zweryfikowano pełną listą 73 ścieżek
  OpenAPI. Jedyna KSeF-natywna „weryfikacja relacji” z kontrahentem to
  `POST /permissions/query/authorizations/grants` z `queryType=Received`
  (opcjonalny filtr `authorizingIdentifier` = NIP kontrahenta) — sprawdza,
  jakie uprawnienia podmiotowe nadał NAM kontrahent. Wynik jest dodatkowo
  filtrowany lokalnie po wymaganym przez OpenAPI polu
  `authorizingEntityIdentifier`; wpis bez zgodnego identyfikatora typu `Nip`
  jest pomijany, aby niespójna odpowiedź nie potwierdziła fałszywej relacji.
  Realny status podatnika (czynny/zwolniony) pochodzi z Wykazu podatników VAT
  (`ContractorLookupService`, poza KSeF). Feature A7 łączy oba źródła
  (`ContractorVerificationService`).
- **Historia kontrahenta (D2)**: `ContractorHistory` dopasowuje sprzedaż po
  `buyerNIP`, a zakupy po `sellerNIP`; usuwa separatory i normalizuje polski
  prefiks `PL`. Ukryte dokumenty są bezwarunkowo pomijane. Otwarte saldo jest
  liczone jako brutto minus historia wpłat i agregowane osobno per waluta:
  należności dla sprzedaży, zobowiązania dla zakupów oraz saldo netto
  (należności minus zobowiązania). Ujemne korekty zachowują znak. Średni czas
  płatności i terminowość dotyczą tylko sprzedaży, bo płatność zakupu ocenia
  nas, nie kontrahenta. Wiarygodna data pełnej zapłaty pochodzi z `paymentDate`
  albo z wpłaty domykającej brutto; ręczny `isPaid` bez daty nie wchodzi do
  średniej ani scoringu. Próba terminowości obejmuje rozliczone faktury z
  terminem i datą zapłaty oraz niezapłacone faktury już po terminie. Progi:
  co najmniej 90% — bardzo dobra, 75% — dobra, 50% — wymaga uwagi, niżej —
  słaba; bez próby widok jawnie pokazuje brak danych.
- Tryby offline: zwykła sesja interaktywna z `offlineMode: true` w żądaniu
  wysyłki (WSPÓLNA flaga dla wszystkich trybów — API nie rozróżnia);
  dosyłany XML musi być BAJT W BAJT tym, z którego policzono skrót
  do kodów QR (stąd `Invoice.offlineHashBase64` + wysyłka `rawXmlContent`
  przez `sendInvoiceXML`, nigdy ponowna generacja). Terminy dosłania
  (`Invoice.OfflineReason`, tabela w docs CIRFMF tryby-offline.md):
  offline24 (art. 106nda) — następny dzień roboczy po dacie wystawienia;
  niedostępność (art. 106nh) — następny dzień roboczy po jej zakończeniu;
  awaria (art. 106nf) — 7 dni roboczych od jej zakończenia.
- **Latarnia KSeF**: oficjalne, publiczne API MF wskazane w BIP:
  `https://api-latarnia.ksef.mf.gov.pl/status` i `/messages` (TEST:
  `api-latarnia-test...`; Demo nie ma własnego źródła). `/status` jest
  bieżącą decyzją: `AVAILABLE`, `MAINTENANCE`, `FAILURE`, `TOTAL_FAILURE`;
  `/messages` zwraca ustrukturyzowane komunikaty przez 30 dni po zdarzeniu.
  `MAINTENANCE_ANNOUNCEMENT` ma znane `start/end`; awaria ma osobne
  `FAILURE_START` i `FAILURE_END`, powiązane przez `eventId`. Formularz
  proponuje `.unavailability` albo `.failure`, lecz nie zmienia wyboru bez
  akcji użytkownika. Po wystawieniu zapisuje na `Invoice` eventId i znany
  koniec; cykl MainContentView co 60 s uzupełnia `offlineEventEndedAt` po
  komunikacie kończącym, tylko dla tego samego zdarzenia i środowiska.
  Ręczna zmiana trybu/daty zeruje eventId, więc automat jej nie nadpisze.
  `TOTAL_FAILURE` świadomie nie ma odpowiednika `OfflineReason` — faktur
  z art. 106ng nie dosyła się później do KSeF. Nieznane przyszłe kody oraz
  nieświeży/nieudany odczyt nigdy nie włączają trybu automatycznie.
  Kontrakt: repozytorium CIRFMF `ksef-latarnia` (`open-api.json`,
  `scenariusze.md`); adresy: BIP MF „API Krajowego Systemu e-Faktur”.
- `Invoice.offlineEventEndedAt` pozostaje opcjonalne: dla trwającej awarii
  termin jest nieznany (nil). `Invoice.offlineEventId` wiąże tylko dane
  pochodzące z Latarni; brak identyfikatora oznacza wpis ręczny. Kopia
  zapasowa v13 utrwala to powiązanie.
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

## Anonimowy dostęp do pojedynczej faktury (A5)

Funkcja „Pobierz po numerze KSeF…” na liście zakupów służy do awaryjnego
wciągnięcia dokumentu, który nie pojawił się w zwykłej synchronizacji.
Nie wymaga poświadczeń i nie wykonuje operacji modyfikującej KSeF.

- **Podstawa i wymagane dane**: § 8 rozporządzenia Ministra Finansów
  i Gospodarki z 12.12.2025 r. w sprawie korzystania z KSeF (Dz.U. poz. 1815)
  oraz oficjalny podręcznik KSeF 2.0 wymagają numeru KSeF, numeru faktury
  sprzedawcy (`P_2`), identyfikatora podatkowego nabywcy lub informacji o jego
  braku, nazwy/imienia i nazwiska nabywcy lub informacji o braku oraz kwoty
  należności ogółem (`P_15`). Bramka obsługuje identyfikatory `Nip`, `VatUe`,
  `Other`, `None`; formularz domyślnie podpowiada NIP i nazwę firmy z ustawień.
- **To nie jest endpoint OpenAPI 2.0**: integratorskie `open-api.json` nie ma
  anonimowego pobrania. Aplikacja Podatnika przed logowaniem przekierowuje do
  osobnej, publicznej bramki: produkcja `qr.ksef.mf.gov.pl`, TEST `qr-test…`,
  Demo `qr-demo…`. Kontrakt ustalono z publicznego formularza MF i potwierdzono
  e2e na TEST 14.07.2026 (`LiveAnonymousAccessTests`, oryginalny XML FA(3)).
- **Przepływ WWW**: `GET /invoice/search` → token anty-CSRF + ciasteczko;
  `POST /invoice/search` z numerem KSeF → przekierowanie do
  `/client-app/invoice/search/{nr}/verify-download`; `POST` tego adresu
  z `handler=Format` i pozostałymi danymi → przekierowanie do wyniku.
  Przy sukcesie wynik zawiera XML jako Base64 w `data-xml-text`; HTML koduje
  znak `+` jako `&#x2B;`, dlatego dekodowanie encji MUSI poprzedzać Base64.
  Brak dopasowania jest rozpoznawany po jednoznacznym komunikacie
  „Nie znaleziono faktury”. Zmiana kontraktu/znaczników przez MF kończy się
  jawnym błędem odpowiedzi bramki, nie zapisem częściowych danych.
- **Transport**: `KSeFAnonymousAccessService` tworzy osobną efemeryczną
  `URLSession` z ciasteczkami tylko na czas operacji, ustawia Origin/Referer
  i nigdy nie dołącza tokenu KSeF. Ciało formularza wymaga dokodowania `+`
  jako `%2B` — `URLComponents` zostawia `+` dosłownie (RFC 3986), a serwer
  form-urlencoded zdekodowałby go jako spację i numer faktury/nazwa nabywcy
  z `+` dawałyby fałszywe „Nie znaleziono faktury”. Kwotę z pola tekstowego
  parsuje wyłącznie `parseAmountInput` (ścisłe wzorce z grupowaniem spacją/
  kropką/przecinkiem) — samo `Decimal(string:)` akceptuje prefiks i po cichu
  obcinało np. „1.234,56” do 1.234. W testach wstrzykiwany jest wspólny
  `HTTPTransport`; pokryte są trzy żądania, formularze, środowiska, wariant
  bez identyfikatora/nazwy, encje HTML, znak `+` w polach i tokenie CSRF,
  parsowanie kwot, odpowiedzi błędne i brak faktury. Checkbox „brak nazwy”
  na bramce nie ma atrybutu `name` (czysto kliencki) — wariant bez nazwy
  wysyła pusty `BuyerName`, co potwierdzono na żywym formularzu 14.07.2026.
- **Zapis lokalny**: `AnonymousInvoiceImportEngine` parsuje XML przez
  `FA2XMLParser`, dopisuje numer KSeF (nie jest elementem XML) i deleguje do
  `InvoiceSyncEngine.merge(kind: .purchase)`. Dzięki temu pozycje przypisywane
  są po `context.insert`, deduplikacja obejmuje WSZYSTKIE faktury (również
  ukryte), a `applyDetails`/`PaymentFormPolicy` nie cofają ręcznego `isPaid`.

## Sesja wsadowa (A4) — wysyłka batch/ZIP

Fakty zweryfikowane u źródła (OpenAPI 2.0, ksef-docs `sesja-wsadowa.md`,
klient referencyjny CIRFMF/ksef-client-csharp) i potwierdzone e2e na
środowisku testowym 14.07.2026 (paczka 3 FA(3) → 3 numery KSeF + UPO):

- **Przepływ**: ZIP ze wszystkimi XML → podział binarny na części
  (≤100 MB PRZED szyfrowaniem, maks. 50 części, paczka ≤5 GB; `ZipWriter`
  bez ZIP64 daje dodatkowy twardy limit 4 GB w `KSeFBatchPackage`) →
  szyfrowanie KAŻDEJ części AES-256-CBC/PKCS#7 wspólnym kluczem sesji →
  `POST /sessions/batch` (formCode + `batchFile{fileSize, fileHash}` z SUROWEGO
  ZIP + `fileParts[{ordinalNumber, fileSize, fileHash}]` z części
  ZASZYFROWANYCH + `encryption`) → upload części pod adresy
  z `partUploadRequests` (dokładnie wskazana metoda/URL/nagłówki magazynu
  Azure, surowe bajty w body, **BEZ tokenu dostępu**; łącznik `ordinalNumber`)
  → `POST /sessions/batch/{ref}/close` → polling `GET /sessions/{ref}` →
  wyniki `GET /sessions/{ref}/invoices` (stronicowanie: żądanie z nagłówkiem
  `x-continuation-token`, token następnej strony w treści odpowiedzi).
- **IV nie jest doklejany do szyfrogramu** — mimo mylącego zdania w ksef-docs
  („IV dołączany jako prefiks") klient referencyjny przekazuje IV wyłącznie
  w `encryption.initializationVector`, dokładnie jak sesja interaktywna
  (zweryfikowane w `CryptographyService.cs` i potwierdzone e2e).
- **Jedna schema na sesję** — formCode dotyczy całej paczki; FA(3) i FA_RR(1)
  wymagają OSOBNYCH sesji (`BatchSendEngine.plan` grupuje dokumenty).
- **Kody statusu sesji wsadowej**: 100 rozpoczęta, 150 w przetwarzaniu,
  200 przetworzona pomyślnie (per dokument nadal możliwe odrzucenia),
  405/415/420/430/435/440/445/500 — błędy CAŁEJ paczki; przy kodzie ≥400
  żaden dokument nie został przyjęty. Limit czasu uploadu: liczba części
  × 20 min na każdą część.
- **Korelacja wyników po `invoiceHash`** (zalecenie ksef-docs): sesja NIE
  zwraca referencji per faktura przy wysyłce — dopiero wyniki po przetworzeniu
  (`invoiceHash` = SHA-256 oryginalnego XML). Aplikacja zapisuje wysłany XML
  w `rawXmlContent` i stan „w toku" z numerem sesji, ale BEZ
  `ksefInvoiceReference` — po tym stanie `BatchSendEngine.pendingReconciliation`
  rozpoznaje dokumenty wsadowe do domknięcia (wysyłka interaktywna zawsze ma
  referencję). Domykanie jest wpięte w `SyncCenter.reconcileSubmissions`
  (ręczne „Pobierz z KSeF", cykl 60 s, Centrum synchronizacji).
- **Zasada bezpieczeństwa cofania**: dokument bez wyniku wraca do stanu
  lokalnego TYLKO gdy sesja zakończyła się błędem paczki (≥400) albo jest
  przetworzona i pełna lista wyników go nie zawiera. Kompletność listy przy
  statusie 200 jest potwierdzana licznikami sesji (`successfulInvoiceCount +
  failedInvoiceCount`, awaryjnie `invoiceCount`). Lista pusta, częściowa,
  wadliwa lub bez liczników zostawia dokument „w toku" — cofnięcie dokumentu,
  który KSeF przyjął, groziłoby duplikatem przy ponownej wysyłce. Stronicowanie
  odrzuca powtórzony token i nie zwraca częściowych wyników po wyczerpaniu
  bezpiecznego limitu stron.
- **Niejednoznaczny wynik `close`**: po wysłaniu wszystkich części błąd
  odpowiedzi na `POST /sessions/batch/{ref}/close` nie może zgubić numeru
  sesji — serwer mógł przyjąć zamknięcie przed zerwaniem połączenia. Dokumenty
  pozostają „w toku", a status rozstrzyga bieżące odpytywanie lub późniejsza
  synchronizacja; dopiero pewny błąd całej paczki przywraca stan lokalny.
- **UPO i status per dokument** — wspólne endpointy sesji
  (`/sessions/{ref}/invoices/ksef/{nr}/upo`, `/sessions/{ref}/invoices/{refFaktury}`)
  działają dla sesji wsadowej tak samo jak interaktywnej; po korelacji
  dokumenty przechodzą na istniejącą ścieżkę `InvoiceSubmissionStatusEngine`.
- **Kolejka offline poza paczką** — dosłania offline mają własną ścieżkę
  (`OfflineQueueEngine`, bajt w bajt); `offlineMode` sesji wsadowej jest
  flagą całej paczki, więc świadomie nie mieszamy trybów.
- Znaczniki czasu KSeF miewają 7 cyfr ułamka sekundy
  (`2025-09-18T12:24:16.0154302+00:00`) — systemowy `ISO8601DateFormatter`
  tego nie parsuje; `KSeFService.parseKSeFTimestamp` przycina ułamek do 3 cyfr.

## FA(3) — zasady generowania XML

Generator emituje **FA(3)** (namespace `http://crd.gov.pl/wzor/2025/06/25/13775/`,
kodSystemowy "FA (3)", wariant 3; sesja interaktywna otwierana z formCode
"FA (3)"). Źródło prawdy: oficjalna XSD (CIRFMF/ksef-api). **Kolejność
elementów musi odpowiadać sekwencji XSD** — Fa: KodWaluty, P_1, P_2, P_6?,
P_13_x/P_14_x (+P_14_xW dla waluty obcej), P_15, Adnotacje (obowiązkowe!,
P_17: 1=samofakturowanie/2=brak — z `InvoiceDraft.isSelfInvoicing`,
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

## VIES — weryfikacja VAT-UE kontrahentów UE (D3)

Weryfikacja numerów VAT-UE kontrahentów unijnych, analogiczna do Wykazu
podatników VAT dla krajowych. **Źródło: publiczne REST API VIES Komisji
Europejskiej** — bez klucza. Fakty zweryfikowane u źródła 13.07.2026 (żywe
odpowiedzi z produkcyjnego endpointu):

- Endpoint: `GET https://ec.europa.eu/taxation_customs/vies/rest-api/ms/{kodKraju}/vat/{numer}`.
  Odpowiedź HTTP 200 (JSON) z polami: `isValid` (bool), `userError`
  (`VALID`/`INVALID`/kody awarii), `name`, `address` (może być wielolinijkowy),
  `requestDate` (ISO 8601), `requestIdentifier` (numer potwierdzenia),
  `originalVatNumber`, `vatNumber`, `viesApproximate` (dopasowanie rozmyte —
  nieużywane). Gdy kraj nie udostępnia danych podmiotu, `name`/`address` = „---”
  (normalizowane do pustego napisu przez `VIESLookupService.normalizeField`).
- **Numer potwierdzenia zapytania** (`requestIdentifier`, tzw. consultation
  number, np. `WAPIAAAAZ9cWmQXG`) może zostać zwrócony **wyłącznie**, gdy w
  zapytaniu podano parametry pytającego:
  `?requesterMemberStateCode=PL&requesterNumber={NIP}`. To dowód sprawdzenia do
  celów należytej staranności. Zapytanie anonimowe zwraca pusty
  `requestIdentifier`; sam NIP pytającego nie gwarantuje numeru potwierdzenia.
- **`INVALID` to legalny wynik „numer nieaktywny”, NIE błąd** (zwracany w
  `isValid == false`) — serwis mapuje go na status `.inactive`. Inne wartości
  `userError` to awarie: `INVALID_INPUT` → błąd danych wejściowych,
  `INVALID_REQUESTER_INFO` → ponowienie bez danych pytającego,
  `MS_UNAVAILABLE`/`TIMEOUT`/`MS_MAX_CONCURRENT_REQ*` → niedostępny
  krajowy rejestr (nie wolno pomylić z „nieaktywny”), pozostałe → ogólny błąd
  usługi. Brak `isValid`/`userError` albo sprzeczność tych pól jest błędem
  odpowiedzi, nigdy wynikiem „nieaktywny”. Klasyfikacja w
  `VIESLookupService.lookup`.
- **Grecja = kod `EL`** (nie `GR`) — normalizowane w ścieżce URL i wyniku;
  `XI` (Irlandia Płn.) jest obsługiwane przez VIES. `PL` jest technicznie
  obsługiwane, ale routing kieruje krajowych do Białej listy — `euIdentity`
  pomija `PL`.
- **Routing UE vs krajowy** (`VIESVerification.euIdentity`): kod kraju bierze
  z pola `Contractor.uePrefix`, a przy pustym — z dwuliterowego prefiksu
  wpisanego w samym identyfikatorze; numer VAT jest oczyszczany ze zdublowanego
  prefiksu. Numery UE mogą zawierać litery (np. Irlandia `IE6388047V`), więc
  bramka „Zweryfikuj” dla kontrahenta UE nie wymaga 10 cyfr jak polski NIP.
- VIES potwierdza tylko aktywność numeru VAT-UE (kluczowe dla stawki 0% przy
  WDT) — nie zastępuje weryfikacji tożsamości ani rachunku. Nic nie jest
  utrwalane lokalnie; dane pobierane na żywo w `VIESVerificationView`.
- Dane pytającego są dołączane tylko dla poprawnego polskiego NIP-u (suma
  kontrolna). Niepoprawny lub pusty NIP nie blokuje sprawdzenia kontrahenta —
  zapytanie pozostaje anonimowe i nie zwraca numeru potwierdzenia. Gdy VIES
  odrzuci poprawny formalnie NIP pytającego, klient automatycznie ponawia
  weryfikację anonimowo.

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
(xmllint, 12.07.2026). Uproszczenia jak w V7M (OSS poza JPK, zwykłe zakupy
jako pozostałe nabycia, okres po dacie sprzedaży/wystawienia).

### VAT RR po stronie nabywcy (art. 116)

`JPKV7VATRRPolicy` jest osobną specyfikacją podatkową dla dokumentów
`kind == .purchase && isRR`; nie korzysta z `salesBuckets`. Reguły:

- faktura VAT RR zwiększa podatek naliczony nabywcy w okresie **pełnej
  zapłaty** należności wraz ze zryczałtowanym zwrotem; datą jest
  `paymentDate` albo dzień, w którym chronologiczna suma `PaymentRecord`
  pokryła bezwzględną kwotę brutto;
- automatyczna kwalifikacja wymaga przelewu i numeru rachunku rolnika;
  alternatywnie pełne pokrycie może wynikać z płatności pochodzących z importu
  wyciągu (`bankImport`). Zapłata częściowa, brak daty albo brak dowodu kanału
  bankowego nie tworzy wiersza i daje ostrzeżenie;
- ewidencja zakupu zawiera `DokumentZakupu=VAT_RR`, `K_42` (wartość nabycia)
  oraz `K_43` (zryczałtowany zwrot jako podatek naliczony). `ZakupCtrl`,
  `P_42/P_43`, rozliczenie VAT-7/VAT-7K i prognoza `TaxCalendarEngine`
  korzystają z tych samych zakwalifikowanych kwot;
- korekta zwiększająca jest ujmowana po dopłacie, a zmniejszająca po dacie
  bankowego zwrotu przez rolnika (kwoty ujemne K_42/K_43). Korekta bez wpływu
  na kwoty nie tworzy pustego wiersza;
- model nie potwierdza celu wykorzystania nabycia ani treści dowodu zapłaty.
  Dlatego nawet zakwalifikowany wiersz przypomina o ręcznej weryfikacji
  związku ze sprzedażą opodatkowaną i numeru/daty faktury albo numeru KSeF na
  dowodzie zapłaty. To warunki art. 116 ust. 6, nie zgadywane przez aplikację.

Źródła prawdy (zweryfikowane 14.07.2026): [art. 116 ustawy o VAT — tekst
ujednolicony ELI](https://eli.gov.pl/eli/DU/2025/775/ogl), [broszura MF
JPK_VAT od 1.02.2026](https://www.podatki.gov.pl/media/wgbkrejs/broszura-jpk_vat-z-deklaracj%C4%85-od-1-lutego-2026-r.pdf)
oraz oficjalne XSD [JPK_V7M(3)](https://crd.gov.pl/wzor/2025/12/19/14090/)
i [JPK_V7K(3)](https://crd.gov.pl/wzor/2025/12/19/14089/). Próbki z wierszem
VAT RR (`NrKSeF`, `DokumentZakupu`, K_42/K_43) przeszły obie oficjalne schemy
przez `xmllint` 14.07.2026.
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

## JPK_FA(4) — JPK faktur na żądanie (B4)

Osobna od JPK_V7 struktura przekazywana WYŁĄCZNIE na wezwanie organu
podatkowego (art. 193a Ordynacji podatkowej; kontrola, czynności
sprawdzające, postępowanie). Fakty zweryfikowane u źródła: oficjalny XSD
`Schemat_JPK_FA(4)_v1-0.xsd` (gov.pl/web/kas/struktury-jpk, namespace
`http://jpk.mf.gov.pl/wzor/2022/02/17/02171/`, obowiązuje od 1.04.2022 —
także dla faktur sprzed tej daty) oraz broszura informacyjna MF JPK_FA(4)
z sekcją pytań i odpowiedzi. Wygenerowany dokument (VAT wielostawkowa,
waluta obca, OSS, KOREKTA, ZAL z zamówieniem, ROZ, marża, samofakturowanie,
nabywca UE) zweryfikowany oficjalną XSD (xmllint, 14.07.2026).

- **Zakres podmiotowy**: wyłącznie faktury SPRZEDAŻY podatnika (broszura,
  pyt. 2 i 8). Zakupy odpadają w całości; samofaktury wystawione przez nas
  w imieniu dostawcy (`isSelfIssuedPurchase`) należą do JPK_FA dostawcy;
  nasza sprzedaż z adnotacją P_17 (wystawiona przez klienta w naszym
  imieniu) wchodzi normalnie. Faktury VAT RR mają osobną strukturę
  JPK_FA_RR — dokumenty `isRR` są pomijane. Proformy są poza strukturalnie
  (osobny model). Okres pliku = zakres dat WYSTAWIENIA (organ żąda wg
  kryteriów kontroli); granice włączne, porównanie po dniach.
- **Nagłówek**: `KodFormularza kodSystemowy="JPK_FA (4)" wersjaSchemy="1-0"`,
  wariant 4, **CelZlozenia=1 na stałe** — JPK na żądanie NIE podlega
  korekcie; DataOd/DataDo, KodUrzedu (wspólny klucz `jpk.kodUrzedu`).
- **Podmiot1**: IdentyfikatorPodmiotu{NIP, PelnaNazwa} w namespace tns,
  ale **elementy adresu (typ etd:TAdresPolski1) są kwalifikowane
  prefiksem etd** — bez prefiksu plik nie waliduje się (ta sama pułapka co
  Podmiot1 w VAT-UE). Adres jest strukturalny (województwo/powiat/gmina/
  ulica?/nr domu/nr lokalu?/miejscowość/kod pocztowy) — nie da się go
  wyprowadzić z jednolinijkowego adresu z Ustawień, stąd osobne klucze
  `jpk.fa.*` wypełniane w arkuszu eksportu (poza kopią zapasową, jak
  pozostałe klucze `jpk.*`).
- **Kwoty w walucie faktury** (broszura, pyt. 7): sekcje Faktura
  i FakturaWiersz w walucie dokumentu (KodWaluty, słownik ISO-4217
  w XSD); jedynie podatek przeliczony na złote (art. 31a) idzie do
  P_14_1W/P_14_2W/P_14_3W (kurs z faktury; brak kursu = ostrzeżenie i brak
  pól W). Sumy kontrolne (WartoscFaktur = suma P_15, WartoscWierszyFaktur =
  suma P_11) są sumami nominalnymi — przy wielu walutach ostrzeżenie.
- **Mapowanie stawek** (pyt. 6 i 9): 23/22→P_13_1/P_14_1, 8/7→P_13_2/P_14_2,
  5→P_13_3/P_14_3, 4/3 oraz odwrotne obciążenie (`oo`)→P_13_4/P_14_4,
  transakcje poza terytorium kraju (`np`)→P_13_5, **eksport towarów
  i WDT→P_13_6** (stawka 0), zw→P_13_7
  (+P_19=true; aplikacja nie przechowuje podstawy zwolnienia — P_19A–C
  puste z ostrzeżeniem), OSS→P_13_5+P_14_5 z **P_12_XII** w wierszu
  (pyt. 16; pole przyjmuje dowolną stawkę państwa konsumpcji). `oo` i `np`
  mogą pochodzić z zaimportowanych pozycji; `oo` ustawia także P_18=true.
  P_12 w wierszu to enum (23|22|8|7|5|4|3|0|zw|oo|np) — stawka spoza
  słownika (np. historyczna RR 6,5%) pomija pole z ostrzeżeniem.
- **Rodzaje dokumentów**: RodzajFaktury ∈ {VAT, KOREKTA, ZAL}.
  ROZ i UPR → "VAT" (pyt. 12; rozliczająca z `NrFaZaliczkowej` — numery
  KSeF poprzednich zaliczkowych, limit 256 znaków z obcięciem
  i ostrzeżeniem). Korekty (KOR/KOR_ZAL/KOR_ROZ) → "KOREKTA" z kwotami
  RÓŻNICY (tak są już zapisane w aplikacji) + PrzyczynaKorekty?/
  NrFaKorygowanej (korekta bez numeru korygowanej pomija sekwencję
  z ostrzeżeniem).
- **Faktury zaliczkowe** (pyt. 12 i 14): ZAL i KOR_ZAL nie mają wierszy
  FakturaWiersz — pozycje idą do węzła **Zamowienie** (P_2AZ = numer
  faktury, ZamowienieWiersz z P_7Z…P_12Z/P_12Z_XII) + ZamowienieCtrl.
  Sekcja Faktura trzyma kwoty ZALICZKI (P_15 = kwota zapłaty). Aplikacja
  nie przechowuje odrębnej wartości całego zamówienia, więc
  WartoscZamowienia = kwoty dokumentu z ostrzeżeniem do weryfikacji.
- **Ograniczenia XSD**: plik wymaga ≥1 Faktura i ≥1 FakturaWiersz
  (TNaturalnyJPK jest minExclusive 0) — pusty okres albo plik z samymi
  zaliczkami nie przejdzie walidacji; generator ostrzega, a UI blokuje
  zapis pliku bez obowiązkowych wierszy. P_16 (metoda kasowa) nie jest
  modelowane i pozostaje false. P_18 jest wyprowadzane z pozycji `oo`. Procedury
  marży mapowane z `marginProcedureRaw`: "2"→P_106E_2,
  "3_1/3_2/3_3"→P_106E_3 + wymagana adnotacja P_106E_3A.
- **Przekazanie**: elektronicznie (Klient JPK WEB, e-mikrofirma) albo na
  nośniku danych; NIE e-mailem ani przez ePUAP. Organ daje ≥3 dni.

## OCR faktur kosztowych — macOS Vision (D1)

- Cel: skan/zdjęcie albo PDF papierowej faktury → wstępnie wypełniony
  formularz „zakupu spoza KSeF" (`NewPurchaseView`). Przetwarzanie w całości
  lokalne (Vision + PDFKit), bez zależności zewnętrznych. OCR jest
  heurystyczny — UI zawsze każe zweryfikować dane przed zapisem, a wynik
  nadpisuje wyłącznie pola rozpoznane (nabywca, status opłacenia, uwagi,
  kategoria i kurs zostają nietknięte — `InvoiceOCRExtraction.applied(to:)`).
- **Podział warstw**: `InvoiceOCRService` (Services) zamienia plik na linie
  tekstu; `InvoiceOCRParser` (Logic, czysta funkcja z pełnymi testami)
  zamienia linie na `InvoiceOCRExtraction`. PDF z warstwą tekstową
  (≥ 32 znaki na stronę) czytany jest wprost przez `PDFPage.string` — bez
  strat OCR; strona-skan jest renderowana do bitmapy (300 DPI, limit 4000 px).
  Obrazy są przed OCR obracane zgodnie z orientacją EXIF i skalowane do
  maks. 4000 px dłuższego boku, żeby nie dekodować dużych zdjęć do pełnej
  bitmapy. Obraz przechodzi przez `VNRecognizeTextRequest` (`.accurate`, korekcja
  językowa). Limit 4 stron PDF. Języki żądania filtrowane przez
  `supportedRecognitionLanguages()` (pl/en) — żądanie niewspieranego języka
  kończy się błędem `perform`. Obserwacje sortowane w kolejność czytania
  (współrzędne Vision są znormalizowane z początkiem w lewym dolnym rogu).
- **Heurystyki parsera** (wszystkie odporne na zgubione diakrytyki —
  `normalized` foldinguje, `ł` zamieniane jawnie, bo nie jest znakiem
  składanym): numer po „Faktura … nr"/etykietach (ucinany przed „z dnia"
  i datami); daty `dd.MM.yyyy`/ISO/słownie z polskimi miesiącami (etykieta
  w tej samej albo następnej linii; jedyna data w dokumencie = data
  wystawienia); NIP z walidacją sumy kontrolnej (`InvoiceValidator`),
  z pominięciem NIP własnej firmy i wyborem najbliższego od etykiety
  „Sprzedawca"; zagraniczny VAT ID tylko z prefiksem z
  `VIESVerification.viesCountryCodes` i tylko w linii z „VAT"/„NIP";
  kwoty najpierw z wiersza podsumowania (netto+VAT=brutto uwiarygodnia
  komplet; brutto = ostatnia kwota wiersza, a para bezpośrednio przed nią
  ma pierwszeństwo — klasyczny układ „netto VAT brutto"), potem z etykiet;
  rachunek NRB przez `ElixirPaymentExporter.isValidNRB` (numer w kontekście
  „nabywcy" tylko jako ostateczność). `resolvedAmounts()` wyprowadza
  brakującą kwotę z równania netto+VAT=brutto (samo brutto → netto=brutto,
  VAT=0 — przypadek paragonu); **para netto+VAT ma pierwszeństwo przed
  brutto**, a jawna etykieta „Suma/Wartość brutto” wygrywa z „Do zapłaty”,
  bo to ostatnie bywa saldem po częściowej wpłacie (ujemna różnica nigdy
  nie jest ufana). Nazwa z łączonej linii „Sprzedawca: …, NIP: …” jest
  odcinana przed identyfikatorem; kody walut, VAT ID i prefiks IBAN są
  niewrażliwe na wielkość liter. Pułapki pokryte testami: „Do zapłaty:
  0,00", numer faktury `1/07/2026` (nie jest datą — daty odrzucane tylko
  w zapisie kropkowym/ISO), „Rachunek bankowy nr" ≠ numer dokumentu,
  prefiks IBAN „PL61" ≠ VAT ID (fallback UE pomija PL i wymaga ≥ 7 znaków
  numeru), „Stawka VAT: 23,00" ≠ kwota VAT, NIP z nagłówka papieru
  firmowego (nad etykietą „Sprzedawca") lepszy niż NIP nabywcy. Samo
  brutto zgodne z brutto edytowanego szkicu nie zeruje istniejącego
  podziału netto/VAT.
- Testy e2e prawdziwego Vision (syntetyczny „skan" rysowany Core Text →
  PNG oraz PDF-obraz bez warstwy tekstowej) są w `InvoiceOCRServiceTests`
  i przechodzą lokalnie w ~1 s; treść syntetyczna bez polskich znaków,
  bo zestaw języków Vision zależy od wersji systemu.

## Faktura proforma (E2)

- Proforma to **dokument handlowy, nie księgowy**: nie idzie do KSeF, nie
  tworzy obowiązku VAT, nie wchodzi do żadnej ewidencji (KPiR, ryczałt,
  JPK_V7, VAT-UE) ani statystyk (Kokpit, raporty, historia kontrahenta,
  terminy). Dlatego jest **osobnym modelem `Proforma` (+ `ProformaLine`)**,
  a NIE flagą na `Invoice`. Dzięki izolacji typem proforma strukturalnie nie
  może trafić do żadnego z ~20 miejsc czytających `FetchDescriptor<Invoice>` /
  `@Query<Invoice>` — nie trzeba pamiętać o jej wykluczaniu (i żadna przyszła
  agregacja jej nie policzy przez pomyłkę). Świadoma decyzja zgodna z filozofią
  niezmienników domenowych.
- Cykl życia: aktywna → (opcjonalnie opłacona zaliczkowo) → **rozliczona**
  właściwą fakturą VAT. Konwersja: `ProformaDetailView`/`ProformaListView`
  otwierają `NewInvoiceView(initialDraft: proforma.invoiceDraft(), …)` — numer
  nadawany z serii VAT, pełna walidacja faktury; po zapisie/wysyłce nowy
  callback `onCreatedInvoice` oznacza proformę jako rozliczoną z numerem
  powstałej faktury (`Proforma.markConverted`). Ręcznie potwierdzone opłacenie
  proformy jest przenoszone na fakturę (nigdy nie cofa statusu już ustawionego
  na fakturze). Dla waluty obcej kurs informacyjny proformy nie jest kopiowany:
  nowa data faktury wymaga uzupełnienia właściwego kursu przed zapisem.
- PDF i e-mail reużywają infrastruktury faktur przez **przejściową
  (nieutrwaloną) `Invoice`** — `Proforma.transientInvoice()` buduje obiekt
  `kind == .sales`, `documentTypeRaw == "PRO"`, bez `ksefId`. Generator PDF
  dostał case „PRO" (tytuł „Faktura PROFORMA" + adnotacja „nie jest fakturą
  VAT"); brak numeru/offline oznacza brak kodów weryfikacyjnych KSeF, a kod QR
  płatności 2D ZBP powstaje normalnie (klient płaci za proformę).
  `ProformaEmailView` używa `InvoiceEmailService.composeDocument` z własnym
  tematem/treścią „proforma" i nazwą załącznika `Proforma-…pdf`.
- Walidacja: `ProformaValidator` (czysta logika, testy). W odróżnieniu od
  faktury VAT **NIP nabywcy jest opcjonalny** (proforma bywa dla konsumenta
  albo kontrahenta zagranicznego) — sprawdzany tylko, gdy podany. NIP
  sprzedawcy (nasza firma) wymagany.
- Daty proformy są datami kalendarzowymi: „ważna do" i termin płatności
  obejmują cały wskazany dzień; status wygasłej/zaległej pojawia się od dnia
  następnego.
- Edycja pozycji używa `Proforma.replaceLines(with:in:)`, które jawnie usuwa
  poprzednie `ProformaLine`; samo przypisanie relacji zostawia w SwiftData
  osierocone rekordy mimo reguły kaskadowej na usunięcie całej proformy.
- Numeracja: osobna seria (domyślny wzorzec `PF/{RRRR}/{MM}/{NNN}`,
  `InvoiceNumberGenerator.defaultProformaPattern`, klucz `numberPatternPRO`;
  puste pole = domyślny wzorzec PF, a NIE seria VAT). Kopia zapasowa v11
  obejmuje proformy (`BackupProforma`/`BackupProformaLine`, import z pominięciem
  duplikatów po id/numerze).

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
