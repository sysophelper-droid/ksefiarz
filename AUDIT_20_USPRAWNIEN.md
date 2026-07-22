# Audyt jakości — 20 usprawnień (22.07.2026)

Dokument jest rejestrem problemów znalezionych w trakcie przeglądu kodu.
Każdy punkt ma osobny test regresyjny w zestawie
`QualityAuditTests`; status „naprawiono” jest nadawany dopiero po przejściu
pełnego zestawu testów.

## Wyszukiwanie i raporty

1. **Wyszukiwanie faktur bez polskich znaków** — lista faktur porównywała
   tekst przez zwykłe `lowercased()`, więc zapytanie „zolw” nie znajdowało
   kontrahenta „Żółw”. Rozwiązanie: wspólna normalizacja bez diakrytyków.
   Status: **naprawiono**, test `[01]`.
2. **NIP wpisany z separatorami** — wyszukiwanie porównywało tekst dosłownie,
   dlatego `526-025-02-74` nie pasował do `5260250274`. Rozwiązanie: osobne
   porównanie cyfr identyfikatora. Status: **naprawiono**, test `[02]`.
3. **Zapytanie wielowyrazowe przez kilka pól** — fraza łącząca nazwę
   kontrahenta i numer dokumentu nie mogła pasować, bo cały tekst musiał
   wystąpić w jednym polu. Rozwiązanie: wszystkie tokeny muszą wystąpić
   w łącznym indeksie faktury. Status: **naprawiono**, test `[03]`.
4. **Ukryte dokumenty w raportach** — `ReportsEngine` polegał na filtrowaniu
   przez widok, więc bezpośrednie wywołanie mogło ujawnić ukrytą fakturę
   w top kontrahentach, produktach lub kosztach. Rozwiązanie: wykluczenie
   egzekwowane w silniku (także w podpowiedziach kategorii). Status:
   **naprawiono**, test `[04]`.
5. **Rozbite grupy kontrahentów bez NIP** — różnice wielkości liter,
   diakrytyków i wielokrotnych białych znaków tworzyły osobne grupy dla tej
   samej nazwy. Rozwiązanie: kanoniczny klucz tekstowy z osobną przestrzenią
   `name:`/`nip:`, która zapobiega też kolizji liczbowej nazwy z NIP-em.
   Status: **naprawiono**, test `[05]`.
6. **Rozbite grupy produktów** — identyczny produkt z inną wielkością liter
   lub odstępami był raportowany wielokrotnie. Rozwiązanie: kanoniczny klucz
   nazwy pozycji. Status: **naprawiono**, test `[06]`.
7. **Rozbite kategorie kosztów** — ręcznie wpisane warianty tej samej
   kategorii (`Sprzęt IT`, ` sprzęt  it`) nie były sumowane. Rozwiązanie:
   grupowanie po kluczu kanonicznym przy zachowaniu pierwszej etykiety.
   Status: **naprawiono**, test `[07]`.
8. **Ujemny limit raportu** — przekazanie `limit < 0` do `prefix` kończyło się
   przerwaniem procesu. Rozwiązanie: ujemny limit jest traktowany jak zero.
   Status: **naprawiono**, test `[08]`.
9. **Ujemny limit wyszukiwarki globalnej** — analogicznie `prefix(limit)`
   mógł przerwać aplikację. Rozwiązanie: bezpieczne ograniczenie do zera.
   Status: **naprawiono**, test `[09]`.
10. **Ujemny limit retencji raportów miesięcznych** — `suffix(keep)` wymaga
    nieujemnej wartości i mógł przerwać proces. Rozwiązanie: ujemna retencja
    oznacza pustą historię. Status: **naprawiono**, test `[10]`.

## Daty, dane finansowe i odporność wejścia

11. **Faktura zaległa już rano w dniu terminu** — `Invoice.isOverdue` używało
    porównania godzinowego, mimo że termin jest datą kalendarzową. Rozwiązanie:
    porównanie kalendarzowe, zaległość dopiero od następnego dnia. Status:
    **naprawiono**, test `[11]`.
12. **Dzisiejszy termin znikał z „najbliższych płatności”** — data z
    DatePickera (00:00) była wcześniejsza niż bieżąca godzina i wypadała
    z widżetu. Rozwiązanie: porównywanie początków dni; horyzont zero obejmuje
    dziś. Status: **naprawiono**, test `[12]`.
13. **Ukryte dokumenty w analityce Kokpitu** — `DashboardAnalytics` również
    ufał filtrowaniu przez wywołującego. Rozwiązanie: ukryte faktury są
    wykluczane we wszystkich agregatach silnika. Status: **naprawiono**,
    test `[13]`.
14. **Niespójny kod PLN** — wartości `pln` lub ` PLN ` były uznawane za
    walutę obcą, co mogło pomnożyć kwoty przez kurs i zgłosić fałszywy brak
    kursu. Rozwiązanie: `CurrencyCode` normalizuje kod na granicy modelu,
    w agregatach, walidatorach, generatorach i zapisie ręcznym. Obejmuje to
    nowe importy, odtwarzane kopie oraz niekanoniczne rekordy istniejącej bazy.
    Status: **naprawiono**, test `[14]`.
15. **Pola ręcznego zakupu z samą nową linią** — walidacja usuwała tylko
    spacje, więc numer lub sprzedawca `"\n"` przechodził jako niepusty.
    Rozwiązanie: `whitespacesAndNewlines`. Status: **naprawiono**, test `[15]`.
16. **Brak normalizacji zapisu ręcznego zakupu** — końcowe nowe linie
    zostawały w numerze, nazwie, NIP, kategorii i kodzie waluty, a biały
    rachunek mógł zostać zapisany jako obecny. Rozwiązanie: kanonizacja przy
    `makeInvoice` i `apply`, pusty rachunek jako `nil`. Status:
    **naprawiono**, test `[16]`.
17. **Proforma rozliczona pustym numerem** — sama nowa linia w
    `convertedInvoiceNumber` dawała `isConverted == true`. Rozwiązanie: pełne
    przycinanie białych znaków przy sprawdzaniu i zapisie. Status:
    **naprawiono**, test `[17]`.
18. **Konfiguracja form płatności z odstępami** — wpisy
    `gotowka, przelew` zachowywały spację i drugi kod nie działał. Rozwiązanie:
    przycinanie elementów podczas dekodowania. Status: **naprawiono**,
    test `[18]`.
19. **Niebezpieczny znak CR w CSV** — pole zawierające `\r` nie było
    ujmowane w cudzysłowy i mogło rozbić rekord w programie arkuszowym.
    Rozwiązanie: CR jest cytowany tak samo jak LF. Status: **naprawiono**,
    test `[19]`.
20. **Nieprawidłowa wpłata w historii** — `PaymentLedger` przyjmował zero,
    kwoty ujemne, `NaN` i nieskończoność, mimo kontraktu dodatniej kwoty.
    Rozwiązanie: taki wpis zwraca `nil` bez mutowania faktury. Status:
    **naprawiono**, test `[20]`.

## Weryfikacja końcowa

- Przebieg pełny 1: **zaliczony** — `swift test`, 1109 testów / 157 zestawów,
  0 błędów (22.07.2026).
- Przebieg pełny 2: **zaliczony** — `swift test`, 1109 testów / 157 zestawów,
  0 błędów (22.07.2026).
- Bundle release i uruchomienie: **zaliczone** — `./Scripts/build-app.sh`,
  podpis ad-hoc, restart i pozytywny `pgrep -x Ksefiarz` (22.07.2026).
