# Buduje tabele do analiz ze wszystkich zebranych snapshotów. Uruchamiasz u siebie,
# kiedy chcesz popracować na danych: source("R/build_panel.R")
#
# Wynik:
#   data/panel/stat_monthly.csv.gz  1 wiersz = kolejka × tryb × miesiąc statystyk
#                                   (liczba oczekujących, skreślonych, średni czas oczekiwania)
#   data/panel/pcus_changes.csv.gz  1 wiersz = okres, w którym PCUŚ, data stanu i flaga CeR
#                                   się nie zmieniały (zamiast powtarzać tę samą wartość co dzień)

if (!file.exists("config.R")) stop("Otwórz projekt nfz-kolejki.Rproj (brak config.R w folderze roboczym).")
source("config.R", encoding = "UTF-8")
source("R/nfz_api.R", encoding = "UTF-8")  # potrzebne tylko write_csv_gz()

files <- sort(list.files(file.path(cfg$data_dir, "raw"), pattern = "^snapshot_.*\\.csv\\.gz$",
                         recursive = TRUE, full.names = TRUE))
if (length(files) == 0) stop("Brak snapshotów w folderze ", file.path(cfg$data_dir, "raw"))

needed <- c("snapshot_at_utc", "snapshot_date", "queue_id", "case", "provider_code", "provider",
            "benefit", "place", "locality", "teryt_place", "queue_in_cer",
            "stat_awaiting", "stat_removed", "stat_average_period", "stat_update",
            "dates_pcus", "dates_situation_as_at")

# Wczytuje tylko potrzebne kolumny, wszystkie jako tekst (kody TERYT i NFZ mają zera wiodące).
read_snapshot <- function(f) {
  header  <- names(read.csv(gzfile(f), nrows = 1, check.names = FALSE))
  classes <- ifelse(header %in% needed, "character", "NULL")
  d <- read.csv(gzfile(f), colClasses = classes, na.strings = "", encoding = "UTF-8",
                check.names = FALSE)
  d[setdiff(needed, names(d))] <- NA_character_
  d <- d[needed]
  d$snapshot_file <- basename(f)
  d
}

message("Wczytuję ", length(files), " snapshotów...")
x <- do.call(rbind, lapply(files, read_snapshot))
x <- x[order(x$snapshot_at_utc), ]

runs_file <- file.path(cfg$data_dir, "logs", "runs.csv")
x$snapshot_status <- NA_character_
if (file.exists(runs_file)) {
  runs <- read.csv(runs_file, colClasses = "character", na.strings = "", encoding = "UTF-8")
  x$snapshot_status <- runs$status[match(x$snapshot_file, basename(runs$snapshot_file))]
}

num <- function(v) suppressWarnings(as.numeric(v))

# ---- 1. Statystyki miesięczne ----------------------------------------------------
# Dla każdej kolejki, trybu i miesiąca bierzemy wartości z NAJNOWSZEGO snapshotu
# (jeśli NFZ poprawił dane w trakcie miesiąca, obowiązuje ostatnia wersja).
# n_versions > 1 oznacza, że wartości za ten miesiąc zmieniały się między snapshotami.
key <- paste(x$queue_id, x$case, x$stat_update, sep = "|")
sig <- paste(x$stat_awaiting, x$stat_removed, x$stat_average_period, sep = "|")
last_row <- !duplicated(key, fromLast = TRUE)
k <- key[last_row]

m <- x[last_row, c("queue_id", "case", "stat_update", "provider_code", "provider", "benefit",
                   "place", "locality", "teryt_place", "queue_in_cer",
                   "stat_awaiting", "stat_removed", "stat_average_period", "snapshot_status")]
names(m)[names(m) == "snapshot_status"] <- "status_of_latest_snapshot"
m$first_seen_utc <- unname(tapply(x$snapshot_at_utc, key, min)[k])
m$last_seen_utc  <- unname(tapply(x$snapshot_at_utc, key, max)[k])
m$n_snapshots    <- as.integer(unname(table(key)[k]))
m$n_versions     <- as.integer(unname(tapply(sig, key, function(v) length(unique(v)))[k]))
m$stat_awaiting       <- num(m$stat_awaiting)
m$stat_removed        <- num(m$stat_removed)
m$stat_average_period <- num(m$stat_average_period)
m$teryt_woj    <- substr(m$teryt_place, 1, 2)  # TERYT: 2 cyfry województwa
m$teryt_powiat <- substr(m$teryt_place, 1, 4)  # TERYT: województwo + powiat
m <- m[order(m$stat_update, m$teryt_place, m$provider_code, m$queue_id, m$case), ]

# ---- 2. Historia PCUŚ ------------------------------------------------------------
# PCUŚ przychodzi jako tekst, np. "12 dni", "2 mies. 1 tydz.". Powyżej ok. miesiąca
# NFZ podaje go z dokładnością do tygodni, więc dni są przybliżeniem (1 mies. = 30,44 dnia),
# a pcus_coarse = TRUE oznacza wartość zaokrągloną (dane przedziałowe).
pcus_parse <- function(s) {
  s[is.na(s)] <- ""
  grab <- function(pattern) {
    hits <- regmatches(s, regexec(paste0("([0-9]+)[[:space:]]*", pattern), s))
    vapply(hits, function(v) if (length(v) >= 2) as.numeric(v[2]) else NA_real_, numeric(1))
  }
  mies <- grab("mies")
  tyg  <- grab("ty[gd]")
  dni  <- grab("(dni|dzie)")
  any_hit <- !is.na(mies) | !is.na(tyg) | !is.na(dni)
  zero <- function(v) ifelse(is.na(v), 0, v)
  days <- zero(mies) * 30.44 + zero(tyg) * 7 + zero(dni)
  days[!any_hit] <- NA
  data.frame(pcus_days_approx = round(days, 1),
             pcus_coarse = ifelse(any_hit, !is.na(mies) | !is.na(tyg), NA))
}

y <- x[order(x$queue_id, x$case, x$snapshot_at_utc), ]
n <- nrow(y)
grp  <- paste(y$queue_id, y$case, sep = "|")
sig2 <- paste(y$dates_pcus, y$dates_situation_as_at, y$queue_in_cer, sep = "|")
new_run <- c(TRUE, grp[-1] != grp[-n] | sig2[-1] != sig2[-n])
run_id  <- cumsum(new_run)

p <- y[new_run, c("queue_id", "case", "provider_code", "benefit", "locality", "teryt_place",
                  "queue_in_cer", "dates_pcus", "dates_situation_as_at", "snapshot_at_utc")]
names(p)[names(p) == "snapshot_at_utc"] <- "first_seen_utc"
p$last_seen_utc <- unname(tapply(y$snapshot_at_utc, run_id, max))
p <- cbind(p, pcus_parse(p$dates_pcus))

# ---- Zapis i krótkie podsumowanie --------------------------------------------------
panel_dir <- file.path(cfg$data_dir, "panel")
dir.create(panel_dir, recursive = TRUE, showWarnings = FALSE)
write_csv_gz(m, file.path(panel_dir, "stat_monthly.csv.gz"))
write_csv_gz(p, file.path(panel_dir, "pcus_changes.csv.gz"))

message(sprintf("Snapshoty: %d (od %s do %s). Kolejki × tryby: %d. Miesiące statystyk: %s.",
                length(files), min(x$snapshot_date), max(x$snapshot_date),
                length(unique(paste(x$queue_id, x$case))),
                paste(sort(unique(na.omit(x$stat_update))), collapse = ", ")))
message("Statusy snapshotów:")
print(table(x$snapshot_status[!duplicated(x$snapshot_file)], useNA = "ifany"))

# Kiedy NFZ faktycznie aktualizuje dane? Pierwszy snapshot pokazuje stan wyjściowy,
# więc liczą się dopiero zmiany zauważone później.
first_snapshot <- min(x$snapshot_at_utc)
later_months <- m$first_seen_utc > first_snapshot
if (any(later_months)) {
  message("Dzień, w którym pojawiły się nowe statystyki miesięczne (liczba kolejek):")
  print(table(m$stat_update[later_months], substr(m$first_seen_utc[later_months], 1, 10)))
}
later_pcus <- p$first_seen_utc > first_snapshot
if (any(later_pcus)) {
  message("Dzień, w którym zmienił się PCUŚ, data stanu albo flaga CeR (liczba kolejek):")
  print(table(substr(p$first_seen_utc[later_pcus], 1, 10)))
}
message("Zapisano: ", file.path(panel_dir, "stat_monthly.csv.gz"), " i ",
        file.path(panel_dir, "pcus_changes.csv.gz"))
