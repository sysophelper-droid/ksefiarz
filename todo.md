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

- [ ] A5. Anonimowy dostęp / pobranie faktury po numerze KSeF — wciągnięcie
  faktury zakupowej po numerze KSeF + danych, gdy nie przyszła synchronizacją.
#### B. Podatki dochodowe / ewidencje

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

- [ ] C3. Ścieżka windykacji — eskalacja: przypomnienie → wezwanie → nota →
  dane do EPU (e-sąd); status windykacji na fakturze (bazuje na wezwaniach).
- [ ] C4. Automatyczne przypomnienia e-mail przed/po terminie — cykliczne
  miękkie ponaglenia do kontrahentów (dziś powiadomienia tylko systemowe).

#### E. Dokumenty / wygląd

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

### Wysyłka wsadowa do KSeF — sesja batch/ZIP (14.07.2026)

- [x] A4. Masowa wysyłka lokalnych dokumentów jedną paczką ZIP zamiast
  pojedynczych sesji interaktywnych (migracja/zaległości, np. po imporcie
  D4). Przycisk „Wyślij wsadowo do KSeF” na liście sprzedaży + akcja zbiorcza
  w menu kontekstowym; arkusz z wyborem kwalifikujących się dokumentów
  (lokalne z cyklem KSeF, także samofaktury i VAT RR), potwierdzeniem
  z nazwą środowiska, postępem i wynikiem per dokument. Przepływ wg
  ksef-docs/OpenAPI: ZIP → podział binarny ≤100 MB/≤50 części → szyfrowanie
  części AES-256-CBC wspólnym kluczem sesji (IV osobno — jak sesja
  interaktywna; USTALENIE z klienta referencyjnego CIRFMF wbrew mylącemu
  zdaniu docs o „prefiksie IV”) → `POST /sessions/batch` → upload części pod
  adresy magazynu (bez tokenu) → close → polling statusu → wyniki
  ze stronicowaniem `x-continuation-token`. FA(3) i FA_RR(1) w osobnych
  sesjach (formCode paczki). Korelacja wyników po skrócie SHA-256 dokumentu;
  dokument „w toku” bez referencji faktury domyka `SyncCenter` (cykl 60 s /
  ręczna synchronizacja / przycisk „Sprawdź teraz”). Reguła bezpieczeństwa:
  cofnięcie do stanu lokalnego tylko przy pewnym braku dokumentu w wynikach
  (błąd paczki ≥400 albo pełna lista bez dokumentu) — pusta lista przy
  statusie 200 niczego nie cofa (ochrona przed duplikatem). UPO wspólną
  ścieżką `InvoiceSubmissionStatusEngine`. 29 nowych testów (paczka/podział,
  silnik, pełny przepływ usługi na atrapie z odszyfrowaniem części,
  domykanie w SyncCenter) + `LiveBatchSendTests` zweryfikowany NA ŻYWO na
  środowisku testowym (paczka 3 faktur → 3 numery KSeF + UPO, 14.07.2026).

### Automatyczne wykrywanie awarii KSeF — Latarnia MF (13.07.2026)

- [x] A6. Publiczny klient API Latarni KSeF (`/status` + `/messages`, bez
  autoryzacji) odświeża komunikaty MF co minutę dla produkcji i TEST; Demo
  świadomie nie dziedziczy zdarzeń testowych. Formularz pokazuje aktywną
  niedostępność/awarię, treść komunikatu i wyliczony lub opisowy termin oraz
  pozwala jednym przyciskiem użyć proponowanego trybu. Próba wysyłki przy
  błędzie łączności korzysta z trybu potwierdzonego przez Latarnię, a bez
  komunikatu bezpiecznie pozostaje w offline24. Faktura zapamiętuje `eventId`;
  `FAILURE_END` albo zmieniony koniec przerwy automatycznie aktualizuje termin
  wyłącznie powiązanego dokumentu, bez nadpisywania ręcznych decyzji.
  Zapowiedzi przerw są widoczne do 7 dni wcześniej, błąd/stary odczyt jest
  jawny, nieznane statusy są bezpieczne, a `TOTAL_FAILURE` jest blokowane jako
  odrębny tryb bez późniejszego dosyłania. Kopia zapasowa v13; 10 nowych
  testów klienta, dekodowania, mapowania, terminów i przypadków brzegowych.

### Samofakturowanie — wystawianie faktur w imieniu dostawcy (13.07.2026)

- [x] A3. Przełącznik „Samofakturowanie” w formularzu wystawiania (i wejście
  „Wystaw samofakturę” pod „+” na liście zakupów): zwykła FA(3) z adnotacją
  `P_17 = 1` (art. 106d), Podmiot1 = dostawca, Podmiot2 = nasza firma;
  dokument zapisywany jako zakup (koszt/VAT naliczony), ale z pełnym cyklem
  KSeF jak sprzedaż (edycja lokalna, wysyłka we własnym kontekście, statusy,
  UPO, tryby offline, korekty dziedziczące adnotację i role). USTALENIE
  u źródła (ksef-docs, OpenAPI): uprawnienia podmiotowe nie zmieniają
  kontekstu uwierzytelnienia — KSeF weryfikuje relację `SelfInvoicing`
  (nadaną nam przez dostawcę) przy walidacji pliku. Osobna seria numeracji
  samofaktur (Ustawienia; pusta dziedziczy wzorzec VAT), adnotacja
  „samofakturowanie” na PDF, wyłączony branding (dokument formalnie
  dostawcy), rachunek płatności = rachunek dostawcy, znaczniki na listach
  i w szczegółach (także dla sprzedaży z P_17 pobranej z KSeF — wystawionej
  przez klienta w naszym imieniu, z flagą wprost z metadanych zapytania;
  dokument tylko do odczytu, bo jego korektę wystawia klient jako podmiot
  sporządzający fakturę pierwotną).
  Kopia zapasowa v12. Przy okazji domknięte regresje RR: lokalna faktura
  VAT RR/samofaktura nie jest już „ręcznym zakupem” (błędny formularz
  edycji), a KOD II QR dokumentów wystawianych przez nas jako nabywcę używa
  kontekstu = NIP nabywcy. Dokument zweryfikowany oficjalną XSD FA(3)
  (xmllint); 19 nowych testów. Wysyłka nieprzetestowana na żywo — wymaga
  kontrahenta, który nadał uprawnienie (polityka „tylko odczyt na żywo”).

### Import wsadowy CSV/Excel (13.07.2026)

- [x] D4. Masowy import kontrahentów, towarów/usług i faktur z CSV/TSV lub
  pierwszego arkusza `.xlsx` (migracja z Fakturowni/wFirmy, czy inny masowy
  import). Kreator w „Słownikach” automatycznie rozpoznaje typowe nagłówki,
  pozwala ręcznie mapować dowolny układ i przed zapisem pokazuje bilans,
  diagnostykę wierszy oraz podgląd źródła. Parser obsługuje polskie kodowania,
  separatory i liczby, tekstowe NIP/SKU/EAN oraz daty/style Excela; układ
  katalogu wFirmy poprawnie rozróżnia cenę netto/brutto. Powtarzane wiersze
  faktury tworzą pozycje. Deduplikacja po NIP, SKU/EAN/nazwie oraz numerze
  KSeF/kluczu dokumentu obejmuje także faktury ukryte i niczego nie nadpisuje.
  Faktury bez numeru KSeF pozostają lokalne, z numerem mają stan przyjęty;
  importer nie wysyła ich do KSeF. Czysta logika, czytnik XLSX i zapis
  SwiftData mają 17 testów (w tym rzeczywisty plik OOXML i regresje
  niezmienników).

### OCR faktur kosztowych — macOS Vision (13.07.2026)

- [x] D1. Przycisk „Wczytaj ze skanu / PDF (OCR)” w formularzu zakupu spoza
  KSeF (+ upuszczenie pliku na okno): skan/zdjęcie (PNG, JPEG, TIFF, HEIC)
  albo PDF papierowej faktury wstępnie wypełnia formularz — natywnie przez
  Vision/PDFKit, bez zależności zewnętrznych i bez wysyłania danych. PDF
  z warstwą tekstową czytany wprost (bez strat OCR), skan przez
  `VNRecognizeTextRequest`. Czysty parser `InvoiceOCRParser`
  (`InvoiceOCRExtraction.applied(to:)` nadpisuje tylko rozpoznane pola):
  numer, daty (też słownie), sprzedawca z NIP (suma kontrolna, NIP własnej
  firmy pomijany) / VAT ID UE, adres, kwoty (wiersz podsumowania
  netto+VAT=brutto), waluta, NRB (IBAN mod 97), termin i forma płatności.
  53 testy, w tym e2e prawdziwego Vision na syntetycznym skanie (PNG
  i PDF-obraz). Heurystyki odporne na zgubione diakrytyki OCR oraz na
  pułapki dokumentów: „Do zapłaty: 0,00” po wpłacie, numery n/MM/RRRR,
  rachunek bankowy vs numer dokumentu, prefiks IBAN vs VAT ID, stawka
  VAT vs kwota VAT, rachunek nabywcy vs rachunek do wpłaty.

### Weryfikacja VIES — kontrahenci UE (13.07.2026)

- [x] D3. Karta „Weryfikacja VAT-UE (VIES)” dla kontrahentów unijnych,
  analogiczna do Białej listy dla krajowych. Ta sama akcja „Zweryfikuj” (menu
  kontekstowe listy kontrahentów oraz przycisk w edytorze) routuje do VIES,
  gdy `VIESVerification.euIdentity` rozpozna prefiks UE (pole „Prefiks UE” inne
  niż PL albo prefiks w identyfikatorze). Sprawdza w REST API VIES Komisji
  Europejskiej, czy numer VAT-UE jest aktywny; przy podanym NIP firmy pobiera
  **numer potwierdzenia zapytania** (dowód należytej staranności). Uczciwa
  klasyfikacja `userError`: `INVALID` = numer nieaktywny (ostrzeżenie o braku
  stawki 0% WDT), a awarie rejestru (`MS_UNAVAILABLE`/`TIMEOUT`) NIE są mylone
  z „nieaktywny”. Czysta logika `VIESVerification` (status, werdykt z wagami,
  routing euIdentity) + `VIESLookupService` (klient REST) + koordynator
  `VIESVerificationService`; 39 testów jednostkowych (atrapa transportu), w tym
  regresje dla niepełnych/niespójnych odpowiedzi i błędnego NIP-u pytającego.
  Kontrakt API zweryfikowany u źródła na żywych odpowiedziach. Publiczne API,
  bez klucza; nic nie jest utrwalane lokalnie.

### Faktura proforma — dokument handlowy (13.07.2026)

- [x] E2. Faktury proforma jako OSOBNY model (`Proforma` + `ProformaLine`),
  a nie flaga na `Invoice` — proforma strukturalnie nie może trafić do żadnego
  `FetchDescriptor<Invoice>`/`@Query<Invoice>`, więc żadna ewidencja (KPiR,
  ryczałt, JPK_V7, VAT-UE) ani statystyka (Kokpit, raporty, historia
  kontrahenta, terminy) nie policzy jej przez pomyłkę — proforma nie jest
  dokumentem księgowym i nie idzie do KSeF. Osobna sekcja „Faktury proforma"
  w pasku bocznym (lista, filtry stanu rozliczenia, akcje). Formularz
  `NewProformaView` (bez trybów KSeF/offline, załączników i pól podatkowych;
  NIP nabywcy opcjonalny — proforma bywa dla konsumenta). Czysty
  `ProformaValidator` z testami. PDF i e-mail reużywają infrastruktury faktur
  przez PRZEJŚCIOWĄ, nieutrwaloną `Invoice` (`transientInvoice()`): wydruk
  „Faktura PROFORMA" z adnotacją „nie jest fakturą VAT", kod QR płatności 2D
  ZBP, brak kodów weryfikacyjnych KSeF; e-mail z proforma-specyficznym tematem
  i treścią. **Konwersja proforma → faktura VAT**: „Konwertuj na fakturę VAT"
  otwiera `NewInvoiceView` wypełniony danymi proformy (numer z serii VAT), a po
  zapisie/wysyłce proforma zostaje oznaczona jako rozliczona z numerem faktury
  (nowy `onCreatedInvoice` na `NewInvoiceView`). Osobna numeracja (wzorzec
  `PF/…`, klucz `numberPatternPRO`) i kopia zapasowa v11. Review doprecyzował
  semantykę konwersji: status zapłaty przechodzi na fakturę, walutowy kurs
  proformy nie jest kopiowany do dokumentu z nową datą, a daty ważności i
  płatności obejmują cały wskazany dzień. Edycja jawnie usuwa stare pozycje,
  żeby nie zostawiać osieroconych rekordów `ProformaLine` w SwiftData.

### Plik przelewów do banku — Elixir-O (13.07.2026)

- [x] C2. Lista zakupów eksportuje zaznaczone albo wszystkie widoczne
  zobowiązania do pliku `.pli` importowanego jako paczka przelewów. Czysty
  `ElixirPaymentExporter` tworzy bez nagłówka 16-polowe rekordy `110` z CRLF,
  datą `RRRRMMDD`, kwotą salda w groszach, rachunkami NRB, numerami
  rozliczeniowymi banków, nazwami/adresami i tytułem do 4×35 znaków. Kontrola
  sumy NRB modulo 97; wyłącznie widoczne, nieopłacone zakupy w PLN; jawna
  lista pominięć (opłacone, ukryte, walutowe, brak/błąd rachunku). MPP ma
  kod `53` i komunikat `/VAT/…/IDC/…/INV/…`; kwota VAT jest edytowalna,
  a dla płatności częściowej podpowiadana proporcjonalnie. Wybór rachunku
  źródłowego, daty oraz kodowania UTF-8/Windows-1250/ISO-8859-2, limit 50
  dyspozycji. Eksport nie ustawia `isPaid` — użytkownik weryfikuje i autoryzuje
  przelewy w banku. Format zweryfikowany z instrukcjami mBanku i PKO BP;
  osobny suite testów generatora, walidacji, MPP, kodowań i zabezpieczenia
  struktury pliku.

### Kod QR płatności na PDF — standard 2D ZBP (13.07.2026)

- [x] ⭐ C1. Na własnych fakturach sprzedaży PDF dostaje kod „Zapłać (QR)”
  zgodny z Rekomendacją Związku Banków Polskich (9 pól rozdzielonych `|`:
  poprawny NIP odbiorcy instytucjonalnego, kod kraju, 26-cyfrowy NRB,
  kwota w groszach `%06d`, nazwa odbiorcy ≤20,
  tytuł ≤32, trzy pola rezerwowe; maks. 160 znaków). Klient skanuje kod
  aplikacją banku i płaci bez przepisywania danych. Kod powstaje wyłącznie dla
  faktur sprzedaży w PLN z podanym rachunkiem i niezerowym saldem — kwota to
  saldo pozostałe do zapłaty (`outstandingAmount`), więc faktura opłacona kodu
  nie dostaje, a częściowo opłacona dostaje kod na kwotę brakującą. Odbiorcą
  przelewu jest sprzedawca, tytułem — numer faktury; rachunek i NIP są
  normalizowane (usuwanie spacji, prefiksu `PL`, kresek), a znaki spoza
  rekomendacji nie mogą wstrzyknąć separatora pól. Renderer używa wymaganego
  przez ZBP poziomu korekcji błędów `L`. Przełącznik
  w Ustawieniach → Firma („Drukuj kod QR płatności na fakturach”, domyślnie
  włączony, w kopii zapasowej; poprawnie odczytywany także po przywróceniu
  tekstowej wartości `"0"`/`"1"`), niezależny od kodu weryfikacyjnego KSeF.
  Czysta logika `PaymentQRCode` (weryfikacja formatu u źródła — referencyjna
  biblioteka ZBP) z osobnym suitem testów; render `QRCodeRenderer`, osadzenie
  w `InvoicePDFGenerator`.

### Karta i historia kontrahenta (13.07.2026)

- [x] ⭐ D2. Ze słownika kontrahentów dostępna jest jedna karta wszystkich
  widocznych dokumentów sprzedaży i zakupu z otwieraniem szczegółów,
  należnościami, zobowiązaniami i saldem netto osobno per waluta. Średni czas
  płatności opiera się na jawnej dacie zapłaty albo wpłacie domykającej brutto;
  ręczny znacznik bez daty nie tworzy fałszywej precyzji. Scoring terminowości
  odbiorcy (bardzo dobra / dobra / wymaga uwagi / słaba) liczy sprzedaż
  rozliczoną z terminem oraz bieżące zaległości; zakupy nie oceniają
  kontrahenta, bo ich płatnikiem jest nasza firma. Dopasowanie normalizuje NIP,
  ujemne korekty zachowują znak, dokumenty ukryte pozostają poza statystyką.
  Czysta logika `ContractorHistory` ma testy sald, walut, korekt, częściowych
  wpłat, scoringu, ról stron oraz przypadków bez danych.

### Weryfikacja kontrahenta w KSeF (13.07.2026)

- [x] A7. Karta „Weryfikacja kontrahenta” (menu kontekstowe listy kontrahentów
  oraz przycisk „Zweryfikuj” w edytorze). USTALENIE u źródła (OpenAPI KSeF 2.0,
  73 ścieżki): KSeF **nie ma** endpointu „aktywne konto” — bo takie pojęcie nie
  istnieje. System jest powszechny, każdy ważny NIP odbiera faktury po NIP
  automatycznie. Zamiast atrapy zbudowano uczciwą, złożoną weryfikację:
  walidacja NIP (suma kontrolna) + status VAT z Wykazu podatników VAT (Biała
  lista: czynny/zwolniony/niezarejestrowany) + KSeF-natywne sprawdzenie relacji
  uprawnień podmiotowych (`POST /permissions/query/authorizations/grants`
  `queryType=Received`, filtr po NIP nadającego — czy kontrahent nadał NASZEJ
  firmie np. samofakturowanie/przedstawiciela). Werdykt z wagami (OK/info/
  ostrzeżenie/krytyczne) i stałą, jawną notą o naturze KSeF. Czysta logika
  `ContractorVerification` + koordynator `ContractorVerificationService`
  (izolacja awarii źródeł) + `receivedAuthorizations(fromNIP:)` na
  `KSeFService`; 22 testy jednostkowe. Klasyfikacja statusu VAT używa dokładnych
  wartości API (bez ryzyka, że „Nieczynny” stanie się „Czynny”), a lokalny
  filtr KSeF pomija wpis bez zgodnego identyfikatora nadającego.
  Relacja uprawnień wymaga poświadczeń KSeF — bez nich karta pokazuje sam
  status VAT. Sprawdzenie relacji KSeF nieprzetestowane na żywo (polityka
  „tylko odczyt na żywo”; endpoint jest odczytowy, więc docelowo dopuszczalny
  do weryfikacji na produkcji).

### Kalendarz i prognoza podatkowa (13.07.2026)

- [x] ⭐ B3. Kokpit pokazuje terminarz ZUS/DRA, zaliczki PIT, miesięcznego
  JPK_V7 i płatności VAT z przesuwaniem 20./25. dnia na pierwszy dzień roboczy.
  Osobne ustawienia obsługują miesięczny lub kwartalny VAT i PIT/ryczałt,
  przy czym JPK zawsze pozostaje miesięczny. Prognoza bieżącego okresu liczy
  saldo VAT z reguł JPK oraz PIT: skalę 12%/32% lub liniowy 19% narastająco
  z KPiR albo ryczałt według stawek wpisów. UI jawnie opisuje ograniczenia
  szacunku (bez składek, ulg, innych dochodów, proporcji VAT i wpłat).
  Podatnik zwolniony może wyłączyć terminy JPK/VAT; VAT RR jest pomijany
  w podatku naliczonym z ostrzeżeniem (do realizacji B5). Ustawienia wchodzą
  do kopii zapasowej v10; logika ma osobny suite testów.

### Ewidencja przychodów — ryczałt (13.07.2026)

- [x] B2. Ewidencja przychodów dla ryczałtu od przychodów ewidencjonowanych
  według 17-kolumnowego wzoru obowiązującego od 2026 r. (Dz.U. 2025 poz. 1294),
  z podziałem na stawki 17/15/14/12,5/12/10/8,5/5,5/3%. W Ustawieniach → Firma
  wybór formy opodatkowania (KPiR albo ryczałt — wzajemnie wykluczające, w pasku
  bocznym widoczna tylko wybrana ewidencja) oraz domyślna stawka ryczałtu.
  Ewidencja obejmuje wyłącznie sprzedaż, przelicza kwoty walutowe na PLN,
  pokazuje przychód i szacowany ryczałt (bez odliczeń składek) łącznie i per
  stawka; użytkownik może na wpisie nadpisać stawkę, datę wpisu, datę uzyskania
  przychodu, kwotę i uwagi lub wykluczyć dokument. Eksport CSV zawiera pełne
  kolumny 1–17 (numer KSeF, identyfikator kontrahenta) oraz wiersz sumy per
  stawka. Faktury ukryte poza ewidencją, klasyfikacja ryczałtu w kopii
  zapasowej (v9).

### KPiR — Księga Przychodów i Rozchodów (13.07.2026)

- [x] B1. Ewidencja KPiR dla zasad ogólnych i podatku liniowego według
  19-kolumnowego wzoru obowiązującego od 2026 r. Faktury są automatycznie
  ujmowane jako sprzedaż albo pozostałe wydatki; użytkownik może zmienić
  datę zdarzenia, opis, kolumnę 9/10/12–15, kwotę podatkową, koszt B+R,
  uwagi lub wykluczyć dokument. Widok pokazuje podsumowanie okresu, ostrzega
  o brakującym kursie waluty i eksportuje pełny układ księgi do CSV.
  Faktury ukryte pozostają poza ewidencją, a lokalna klasyfikacja KPiR
  wchodzi do kopii zapasowej.

### Logo i branding wydruków PDF (13.07.2026)

- [x] E5. Kosmetyka brandingu: na stronach kontynuacji wielostronicowej
  faktury (tryb z brandingiem) notka „ciąg dalszy" i numer strony zawisały
  pośrodku między dwoma rozpychanymi `Spacer`-ami. Zastąpione jednym wspólnym
  `Spacer`-em nad dolnym blokiem („ciąg dalszy" + numer strony + stopka marki),
  który dosuwa cały blok do dołu strony. Numer strony jest teraz przy stopce
  także na stronie ostatniej. Tryb klasyczny (content-sized) bez zmian.
  Ujawnione w review PR #20.
- [x] ⭐ E1. Konfigurowalny branding własnych faktur PDF: import i
  automatyczne skalowanie logo, osobny kolor główny i akcent, własna stopka
  na każdej stronie oraz pasek marki w nagłówku. Ustawienia są dostępne
  w zakładce Firma i wchodzą do kopii zapasowej. Reguła po NIP chroni
  pobrane faktury kosztowe przed oznaczeniem logo użytkownika; VAT RR jest
  rozpoznawany po firmie występującej jako nabywca/wystawca dokumentu.

### JPK_V7K — kwartalny wariant ewidencji VAT (12.07.2026)

- [x] B0. Generator JPK_V7K obok JPK_V7M — wariant kwartalny (mały
  podatnik / VAT kwartalny): ewidencja składana co miesiąc, część deklaracyjna
  raz na kwartał, wyłącznie w pliku ostatniego miesiąca kwartału (marzec,
  czerwiec, wrzesień, grudzień). Wtedy ewidencja obejmuje tylko ten miesiąc,
  a deklaracja VAT-7K — sumy CAŁEGO kwartału, z elementem `Kwartal` (1–4).
  Generator dobiera wydanie XSD do okresu: aktualne V7M(3)/V7K(3) od lutego
  2026 r. (w tym obowiązkowy `NrKSeF` albo OFF/BFK/DI) oraz historyczne wydanie
  (2) dla okresów od 2022 r. do stycznia 2026 r.
  Enum `JPKV7Variant` w `JPKV7Generator` (miesięce 1–2 kwartału → sama
  ewidencja z ostrzeżeniem; okno eksportu dobiera wariant, etykiety i nazwę
  pliku). Dokumenty (kwartalny z deklaracją oraz miesiąc-w-trakcie)
  zweryfikowane oficjalnymi XSD (xmllint). Nowy suite testów JPK_V7K.

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
