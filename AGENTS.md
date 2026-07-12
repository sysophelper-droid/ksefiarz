# Ksefiarz — przewodnik dla Codex

Natywna aplikacja macOS (SwiftUI + SwiftData, Swift Package) do zarządzania
fakturami z pełną integracją z **KSeF 2.0** (produkcyjne API, prawdziwa
kryptografia). Język projektu: **polski** — UI, komentarze, komunikaty błędów,
nazwy testów. Kod w trybie języka Swift 5 (`.swiftLanguageMode(.v5)`).

Ten plik zawiera **zasady pracy i decyzje projektowe**. Wiedza referencyjna
(mapa modułów, fakty o API, zasady schemy FA(3), lokalizacje danych) jest
w **`ARCHITECTURE.md`**; zadania i backlog w **`todo.md`**.

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
produkcję i nie modyfikuj tam uprawnień**; takie operacje testuj na mockach
albo na środowisku `test`.

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

## Zasada architektury

**Logika domenowa w `Logic/` i `Services/` jako czyste funkcje/typy z testami**;
widoki (`Views/`) tylko spinają logikę z SwiftUI. Klucze ustawień wyłącznie
przez `AppSettingsKeys` (@AppStorage). Pełna mapa modułów → `ARCHITECTURE.md`.

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

## Decyzje projektowe (krytyczne)

- **Dedykowany plik bazy** `Ksefiarz/Ksefiarz.store`, NIGDY domyślny
  `default.store` — plik współdzielony między procesami; obcy proces
  (`com.apple.icloudmailagent`) skasował w nim kiedyś wszystkie faktury
  (12.06.2026). Szczegóły lokalizacji danych → `ARCHITECTURE.md`.
- **Ikona w pasku menu przez AppKit `NSStatusItem`**, NIE scena SwiftUI
  `MenuBarExtra` — na macOS 26 współistnienie `MenuBarExtra`
  z `NavigationSplitView` wpada w nieskończoną pętlę renderowania (100% CPU,
  zawieszenie). `NSStatusItem` nie dotyka grafu scen SwiftUI. Kontroler
  startuje z `InvoiceApp.init()` ORAZ `MainContentView.onAppear` (idempotentnie,
  bo `applicationDidFinishLaunching` przy `@NSApplicationDelegateAdaptor` bywa
  pomijany, a `onAppear` na `NavigationSplitView` nie jest niezawodny).
- **Sekrety w pęku kluczy, nie w UserDefaults ani kopiach** — token KSeF
  (usługa `pl.itkrak.ksefiarz`, konto `ksef.token`, dostęp przez
  `TokenStore`/`KeychainSecretStorage`); NIE loguj go i nie commituj. Bundle
  ad-hoc zmienia sygnaturę przy każdym wydaniu — pierwszy dostęp do tokenu po
  aktualizacji może wywołać systemowe okno „Zezwól”.
- **Automatyczna synchronizacja tylko na produkcji** — bezpiecznik przed
  zaśmieceniem bazy fakturami z testowego KSeF; na test/demo synchronizuj
  ręcznie z listy.

## Proces pracy

1. Każda zmiana logiki = testy (Swift Testing, polskie nazwy `@Test("...")`).
   Po zmianach: `swift test` — komplet na zielono.
2. Fakty o API/schemie weryfikuj u źródła (OpenAPI, XSD z CIRFMF/ksef-api,
   docs CIRFMF/ksef-docs) — nie zgaduj pól. Szczegóły w `ARCHITECTURE.md`.
3. Po zmianach widocznych dla użytkownika: `./Scripts/build-app.sh`,
   `pkill -x Ksefiarz; open dist/Ksefiarz.app` (użytkownik pracuje na bundlu).
4. Aktualizuj `README.md` (funkcje, lokalizacje danych) przy zmianach
   funkcjonalnych, a `todo.md` przy domykaniu/dodawaniu zadań. Nową wiedzę
   o module/API dopisuj do `ARCHITECTURE.md`, a nie do tego pliku.
