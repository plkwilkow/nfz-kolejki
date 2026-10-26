# Funkcje do pracy z danymi na Twoim komputerze (GitHub Actions ich nie używa).
#
#   pobierz_z_github()   dociąga z GitHuba snapshoty, których jeszcze nie masz w folderze data/
#   wczytaj_snapshoty()  wczytuje wszystkie snapshoty w jedną tabelę i dodaje stały klucz kolejki
#   pcus_na_dni()        zamienia tekst PCUŚ ("12 dni", "2 mies. 1 tydz.") na przybliżoną liczbę dni
#
# WAŻNE: queue_id z API NFZ zmienia się codziennie (w snapshotach z 21–25.10.2026 żaden
# identyfikator się nie powtórzył). Dni łączymy więc po kolumnie `klucz`, czyli:
# kod świadczeniodawcy + kody resortowe komórki (cz. VII i VIII) + świadczenie + tryb.

KLUCZ_KOLUMNY <- c("provider_code", "id_resort_part_vii", "id_resort_part_viii", "benefit", "case")

# Kody TERYT województw (pierwsze 2 cyfry kolumny teryt_place).
WOJEWODZTWA <- c(
  "02" = "dolnośląskie", "04" = "kujawsko-pomorskie", "06" = "lubelskie", "08" = "lubuskie",
  "10" = "łódzkie", "12" = "małopolskie", "14" = "mazowieckie", "16" = "opolskie",
  "18" = "podkarpackie", "20" = "podlaskie", "22" = "pomorskie", "24" = "śląskie",
  "26" = "świętokrzyskie", "28" = "warmińsko-mazurskie", "30" = "wielkopolskie",
  "32" = "zachodniopomorskie"
)

# Pobiera z publicznego repozytorium data/logs/runs.csv oraz te snapshoty (i pliki queries_),
# których nie ma jeszcze lokalnie. Pliki trafiają do tych samych ścieżek co na GitHubie.
pobierz_z_github <- function(repo = "plkwilkow/nfz-kolejki", galaz = "main",
                             data_dir = "data", surowe = FALSE) {
  baza <- sprintf("https://raw.githubusercontent.com/%s/%s/", repo, galaz)

  pobierz <- function(sciezka, cel) {
    wynik <- tryCatch(
      utils::download.file(paste0(baza, sciezka), cel, mode = "wb", quiet = TRUE),
      error = function(e) e, warning = function(w) w
    )
    ok <- is.numeric(wynik) && length(wynik) == 1 && wynik == 0
    if (!ok && file.exists(cel)) file.remove(cel)
    ok
  }

  runs_plik <- file.path(data_dir, "logs", "runs.csv")
  dir.create(dirname(runs_plik), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(fileext = ".csv")
  if (pobierz("data/logs/runs.csv", tmp)) {
    file.copy(tmp, runs_plik, overwrite = TRUE)
  } else if (file.exists(runs_plik)) {
    message("Nie udało się pobrać aktualnego runs.csv z GitHuba, używam kopii z komputera.")
  } else {
    stop("Nie udało się pobrać runs.csv z GitHuba. Sprawdź połączenie z internetem.")
  }

  runs <- utils::read.csv(runs_plik, colClasses = "character", na.strings = "", encoding = "UTF-8")
  sciezki <- unique(runs$snapshot_file[!is.na(runs$snapshot_file)])
  sciezki <- c(sciezki, sub("snapshot_", "queries_", sub("\\.csv\\.gz$", ".csv", sciezki)))
  if (surowe) sciezki <- c(sciezki, unique(runs$raw_file[!is.na(runs$raw_file)]))
  lokalne <- sub("^data/", paste0(data_dir, "/"), sciezki)

  brak <- which(!file.exists(lokalne))
  if (length(brak) == 0) {
    message("Masz już wszystkie pliki z GitHuba.")
    return(invisible(runs))
  }
  message("Pobieram z GitHuba ", length(brak), " brakujących plików...")
  nieudane <- character()
  for (i in brak) {
    dir.create(dirname(lokalne[i]), recursive = TRUE, showWarnings = FALSE)
    if (!pobierz(sciezki[i], lokalne[i])) nieudane <- c(nieudane, sciezki[i])
  }
  if (length(nieudane) > 0) {
    message("Nie udało się pobrać: ", paste(nieudane, collapse = ", "))
  }
  invisible(runs)
}

# Wczytuje wszystkie snapshoty z data/raw/ w jedną tabelę (wszystkie kolumny jako tekst)
# i dodaje kolumny pomocnicze: snapshot, klucz, liczby, aktywność kolejki, województwo.
wczytaj_snapshoty <- function(data_dir = "data") {
  pliki <- sort(list.files(file.path(data_dir, "raw"), pattern = "^snapshot_.*\\.csv\\.gz$",
                           recursive = TRUE, full.names = TRUE))
  if (length(pliki) == 0) {
    stop("Brak snapshotów w folderze ", file.path(data_dir, "raw"),
         ". Najpierw uruchom pobierz_z_github().")
  }
  lista <- lapply(pliki, function(f) {
    d <- utils::read.csv(f, colClasses = "character", na.strings = "", encoding = "UTF-8",
                         check.names = FALSE)
    d$snapshot_file <- basename(f)
    d
  })
  wspolne <- Reduce(intersect, lapply(lista, names))  # gdyby API kiedyś dodało nowe pola
  x <- do.call(rbind, lapply(lista, function(d) d[wspolne]))

  x$snapshot <- sub("^snapshot_(.*)\\.csv\\.gz$", "\\1", x$snapshot_file)
  x$klucz <- do.call(paste, c(unname(as.list(x[KLUCZ_KOLUMNY])), sep = "|"))

  # Ta sama kolejka dwa razy w jednym snapshocie zdarzyłaby się, gdyby NFZ odświeżył dane
  # w trakcie pobierania. Zostawiamy wtedy pierwsze wystąpienie.
  dup <- duplicated(x[c("snapshot", "klucz")])
  if (any(dup)) {
    message("Uwaga: ", sum(dup), " powtórzonych kolejek w obrębie snapshotów, ",
            "zostawiam pierwsze wystąpienie.")
    x <- x[!dup, ]
  }

  num <- function(v) suppressWarnings(as.numeric(v))
  zero <- function(v) ifelse(is.na(v), 0, v)
  x$oczekujacy  <- num(x$stat_awaiting)
  x$skresleni   <- num(x$stat_removed)
  x$sredni_czas <- num(x$stat_average_period)
  x$ma_statystyki <- !is.na(x$stat_update)
  # Aktywna = ktoś czeka, ktoś został skreślony albo średni czas jest większy od zera.
  x$aktywna <- x$ma_statystyki &
    (zero(x$oczekujacy) > 0 | zero(x$skresleni) > 0 | zero(x$sredni_czas) > 0)
  x$teryt_woj <- substr(x$teryt_place, 1, 2)
  x$wojewodztwo <- unname(WOJEWODZTWA[x$teryt_woj])

  x <- x[order(x$snapshot, x$klucz), ]
  rownames(x) <- NULL
  x
}

# PCUŚ przychodzi jako tekst. Powyżej ok. miesiąca NFZ podaje go z dokładnością do tygodni,
# więc liczba dni jest przybliżeniem (1 mies. = 30,44 dnia), a pcus_zaokraglony = TRUE oznacza
# wartość zaokrągloną. "-" (PCUŚ nie dotyczy) i puste pola dają NA.
pcus_na_dni <- function(s) {
  s <- ifelse(is.na(s), "", s)
  wyciagnij <- function(wzor) {
    m <- regmatches(s, regexec(paste0("([0-9]+)[[:space:]]*", wzor), s))
    vapply(m, function(v) if (length(v) >= 2) as.numeric(v[2]) else NA_real_, numeric(1))
  }
  mies <- wyciagnij("mies")
  tyg  <- wyciagnij("ty[gd]")
  dni  <- wyciagnij("(dni|dzie)")
  trafienie <- !is.na(mies) | !is.na(tyg) | !is.na(dni)
  z <- function(v) ifelse(is.na(v), 0, v)
  dni_przybl <- z(mies) * 30.44 + z(tyg) * 7 + z(dni)
  dni_przybl[!trafienie] <- NA
  data.frame(pcus_dni_przybl = round(dni_przybl, 1),
             pcus_zaokraglony = ifelse(trafienie, !is.na(mies) | !is.na(tyg), NA))
}

# Zapis skompresowanego CSV (do danych).
zapisz_csv_gz <- function(df, sciezka) {
  con <- gzfile(sciezka, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  utils::write.csv(df, con, row.names = FALSE, na = "")
}

# Zapis CSV, który poprawnie otwiera się w polskim Excelu (średniki, przecinek dziesiętny,
# znacznik UTF-8 na początku pliku, żeby polskie litery się nie rozjechały).
# W R wczytasz go przez read.csv2(sciezka, fileEncoding = "UTF-8-BOM").
zapisz_dla_excela <- function(df, sciezka) {
  con <- file(sciezka, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  cat("﻿", file = con)
  utils::write.csv2(df, con, row.names = FALSE, na = "")
}
