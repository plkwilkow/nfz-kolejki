# Buduje tabele do analiz ze wszystkich zebranych snapshotów. Uruchamiasz u siebie,
# kiedy chcesz popracować na danych: source("R/build_panel.R")
#
# Wynik:
#   data/panel/stat_monthly.csv.gz  1 wiersz = kolejka × tryb × miesiąc statystyk
#                                   (liczba oczekujących, skreślonych, średni czas oczekiwania)
#   data/panel/pcus_changes.csv.gz  1 wiersz = okres, w którym PCUŚ i jego dostępność się nie
#                                   zmieniały (zamiast powtarzać tę samą wartość co dzień)
#
# Kolejki łączymy po kolumnie `klucz` (kod świadczeniodawcy + kody resortowe komórki + świadczenie
# + tryb), bo queue_id z API NFZ zmienia się codziennie. Opis w R/dane_lokalne.R.

if (!file.exists("config.R")) stop("Otwórz projekt nfz-kolejki.Rproj (brak config.R w folderze roboczym).")
source("R/dane_lokalne.R", encoding = "UTF-8")

pobierz_z_github()
x <- wczytaj_snapshoty()
x <- x[order(x$snapshot_at_utc), ]

runs_file <- file.path("data", "logs", "runs.csv")
x$status_snapshotu <- NA_character_
if (file.exists(runs_file)) {
  runs <- read.csv(runs_file, colClasses = "character", na.strings = "", encoding = "UTF-8")
  x$status_snapshotu <- runs$status[match(x$snapshot_file, basename(runs$snapshot_file))]
}

# ---- 1. Statystyki miesięczne ----------------------------------------------------
# Dla każdej kolejki i miesiąca bierzemy wartości z NAJNOWSZEGO snapshotu
# (jeśli placówka poprawiła dane w trakcie miesiąca, obowiązuje ostatnia wersja).
# liczba_wersji > 1 oznacza, że wartości za ten miesiąc zmieniały się między snapshotami.
s <- x[x$ma_statystyki, ]
klucz_m <- paste(s$klucz, s$stat_update, sep = "|")
sygnatura <- paste(s$stat_awaiting, s$stat_removed, s$stat_average_period, sep = "|")
ostatni <- !duplicated(klucz_m, fromLast = TRUE)
k <- klucz_m[ostatni]

m <- s[ostatni, c("klucz", "case", "stat_update", "provider_code", "provider", "benefit", "place",
                  "locality", "teryt_place", "wojewodztwo", "queue_in_cer",
                  "oczekujacy", "skresleni", "sredni_czas", "status_snapshotu")]
names(m)[names(m) == "status_snapshotu"] <- "status_ostatniego_snapshotu"
m$pierwszy_raz_utc  <- unname(tapply(s$snapshot_at_utc, klucz_m, min)[k])
m$ostatni_raz_utc   <- unname(tapply(s$snapshot_at_utc, klucz_m, max)[k])
m$liczba_snapshotow <- as.integer(unname(table(klucz_m)[k]))
m$liczba_wersji     <- as.integer(unname(tapply(sygnatura, klucz_m,
                                                function(v) length(unique(v)))[k]))
m$teryt_powiat <- substr(m$teryt_place, 1, 4)  # TERYT: województwo + powiat
m <- m[order(m$stat_update, m$teryt_place, m$klucz), ]

# ---- 2. Historia PCUŚ ------------------------------------------------------------
# Nowy okres zaczyna się, gdy zmienia się PCUŚ, jego dostępność (dates_applicable) albo flaga
# Centralnej e-Rejestracji. Data stanu (dates_situation_as_at) zmienia się prawie codziennie,
# więc nie tworzy nowego okresu, tylko zapisujemy jej zakres.
y <- x[order(x$klucz, x$snapshot_at_utc), ]
n <- nrow(y)
sygnatura2 <- paste(y$dates_pcus, y$dates_applicable, y$queue_in_cer, sep = "|")
nowy_okres <- c(TRUE, y$klucz[-1] != y$klucz[-n] | sygnatura2[-1] != sygnatura2[-n])
okres <- cumsum(nowy_okres)

zakres <- function(v, f) if (all(is.na(v))) NA_character_ else f(v, na.rm = TRUE)
p <- y[nowy_okres, c("klucz", "case", "provider_code", "benefit", "locality", "teryt_place",
                     "wojewodztwo", "queue_in_cer", "dates_applicable", "dates_pcus",
                     "snapshot_at_utc")]
names(p)[names(p) == "snapshot_at_utc"] <- "od_utc"
p$do_utc        <- unname(tapply(y$snapshot_at_utc, okres, max))
p$data_stanu_od <- unname(tapply(y$dates_situation_as_at, okres, zakres, f = min))
p$data_stanu_do <- unname(tapply(y$dates_situation_as_at, okres, zakres, f = max))
p <- cbind(p, pcus_na_dni(p$dates_pcus))

# ---- Zapis i krótkie podsumowanie --------------------------------------------------
panel_dir <- file.path("data", "panel")
dir.create(panel_dir, recursive = TRUE, showWarnings = FALSE)
zapisz_csv_gz(m, file.path(panel_dir, "stat_monthly.csv.gz"))
zapisz_csv_gz(p, file.path(panel_dir, "pcus_changes.csv.gz"))

message(sprintf("Snapshoty: %d (od %s do %s). Kolejki × tryby: %d. Miesiące statystyk: %s.",
                length(unique(x$snapshot)), min(x$snapshot), max(x$snapshot),
                length(unique(x$klucz)),
                paste(sort(unique(stats::na.omit(x$stat_update))), collapse = ", ")))
message("Statusy snapshotów:")
print(table(x$status_snapshotu[!duplicated(x$snapshot)], useNA = "ifany"))

# Kiedy NFZ faktycznie aktualizuje dane? Pierwszy snapshot pokazuje stan wyjściowy,
# więc liczą się dopiero zmiany zauważone później.
pierwszy <- min(x$snapshot_at_utc)
pozniej_m <- m$pierwszy_raz_utc > pierwszy
if (any(pozniej_m)) {
  message("Dzień, w którym pojawiły się nowe statystyki miesięczne (liczba kolejek):")
  print(table(m$stat_update[pozniej_m], substr(m$pierwszy_raz_utc[pozniej_m], 1, 10)))
}
pozniej_p <- p$od_utc > pierwszy
if (any(pozniej_p)) {
  message("Dzień, w którym zmienił się PCUŚ, jego dostępność albo flaga CeR (liczba kolejek):")
  print(table(substr(p$od_utc[pozniej_p], 1, 10)))
}
message("Zapisano: ", file.path(panel_dir, "stat_monthly.csv.gz"), " i ",
        file.path(panel_dir, "pcus_changes.csv.gz"))
