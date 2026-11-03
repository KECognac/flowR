# Model forcing: one contract for every climate source -----------------------------
# Every model in flowR is driven by the same daily basin-mean variables, so a
# model calibrated on historical GridMET can be run unchanged on downscaled
# climate projections (MACAv2-METDATA is bias-corrected to GridMET and
# provides all of them). PET is always computed here from the
# meteorological variables, never taken from a dataset's own PET product,
# so historical and future runs use an identical PET method.
#
# Required columns (basin means):
#   date, prcp_mm, tmin_c, tmax_c, srad_wm2 (shortwave, W m-2),
#   rhmin_pct, rhmax_pct, wind_ms (at 10 m)
# Added by prepare_forcing():
#   tmean_c   (if missing) mean of tmin and tmax
#   eto_mm    FAO-56 Penman-Monteith grass reference ET
#   pet_mm    eto_mm x seasonal land-cover Kc (the PET every process model uses)

#' Columns every forcing table must have (the forcing contract)
#' @return Character vector of column names.
#' @export
forcing_required_vars <- function() {
  c("date", "prcp_mm", "tmin_c", "tmax_c", "srad_wm2", "rhmin_pct", "rhmax_pct", "wind_ms")
}

#' Check a forcing table against the contract and add derived variables
#'
#' @param daily Daily basin-mean forcing (other columns, e.g. q_mm, are kept).
#' @param static One-row static table with lat, elev_m, kc_dormant, kc_growing.
#' @param kc_t_lo,kc_t_hi,kc_window Seasonal Kc settings (`kc_seasonal()`).
#' @return `daily` with tmean_c, eto_mm and pet_mm.
#' @export
prepare_forcing <- function(daily, static, kc_t_lo = 2, kc_t_hi = 10, kc_window = 15) {
  missing <- setdiff(forcing_required_vars(), names(daily))
  if (length(missing)) stop("Forcing is missing: ", paste(missing, collapse = ", "))
  if (!"tmean_c" %in% names(daily)) daily$tmean_c <- (daily$tmin_c + daily$tmax_c) / 2
  doy <- as.integer(format(as.Date(daily$date), "%j"))
  daily$eto_mm <- pet_penman_monteith(doy, static$lat, static$elev_m, daily$tmin_c, daily$tmax_c,
                                      srad_wm2 = daily$srad_wm2, rhmin_pct = daily$rhmin_pct,
                                      rhmax_pct = daily$rhmax_pct, wind_ms = daily$wind_ms,
                                      wind_height = 10)
  daily$pet_mm <- daily$eto_mm * kc_seasonal(daily$tmean_c, static$kc_dormant, static$kc_growing,
                                             t_lo = kc_t_lo, t_hi = kc_t_hi, window = kc_window)
  daily
}

#' Read a prepared basin's daily table, static attributes and hypsometry
#'
#' @return list(daily = forcing + q_mm with eto_mm/pet_mm, static, hypso)
#' @param site_no Basin id (folder under `wsva_path("processed")`).
#' @export
read_basin_inputs <- function(site_no) {
  p <- function(f) wsva_path("processed", site_no, f)
  static <- readr::read_csv(p("static.csv"), show_col_types = FALSE)
  list(daily = prepare_forcing(arrow::read_parquet(p("daily.parquet")), static),
       static = static,
       hypso = readr::read_csv(p("hypsometry.csv"), show_col_types = FALSE)$elev_m)
}
