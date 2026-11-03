# Crop coefficients for reference ET ----------------------------------------------
# Penman-Monteith (and GridMET's `pet`) give grass reference ET (ETo). Actual
# vegetation differs, so PET = Kc(t) x ETo, where Kc comes from basin land
# cover rather than a calibrated multiplier:
#   1. NLCD 2019 class fractions over the basin polygon (`get_basin_landcover()`,
#      R/attributes.R)
#   2. A dormant- and a growing-season Kc per class (inst/extdata/kc_nlcd.csv),
#      area-weighted to one dormant and one growing Kc per basin
#   3. A temperature phenology index that ramps daily Kc between the two
#
# Kc sources (see the status/source columns of inst/extdata/kc_nlcd.csv):
#   CURRENT TABLE: placeholder potential Kc for vegetated classes. The Liu et al.
#   (2017) actual-Kc table below was tested and rejected (double counts water
#   stress); it is archived in inst/extdata/kc_nlcd_liu2017.csv. Tested alternative:
#   - Forest, shrub, grassland, crop classes: Liu et al. (2017, HESS 21:311),
#     FLUXNET-derived seasonal Kc relative to FAO-56 grass ETo. Dormant Kc =
#     winter (Nov-Jan) mean; growing Kc = the largest seasonal mean.
#   - Open water: FAO-56 (Allen et al. 1998), Table 12.
#   - Wetlands: pending Pereira et al. (2024, Irrig. Sci. 42:1171).
#   - Developed, barren, ice: placeholders.
# Caveat: the Liu et al. values are *actual* Kc (AET/ETo), so they already
# include water stress. The soil bucket also limits AET when dry, so these
# values act as a lower bound on potential (well-watered) Kc.

nlcd_codes <- c(11, 12, 21, 22, 23, 24, 31, 41, 42, 43, 52, 71, 81, 82, 90, 95)

#' Kc lookup table by NLCD class
#' @param path csv with nlcd_code, kc_dormant, kc_growing.
#' @export
read_kc_table <- function(path = wsva_extdata("kc_nlcd.csv")) {
  readr::read_csv(path, show_col_types = FALSE)
}

#' Area-weighted basin dormant and growing-season Kc
#'
#' @param landcover Output of `get_basin_landcover()`.
#' @param kc_table Output of `read_kc_table()`.
#' @return One-row tibble: kc_dormant, kc_growing, pct_covered (share of
#'   the basin whose class has a Kc; weights are renormalized over it).
#' @export
basin_kc <- function(landcover, kc_table = read_kc_table()) {
  x <- dplyr::inner_join(landcover, kc_table, by = "nlcd_code")
  w <- x$pct / sum(x$pct)
  tibble::tibble(kc_dormant = sum(w * x$kc_dormant),
                 kc_growing = sum(w * x$kc_growing),
                 pct_covered = sum(x$pct))
}

#' Daily Kc from a temperature phenology index
#'
#' Growing-season weight g = 0 when the trailing `window`-day mean
#' temperature is at or below `t_lo`, 1 at or above `t_hi`, linear between;
#' Kc = kc_dormant + g (kc_growing - kc_dormant). The trailing mean keeps
#' single warm days in winter from switching the canopy on.
#'
#' @param tmean_c Daily mean temperature.
#' @param kc_dormant,kc_growing Basin Kc values (from `basin_kc()`).
#' @param t_lo,t_hi Temperature ramp (deg C).
#' @param window Days in the trailing mean.
#' @return Numeric vector of daily Kc.
#' @export
kc_seasonal <- function(tmean_c, kc_dormant, kc_growing, t_lo = 2, t_hi = 10, window = 15) {
  t_avg <- as.numeric(stats::filter(tmean_c, rep(1 / window, window), sides = 1))
  head_n <- min(window - 1, length(tmean_c))
  t_avg[seq_len(head_n)] <- cumsum(tmean_c[seq_len(head_n)]) / seq_len(head_n)   # partial window at start
  g <- pmin(pmax((t_avg - t_lo) / (t_hi - t_lo), 0), 1)
  kc_dormant + g * (kc_growing - kc_dormant)
}

#' Daily vegetation PET (mm) = FAO-56 Penman-Monteith ETo x seasonal Kc
#'
#' The same PET wbm_run() uses with pet_method = "penman_monteith", minus the
#' WBM-specific snow rule, so other models (GR4J, ...) get identical PET.
#'
#' @param daily Daily GridMET forcing (tmin_c, tmax_c, tmean_c, srad_wm2,
#'   rhmin_pct, rhmax_pct, wind_ms at 10 m).
#' @param static One-row static table with lat, elev_m, kc_dormant, kc_growing.
#' @param kc_t_lo,kc_t_hi,kc_window Seasonal Kc settings, see `kc_seasonal()`.
#' @export
pet_ref_kc <- function(daily, static, kc_t_lo = 2, kc_t_hi = 10, kc_window = 15) {
  prepare_forcing(daily, static, kc_t_lo, kc_t_hi, kc_window)$pet_mm   # R/forcing.R
}
