# Konfiguracja zbierania danych z API NFZ "Terminy leczenia" (wersja 1.4).
#
# Zmieniasz zakres (słowa kluczowe, tryby, województwa)? Zapisz datę i powód
# w pliku ZMIANY.md: zmiana zakresu zmienia definicję Twojego panelu.

cfg <- list(
  # Adres API. Od 10.07.2026 obowiązuje wersja 1.4 pod tym adresem
  # (stary adres api.nfz.gov.pl/app-itl-api to nieaktualna wersja 1.3).
  base_url    = Sys.getenv("NFZ_BASE_URL", "https://apinfz.nfz.gov.pl/app-itl-api-pcus"),
  api_version = "1.4",

  page_size   = 25,  # maksymalna liczba rekordów na stronę, jaką przyjmuje API
  delay_s     = 1,   # przerwa między zapytaniami w sekundach (regulamin zakazuje przeciążania API)
  max_passes  = 3,   # ile razy powtórzyć zapytanie, gdy liczba rekordów nie zgadza się z meta.count
  timezone    = "Europe/Warsaw",
  user_agent  = "nfz-kolejki-panel (projekt badawczy; R/httr2)",

  # Fragmenty nazw świadczeń. API szuka po fragmencie nazwy, bez względu na wielkość liter.
  # Ten sam rekord może pasować do kilku fragmentów; skrypt usuwa duplikaty.
  keywords = c(
    "PSYCH",           # oddziały i poradnie psychiatryczne, PZP, poradnie psychologiczne,
                       # psychogeriatria, psychosomatyka, uzależnienia od substancji psychoaktywnych
    "UZALE",           # leczenie uzależnień, w tym od alkoholu
    "ALKOHOLOWYCH",    # detoksykacja alkoholowa ("alkoholowych zespołów abstynencyjnych")
    "ŚRODOWISK",  # = "ŚRODOWISK": zespoły leczenia środowiskowego (domowego)
    "NERWIC",          # leczenie nerwic i zaburzeń nerwicowych
    "AUTYZ"            # poradnie i oddziały dzienne dla osób z autyzmem
  ),
  cases     = c(1, 2),            # 1 = przypadek stabilny, 2 = przypadek pilny
  provinces = sprintf("%02d", 1:16), # kody województw w numeracji NFZ: 01 dolnośląskie ...
                                     # 10 podlaskie ... 16 zachodniopomorskie (to NIE są kody TERYT)

  data_dir  = "data"
)
