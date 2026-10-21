# Funkcje do pobierania danych z API NFZ "Terminy leczenia" (wersja 1.4).
# Ten plik tylko definiuje funkcje i niczego nie pobiera. Używa ich R/collect_nfz.R.

# Pola rekordu zapisywane jako osobne kolumny, w kolejności z API.
# Każde nowe pole, którego tu nie ma, trafi do kolumny extra_attributes_json,
# więc nic nie zginie, jeśli NFZ zmieni strukturę danych.
SIMPLE_KEYS <- c(
  "benefit", "anesthesia", "many-places", "provider", "provider-code",
  "regon-provider", "nip-provider", "teryt-provider", "place", "address",
  "locality", "phone", "teryt-place", "registry-number", "id-resort-part-VII",
  "id-resort-part-VIII", "benefits-for-children", "age-range", "covid-19",
  "toilet", "ramp", "car-park", "elevator", "type-building", "ac",
  "automatic-door", "public-transport-lines", "wheelchairs", "corridors",
  "latitude", "longitude", "queue-in-cer"
)
KNOWN_ATTR_KEYS <- c("case", SIMPLE_KEYS, "statistics", "dates", "benefits-provided")

# Jedna wartość z JSON-a jako tekst: null -> NA, obiekt lub lista -> tekst JSON.
as_text <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  if (is.list(x) || length(x) > 1) {
    return(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null",
                                         na = "null", digits = NA)))
  }
  if (is.na(x)) return(NA_character_)
  if (is.numeric(x)) return(format(x, scientific = FALSE, digits = 15, trim = TRUE))
  as.character(x)
}

# Pola obiektu x spoza listy `known`, zapisane jako JSON (żeby nic nie zginęło).
extra_json <- function(x, known) {
  if (!is.list(x) || length(x) == 0 || is.null(names(x))) return(NA_character_)
  extra <- setdiff(names(x), known)
  if (length(extra) == 0) return(NA_character_)
  as_text(x[extra])
}

# Spłaszcza jeden rekord kolejki do nazwanego wektora tekstowego (= jeden wiersz tabeli).
flatten_queue <- function(rec) {
  a <- rec[["attributes"]]
  if (!is.list(a)) a <- list()
  get_in <- function(obj, key) if (is.list(obj)) obj[[key]] else NULL
  st <- a[["statistics"]]
  pd <- get_in(st, "provider-data")
  dt <- a[["dates"]]

  simple <- vapply(SIMPLE_KEYS, function(k) as_text(a[[k]]), character(1), USE.NAMES = FALSE)
  names(simple) <- gsub("-", "_", tolower(SIMPLE_KEYS))

  c(
    queue_id = as_text(rec[["id"]]),
    case     = as_text(a[["case"]]),
    simple,
    stat_awaiting          = as_text(get_in(pd, "awaiting")),
    stat_removed           = as_text(get_in(pd, "removed")),
    stat_average_period    = as_text(get_in(pd, "average-period")),
    stat_update            = as_text(get_in(pd, "update")),
    stat_computed_json     = as_text(get_in(st, "computed-data")),
    stat_extra_json        = extra_json(pd, c("awaiting", "removed", "average-period", "update")),
    stat_other_json        = extra_json(st, c("provider-data", "computed-data")),
    dates_applicable       = as_text(get_in(dt, "applicable")),
    dates_pcus             = as_text(get_in(dt, "pcus")),
    dates_situation_as_at  = as_text(get_in(dt, "date-situation-as-at")),
    dates_extra_json       = extra_json(dt, c("applicable", "pcus", "date-situation-as-at")),
    benefits_provided_json = as_text(a[["benefits-provided"]]),
    extra_attributes_json  = extra_json(a, KNOWN_ATTR_KEYS)
  )
}

# Jedno zapytanie GET do API.
# Zwraca list(ok = TRUE, json, body) albo list(ok = FALSE, error = opis problemu).
nfz_get <- function(cfg, path, query) {
  req <- httr2::request(cfg$base_url) |>
    httr2::req_url_path_append(path)
  req <- do.call(httr2::req_url_query,
                 c(list(req), query, list(`api-version` = cfg$api_version)))
  req <- req |>
    httr2::req_user_agent(cfg$user_agent) |>
    httr2::req_timeout(30) |>
    httr2::req_retry(
      max_tries = 5,
      retry_on_failure = TRUE,  # ponawiaj także po zerwanym połączeniu
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504),
      backoff = function(attempt) min(60, 5 * 2^(attempt - 1))  # 5, 10, 20, 40 s
    ) |>
    httr2::req_error(is_error = function(resp) FALSE)  # błędy HTTP obsługujemy sami, niżej

  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) {
    return(list(ok = FALSE, error = paste("brak połączenia:", conditionMessage(resp))))
  }

  status <- httr2::resp_status(resp)
  body <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
  if (status != 200) {
    return(list(ok = FALSE, error = sprintf("HTTP %d: %s", status, substr(body, 1, 300))))
  }
  json <- tryCatch(jsonlite::fromJSON(body, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(json)) {
    return(list(ok = FALSE, error = "odpowiedź nie jest poprawnym JSON-em"))
  }
  if (!is.null(json[["errors"]])) {
    return(list(ok = FALSE, error = paste("błąd API:", substr(as_text(json[["errors"]]), 1, 300))))
  }
  if (is.null(json[["meta"]][["count"]])) {
    return(list(ok = FALSE, error = "w odpowiedzi brakuje meta.count"))
  }
  list(ok = TRUE, json = json, body = body)
}

# Linia pliku surowych odpowiedzi: parametry zapytania + odpowiedź API bez zmian.
raw_line <- function(keyword, case, province, page, pass, body) {
  query <- jsonlite::toJSON(list(
    keyword = keyword, case = case, province = province, page = page, pass = pass,
    fetched_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ), auto_unbox = TRUE)
  paste0('{"query":', query, ',"response":', gsub("[\r\n]+", " ", body), "}")
}

# Wszystkie strony jednego zapytania (fragment nazwy × tryb × województwo).
# Jeśli liczba unikalnych rekordów nie zgadza się z meta.count (np. gdy kolejność
# rekordów zmienia się między stronami), zapytanie jest powtarzane do cfg$max_passes razy,
# a wyniki są łączone. Gdy nie da się pobrać pierwszej strony (każde zapytanie HTTP
# i tak jest ponawiane do 5 razy), zapytanie kończy się od razu z expected = NA.
fetch_query <- function(cfg, keyword, case, province, max_pages = Inf) {
  base_query <- list(limit = cfg$page_size, format = "json", case = case,
                     province = province, benefit = keyword)
  recs <- new.env(hash = TRUE)
  raw <- character()
  errors <- character()
  expected <- NA_integer_
  requests <- 0L
  failed <- 0L
  passes <- 0L
  complete <- FALSE
  first_page_failed <- FALSE

  repeat {
    passes <- passes + 1L
    page <- 1L
    n_pages <- 1
    while (page <= min(n_pages, max_pages)) {
      r <- nfz_get(cfg, "queues", c(base_query, list(page = page)))
      requests <- requests + 1L
      if (r$ok) {
        if (page == 1L) {
          expected <- as.integer(r$json[["meta"]][["count"]])
          n_pages <- ceiling(expected / cfg$page_size)
        }
        for (rec in r$json[["data"]]) {
          id <- rec[["id"]]
          if (!is.null(id)) assign(id, rec, envir = recs)
        }
        raw <- c(raw, raw_line(keyword, case, province, page, passes, r$body))
      } else {
        failed <- failed + 1L
        errors <- c(errors, sprintf("przebieg %d, strona %d: %s", passes, page, r$error))
        if (page == 1L) {  # bez pierwszej strony nie wiadomo, ile jest stron
          first_page_failed <- TRUE
          Sys.sleep(cfg$delay_s)
          break
        }
      }
      page <- page + 1L
      Sys.sleep(cfg$delay_s)
    }
    n_unique <- length(ls(recs))
    complete <- !is.na(expected) && n_unique >= expected
    if (complete || first_page_failed || passes >= cfg$max_passes || is.finite(max_pages)) break
  }

  ids <- ls(recs)
  list(
    keyword = keyword, case = case, province = province,
    records = mget(ids, envir = recs),
    expected = expected, n_unique = length(ids), complete = complete,
    requests = requests, failed = failed, passes = passes,
    error = if (length(errors) > 0) paste(errors, collapse = " | ") else NA_character_,
    raw = raw
  )
}

# Pomocniczo: pełne nazwy świadczeń zawierające dany fragment, np. nfz_benefits(cfg, "PSYCH").
# Przydaje się, gdy chcesz sprawdzić, co obejmuje słowo kluczowe w config.R.
nfz_benefits <- function(cfg, keyword) {
  out <- character()
  page <- 1
  n_pages <- 1
  while (page <= n_pages) {
    r <- nfz_get(cfg, "benefits", list(name = keyword, page = page,
                                       limit = cfg$page_size, format = "json"))
    if (!r$ok) stop(r$error)
    n_pages <- ceiling(r$json[["meta"]][["count"]] / cfg$page_size)
    out <- c(out, unlist(r$json[["data"]]))
    page <- page + 1
    Sys.sleep(cfg$delay_s)
  }
  out
}

# Zapis tabeli do skompresowanego pliku CSV (UTF-8).
write_csv_gz <- function(df, path) {
  con <- gzfile(path, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  write.csv(df, con, row.names = FALSE, na = "")
}

# Dopisanie wiersza (wierszy) do pliku CSV; nagłówek tylko przy tworzeniu pliku.
append_csv <- function(df, path) {
  already <- file.exists(path)
  write.table(df, path, sep = ",", row.names = FALSE, col.names = !already,
              append = already, qmethod = "double", na = "", fileEncoding = "UTF-8")
}
