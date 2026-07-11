---
description: Zbuduj bundle Ksefiarz.app i uruchom go ponownie u użytkownika
---

Wydaj nową wersję aplikacji użytkownikowi:

1. Uruchom `swift test` — jeśli jakikolwiek test nie przechodzi, ZATRZYMAJ się
   i napraw przed wydaniem.
2. Zbuduj bundle: `./Scripts/build-app.sh`.
3. Zrestartuj aplikację: `pkill -x Ksefiarz; sleep 1; open dist/Ksefiarz.app`.
4. Zweryfikuj, że proces działa (`pgrep -x Ksefiarz`) — jeśli nie, sprawdź
   log i zdiagnozuj awarię (częsta przyczyna: migracja SwiftData — nowe pola
   modeli muszą mieć wartości domyślne).
5. Podsumuj użytkownikowi, co zawiera nowa wersja.
