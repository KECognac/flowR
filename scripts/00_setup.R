# Analysis setup: load the WSVAflowR package from this repo -------------------------
# Run from anywhere inside the project: source(here::here("scripts/00_setup.R"))
# The notebooks and scripts in scripts/ are analyses that use the package;
# they are not part of the package build.

pkgs <- c("arrow", "climateR", "dataRetrieval", "dplyr", "exactextractr",
          "ggplot2", "here", "nhdplusTools", "pkgload", "purrr", "readr", "sf", "terra",
          "tibble", "tidyr")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install missing packages: ", paste(missing, collapse = ", "))

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
`%>%` <- magrittr::`%>%`

pkgload::load_all(here::here(), quiet = TRUE)

# Analysis-only helpers (CAMELS donors, regional attributes); not in the package
invisible(lapply(list.files(here::here("scripts", "R"), pattern = "\\.R$", full.names = TRUE), source))

# Analyses keep their downloads, caches and results in this repo's git-ignored data/
options(wsva.data_dir = here::here("data"))

# Shared study period: GridMET starts 1979; WY1981 is used for model warm-up.
flowr_period <- wsva_default_period()

#' Read the shared set of test gauges every model is evaluated on
#' @param path csv written by scripts/01_select_test_gauges.R
get_test_gauges <- function(path = here::here("config", "test_gauges.csv")) {
  readr::read_csv(path, col_types = readr::cols(site_no = "c", .default = readr::col_guess()),
                  progress = FALSE)
}
