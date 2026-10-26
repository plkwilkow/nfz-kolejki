# Panel kolejek NFZ: zdrowie psychiczne i uzależnienia

Automatyczny zapis publicznych danych o kolejkach z API NFZ „Terminy leczenia” dla świadczeń
psychiatrycznych, psychologicznych i leczenia uzależnień w całej Polsce. API pokazuje tylko
**stan bieżący**, więc historię trzeba zbudować samemu, zapisując kolejne „zdjęcia” (snapshoty).
Ten projekt robi to automatycznie na GitHubie, bez Twojego komputera.

**Źródło danych:** Narodowy Fundusz Zdrowia, API Terminy Leczenia, https://api.nfz.gov.pl/
(wersja 1.4: https://apinfz.nfz.gov.pl/app-itl-api-pcus/). Regulamin API wymaga podawania źródła
i zakazuje przeciążania usługi, dlatego skrypt robi 1 s przerwy między zapytaniami.

Opis stanu systemu NFZ: październik 2026.

---

## Co jest w danych i jak często się zmienia

| Pole w API | Znaczenie | Jak często się zmienia |
|---|---|---|
| `statistics.provider-data.awaiting` | liczba oczekujących, stan na ostatni dzień miesiąca | raz w miesiącu |
| `statistics.provider-data.removed` | liczba osób skreślonych z listy w miesiącu | raz w miesiącu |
| `statistics.provider-data.average-period` | średni czas oczekiwania w dniach, raportowany przez placówkę | raz w miesiącu |
| `statistics.provider-data.update` | miesiąc, którego dotyczą statystyki (np. `2026-09`) | raz w miesiącu |
| `dates.pcus` | **PCUŚ**: prognozowany czas oczekiwania, liczony przez NFZ (np. `12 dni`, `2 mies. 1 tydz.`) | poza Centralną e-Rejestracją: raz w miesiącu |
| `dates.date-situation-as-at` | data ostatniej informacji od placówki, różna dla kolejek | codziennie w ok. 6% kolejek, zwykle bez zmiany innych pól |
| `queue-in-cer` | czy kolejka jest w Centralnej e-Rejestracji (CeR) | przy zmianach systemowych |
| adres, telefon, dostępność | dane placówki | rzadko |
| `id` (w snapshotach `queue_id`) | identyfikator rekordu | **codziennie od nowa**, nie nadaje się do łączenia dni (zob. „Klucz kolejki”) |

Pomiar z 5 snapshotów (21–25.10.2026): z dnia na dzień statystyki miesięczne zmieniały się
w 2–18 kolejkach (spóźnione raporty za wrzesień), PCUŚ w 1–5, zawsze razem z nowymi
statystykami danej kolejki. Duża zmiana przyjdzie z raportami za październik, po 10 listopada.

Od 1 lipca 2026 r. NFZ nie publikuje już „pierwszego wolnego terminu”; zastąpił go PCUŚ.
Dla świadczeń spoza CeR PCUŚ jest liczony raz w miesiącu ze średnich czasów oczekiwania
z ostatnich 12 miesięcy. W próbce kolejek psychiatrycznych z województwa podlaskiego
(październik 2026) wszystkie miały `queue-in-cer = N`. Większość danych zmienia się więc
mniej więcej raz w miesiącu.

**Dlaczego mimo to codziennie?** Przez pierwsze ~6 tygodni codzienne snapshoty pokażą
empirycznie, w które dni NFZ faktycznie podmienia dane (źródła podają to różnie, a data stanu
różni się między kolejkami). Potem wystarczą dwa razy w tygodniu. Rzadziej niż raz w tygodniu
nie warto: API nadpisuje stare wartości, więc miesiąc, którego nie złapiesz, przepada na zawsze.

---

## Krok 1. Test na własnym komputerze (ok. 5 minut)

1. Rozpakuj ZIP i kliknij dwukrotnie **`nfz-kolejki.Rproj`**. Otworzy się RStudio z folderem
   projektu jako folderem roboczym.
2. W konsoli zainstaluj pakiety (raz):
   ```r
   install.packages(c("httr2", "jsonlite"))
   ```
3. Uruchom szybki test, czyli dwa zapytania do API o świadczenia psychiatryczne w województwie podlaskim:
   ```r
   source("R/test_nfz.R")
   ```
   Po kilkunastu sekundach zobaczysz podsumowanie i pierwsze wiersze tabeli: świadczenie,
   miejscowość, liczbę oczekujących, średni czas oczekiwania, PCUŚ. Pliki testu trafiają do
   folderu `data_test/`, który nie jest wysyłany na GitHuba.
4. Pełne pobranie u siebie jest nieobowiązkowe, trwa ok. 15–20 minut:
   ```r
   source("R/collect_nfz.R")
   ```

Jeśli test zakończy się błędem, skopiuj komunikat z konsoli.

---

## Krok 2. Repozytorium na GitHubie (ok. 10 minut)

1. Zaloguj się na https://github.com albo załóż konto.
2. Kliknij **+** w prawym górnym rogu, potem **New repository**.
   - Nazwa: `nfz-kolejki`.
   - Widoczność: **Public**. Dane są publiczne, publiczne repozytorium ma nielimitowane minuty
     GitHub Actions, a przy okazji jest częścią portfolio.
   - **Nie** zaznaczaj „Add a README file”, bo masz własny.
   - **Create repository**.
3. Na stronie pustego repozytorium kliknij link **uploading an existing file**. Przeciągnij do okna
   **zawartość** rozpakowanego folderu `nfz-kolejki`, czyli pliki i foldery `R` oraz `.github`, a nie
   sam folder. Na dole kliknij **Commit changes**.
4. Sprawdź, czy w repozytorium jest plik `.github/workflows/collect.yml`. Jeśli go nie ma:
   **Add file → Create new file**, w polu nazwy wpisz `.github/workflows/collect.yml` (ukośniki
   utworzą foldery), wklej zawartość pliku z ZIP-a i kliknij **Commit changes**. Ten krok jest
   potrzebny najczęściej na macOS, który ukrywa foldery zaczynające się od kropki. W Finderze
   pokażesz je skrótem Cmd+Shift+.

---

## Krok 3. Pierwsze uruchomienie na GitHubie

1. Wejdź w zakładkę **Actions**. Jeśli GitHub zapyta o włączenie workflowów, potwierdź.
2. Po lewej wybierz **Zbieranie danych NFZ**, po prawej kliknij **Run workflow**, a potem zielony **Run workflow**.
3. Po ok. 15–20 minutach (w tym ok. 2 minuty instalacji R) przebieg powinien mieć zielony znaczek.
   W zakładce **Code** pojawi się commit „Dane NFZ …” i folder `data/`. Po kliknięciu w przebieg
   zobaczysz podsumowanie: status, liczbę rekordów i pokrycie zapytań.
4. Jeśli przebieg ma czerwony znaczek, kliknij go, otwórz krok, który się nie udał, i skopiuj komunikat.
   Typowe przyczyny są w sekcji „Gdy coś nie działa”.

---

## Krok 4. Codzienna praca systemu

- Przebieg jest zaplanowany codziennie na 07:17 czasu letniego (06:17 zimowego). Harmonogram
  GitHuba nie jest punktualny: w październiku 2026 przebiegi ruszały 4–5 godzin po czasie.
  Przy danych zmieniających się raz w miesiącu to bez znaczenia.
- Gdy przebieg się nie uda albo pobierze wyraźnie mniej danych niż powinien, GitHub wyśle Ci
  e-mail. Pobrane dane zostają zapisane także wtedy.
- **Po ok. 6 tygodniach** uruchom u siebie `R/build_panel.R` (opis niżej). Pokaże, w które dni
  zmieniały się dane. Jeśli tylko raz w miesiącu, zmień w pliku `.github/workflows/collect.yml` linię
  `cron` na `"17 5 * * 1,4"` (poniedziałki i czwartki) i wpisz tę zmianę do `ZMIANY.md`.
- W publicznym repozytorium GitHub wyłącza harmonogram po 60 dniach bez aktywności. Codzienne
  commity z danymi są aktywnością. Gdyby harmonogram jednak się wyłączył, włączysz go z powrotem
  w zakładce Actions (Enable workflow).
- Jeden przebieg zajmuje ok. 2 MB.

---

## Gdzie są dane i jak je czytać

```
data/
  raw/2026/10/
    snapshot_2026-10-16_0717.csv.gz   tabela, 1 wiersz = kolejka × tryb (na tym pracujesz)
    raw_2026-10-16_0717.jsonl.gz      surowe odpowiedzi API (dowód źródłowy)
    queries_2026-10-16_0717.csv       kompletność każdego zapytania
  logs/runs.csv                       1 wiersz = 1 uruchomienie: status, pokrycie, czas
  panel/                              tabele do analiz (tworzy R/build_panel.R)
```

Najważniejsze kolumny snapshotu: `case` (1 = stabilny, 2 = pilny), `benefit`,
`provider`, `provider_code`, `place`, `locality`, `teryt_place`, `queue_in_cer`,
`stat_awaiting`, `stat_removed`, `stat_average_period`, `stat_update`, `dates_pcus`,
`dates_situation_as_at`, `matched_keywords`. Kolumny `*_extra_json` zbierają pola, których
skrypt jeszcze nie zna. Jeśli NFZ coś doda, nic nie zginie, a w `runs.csv` pojawi się nazwa
nowego pola.

**Klucz kolejki.** `queue_id` zmienia się codziennie (w snapshotach z 21–25.10.2026 żaden się
nie powtórzył), więc do łączenia dni służy klucz złożony z pięciu kolumn: `provider_code`,
`id_resort_part_vii`, `id_resort_part_viii`, `benefit`, `case`. W tych snapshotach był unikalny
każdego dnia. Skrypty w `R/dane_lokalne.R` dodają go jako kolumnę `klucz`. Klucz zmienia się,
gdy placówka dostanie nowy kod resortowy komórki (raz w tych 5 dniach: poradnia we Wrocławiu),
wtedy ta sama kolejka wygląda jak zamknięta i nowa.

```r
x <- read.csv("data/raw/2026/10/snapshot_2026-10-16_0717.csv.gz",
              colClasses = "character", encoding = "UTF-8")
```

`colClasses = "character"` jest ważne, bo kody TERYT i NFZ mają zera wiodące (np. `0264011`).

**Kompletność:** każde zapytanie porównuje liczbę pobranych rekordów z liczbą, którą podaje API
(`meta.count`). Gdy się nie zgadza, zapytanie jest powtarzane do 3 razy. Wynik trafia do
`queries_*.csv`, a status całego przebiegu (`complete`, `incomplete`, `failed`) do `runs.csv`.
Rzetelność bazy zależy właśnie od tego, a nie od częstotliwości pobierania.

---

## Analiza na własnym komputerze

```r
source("R/analiza_kolejek.R")
```

Skrypt sam pobiera z GitHuba snapshoty, których nie masz jeszcze w folderze `data/`
(funkcja `pobierz_z_github()` z `R/dane_lokalne.R`), a potem:

1. podsumowuje najnowszy snapshot: aktywność kolejek, rozkład czasu oczekiwania, województwa,
   świadczenia;
2. pokazuje, ile kolejek zmieniło każde pole między kolejnymi snapshotami;
3. oznacza kolejki do sprawdzenia czterema flagami: czas skrajnie dłuższy niż w kolejkach
   z tym samym świadczeniem i trybem, skrajnie dużo oczekujących, niespójność liczby
   oczekujących, skreśleń i średniego czasu (prawo Little'a), tryb pilny tak długi jak stabilny.

Tabele trafiają do folderu `wyniki/` i otwierają się poprawnie w Excelu. Pojedynczą kolejkę
obejrzysz funkcją `sprawdz()`, np. `sprawdz("WEJHEROWO", "ALKOHOL")`.

---

## Panel do analiz

```r
source("R/build_panel.R")
```

Tworzy dwie tabele w `data/panel/`:

- **`stat_monthly.csv.gz`**: jeden wiersz to kolejka × tryb × miesiąc statystyk. Wartości pochodzą
  z najnowszego snapshotu, w którym występuje dany miesiąc. `liczba_wersji > 1` oznacza, że
  wartości za ten miesiąc zmieniały się między snapshotami. Są też kolumny `wojewodztwo`
  i `teryt_powiat` do agregacji.
- **`pcus_changes.csv.gz`**: historia PCUŚ, czyli jeden wiersz na okres, w którym PCUŚ, jego
  dostępność i flaga CeR się nie zmieniały (data stanu ma swój zakres w kolumnach `data_stanu_od`
  i `data_stanu_do`). PCUŚ powyżej ok. miesiąca jest podawany z dokładnością do tygodni, więc
  `pcus_dni_przybl` to przybliżenie, a `pcus_zaokraglony = TRUE` oznacza wartość zaokrągloną
  (w praktyce są to dane przedziałowe).

Kolejki są łączone po kluczu kolejki, nie po `queue_id`. Skrypt wypisuje też, w które dni
pojawiły się nowe statystyki miesięczne i zmienił się PCUŚ, czyli empiryczną odpowiedź na
pytanie, jak często NFZ aktualizuje dane.

---

## Zmiana zakresu

Zakres ustawiasz w `config.R`. API szuka świadczeń po fragmencie nazwy, np. `"PSYCH"` obejmuje
68 świadczeń. Pełne nazwy dla danego fragmentu sprawdzisz tak:

```r
source("config.R"); source("R/nfz_api.R")
nfz_benefits(cfg, "PSYCH")
```

Kody województw w API to numeracja NFZ (01 dolnośląskie … 10 podlaskie … 16 zachodniopomorskie),
a **nie** TERYT. W danych kolumna `teryt_place` ma już kod TERYT (np. podlaskie = 20).

Każdą zmianę zakresu zapisz w `ZMIANY.md` z datą i powodem.

---

## Ograniczenia danych

1. **PCUŚ to prognoza, nie pomiar.** Poza CeR jest liczony raz w miesiącu jako średnia ważona
   z przeszłych czasów oczekiwania, więc reaguje z opóźnieniem i wygładza nagłe zmiany. Do analizy
   kolejek lepsze są statystyki miesięczne. PCUŚ jest natomiast ciekawy jako przedmiot badania:
   jak trafne są prognozy, które NFZ pokazuje pacjentom?
2. **Przerwa w szeregu w lipcu 2026 r.** Wtedy zniknął „pierwszy wolny termin” i weszła nowa wersja
   API. Twoje dane zaczynają się już w nowym systemie.
3. **Centralna e-Rejestracja.** Świadczenia przenoszone etapami do CeR mogą zmienić sposób liczenia
   PCUŚ albo zniknąć z tego API. Kolumna `queue_in_cer` i liczby rekordów w `runs.csv` pokażą
   taki moment.
4. **Statystyki raportują same placówki.** NFZ sprawdza je automatycznie, ale to nie jest audyt.
5. **Brak historii wstecz.** Danych sprzed pierwszego uruchomienia nie da się odtworzyć z API.
6. **Kolejka to nie placówka.** Kolejka = świadczenie × miejsce udzielania × tryb, a jeden
   świadczeniodawca może mieć wiele kolejek.

---

## Gdy coś nie działa

- **„Brakuje pakietu …”**: uruchom `install.packages(c("httr2", "jsonlite"))`.
- **„Nie widzę pliku config.R”**: otwórz projekt przez `nfz-kolejki.Rproj`, nie sam skrypt.
- **Błąd przy `git push` (403, „Permission denied”) w kroku „Zapisz dane w repozytorium”**:
  Settings → Actions → General → Workflow permissions → **Read and write permissions** → Save,
  potem uruchom przebieg ponownie.
- **„brak połączenia” albo „HTTP 403” w kroku „Pobierz dane z API NFZ”, podczas gdy test u Ciebie
  działa**: serwer NFZ może nie przyjmować zapytań z serwerów GitHuba, które stoją poza Polską.
  Wtedy użyj planu B poniżej.
- **Status `incomplete`**: pojedyncze niekompletne zapytania się zdarzają, np. gdy NFZ podmienia
  dane w trakcie przebiegu. Przy pokryciu ≥ 99% przebieg jest zielony, a ostrzeżenia są
  w podsumowaniu.

### Plan B: uruchamianie na własnym komputerze (Windows)

```r
install.packages("taskscheduleR")
taskscheduleR::taskscheduler_create(
  taskname  = "nfz_kolejki",
  rscript   = normalizePath("R/collect_nfz.R"),
  schedule  = "DAILY",
  starttime = "08:15"
)
```

Komputer musi być wtedy włączony. Dane trafią do `data/` w folderze projektu. Od czasu do czasu
wgraj je do repozytorium przez Add file → Upload files.
