# Daily bucket water balance model -------------------------------------------------
# Generic version of the Thoma / NPS water balance model (Thornthwaite-Mather
# style soil bucket with a temperature-index snow model), with the CSU
# additions (direct runoff fraction, linear storage release, PET and soil
# multipliers). Units are mm and deg C throughout; nothing is converted to
# inches.
#
# Rain/snow partitioning uses a linear ramp centered on the Jennings et al.
# (2018) threshold temperature (jtemp): all snow below jtemp - 3 C, all rain
# above jtemp + 3 C. Melt is a degree-day model (Hock 2003) above jtemp - 3 C.
#
# PET: for the reference-ET methods ("penman_monteith", "gridmet"),
# PET = Kc(t) x ETo with a land-cover, temperature-phenology crop
# coefficient (see wbm_kc.R) supplied as kc_dormant / kc_growing. For all
# methods, PET is set to 0 on days with snowpack above `snow_et_thresh`.

# Optional forcing column, NULL when absent (avoids tibble's unknown-column warning)
.opt_col <- function(df, nm) if (nm %in% names(df)) df[[nm]] else NULL

#' Default WBM parameters
#'
#' Site parameters (lat, elev_m, slope_deg, aspect_deg, swc_max_mm, jtemp_c,
#' and kc_dormant / kc_growing for reference-ET methods) come from
#' `get_basin_static()` and `basin_kc()`. The rest are calibration knobs or
#' fixed settings; with pet_method = "oudin" these defaults reproduce the
#' original NPS model.
#' @export
wbm_default_params <- function() {
  list(
    hock = 4,            # degree-day melt factor (mm C-1 day-1)
    jtemp_offset = 0,    # shift applied to the rain/snow threshold (C)
    soil_mult = 1,       # multiplier on swc_max_mm
    direct_frac = 0,     # fraction of rain bypassing soil straight to runoff
    return_rate = 1,     # daily fraction of excess-water storage released
    shade_coeff = 1,     # Oudin shading coefficient
    snow_et_thresh = 2,  # mm SWE; PET = 0 above this snowpack
    kc_t_lo = 2,         # Kc phenology ramp: fully dormant at/below (C) ...
    kc_t_hi = 10,        # ... fully growing at/above (C)
    kc_window = 15,      # days in the trailing temperature mean
    pet_mult = 1         # legacy PET multiplier; leave at 1 when using Kc
  )
}

#' Run the water balance model
#'
#' @param forcing Daily tibble with date, prcp_mm, tmean_c; plus tmin_c,
#'   tmax_c, srad_wm2, rhmin_pct, rhmax_pct, wind_ms for Penman-Monteith, or
#'   pet_ref_mm for `pet_method = "gridmet"`. Must be gap-free.
#' @param params Named list or one-row data frame: site parameters plus any of
#'   `wbm_default_params()` to override.
#' @param pet_method "oudin", "hamon", "penman_monteith" (FAO-56 grass
#'   reference ET computed from the forcing), or "gridmet" (GridMET's
#'   precomputed ASCE grass reference ET). The two reference-ET methods
#'   require kc_dormant and kc_growing in `params`.
#' @param ros If TRUE, add rain-on-snow melt enhancement (hock + 0.0125 x rain).
#' @param init list(snowpack, soil, storage) initial states in mm.
#' @return Tibble of daily fluxes and states (mm): rain, snow, melt, snowpack,
#'   pet_ref (ETo or the raw Oudin/Hamon PET), kc, pet, aet, soil, excess,
#'   storage, direct, runoff, deficit.
#' @export
wbm_run <- function(forcing, params, pet_method = c("oudin", "hamon", "penman_monteith", "gridmet"),
                    ros = FALSE, init = list(snowpack = 0, soil = 0, storage = 0)) {

  pet_method <- match.arg(pet_method)
  p <- utils::modifyList(wbm_default_params(), as.list(params))
  required <- c("lat", "swc_max_mm", "jtemp_c")
  if (!all(required %in% names(p))) stop("params missing: ", paste(setdiff(required, names(p)), collapse = ", "))
  if (anyNA(forcing$prcp_mm) || anyNA(forcing$tmean_c)) stop("forcing has NA prcp_mm/tmean_c; fill gaps first")
  if (any(diff(as.Date(forcing$date)) != 1)) stop("forcing dates must be a gap-free daily sequence")

  n <- nrow(forcing)
  ppt <- forcing$prcp_mm
  tmean <- forcing$tmean_c
  doy <- as.integer(format(as.Date(forcing$date), "%j"))
  jt <- p$jtemp_c + p$jtemp_offset
  t_lo <- jt - 3
  cap <- p$swc_max_mm * p$soil_mult

  # Rain / snow partition
  frac_rain <- pmin(pmax((tmean - t_lo) / 6, 0), 1)
  rain <- ppt * frac_rain
  snow <- ppt - rain

  # Snow: melt is limited by the previous day's pack (as in the original)
  melt <- pack <- numeric(n)
  pack_prev <- init$snowpack
  for (i in seq_len(n)) {
    m <- 0
    if (tmean[i] >= t_lo && pack_prev > 0) {
      ddf <- if (ros && rain[i] > 0) p$hock + 0.0125 * rain[i] else p$hock
      m <- min((tmean[i] - t_lo) * ddf, pack_prev)
    }
    melt[i] <- m
    pack[i] <- pack_prev + snow[i] - m
    pack_prev <- pack[i]
  }

  pet_ref <- switch(pet_method,
    oudin = pet_oudin(doy, p$lat, tmean,
                      heat_load = heat_load_index(p$lat, p$slope_deg %||% 0, p$aspect_deg %||% 180) * p$shade_coeff),
    hamon = pet_hamon(doy, p$lat, tmean),
    penman_monteith = pet_penman_monteith(doy, p$lat, p$elev_m, forcing$tmin_c, forcing$tmax_c,
                                          srad_wm2 = .opt_col(forcing, "srad_wm2"),
                                          rhmin_pct = .opt_col(forcing, "rhmin_pct"),
                                          rhmax_pct = .opt_col(forcing, "rhmax_pct"),
                                          wind_ms = .opt_col(forcing, "wind_ms") %||% 2,
                                          wind_height = if (is.null(.opt_col(forcing, "wind_ms"))) 2 else 10),
    gridmet = forcing$pet_ref_mm
  )

  # Crop coefficient: reference ET -> vegetation PET
  kc <- rep(1, n)
  if (pet_method %in% c("penman_monteith", "gridmet")) {
    if (is.null(p$kc_dormant) || is.null(p$kc_growing)) {
      stop("pet_method '", pet_method, "' gives grass reference ET; supply kc_dormant and kc_growing (see basin_kc())")
    }
    kc <- kc_seasonal(tmean, p$kc_dormant, p$kc_growing,
                      t_lo = p$kc_t_lo, t_hi = p$kc_t_hi, window = p$kc_window)
  }

  # FIX: the original applied pet_mult inside the soil update but used the
  # unmultiplied PET for W - PET and AET, so the multiplier was only
  # partially applied. Here the multiplied PET is used everywhere.
  pet <- pet_ref * kc * p$pet_mult

  # Snow-covered ground: no ET (the original applied this to Oudin only)
  if (!is.null(p$snow_et_thresh) && !is.na(p$snow_et_thresh)) pet[pack > p$snow_et_thresh] <- 0

  direct <- rain * p$direct_frac
  w <- rain + melt - direct

  # Soil bucket (Thornthwaite-Mather exponential drying) and excess storage
  soil <- aet <- excess <- storage <- release <- numeric(n)
  soil_prev <- init$soil
  stor_prev <- init$storage
  for (i in seq_len(n)) {
    if (w[i] > pet[i]) {
      s <- min(w[i] - pet[i] + soil_prev, cap)
      a <- pet[i]
    } else {
      s <- soil_prev * exp(-(pet[i] - w[i]) / cap)
      a <- w[i] + soil_prev - s
    }
    ex <- w[i] - a - (s - soil_prev)        # water exceeding soil capacity
    avail <- stor_prev + ex
    release[i] <- avail * p$return_rate
    storage[i] <- avail - release[i]
    soil[i] <- s; aet[i] <- a; excess[i] <- ex
    soil_prev <- s; stor_prev <- storage[i]
  }

  tibble::tibble(
    date = as.Date(forcing$date),
    prcp = ppt, rain = rain, snow = snow, melt = melt, snowpack = pack,
    pet_ref = pet_ref, kc = kc, pet = pet,
    aet = aet, soil = soil, excess = excess, storage = storage,
    direct = direct, runoff = release + direct, deficit = pet - aet
  )
}
