---
name: "source-command-live-check"
description: "Weryfikacja integracji z KSeF na żywo (wyłącznie odczyt)"
---

# source-command-live-check

Use this skill when the user asks to run the migrated source command `live-check`.

## Command Template

Uruchom testy integracyjne na żywym API KSeF z poświadczeniami użytkownika.

⚠️ Zasady bezpieczeństwa:
- Operacje WYŁĄCZNIE do odczytu (uwierzytelnienie, metadane, pobieranie XML/UPO).
- NIGDY nie wysyłaj faktur — środowisko użytkownika to PRODUKCJA.
- Nie wypisuj tokenu w odpowiedziach.

Polecenie:

```bash
KSEF_LIVE_NIP="$(defaults read pl.itkrak.ksefiarz ksef.nip)" \
KSEF_LIVE_TOKEN="$(security find-generic-password -s pl.itkrak.ksefiarz -a ksef.token -w)" \
KSEF_LIVE_ENV="$(defaults read pl.itkrak.ksefiarz ksef.environment)" \
swift test --filter LiveKSeFIntegrationTests
```

Token leży w pęku kluczy (nie w UserDefaults). Odczyt przez `security` może
wywołać systemowe okno zgody — użytkownik musi kliknąć „Zezwól"; uprzedź go.

Pamiętaj o limitach API (8 żądań/s, 16 pobrań dokumentów/min) — nie uruchamiaj
testów na żywo wielokrotnie pod rząd; usługa ponawia 429 z backoffem, ale
limit minutowy łatwo wyczerpać serią przebiegów.

Zinterpretuj wyniki dla użytkownika: liczba faktur, kompletność danych
(adresy, pozycje, płatności), ewentualne błędy API z diagnozą.
