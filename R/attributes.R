# Basin attributes from public national datasets ------------------------------------
# Everything here works for any basin polygon (USGS gauge, delineated point,
# or a user's own watershed) and is cached per basin id:
#
#   Elevation, slope, aspect, hypsometry  AWS Terrain Tiles via elevatr
#                                         (USGS 3DEP in the US), ~60 m for
#                                         basins < 2,000 km2
#   Soil water storage (swc_max_mm)       gNATSGO (SSURGO, gap-filled with
#                                         STATSGO2) via soilDB: 30 m map-unit
#                                         grid + available water storage
#                                         (muaggatt aws0100wta / aws0150wta)
#   Rain/snow threshold (jtemp_c)         Jennings et al. 2018 (Dryad,
#                                         doi:10.5061/dryad.c9h35, CC0),
#                                         shipped in inst/extdata
#   Land cover (Kc)                       NLCD via FedData (MRLC services)
#
# Jennings, K.S., Winchell, T.S., Livneh, B., Molotch, N.P. (2018) Spatial
#   variation of the rain-snow temperature threshold across the Northern
#   Hemisphere. Nat. Commun. 9, 1148.

.albers <- "EPSG:5070"

#' Identifier of a basin polygon (`id`, else `site_no`)
#' @param basin sf polygon from `get_gauge_basin()`, `delineate_basin()` or a user.
#' @export
basin_id <- function(basin) {
  id <- if ("id" %in% names(basin)) basin$id else if ("site_no" %in% names(basin)) basin$site_no else NULL
  if (is.null(id) || is.na(id[1])) stop("Basin needs an `id` (or `site_no`) column")
  as.character(id[1])
}

.cache_file <- function(kind, id, ext) {
  d <- wsva_path("raw", kind)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  file.path(d, paste0(id, ext))
}

.basin_area_km2 <- function(basin) as.numeric(sf::st_area(sf::st_transform(basin, .albers)))[1] / 1e6

#' Digital elevation model for a basin (cached GeoTIFF, CONUS Albers)
#'
#' @param basin sf polygon.
#' @param z elevatr zoom level; default by basin area (10: ~60 m below
#'   2,000 km2; 9: ~120 m below 20,000 km2; 8 above).
#' @return SpatRaster (m) covering the basin plus a 2 km buffer.
#' @export
basin_dem <- function(basin, z = NULL) {
  if (!requireNamespace("elevatr", quietly = TRUE)) stop("basin_dem() needs the elevatr package")
  f <- .cache_file("dem", basin_id(basin), ".tif")
  if (file.exists(f)) return(terra::rast(f))
  b <- sf::st_transform(basin, .albers)
  a <- .basin_area_km2(b)
  z <- z %||% if (a < 2000) 10 else if (a < 20000) 9 else 8
  dem <- suppressMessages(elevatr::get_elev_raster(sf::st_buffer(b, 2000), z = z, src = "aws",
                                                   clip = "bbox", verbose = FALSE, prj = .albers))
  dem <- terra::rast(dem)
  names(dem) <- "elev_m"
  terra::writeRaster(dem, f, overwrite = TRUE)
  terra::rast(f)
}

#' Basin hypsometry: 101 area-weighted elevation quantiles (min, 1%, ..., max)
#'
#' @param basin sf polygon (single feature).
#' @param dem SpatRaster of elevation (m); default `basin_dem(basin)`.
#' @return Numeric vector of length 101, as required by airGR's HypsoData.
#' @export
get_basin_hypsometry <- function(basin, dem = basin_dem(basin)) {
  v <- exactextractr::exact_extract(dem, sf::st_transform(basin, terra::crs(dem)), progress = FALSE)[[1]]
  v <- v[!is.na(v$value), ]
  o <- order(v$value)
  z <- v$value[o]
  w <- cumsum(v$coverage_fraction[o]) / sum(v$coverage_fraction)
  q <- vapply(seq(0, 1, by = 0.01), function(p) z[which(w >= p)[1]], numeric(1))
  q[1] <- min(z); q[101] <- max(z)
  q
}

#' Basin-mean elevation, slope and (circular-mean) aspect
#'
#' @param basin sf polygon.
#' @param dem SpatRaster of elevation (m).
#' @return One-row tibble: elev_m, slope_deg, aspect_deg.
#' @export
basin_terrain <- function(basin, dem = basin_dem(basin)) {
  b <- sf::st_transform(basin, terra::crs(dem))
  slope <- terra::terrain(dem, v = "slope", unit = "degrees", neighbors = 8)
  aspect <- terra::terrain(dem, v = "aspect", unit = "degrees")
  asp <- exactextractr::exact_extract(aspect, b, progress = FALSE)[[1]]
  asp <- asp[!is.na(asp$value), ]
  w <- asp$coverage_fraction / sum(asp$coverage_fraction)
  asp_mean <- (atan2(sum(sin(asp$value * pi / 180) * w), sum(cos(asp$value * pi / 180) * w)) * 180 / pi + 360) %% 360
  tibble::tibble(elev_m = exactextractr::exact_extract(dem, b, "mean", progress = FALSE),
                 slope_deg = exactextractr::exact_extract(slope, b, "mean", progress = FALSE),
                 aspect_deg = asp_mean)
}

#' Soil available water storage from gNATSGO (SSURGO + STATSGO2)
#'
#' Map units come from the gNATSGO 30 m grid (`soilDB::mukey.wcs()`); each
#' map unit's component-weighted available water storage (`muaggatt`
#' aws0100wta, aws0150wta, in cm, already truncated at bedrock) comes from
#' Soil Data Access and is area-weighted over the basin. Map units without a
#' value (water, rock outcrop, urban land) are left out of the mean, and
#' their share is reported.
#'
#' @param basin sf polygon.
#' @param res Grid resolution (m); default 30 m, coarser for large basins so
#'   the web request stays small.
#' @return One-row tibble: aws0100_mm, aws0150_mm, soil_frac_with_data.
#' @export
basin_soil_storage <- function(basin, res = NULL) {
  if (!requireNamespace("soilDB", quietly = TRUE)) stop("basin_soil_storage() needs the soilDB package")
  f <- .cache_file("soils", basin_id(basin), "_aws.csv")
  if (file.exists(f)) return(readr::read_csv(f, show_col_types = FALSE))
  b <- sf::st_transform(basin, .albers)
  a <- .basin_area_km2(b)
  res <- res %||% if (a < 1500) 30 else if (a < 15000) 90 else 270
  mk <- suppressMessages(soilDB::mukey.wcs(aoi = b, db = "gNATSGO", res = res, quiet = TRUE))
  levels(mk) <- NULL
  cells <- exactextractr::exact_extract(mk, b, progress = FALSE)[[1]]
  cells <- cells[!is.na(cells$value), ]
  w <- tapply(cells$coverage_fraction, cells$value, sum)
  keys <- names(w)
  aws <- dplyr::bind_rows(lapply(split(keys, ceiling(seq_along(keys) / 1000)), function(k)
    suppressMessages(soilDB::SDA_query(sprintf(
      "SELECT mukey, aws0100wta, aws0150wta FROM muaggatt WHERE mukey IN (%s)", paste(k, collapse = ","))))))
  aws$mukey <- as.character(aws$mukey)
  x <- tibble::tibble(mukey = keys, w = as.numeric(w)) %>% dplyr::left_join(aws, by = "mukey")
  wm <- function(v) { ok <- !is.na(v); sum(v[ok] * x$w[ok]) / sum(x$w[ok]) }
  out <- tibble::tibble(aws0100_mm = 10 * wm(x$aws0100wta), aws0150_mm = 10 * wm(x$aws0150wta),
                        soil_frac_with_data = sum(x$w[!is.na(x$aws0150wta)]) / sum(x$w))
  readr::write_csv(out, f)
  out
}

#' Basin-mean rain/snow temperature threshold (Jennings et al. 2018)
#'
#' @param basin sf polygon.
#' @param path The Jennings 50% rain-snow threshold raster
#'   (`jennings_et_al_2018_file4_temp50_raster.tif` on Dryad). Default: the
#'   copy shipped in `inst/extdata`, or `getOption("wsva.jennings_path")`.
#' @return Threshold (deg C).
#' @export
basin_jennings <- function(basin, path = getOption("wsva.jennings_path",
                                                   system.file("extdata", "jennings2018_temp50.tif", package = "WSVAflowR"))) {
  if (!nzchar(path) || !file.exists(path))
    stop("Jennings et al. (2018) raster not found. Download ",
         "'jennings_et_al_2018_file4_temp50_raster.tif' from https://doi.org/10.5061/dryad.c9h35 ",
         "and save it as inst/extdata/jennings2018_temp50.tif", call. = FALSE)
  jt <- terra::rast(path)[[1]]
  if (is.na(terra::crs(jt)) || terra::crs(jt) == "") terra::crs(jt) <- "EPSG:4326"
  exactextractr::exact_extract(jt, sf::st_transform(basin, terra::crs(jt)), "mean", progress = FALSE)
}

#' NLCD land-cover percentages over a basin polygon
#'
#' @param basin sf polygon.
#' @param year NLCD year (2019 matches the Kc table's land-cover basis).
#' @return Tibble: nlcd_code, pct (sums to ~100).
#' @export
get_basin_landcover <- function(basin, year = 2019) {
  if (!requireNamespace("FedData", quietly = TRUE)) stop("get_basin_landcover() needs the FedData package")
  id <- basin_id(basin)
  f <- .cache_file("landcover", id, sprintf("_nlcd%d.csv", year))
  if (file.exists(f)) return(readr::read_csv(f, show_col_types = FALSE))
  nl <- suppressMessages(FedData::get_nlcd(template = basin, label = id, year = year,
                                           extraction.dir = wsva_path("raw", "nlcd"), force.redo = TRUE))
  levels(nl) <- NULL
  fr <- unlist(exactextractr::exact_extract(nl, sf::st_transform(basin, terra::crs(nl)), "frac", progress = FALSE))
  lc <- tibble::tibble(nlcd_code = as.integer(sub("frac_", "", names(fr))), pct = 100 * as.numeric(fr)) %>%
    dplyr::filter(nlcd_code %in% nlcd_codes) %>%
    dplyr::arrange(nlcd_code)
  readr::write_csv(lc, f)
  lc
}

#' Basin-mean static parameters for `wbm_run()` from public datasets
#'
#' @param basin sf polygon with an `id` or `site_no` column.
#' @param soil_depth_cm Depth of the available-water-storage profile that
#'   sets `swc_max_mm`: 100 or 150.
#' @return One-row tibble: id, lat, lon, elev_m, slope_deg, aspect_deg,
#'   swc_max_mm, jtemp_c, aws0100_mm, aws0150_mm, soil_frac_with_data.
#' @export
get_basin_static <- function(basin, soil_depth_cm = 150) {
  stopifnot(nrow(basin) == 1, soil_depth_cm %in% c(100, 150))
  centroid <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(sf::st_transform(basin, 4326))))
  soil <- basin_soil_storage(basin)
  dplyr::bind_cols(
    tibble::tibble(id = basin_id(basin), lat = centroid[1, "Y"], lon = centroid[1, "X"]),
    basin_terrain(basin),
    tibble::tibble(swc_max_mm = soil[[sprintf("aws%04d_mm", soil_depth_cm)]],
                   jtemp_c = basin_jennings(basin)),
    soil
  )
}
