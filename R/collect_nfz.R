# Zbiera jeden snapshot kolejek z API NFZ "Terminy leczenia" i zapisuje go w data/.
#
# Uruchamianie:
#   - w RStudio (po otwarciu nfz-kolejki.Rproj): source("R/collect_nfz.R")
#   - w terminalu, z folderu projektu:           Rscript R/collect_nfz.R
#   - szybki test (dwa zapytania do API):        source("R/test_nfz.R")
#
# Co powstaje (RRRR/MM = rok i miesiąc, znacznik = data_godzina startu):
#   data/raw/RRRR/MM/snapshot_<znacznik>.csv.gz  tabela: 1 wiersz = kolejka × tryb
#   data/raw/RRRR/MM/raw_<znacznik>.jsonl.gz     surowe odpowiedzi API (dowód źródłowy)
#   data/raw/RRRR/MM/queries_<znacznik>.csv      kompletność każdego zapytania
#   data/logs/runs.csv                           1 wiersz = 1 uruchomienie

# Przy uruchomieniu przez Rscript ustaw folder roboczy na folder projektu.
local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  f <- gsub("~+~", " ", f, fixed = TRUE)  # Rscript koduje spacje w ścieżce jako ~+~
  if (length(f) == 1 && file.exists(f)) setwd(dirname(dirname(normalizePath(f))))
})
if (!file.exists("config.R")) {
  stop("Nie widzę pliku config.R. Otwórz projekt nfz-kolejki.Rproj ",
       "albo ustaw folder roboczy na folder projektu.")
}
for (pkg in c("httr2", "jsonlite")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Brakuje pakietu ", pkg, '. Zainstaluj: install.packages(c("httr2", "jsonlite"))')
  }
}
if (utils::packageVersion("httr2") < "1.0.5") {
  stop("Masz za starą wersję pakietu httr2 (", utils::packageVersion("httr2"),
       "). Zaktualizuj: install.packages(\"httr2\")")
}

source("config.R", encoding = "UTF-8")
source("R/nfz_api.R", encoding = "UTF-8")

test_mode <- identical(Sys.getenv("NFZ_TEST"), "1")
max_pages <- Inf
if (test_mode) {
  cfg$keywords  <- "PSYCH"
  cfg$cases     <- 1
  cfg$provinces <- "10"         # podlaskie
  cfg$data_dir  <- "data_test"  # wyniki testu nie mieszają się z właściwymi danymi
  max_pages     <- 2
  message("TRYB TESTOWY: tylko PSYCH, przypadek stabilny, woj. podlaskie, maks. 2 strony.")
}

started         <- Sys.time()
stamp           <- format(started, "%Y-%m-%d_%H%M", tz = cfg$timezone)
snapshot_at_utc <- format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
snapshot_date   <- format(started, "%Y-%m-%d", tz = cfg$timezone)

queries <- expand.grid(keyword = cfg$keywords, case = cfg$cases, province = cfg$provinces,
                       stringsAsFactors = FALSE)
message(sprintf("Start %s: %d zapytań (fragment nazwy × tryb × województwo), API %s.",
                format(started, "%Y-%m-%d %H:%M", tz = cfg$timezone), nrow(queries),
                cfg$api_version))

all_recs  <- new.env(hash = TRUE)  # unikalne rekordy; klucz = id kolejki + tryb
all_kw    <- new.env(hash = TRUE)  # które fragmenty nazw zwróciły dany rekord
raw_lines <- character()
qlog      <- vector("list", nrow(queries))
aborted   <- FALSE
abort_msg <- NA_character_

# ---- Sprawdzenie połączenia -----------------------------------------------------
pre <- nfz_get(cfg, "benefits", list(name = cfg$keywords[1], page = 1, limit = 1,
                                     format = "json"))
if (!pre$ok) {
  aborted   <- TRUE
  abort_msg <- paste("Brak dostępu do API NFZ:", pre$error)
  message(abort_msg)
}

# ---- Pobieranie ----------------------------------------------------------------
consecutive_down <- 0L
for (i in seq_len(nrow(queries))) {
  if (aborted) break
  q <- queries[i, ]
  res <- fetch_query(cfg, q$keyword, q$case, q$province, max_pages = max_pages)

  for (rec in res$records) {
    key <- paste(rec[["id"]], as_text(rec[["attributes"]][["case"]]), sep = "_")
    if (!exists(key, envir = all_recs, inherits = FALSE)) assign(key, rec, envir = all_recs)
    prev <- if (exists(key, envir = all_kw, inherits = FALSE)) get(key, envir = all_kw) else character()
    assign(key, unique(c(prev, res$keyword)), envir = all_kw)
  }
  raw_lines <- c(raw_lines, res$raw)

  qlog[[i]] <- data.frame(
    keyword = res$keyword, case = res$case, province = res$province,
    expected = res$expected, received_unique = res$n_unique, complete = res$complete,
    requests = res$requests, failed_requests = res$failed, passes = res$passes,
    error = res$error, stringsAsFactors = FALSE
  )
  message(sprintf("[%3d/%d] %-12s tryb %s woj. %s: %4d z %s%s",
                  i, nrow(queries), res$keyword, res$case, res$province, res$n_unique,
                  if (is.na(res$expected)) "?" else res$expected,
                  if (res$complete) "" else "   <- NIEKOMPLETNE"))

  # Trzy kolejne zapytania bez odpowiedzi = API niedostępne; nie ma sensu czekać godzinami.
  consecutive_down <- if (is.na(res$expected)) consecutive_down + 1L else 0L
  if (consecutive_down >= 3) {
    aborted   <- TRUE
    abort_msg <- paste("API nie odpowiada w 3 kolejnych zapytaniach. Ostatni błąd:", res$error)
    message(abort_msg)
  }
}

qlog_empty <- data.frame(keyword = character(), case = numeric(), province = character(),
                         expected = integer(), received_unique = integer(),
                         complete = logical(), requests = integer(),
                         failed_requests = integer(), passes = integer(),
                         error = character(), stringsAsFactors = FALSE)
qlog <- do.call(rbind, c(list(qlog_empty), qlog))  # puste elementy (niewykonane zapytania) znikają

# ---- Zapis ---------------------------------------------------------------------
out_dir <- file.path(cfg$data_dir, "raw",
                     format(started, "%Y", tz = cfg$timezone),
                     format(started, "%m", tz = cfg$timezone))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

keys      <- sort(ls(all_recs))
n_records <- length(keys)
new_keys  <- character()
snap_file <- NA_character_
raw_file  <- NA_character_

if (n_records > 0) {
  recs <- mget(keys, envir = all_recs)
  tab  <- as.data.frame(do.call(rbind, lapply(recs, flatten_queue)), stringsAsFactors = FALSE)
  tab  <- data.frame(
    snapshot_at_utc  = snapshot_at_utc,
    snapshot_date    = snapshot_date,
    matched_keywords = vapply(keys, function(k) paste(get(k, envir = all_kw), collapse = "|"),
                              character(1), USE.NAMES = FALSE),
    tab,
    check.names = FALSE, stringsAsFactors = FALSE, row.names = NULL
  )
  snap_file <- file.path(out_dir, paste0("snapshot_", stamp, ".csv.gz"))
  write_csv_gz(tab, snap_file)

  new_keys <- sort(unique(as.character(unlist(lapply(recs, function(r) {
    setdiff(names(r[["attributes"]]), KNOWN_ATTR_KEYS)
  })))))
}

if (length(raw_lines) > 0) {
  raw_file <- file.path(out_dir, paste0("raw_", stamp, ".jsonl.gz"))
  con <- gzfile(raw_file, open = "w", encoding = "UTF-8")
  writeLines(raw_lines, con)
  close(con)
}

write.csv(qlog, file.path(out_dir, paste0("queries_", stamp, ".csv")),
          row.names = FALSE, na = "", fileEncoding = "UTF-8")

# ---- Ocena kompletności i dziennik uruchomień --------------------------------------
sum_expected     <- sum(qlog$expected, na.rm = TRUE)
coverage         <- if (sum_expected > 0) {
  sum(pmin(qlog$received_unique, qlog$expected), na.rm = TRUE) / sum_expected
} else NA_real_
n_failed_queries <- sum(is.na(qlog$expected))  # zapytania, w których nie udało się pobrać 1. strony
n_incomplete     <- sum(!qlog$complete)

status <- if (aborted || n_records == 0) {
  "failed"
} else if (test_mode) {
  "test"
} else if (n_failed_queries > 0 || n_incomplete > 0) {
  "incomplete"
} else {
  "complete"
}

finished     <- Sys.time()
duration_min <- round(as.numeric(difftime(finished, started, units = "mins")), 1)

log_dir <- file.path(cfg$data_dir, "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
append_csv(data.frame(
  started_at_utc       = snapshot_at_utc,
  finished_at_utc      = format(finished, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  duration_min         = duration_min,
  api_base             = cfg$base_url,
  api_version          = cfg$api_version,
  n_queries_planned    = nrow(queries),
  n_queries            = nrow(qlog),
  n_incomplete_queries = n_incomplete,
  n_failed_queries     = n_failed_queries,
  n_requests           = sum(qlog$requests) + 1L,  # +1 = sprawdzenie połączenia
  n_failed_requests    = sum(qlog$failed_requests) + as.integer(!pre$ok),
  sum_expected         = sum_expected,
  coverage             = round(coverage, 4),
  n_records            = n_records,
  snapshot_file        = snap_file,
  raw_file             = raw_file,
  status               = status,
  aborted              = aborted,
  error                = abort_msg,
  new_attribute_keys   = paste(new_keys, collapse = ";"),
  stringsAsFactors     = FALSE
), file.path(log_dir, "runs.csv"))

coverage_txt <- if (is.na(coverage)) "brak danych" else sprintf("%.1f%%", 100 * coverage)
message(sprintf(paste0("\nGotowe w %.1f min. Status: %s. Rekordów (kolejka × tryb): %d. ",
                       "Pokrycie zapytań: %s. Niekompletne zapytania: %d z %d."),
                duration_min, status, n_records, coverage_txt, n_incomplete, nrow(qlog)))
if (!is.na(snap_file)) message("Zapisano: ", snap_file)
if (length(new_keys) > 0) {
  message("UWAGA: w API pojawiły się nowe pola: ", paste(new_keys, collapse = ", "),
          " (są zapisane w kolumnie extra_attributes_json).")
}

if (test_mode && n_records > 0) {
  message("\nPierwsze wiersze (statystyki miesięczne i PCUŚ):")
  print(head(tab[, c("benefit", "locality", "stat_awaiting", "stat_average_period",
                     "stat_update", "dates_pcus", "dates_situation_as_at")], 10),
        row.names = FALSE)
}

# ---- Komunikaty dla GitHub Actions --------------------------------------------------
summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) {
  cat(c("## Zbieranie danych NFZ", "",
        sprintf("- Status: **%s**", status),
        if (aborted) sprintf("- Przerwano: %s", abort_msg),
        sprintf("- Rekordy (kolejka × tryb): %d", n_records),
        sprintf("- Pokrycie zapytań: %s", coverage_txt),
        sprintf("- Niekompletne zapytania: %d z %d", n_incomplete, nrow(qlog)),
        sprintf("- Czas: %.1f min", duration_min),
        sprintf("- Plik: `%s`", snap_file), ""),
      file = summary_file, sep = "\n", append = TRUE)
}
if (nzchar(Sys.getenv("GITHUB_ACTIONS"))) {
  if (aborted) cat(sprintf("::error::%s\n", substr(abort_msg, 1, 500)))
  bad <- qlog[!qlog$complete, ]
  for (j in seq_len(min(nrow(bad), 10))) {
    cat(sprintf("::warning::Niekompletne zapytanie: %s, tryb %s, woj. %s (%d z %s). %s\n",
                bad$keyword[j], bad$case[j], bad$province[j], bad$received_unique[j],
                if (is.na(bad$expected[j])) "?" else bad$expected[j],
                if (is.na(bad$error[j])) "" else substr(bad$error[j], 1, 200)))
  }
}

# Przebieg nieudany albo wyraźnie niepełny kończy się kodem błędu: GitHub oznaczy go
# na czerwono i wyśle e-mail. Dane, które udało się pobrać, i tak zostają zapisane.
if (!interactive() && !test_mode &&
    (status == "failed" || n_failed_queries > 0 || isTRUE(coverage < 0.99))) {
  message("Kończę z kodem błędu, żeby GitHub oznaczył przebieg jako nieudany.")
  quit(save = "no", status = 1)
}
