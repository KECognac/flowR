# Model-ready inputs for a gauge ------------------------------------------------------
# prepare_basin() turns a USGS site number or any `wsva_basin` (R/basin.R)
# into the files the models and notebooks read:
#   <wsva.data_dir>/processed/<id>/daily.parquet   forcing + observed flow
#                                  static.csv      WBM site parameters + Kc
#                                  hypsometry.csv  101 elevation quantiles
#                                  gauge_info.csv  provenance and checks
#
# Reference area for a USGS gauge (used to convert flow to mm/day), in order
# of preference: GAGES-II DRAIN_SQKM (the area CAMELS also uses) -> USGS
# site drainage area -> delineated basin.

#' What is known about a USGS gauge: name, GAGES-II screening, reference area
#'
#' @param site_no USGS site number.
#' @return One-row tibble: site_no, name, gagesii_class (NA if not in
#'   GAGES-II), hcdn_2009, ref_area_km2, ref_area_source, lat, lon.
#' @export
gauge_info <- function(site_no) {
  site_no <- usgs_site_no(site_no)
  out <- tibble::tibble(site_no = site_no, name = NA_character_,
                        gagesii_class = NA_character_, hcdn_2009 = NA,
                        ref_area_km2 = NA_real_, ref_area_source = NA_character_,
                        lat = NA_real_, lon = NA_real_)
  g2 <- tryCatch(get_gagesii_points(), error = function(e) NULL)
  if (!is.null(g2)) {
    i <- match(site_no, g2$site_no)
    if (!is.na(i)) {
      out$gagesii_class <- g2$class[i]; out$hcdn_2009 <- g2$hcdn_2009[i]
      if (is.na(out$name)) out$name <- g2$station_name[i]
      if (is.na(out$ref_area_km2)) {
        out$ref_area_km2 <- g2$drain_sqkm[i]; out$ref_area_source <- "GAGES-II"
      }
      if (is.na(out$lat)) { xy <- sf::st_coordinates(sf::st_transform(g2[i, ], 4326)); out$lon <- xy[1]; out$lat <- xy[2] }
    }
  }
  if (is.na(out$name) || is.na(out$ref_area_km2)) {
    u <- tryCatch(list_usgs_gauges(sites = site_no), error = function(e) NULL)
    if (!is.null(u) && nrow(u)) {
      if (is.na(out$name)) out$name <- u$name[1]
      if (is.na(out$ref_area_km2) && !is.na(u$drainage_area_km2[1])) {
        out$ref_area_km2 <- u$drainage_area_km2[1]; out$ref_area_source <- "USGS site drainage area"
      }
      if (is.na(out$lat)) { xy <- sf::st_coordinates(u[1, ]); out$lon <- xy[1]; out$lat <- xy[2] }
    }
  }
  out
}

#' Build the processed model inputs for one gauge
#'
#' @param x A USGS site number, or a `wsva_basin` from `wsva_basin()` (any
#'   flow source).
#' @param start,end Study period (default `wsva_default_period()`).
#' @param soil_depth_cm Soil profile depth for `swc_max_mm` (100 or 150).
#' @param overwrite Rebuild files that already exist.
#' @return list(info, basin (sf polygon), daily, static, hypso). `info` has
#'   id, name, flow_source, basin_method, gagesii_class,
#'   hcdn_2009, ref_area_km2, ref_area_source, delineated_area_km2,
#'   area_err_pct, gridmet_source, lon, lat.
#' @export
prepare_basin <- function(x, start = wsva_default_period()$start, end = wsva_default_period()$end,
                          soil_depth_cm = 150, overwrite = FALSE) {
  b <- if (inherits(x, "wsva_basin")) x else wsva_basin_usgs(x, start, end)
  out_dir <- wsva_path("processed", b$id)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  f <- function(x) file.path(out_dir, x)

  gridmet_source <- "cached"
  if (overwrite || !file.exists(f("daily.parquet"))) {
    b <- add_forcing(b, start = start, end = end)
    gridmet_source <- b$forcing_source
    daily <- b$forcing %>%
      dplyr::left_join(dplyr::transmute(b$flow, date, q_cms, q_cfs = q_cms / .cfs_to_cms, q_mm, flag), by = "date") %>%
      dplyr::mutate(site_no = b$id, wy = calc_water_year(date), .before = 1)
    arrow::write_parquet(daily, f("daily.parquet"))
  }
  if (overwrite || !file.exists(f("static.csv")) || !file.exists(f("hypsometry.csv"))) {
    b <- add_basin_attributes(b, soil_depth_cm = soil_depth_cm)
    readr::write_csv(b$static, f("static.csv"))
    readr::write_csv(tibble::tibble(pct = 0:100, elev_m = b$hypso), f("hypsometry.csv"))
    readr::write_csv(b$landcover, f("landcover.csv"))
  }
  scr <- b$screening %||% tibble::tibble(gagesii_class = NA_character_, hcdn_2009 = NA)
  info <- dplyr::bind_cols(
    tibble::tibble(id = b$id, name = b$name %||% NA_character_, flow_source = b$provenance$flow,
                   basin_method = b$provenance$basin),
    scr,
    tibble::tibble(ref_area_km2 = b$area$reference_km2, ref_area_source = b$area$reference_source,
                   delineated_area_km2 = b$area$delineated_km2, area_err_pct = b$area$err_pct,
                   gridmet_source = gridmet_source, lon = b$outlet[1], lat = b$outlet[2]))
  readr::write_csv(info, f("gauge_info.csv"))
  c(list(info = info, basin = b$polygon), read_basin_inputs(b$id))
}
