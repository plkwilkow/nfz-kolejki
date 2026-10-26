# Dziennik zmian zakresu i decyzji

Każda zmiana zakresu (słowa kluczowe, tryby, województwa), harmonogramu albo kodu,
która może wpłynąć na dane, z datą i powodem. Dzięki temu w artykule opiszesz
dokładnie, jak powstał panel.

| Data | Zmiana | Powód |
|---|---|---|
| 2026-10-16 | Start. API NFZ „Terminy leczenia” 1.4. Fragmenty nazw: PSYCH, UZALE, ALKOHOLOWYCH, ŚRODOWISK, NERWIC, AUTYZ; tryby 1 i 2; wszystkie województwa. Codziennie o 05:17 UTC. | Codzienne snapshoty przez pierwsze tygodnie, żeby sprawdzić, kiedy NFZ faktycznie aktualizuje dane. |
| 2026-10-21 | Pierwszy udany przebieg na GitHubie: snapshot 2026-10-21_1729, 8536 rekordów, pokrycie 100%. | — |
| 2026-10-26 | Kolejki łączone po kluczu `provider_code` + `id_resort_part_vii` + `id_resort_part_viii` + `benefit` + `case` zamiast `queue_id`. Nowe skrypty `R/dane_lokalne.R` i `R/analiza_kolejek.R`, poprawiony `R/build_panel.R`. Samo zbieranie danych bez zmian. | W 5 snapshotach (21–25.10) żaden `queue_id` się nie powtórzył: NFZ nadaje identyfikatory codziennie od nowa. Klucz złożony był unikalny w każdym snapshocie. |
