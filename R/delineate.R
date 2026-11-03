# Watershed delineation from an outlet point ----------------------------------------
# Two methods, for gauges that are not (or not only) USGS sites:
#
#   "streamstats"  USGS StreamStats delineation service (state DEM-based
#                  flow-direction grids, snapped to the nearest stream). Most
#                  accurate; available in states with a StreamStats
#                  application.
#   "nldi"         NHDPlusV2 via the NLDI: the catchment containing the point
#                  is split at the point if the split-catchment service
#                  responds; otherwise the whole upstream basin to the bottom
#                  of that catchment is returned (slightly too large) with a
#                  warning.
#
# Always compare the delineated area with a reported drainage area when one
# exists: a large mismatch usually means the point snapped to the wrong
# stream (e.g. a tributary at a confluence).

#' Delineate the watershed upstream of an outlet point
#'
#' @param lon,lat Outlet location (decimal degrees, WGS84).
#' @param method "streamstats" (default) or "nldi". With "auto", StreamStats
#'   is tried first and NLDI is the fallback.
#' @param state Two-letter state code for StreamStats; looked up from the
#'   point (US Census geocoder) if NULL.
#' @param id Identifier stored with the basin and used for the cache file.
#' @param cache_dir Directory for cached GeoPackages. NULL disables caching.
#' @param timeout Seconds to wait for StreamStats.
#' @return sf polygon (EPSG:4326) with id, area_km2, method, outlet_lon,
#'   outlet_lat (the snapped outlet).
#' @export
delineate_basin <- function(lon, lat, method = c("auto", "streamstats", "nldi"), state = NULL,
                            id = sprintf("pt_%.5f_%.5f", lon, lat),
                            cache_dir = wsva_path("raw", "basins"), timeout = 180) {
  method <- match.arg(method)
  stopifnot(is.finite(lon), is.finite(lat))
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, paste0(id, "_basin.gpkg"))
  if (!is.null(cache_file) && file.exists(cache_file)) return(sf::st_read(cache_file, quiet = TRUE))

  basin <- switch(method,
    streamstats = .delineate_streamstats(lon, lat, state, timeout),
    nldi = .delineate_nldi(lon, lat),
    auto = tryCatch(.delineate_streamstats(lon, lat, state, timeout), error = function(e) {
      message("StreamStats delineation failed (", conditionMessage(e), "); using NLDI")
      .delineate_nldi(lon, lat)
    }))
  how <- attr(basin, "method"); outlet <- attr(basin, "outlet")    # sf operations drop attributes
  geom <- sf::st_make_valid(sf::st_transform(basin, 4326))
  basin <- sf::st_sf(id = id, area_km2 = as.numeric(sf::st_area(geom)) / 1e6, method = how,
                     outlet_lon = outlet[1], outlet_lat = outlet[2], geometry = geom)
  if (!is.null(cache_file)) {
    dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
    sf::st_write(basin, cache_file, quiet = TRUE, delete_dsn = TRUE)
  }
  basin
}

# Two-letter state code for a point (US Census geocoder)
.state_of_point <- function(lon, lat) {
  url <- sprintf(paste0("https://geocoding.geo.census.gov/geocoder/geographies/coordinates?",
                        "x=%.6f&y=%.6f&benchmark=Public_AR_Current&vintage=Current_Current",
                        "&layers=States&format=json"), lon, lat)
  j <- .fetch_json(url, timeout = 60)
  st <- j$result$geographies$States
  if (!length(st)) stop("Point is not inside a US state")
  st[[1]]$STUSAB
}

.fetch_json <- function(url, timeout = 60) {
  if (!requireNamespace("curl", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE))
    stop("Delineation needs the curl and jsonlite packages")
  h <- curl::new_handle(timeout = timeout, connecttimeout = 30)
  r <- curl::curl_fetch_memory(url, handle = h)
  if (r$status_code != 200) stop("HTTP ", r$status_code, " from ", sub("\\?.*", "", url))
  jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE)
}

.delineate_streamstats <- function(lon, lat, state, timeout) {
  state <- toupper(state %||% .state_of_point(lon, lat))
  url <- sprintf("https://streamstats.usgs.gov/ss-delineate/v1/delineate/sshydro/%s?lat=%.6f&lon=%.6f",
                 state, lat, lon)
  j <- .fetch_json(url, timeout = timeout)
  fc <- j$bcrequest$wsresp$featurecollection
  if (is.null(fc) || !length(fc)) stop("no watershed returned")
  fc <- fc[[1]]
  part <- function(name) {
    i <- which(vapply(fc, function(x) identical(x$name, name), logical(1)))
    if (!length(i)) stop("response has no '", name, "'")
    sf::st_read(jsonlite::toJSON(fc[[i]]$feature, auto_unbox = TRUE, digits = NA), quiet = TRUE)
  }
  ws <- part("globalwatershed")
  outlet <- sf::st_coordinates(sf::st_transform(part("globalwatershedpoint"), 4326))[1, 1:2]
  ws <- sf::st_union(ws)
  attr(ws, "method") <- paste0("StreamStats (", state, ")")
  attr(ws, "outlet") <- outlet
  ws
}

.delineate_nldi <- function(lon, lat) {
  pt <- sf::st_sfc(sf::st_point(c(lon, lat)), crs = 4326)
  split <- tryCatch(suppressMessages(nhdplusTools::get_split_catchment(pt, upstream = TRUE)),
                    error = function(e) NULL)
  if (!is.null(split) && "drainageBasin" %in% split$id) {
    ws <- sf::st_geometry(split[split$id == "drainageBasin", ])
    attr(ws, "method") <- "NLDI split catchment"
  } else {
    comid <- nhdplusTools::discover_nhdplus_id(pt)
    if (!length(comid) || is.na(comid)) stop("No NHDPlus flowline found near the point")
    ws <- sf::st_geometry(nhdplusTools::get_nldi_basin(list(featureSource = "comid", featureID = as.character(comid))))
    attr(ws, "method") <- "NLDI catchment outlet"
    warning("NLDI split-catchment service unavailable: basin runs to the bottom of NHDPlus catchment ",
            comid, " and may be slightly larger than the true basin")
  }
  attr(ws, "outlet") <- c(lon, lat)
  ws
}
