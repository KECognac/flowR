# GAGES-II ------------------------------------------------------------------------
# Falcone, J.A. (2011) GAGES-II: Geospatial Attributes of Gages for Evaluating
# Streamflow. USGS. https://doi.org/10.5066/P96CPHOT
# CLASS == "Ref" marks basins judged least disturbed (minimal diversions,
# regulation, and development); HCDN_2009 marks the Hydro-Climatic Data
# Network subset of those.

gagesii_point_url <- paste0(
  "https://www.sciencebase.gov/catalog/file/get/631405bbd34e36012efa304a",
  "?f=__disk__53%2Fba%2F17%2F53ba17cfb64d2d50d3876864edf519eb7295945a"
)

#' GAGES-II gauge points with classification attributes
#'
#' Downloads the 9,322-gauge point shapefile (~0.7 MB) on first use.
#'
#' @param dir Directory to store the shapefile.
#' @param ref_only If TRUE, keep only CLASS == "Ref" gauges.
#' @return sf points with site_no, class, ecoregion, drain_sqkm, hcdn_2009, ...
#' @export
get_gagesii_points <- function(dir = wsva_path("raw", "gagesii"),
                               ref_only = FALSE) {
  shp <- file.path(dir, "gagesII_9322_sept30_2011.shp")
  if (!file.exists(shp)) {
    dir.create(dir, showWarnings = FALSE, recursive = TRUE)
    zip <- file.path(dir, "gagesII_9322_point_shapefile.zip")
    utils::download.file(gagesii_point_url, zip, mode = "wb", quiet = TRUE)
    utils::unzip(zip, exdir = dir)
  }
  g <- sf::st_read(shp, quiet = TRUE) %>%
    dplyr::rename_with(tolower) %>%
    dplyr::rename(site_no = staid, station_name = staname,
                  ecoregion = aggecoregi) %>%
    dplyr::mutate(hcdn_2009 = hcdn_2009 %in% "yes",
                  active09 = active09 %in% "yes")
  if (ref_only) g <- dplyr::filter(g, class == "Ref")
  g
}
