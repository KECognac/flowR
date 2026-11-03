#' WSVAflowR: multi-model streamflow simulation for gauged basins
#'
#' Builds model inputs for a stream gauge, calibrates and cross-validates
#' several process models on identical forcing and folds, and tests their
#' transfer to contrasting climates. See `dev/package_design.md` in the source
#' repository for the planned interface.
#'
#' @section Data directory:
#' Downloads, caches and prepared basin inputs live under one directory:
#' `getOption("wsva.data_dir")`, defaulting to
#' `tools::R_user_dir("WSVAflowR", "cache")`. Set it once per session, e.g.
#' `options(wsva.data_dir = "~/flow_data")`.
#'
#' @keywords internal
#' @importFrom magrittr %>%
#' @importFrom rlang :=
"_PACKAGE"

#' Path inside the WSVAflowR data directory
#'
#' @param ... Path components, as for [file.path()].
#' @return A file path under `getOption("wsva.data_dir")` (default
#'   `tools::R_user_dir("WSVAflowR", "cache")`). Nothing is created.
#' @export
wsva_path <- function(...) {
  file.path(getOption("wsva.data_dir", tools::R_user_dir("WSVAflowR", "cache")), ...)
}

#' Path to a file shipped with the package (`inst/extdata`)
#' @param file File name.
#' @keywords internal
wsva_extdata <- function(file) {
  f <- system.file("extdata", file, package = "WSVAflowR")
  if (!nzchar(f)) stop("Package file not found: ", file)
  f
}

#' Default study period: WY1981-WY2024 (GridMET starts 1979; WY1981 is warm-up)
#' @export
wsva_default_period <- function() {
  list(start = as.Date("1980-10-01"), end = as.Date("2024-09-30"))
}

# Column names used inside dplyr / tidyr verbs (data masking)
utils::globalVariables(c(
  ".", "active09", "aggecoregi", "altitude", "approval_status", "area_gages2", "begin",
  "cell", "cell_area_km2", "contributing_drainage_area", "coverage_fraction", "distance_km",
  "drainage_area", "drainage_area_mi2", "end", "estimated", "gauge_id", "gauge_name", "has_q",
  "hcdn_2009", "huc_02", "hydrologic_unit_code", "monitoring_location_id",
  "monitoring_location_name", "n", "nlcd_code", "obs", "p", "pct", "primary", "q_cfs", "q_mm",
  "qualifier", "q_cms", "flag", "random_key", "rank_similar", "similarity_dist", "site_no", "site_type", "staid",
  "staname", "time_series_id", "tmax_c", "tmin_c", "unit_of_measure", "value", "var", "weight",
  # fit_models() / wsva_fit methods
  "abs_pbias", "contrast", "design", "exceedance", "fold", "id", "kge_blocked", "kge_drop", "kge_worst",
  "lower", "model", "month", "objective", "param", "scaled", "series", "set", "upper", "worst_abs_pbias", "wy"
))
