# Static basin attributes for regional models -------------------------------------
# Every attribute here can be computed for an ungauged basin: they come from
# GridMET forcing, the DEM, NLCD, the soil-storage raster, and NHDPlusV2
# accumulated soil attributes. Nothing is derived from observed streamflow
# (e.g. NHDPlus TOT_BFI is excluded: it is interpolated from gauge-based
# baseflow estimates).

nhd_soil_vars <- c("TOT_SANDAVE", "TOT_CLAYAVE", "TOT_PERMAVE", "TOT_AWCAVE", "TOT_ROCKDEP",
                   "TOT_WTDEP", "TOT_HGA", "TOT_HGB", "TOT_HGC", "TOT_HGD")

#' NHDPlusV2 accumulated soil attributes for a gauge's upstream basin
#' @return One-row tibble named by lower-case attribute id (NA for no data).
get_basin_soils <- function(site_no, cache_dir = wsva_path("raw", "nhd_attributes")) {
  site_no <- usgs_site_no(site_no)
  f <- file.path(cache_dir, paste0(site_no, "_soils.csv"))
  if (file.exists(f)) return(readr::read_csv(f, show_col_types = FALSE))
  comid <- nhdplusTools::get_nldi_feature(list(featureSource = "nwissite", featureID = usgs_id(site_no)))$comid
  x <- suppressWarnings(nhdplusTools::get_catchment_characteristics(varname = nhd_soil_vars, ids = as.integer(comid)))
  v <- as.numeric(x$characteristic_value)
  v[v < -9000] <- NA
  out <- tibble::as_tibble(as.list(stats::setNames(v, tolower(x$characteristic_id))))
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(out, f)
  out
}

#' Climate indices from daily basin-mean forcing
#' @param daily Daily tibble with date, prcp_mm, tmean_c, pet_ref_mm.
basin_climate_indices <- function(daily) {
  p <- daily$prcp_mm
  mo <- as.integer(format(daily$date, "%m"))
  p_mean <- mean(p)
  tibble::tibble(
    p_mean = p_mean,                                         # mm/day
    pet_mean = mean(daily$pet_ref_mm),                       # GridMET grass ETo, mm/day
    aridity = mean(daily$pet_ref_mm) / p_mean,
    t_mean = mean(daily$tmean_c),
    frac_snow = sum(p[daily$tmean_c < 0]) / sum(p),          # precipitation on sub-freezing days
    p_seasonality = (mean(p[mo %in% 6:8]) - mean(p[mo %in% c(12, 1, 2)])) / p_mean,
    high_prec_freq = 365.25 * mean(p >= 5 * p_mean),         # days/yr
    low_prec_freq = 365.25 * mean(p < 1)                     # days/yr
  )
}

#' Land-cover fractions (%) grouped from NLCD 2019 classes
basin_landcover_groups <- function(landcover) {
  g <- function(codes) sum(landcover$pct[landcover$nlcd_code %in% codes])
  tibble::tibble(lc_forest = g(41:43), lc_shrub = g(52), lc_herb = g(c(71, 81)),
                 lc_crop = g(82), lc_developed = g(21:24), lc_water_wetland = g(c(11, 90, 95)),
                 lc_barren_ice = g(c(12, 31)))
}

#' All static attributes for one basin
#'
#' @param site_no Gauge id (its data must already be prepared).
#' @param daily Basin-mean daily forcing (for climate indices).
#' @return One-row tibble.
basin_attributes <- function(site_no, daily) {
  p <- function(f) wsva_path("processed", site_no, f)
  static <- readr::read_csv(p("static.csv"), show_col_types = FALSE)
  hyps <- readr::read_csv(p("hypsometry.csv"), show_col_types = FALSE)$elev_m
  dplyr::bind_cols(
    tibble::tibble(site_no = site_no),
    basin_climate_indices(daily),
    tibble::tibble(elev_mean = static$elev_m, elev_range = hyps[91] - hyps[11],   # 10th-90th pct
                   slope_mean = static$slope_deg, log_area = log(static$area_km2),
                   swc_max_mm = static$swc_max_mm, kc_dormant = static$kc_dormant,
                   kc_growing = static$kc_growing, jtemp_c = static$jtemp_c),
    basin_landcover_groups(if (file.exists(p("landcover.csv"))) readr::read_csv(p("landcover.csv"), show_col_types = FALSE)
                           else get_basin_landcover(get_gauge_basin(site_no))),
    get_basin_soils(site_no)
  )
}
