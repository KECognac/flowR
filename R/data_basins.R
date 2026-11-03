# Basin boundaries ------------------------------------------------------------------

#' Upstream basin for a USGS gauge from the NLDI
#'
#' Uses the Network-Linked Data Index (NHDPlusV2-based) basin for the gauge.
#' Compare `area_km2` to the GAGES-II / USGS drainage area as a sanity check:
#' a large mismatch usually means the gauge is snapped to the wrong flowline.
#'
#' @param site_no Site number (with or without "USGS-").
#' @param cache_dir Directory for cached GeoPackages. NULL disables caching.
#' @return sf polygon (EPSG:4326) with site_no and area_km2.
#' @export
get_gauge_basin <- function(site_no, cache_dir = wsva_path("raw", "basins")) {
  site_no <- usgs_site_no(site_no)
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, paste0(site_no, "_basin.gpkg"))
  if (!is.null(cache_file) && file.exists(cache_file)) {
    return(sf::st_read(cache_file, quiet = TRUE))
  }

  basin <- nhdplusTools::get_nldi_basin(
    nldi_feature = list(featureSource = "nwissite", featureID = usgs_id(site_no))
  ) %>%
    sf::st_make_valid() %>%
    sf::st_transform(4326) %>%
    dplyr::mutate(site_no = site_no, .before = 1)
  basin$area_km2 <- as.numeric(sf::st_area(basin)) / 1e6

  if (!is.null(cache_file)) {
    dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
    sf::st_write(basin, cache_file, quiet = TRUE, delete_dsn = TRUE)
  }
  basin
}
