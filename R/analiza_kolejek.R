# Podsumowanie i kontrola jakości danych z panelu kolejek NFZ.
# Uruchom w RStudio po otwarciu nfz-kolejki.Rproj:  source("R/analiza_kolejek.R")
#
# Co robi skrypt:
#   1. dociąga z GitHuba snapshoty, których jeszcze nie masz na komputerze,
#   2. podsumowuje najnowszy snapshot,
#   3. pokazuje, jak często zmieniają się dane między kolejnymi snapshotami,
#   4. oznacza kolejki, których wartości warto sprawdzić (możliwe błędy w danych).
# Tabele trafiają do folderu wyniki/ (otwierają się poprawnie w Excelu), a wykres do
# wyniki/czas_oczekiwania_wg_swiadczen.png.

if (!file.exists("config.R")) {
  stop("Nie widzę pliku config.R. Otwórz projekt nfz-kolejki.Rproj.")
}
source("R/dane_lokalne.R", encoding = "UTF-8")

pobierz_z_github()
x <- wczytaj_snapshoty()
dir.create("wyniki", showWarnings = FALSE)

kw <- function(v, p) unname(stats::quantile(v, p, na.rm = TRUE))
snapshoty <- sort(unique(x$snapshot))
najnowszy <- snapshoty[length(snapshoty)]
ost <- x[x$snapshot == najnowszy, ]
akt <- ost[ost$aktywna, ]

# ---- 1. Podsumowanie najnowszego snapshotu ------------------------------------------
cat("\n==== 1. PODSUMOWANIE NAJNOWSZEGO SNAPSHOTU (", najnowszy, ") ====\n", sep = "")
cat(sprintf("Snapshotów: %d (od %s do %s)\n", length(snapshoty), snapshoty[1], najnowszy))
cat(sprintf("Wierszy (kolejka × tryb): %d; tryb stabilny: %d, pilny: %d\n",
            nrow(ost), sum(ost$case == "1"), sum(ost$case == "2")))

cat("\nMiesiąc, którego dotyczą statystyki (stat_update):\n")
print(table(ost$stat_update, useNA = "ifany"))

kategoria <- ifelse(!ost$ma_statystyki, "brak statystyk",
                    ifelse(ost$aktywna, "aktywna", "same zera"))
cat("\nAktywność kolejek (aktywna = ktoś czeka, ktoś został skreślony albo średni czas > 0):\n")
print(table(kategoria))

cat(sprintf(paste0("\nŚredni czas oczekiwania w aktywnych kolejkach (dni): mediana %.0f, ",
                   "Q3 %.0f, P90 %.0f, P99 %.0f, maksimum %.0f\n"),
            kw(akt$sredni_czas, 0.5), kw(akt$sredni_czas, 0.75), kw(akt$sredni_czas, 0.9),
            kw(akt$sredni_czas, 0.99), max(akt$sredni_czas, na.rm = TRUE)))
cat(sprintf("Wpisy na listach oczekujących: łącznie %s, mediana na kolejkę %.0f, P90 %.0f, maksimum %.0f\n",
            format(sum(akt$oczekujacy, na.rm = TRUE), big.mark = " "), kw(akt$oczekujacy, 0.5),
            kw(akt$oczekujacy, 0.9), max(akt$oczekujacy, na.rm = TRUE)))

podsumuj <- function(d, grupa) {
  do.call(rbind, lapply(split(d, d[[grupa]]), function(g) data.frame(
    grupa = g[[grupa]][1],
    kolejek = nrow(g),
    oczekujacych = sum(g$oczekujacy, na.rm = TRUE),
    mediana_czasu_dni = stats::median(g$sredni_czas, na.rm = TRUE),
    p90_czasu_dni = round(kw(g$sredni_czas, 0.9)),
    check.names = FALSE
  )))
}
stab <- akt[akt$case == "1", ]

woj <- podsumuj(stab, "wojewodztwo")
names(woj)[1] <- "wojewodztwo"
woj <- woj[order(-woj$mediana_czasu_dni), ]
cat("\nWojewództwa (tryb stabilny, aktywne kolejki), od najdłuższej mediany czasu oczekiwania:\n")
print(woj, row.names = FALSE)
zapisz_dla_excela(woj, "wyniki/wojewodztwa.csv")

sw <- podsumuj(stab, "benefit")
names(sw)[1] <- "swiadczenie"
sw <- sw[order(-sw$oczekujacych), ]
cat("\nŚwiadczenia z największą liczbą oczekujących (tryb stabilny, aktywne kolejki):\n")
print(utils::head(sw, 12), row.names = FALSE)
zapisz_dla_excela(sw, "wyniki/swiadczenia.csv")

# ---- 2. Jak często zmieniają się dane -----------------------------------------------
cat("\n==== 2. JAK CZĘSTO ZMIENIAJĄ SIĘ DANE ====\n")
if (length(snapshoty) < 2) {
  cat("Do porównania potrzebne są co najmniej 2 snapshoty.\n")
} else {
  rozne <- function(u, v) (is.na(u) != is.na(v)) | (!is.na(u) & !is.na(v) & u != v)
  pola <- list(
    "oczekujący" = "stat_awaiting",
    "skreśleni" = "stat_removed",
    "średni czas" = "stat_average_period",
    "miesiąc statystyk" = "stat_update",
    "PCUŚ" = "dates_pcus",
    "data stanu" = "dates_situation_as_at",
    "nazwa/adres" = c("provider", "place", "address", "locality"),
    "telefon" = "phone"
  )
  zmiany <- do.call(rbind, lapply(seq_along(snapshoty)[-1], function(i) {
    a <- x[x$snapshot == snapshoty[i - 1], ]
    b <- x[x$snapshot == snapshoty[i], ]
    wspolne <- intersect(a$klucz, b$klucz)
    A <- a[match(wspolne, a$klucz), ]
    B <- b[match(wspolne, b$klucz), ]
    w <- data.frame(od = snapshoty[i - 1], do = snapshoty[i],
                    kolejek_w_obu = length(wspolne),
                    zniknelo = length(setdiff(a$klucz, b$klucz)),
                    nowych = length(setdiff(b$klucz, a$klucz)),
                    te_same_queue_id = length(intersect(a$queue_id, b$queue_id)),
                    check.names = FALSE)
    for (p in names(pola)) {
      w[[p]] <- sum(Reduce(`|`, lapply(pola[[p]], function(k) rozne(A[[k]], B[[k]]))))
    }
    w
  }))
  print(zmiany, row.names = FALSE)
  zapisz_dla_excela(zmiany, "wyniki/zmiany_miedzy_snapshotami.csv")
  cat(paste0("\nLiczby w kolumnach pól to kolejki, w których dane pole zmieniło się między dwoma\n",
             "kolejnymi snapshotami. te_same_queue_id pokazuje, ile identyfikatorów kolejek się\n",
             "powtórzyło: NFZ nadaje je codziennie od nowa, dlatego dni łączymy po kolumnie klucz.\n"))
}

# ---- 3. Kolejki do sprawdzenia --------------------------------------------------------
cat("\n==== 3. KOLEJKI DO SPRAWDZENIA (najnowszy snapshot) ====\n")
# Grupa porównawcza = to samo świadczenie w tym samym trybie (tylko kolejki aktywne).
akt$grupa <- paste(akt$benefit, akt$case, sep = " | tryb ")
staty <- do.call(rbind, lapply(split(akt, akt$grupa), function(g) data.frame(
  grupa = g$grupa[1], n_w_grupie = nrow(g),
  czas_q1 = kw(g$sredni_czas, 0.25), czas_mediana = kw(g$sredni_czas, 0.5),
  czas_q3 = kw(g$sredni_czas, 0.75),
  oczek_q1 = kw(g$oczekujacy, 0.25), oczek_mediana = kw(g$oczekujacy, 0.5),
  oczek_q3 = kw(g$oczekujacy, 0.75)
)))
akt <- merge(akt, staty, by = "grupa", all.x = TRUE, sort = FALSE)
duza_grupa <- akt$n_w_grupie >= 10

# Flaga 1: średni czas skrajnie dłuższy niż w grupie (powyżej Q3 + 3·IQR) i dłuższy niż pół roku.
akt$flaga_czas <- (duza_grupa &
  akt$sredni_czas > akt$czas_q3 + 3 * (akt$czas_q3 - akt$czas_q1) &
  akt$sredni_czas > 180) %in% TRUE
# Flaga 2: liczba oczekujących skrajnie wyższa niż w grupie i większa niż 200.
akt$flaga_kolejka <- (duza_grupa &
  akt$oczekujacy > akt$oczek_q3 + 3 * (akt$oczek_q3 - akt$oczek_q1) &
  akt$oczekujacy > 200) %in% TRUE
# Flaga 3: prawo Little'a. Liczba oczekujących podzielona przez liczbę skreślonych w miesiącu
# daje w przybliżeniu, ile miesięcy zajęłoby „rozładowanie” kolejki. Jeśli ten czas różni się
# od raportowanego średniego czasu oczekiwania więcej niż 10 razy, liczby się nie spinają.
czas_little <- ifelse(akt$skresleni > 0, akt$oczekujacy / akt$skresleni * 30.44, NA)
iloraz_little <- ifelse(akt$sredni_czas > 0, czas_little / akt$sredni_czas, NA)
akt$flaga_little <- (akt$skresleni >= 5 &
  (iloraz_little > 10 | iloraz_little < 0.1)) %in% TRUE
akt$czas_z_prawa_littlea <- round(czas_little)
akt$iloraz_littlea <- round(iloraz_little, 2)
# Flaga 4: w trybie pilnym czeka się (prawie) tyle samo co w stabilnym, choć dłużej niż 3 miesiące.
para <- paste(akt$provider_code, akt$id_resort_part_vii, akt$id_resort_part_viii, akt$benefit,
              sep = "|")
czas_stab <- stats::setNames(akt$sredni_czas[akt$case == "1"], para[akt$case == "1"])
akt$czas_w_trybie_stabilnym <- ifelse(akt$case == "2", unname(czas_stab[para]), NA)
akt$flaga_pilny <- (akt$case == "2" & akt$czas_w_trybie_stabilnym > 90 &
  akt$sredni_czas >= 0.95 * akt$czas_w_trybie_stabilnym) %in% TRUE

akt$liczba_flag <- akt$flaga_czas + akt$flaga_kolejka + akt$flaga_little + akt$flaga_pilny

kolumny <- c("liczba_flag", "flaga_czas", "flaga_kolejka", "flaga_little", "flaga_pilny",
             "benefit", "case", "locality", "wojewodztwo", "provider", "oczekujacy", "skresleni",
             "sredni_czas", "dates_pcus", "n_w_grupie", "czas_mediana", "czas_q3",
             "oczek_mediana", "czas_z_prawa_littlea", "iloraz_littlea",
             "czas_w_trybie_stabilnym", "stat_update", "klucz")
flagi <- akt[akt$liczba_flag > 0, kolumny]
flagi <- flagi[order(-flagi$liczba_flag, -flagi$sredni_czas), ]
zapisz_dla_excela(flagi, "wyniki/kolejki_do_sprawdzenia.csv")

cat(sprintf("Aktywnych kolejek: %d. Z co najmniej jedną flagą: %d, z dwiema lub więcej: %d.\n",
            nrow(akt), nrow(flagi), sum(flagi$liczba_flag >= 2)))
cat(sprintf("  flaga_czas    (czas skrajnie dłuższy niż w podobnych kolejkach): %d\n",
            sum(akt$flaga_czas)))
cat(sprintf("  flaga_kolejka (skrajnie dużo oczekujących):                     %d\n",
            sum(akt$flaga_kolejka)))
cat(sprintf("  flaga_little  (liczby oczekujących, skreśleń i czasu się nie spinają): %d\n",
            sum(akt$flaga_little)))
cat(sprintf("  flaga_pilny   (tryb pilny tak długi jak stabilny):               %d\n",
            sum(akt$flaga_pilny)))
cat("\nNa górze listy (pełna lista: wyniki/kolejki_do_sprawdzenia.csv):\n")
print(utils::head(flagi[, c("liczba_flag", "benefit", "case", "locality", "oczekujacy",
                            "skresleni", "sredni_czas", "dates_pcus", "czas_mediana",
                            "iloraz_littlea")], 15), row.names = FALSE)

# Pojedyncze kolejki obejrzysz tą funkcją, np. sprawdz("WEJHEROWO", "ALKOHOL").
sprawdz <- function(miejscowosc, fragment_swiadczenia = "") {
  w <- akt[grepl(miejscowosc, akt$locality, ignore.case = TRUE) &
             grepl(fragment_swiadczenia, akt$benefit, ignore.case = TRUE),
           c("benefit", "case", "locality", "provider", "oczekujacy", "skresleni",
             "sredni_czas", "dates_pcus", "n_w_grupie", "czas_mediana", "czas_q3",
             "czas_z_prawa_littlea", "iloraz_littlea", "liczba_flag")]
  if (nrow(w) == 0) {
    cat("Brak aktywnych kolejek dla tego wyszukiwania.\n")
  } else {
    print(w, row.names = FALSE)
  }
  invisible(w)
}

# ---- Wykres: rozkład średniego czasu oczekiwania dla najczęstszych świadczeń ------------
otwarty <- FALSE
tryCatch({
  liczebnosc <- sort(table(stab$benefit), decreasing = TRUE)
  top <- names(liczebnosc)[seq_len(min(12, length(liczebnosc)))]
  d <- stab[stab$benefit %in% top & !is.na(stab$sredni_czas), ]
  mediany <- tapply(d$sredni_czas, d$benefit, stats::median)
  d$swiadczenie <- factor(d$benefit, levels = names(sort(mediany)))
  d$log_czas <- log10(d$sredni_czas + 1)
  grDevices::png("wyniki/czas_oczekiwania_wg_swiadczen.png", width = 1700, height = 1000, res = 140)
  otwarty <- TRUE
  stary_par <- graphics::par(mar = c(5, 28, 3, 2))
  graphics::boxplot(log_czas ~ swiadczenie, data = d, horizontal = TRUE, axes = FALSE,
                    col = "#BFD0E0", border = "#2E5A88", outcex = 0.5, xlab = "", ylab = "",
                    main = "Średni czas oczekiwania: tryb stabilny, aktywne kolejki")
  dni <- c(0, 7, 30, 91, 182, 365, 730, 1461)
  graphics::axis(1, at = log10(dni + 1),
                 labels = c("0", "1 tydz.", "1 mies.", "3 mies.", "6 mies.", "1 rok", "2 lata",
                            "4 lata"))
  graphics::axis(2, at = seq_along(levels(d$swiadczenie)),
                 labels = substr(levels(d$swiadczenie), 1, 55), las = 1, cex.axis = 0.7)
  graphics::box()
  graphics::par(stary_par)
  grDevices::dev.off()
  otwarty <- FALSE
  cat("\nWykres: wyniki/czas_oczekiwania_wg_swiadczen.png\n")
}, error = function(e) {
  if (otwarty) grDevices::dev.off()
  message("Nie udało się narysować wykresu: ", conditionMessage(e))
})

cat("\nTabele zapisane w folderze wyniki/: wojewodztwa.csv, swiadczenia.csv,",
    "zmiany_miedzy_snapshotami.csv, kolejki_do_sprawdzenia.csv\n")
cat('Pojedynczą kolejkę obejrzysz funkcją sprawdz(), np. sprawdz("WEJHEROWO", "ALKOHOL")\n')
