# Szybki test (kilkanaście sekund): dwa zapytania do API, wyniki w folderze data_test/.
# Uruchom w RStudio po otwarciu nfz-kolejki.Rproj: source("R/test_nfz.R")

Sys.setenv(NFZ_TEST = "1")
tryCatch(
  source("R/collect_nfz.R", encoding = "UTF-8"),
  finally = Sys.unsetenv("NFZ_TEST")
)
