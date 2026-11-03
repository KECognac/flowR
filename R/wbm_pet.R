# Potential evapotranspiration and solar geometry ----------------------------------
# All functions are vectorized and return mm/day. Equations follow FAO-56
# (Allen et al. 1998) unless noted. Ported from the NPS/Thoma water balance
# model (orig. ARC 2019, MGS 2021) with fixes noted inline as "FIX:".

# Solar declination (rad) and inverse relative Earth-Sun distance, FAO-56 eq. 23-24
.solar_decl <- function(doy) 0.409 * sin(2 * pi / 365 * doy - 1.39)
.inv_rel_dist <- function(doy) 1 + 0.033 * cos(2 * pi / 365 * doy)

# Sunset hour angle (rad), FAO-56 eq. 25. Clamped for polar day/night.
.sunset_angle <- function(doy, lat) {
  acos(pmin(pmax(-tan(lat * pi / 180) * tan(.solar_decl(doy)), -1), 1))
}

#' Extraterrestrial radiation Ra (MJ m-2 day-1), FAO-56 eq. 21
#' @keywords internal
extraterrestrial_rad <- function(doy, lat) {
  phi <- lat * pi / 180
  ws <- .sunset_angle(doy, lat)
  dl <- .solar_decl(doy)
  (24 * 60 / pi) * 0.0820 * .inv_rel_dist(doy) *
    (ws * sin(phi) * sin(dl) + cos(phi) * cos(dl) * sin(ws))
}

#' Daylight hours, FAO-56 eq. 34
#' (The NPS WBM used geosphere::daylength(); differences are < ~10 min/day.)
#' @keywords internal
daylength_hours <- function(doy, lat) 24 / pi * .sunset_angle(doy, lat)

#' Saturation vapor pressure (kPa), FAO-56 eq. 11
#' @keywords internal
svp_kpa <- function(t_c) 0.6108 * exp(17.27 * t_c / (t_c + 237.3))

#' Heat load index (McCune & Keon 2002, as used by Lutz et al. 2010)
#'
#' Scales PET for slope/aspect. Returns ~1 for flat ground at mid latitudes.
#' @param lat Latitude (degrees).
#' @param slope_deg,aspect_deg Slope and aspect (degrees).
#' @export
heat_load_index <- function(lat, slope_deg, aspect_deg) {
  folded <- abs(180 - abs(aspect_deg - 225))
  lat_r <- pmin(lat, 66.7) * pi / 180
  s <- slope_deg * pi / 180
  a <- folded * pi / 180
  0.339 + 0.808 * cos(lat_r) * cos(s) - 0.196 * sin(lat_r) * sin(s) -
    0.482 * cos(a) * sin(s)
}

#' Oudin et al. (2005) temperature/radiation PET
#'
#' PE = Ra / lambda * (T + 5) / 100 for T > -5 C, else 0. As in the NPS WBM,
#' PET is set to 0 when snowpack > `snow_thresh` mm (snow-covered ground).
#' @param snowpack Optional snowpack (mm SWE) series.
#' @param heat_load Multiplier (e.g. `heat_load_index()` x shade coefficient).
#' @param doy Day of year.
#' @param lat Latitude (degrees).
#' @param tmean_c Daily mean temperature (C).
#' @param snow_thresh Snowpack (mm SWE) above which PET is zero.
#' @export
pet_oudin <- function(doy, lat, tmean_c, snowpack = NULL, heat_load = 1, snow_thresh = 2) {
  pe <- ifelse(tmean_c > -5, extraterrestrial_rad(doy, lat) * 0.408 * (tmean_c + 5) / 100, 0)
  if (!is.null(snowpack)) pe[snowpack > snow_thresh] <- 0
  pe * heat_load
}

#' Hamon (1963) PET, in the form given by Lu et al. (2005)
#'
#' FIX: the NPS WBM version used (T + 273.3) inside the exponent of the
#' saturation vapor pressure term; the Tetens form is exp(17.27 T / (T + 237.3)).
#' The typo underestimated PET by roughly 15% at 20 C.
#' @param doy Day of year.
#' @param lat Latitude (degrees).
#' @param tmean_c Daily mean temperature (C).
#' @export
pet_hamon <- function(doy, lat, tmean_c) {
  esat_mb <- 6.108 * exp(17.27 * tmean_c / (tmean_c + 237.3))
  rho_sat <- 216.7 * esat_mb / (tmean_c + 273.3)
  pmax(0.1651 * (daylength_hours(doy, lat) / 12) * rho_sat, 0)
}

#' FAO-56 Penman-Monteith grass reference ET
#'
#' FIX (vs. NPS WBM): uses observed shortwave radiation when supplied (the
#' original always used clear-sky radiation); Tmin is raised to the 4th power
#' in net longwave (the original omitted ^4); actual vapor pressure uses
#' RHmin/RHmax with the correct arguments.
#'
#' @param srad_wm2 Daily mean shortwave (W m-2). If NULL, clear-sky Rso is
#'   used (overestimates PET on cloudy days).
#' @param rhmin_pct,rhmax_pct Relative humidity (%). If NULL, ea = es(Tmin).
#' @param wind_ms Wind speed (m/s); scalar or vector.
#' @param wind_height Measurement height (m). GridMET wind is 10 m.
#' @param doy Day of year.
#' @param lat Latitude (degrees).
#' @param elev_m Elevation (m), for atmospheric pressure.
#' @param tmin_c,tmax_c Daily minimum and maximum temperature (C).
#' @export
pet_penman_monteith <- function(doy, lat, elev_m, tmin_c, tmax_c, srad_wm2 = NULL,
                                rhmin_pct = NULL, rhmax_pct = NULL,
                                wind_ms = 2, wind_height = 2) {
  tmean <- (tmin_c + tmax_c) / 2
  u2 <- wind_ms * 4.87 / log(67.8 * wind_height - 5.42)       # eq. 47
  p <- 101.3 * ((293 - 0.0065 * elev_m) / 293)^5.26           # eq. 7
  gamma <- 0.000665 * p                                        # eq. 8
  delta <- 4098 * svp_kpa(tmean) / (tmean + 237.3)^2           # eq. 13
  es <- (svp_kpa(tmax_c) + svp_kpa(tmin_c)) / 2
  ea <- if (!is.null(rhmin_pct) && !is.null(rhmax_pct)) {
    (svp_kpa(tmin_c) * rhmax_pct / 100 + svp_kpa(tmax_c) * rhmin_pct / 100) / 2  # eq. 17
  } else {
    svp_kpa(tmin_c)
  }
  rso <- (0.75 + 2e-5 * elev_m) * extraterrestrial_rad(doy, lat)  # eq. 37
  rs <- if (!is.null(srad_wm2)) srad_wm2 * 0.0864 else rso         # W m-2 -> MJ m-2 d-1
  rns <- (1 - 0.23) * rs
  rnl <- 4.903e-9 * ((tmax_c + 273.16)^4 + (tmin_c + 273.16)^4) / 2 *
    (0.34 - 0.14 * sqrt(ea)) * (1.35 * pmin(rs / rso, 1) - 0.35)   # eq. 39
  rn <- rns - rnl
  et0 <- (0.408 * delta * rn + gamma * 900 / (tmean + 273) * u2 * (es - ea)) /
    (delta + gamma * (1 + 0.34 * u2))
  pmax(et0, 0)
}
