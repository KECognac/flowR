# Basins: one object from any flow source -------------------------------------------
# A `wsva_basin` gathers what every model needs about one gauged watershed:
#   id, name           identifier and station name
#   polygon            sf watershed (EPSG:4326)
#   outlet             c(lon, lat) of the gauge
#   area               reference area used for mm/day, its source, the
#                      delineated area and the mismatch (%)
#   flow               standard flow table (R/flow_sources.R) with q_mm
#   forcing            daily basin-mean forcing (after add_forcing())
#   static, hypso,     basin attributes (after add_basin_attributes())
#   landcover
#   provenance         where each piece came from
#
#   b <- wsva_basin_usgs("01154000")
#   b <- wsva_basin(flow_cdss("CCACCRCO"))                       # delineated at the gauge
#   b <- wsva_basin(flow_from_csv("q.csv", q_col = "Q", lon = -105.3, lat = 40.0))
#   b <- wsva_basin(my_flow, polygon = my_watershed_sf)
#   b <- add_forcing(b) |> add_basin_attributes()

#' Build a basin from flow data and a watershed (given or delineated)
#'
#' @param flow Standard flow table (`flow_usgs()`, `flow_cdss()`,
#'   `flow_from_df()`, `flow_from_csv()`).
#' @param polygon Optional sf watershed. If NULL, the watershed is delineated
#'   upstream of `outlet` with `delineate_basin()`.
#' @param outlet Optional c(lon, lat); default from the flow metadata.
#' @param id,name Optional; default from the flow metadata.
#' @param area_km2 Reference drainage area for converting flow to mm/day.
#'   Default: the reported area in the flow metadata, else the published
#'   GAGES-II / USGS area when the station has a USGS id, else the
#'   delineated area.
#' @param delineation,state Passed to `delineate_basin()`.
#' @return A `wsva_basin`.
#' @export
wsva_basin <- function(flow, polygon = NULL, outlet = NULL, id = NULL, name = NULL, area_km2 = NULL,
                       delineation = "auto", state = NULL) {
  stopifnot(inherits(flow, "wsva_flow"))
  m <- flow_meta(flow)
  id <- id %||% m$id
  if (is.null(id) || is.na(id)) stop("Give the basin an `id`")
  name <- name %||% m$name
  outlet <- outlet %||% c(m$lon, m$lat)

  if (is.null(polygon)) {
    if (anyNA(outlet)) stop("No watershed polygon and no outlet location: give `polygon` or `outlet = c(lon, lat)`")
    polygon <- delineate_basin(outlet[1], outlet[2], method = delineation, state = state, id = id)
    basin_method <- polygon$method[1]
  } else {
    polygon <- sf::st_make_valid(sf::st_transform(sf::st_as_sf(polygon), 4326))
    if (nrow(polygon) > 1) polygon <- sf::st_sf(geometry = sf::st_union(polygon))
    basin_method <- "user polygon"
  }
  polygon <- sf::st_sf(id = id, site_no = id, geometry = sf::st_geometry(polygon))
  delineated <- .basin_area_km2(polygon)

  area_src <- "user"
  if (is.null(area_km2) && !is.na(m$reported_area_km2)) { area_km2 <- m$reported_area_km2; area_src <- paste(m$source, "reported area") }
  info <- NULL
  if (!is.na(m$usgs_site_no %||% NA)) info <- tryCatch(gauge_info(m$usgs_site_no), error = function(e) NULL)
  if (is.null(area_km2) && !is.null(info) && !is.na(info$ref_area_km2)) { area_km2 <- info$ref_area_km2; area_src <- info$ref_area_source }
  if (is.null(area_km2)) { area_km2 <- delineated; area_src <- "delineated basin" }
  err <- 100 * (delineated - area_km2) / area_km2
  if (abs(err) > 20)
    warning(id, ": delineated basin (", round(delineated, 1), " km2) differs from the reference area (",
            round(area_km2, 1), " km2) by ", round(err), "%; check the outlet location", call. = FALSE)

  structure(list(
    id = id, name = name, polygon = polygon, outlet = outlet,
    area = list(reference_km2 = area_km2, reference_source = area_src, delineated_km2 = delineated, err_pct = err),
    flow = flow_to_mm(flow, area_km2),
    screening = if (!is.null(info)) info[, c("gagesii_class", "hcdn_2009")] else NULL,
    provenance = list(flow = m$source, basin = basin_method, usgs_site_no = m$usgs_site_no %||% NA)
  ), class = "wsva_basin")
}

#' Basin for a USGS gauge: USGS flow and the NLDI basin for the site
#'
#' @param site_no USGS site number.
#' @param start,end Flow period.
#' @return A `wsva_basin`.
#' @export
wsva_basin_usgs <- function(site_no, start = wsva_default_period()$start, end = wsva_default_period()$end) {
  site_no <- usgs_site_no(site_no)
  info <- gauge_info(site_no)
  flow <- flow_usgs(site_no, start, end)
  m <- attr(flow, "flow_meta")
  m$name <- info$name %||% m$name
  m$reported_area_km2 <- NA_real_                  # use the published (CAMELS / GAGES-II) area below
  attr(flow, "flow_meta") <- m
  b <- wsva_basin(flow, polygon = get_gauge_basin(site_no), outlet = c(info$lon, info$lat),
                  area_km2 = if (!is.na(info$ref_area_km2)) info$ref_area_km2 else NULL)
  b$provenance$basin <- "NLDI basin for the USGS site"
  b$area$reference_source <- info$ref_area_source %||% b$area$reference_source
  b
}

#' @export
print.wsva_basin <- function(x, ...) {
  cat(sprintf("<wsva_basin> %s %s\n", x$id, x$name %||% ""))
  cat(sprintf("  flow: %s, %s to %s, %.0f%% observed\n", x$provenance$flow, min(x$flow$date), max(x$flow$date),
              100 * mean(!is.na(x$flow$q_mm))))
  cat(sprintf("  watershed: %s, %.1f km2 (reference %.1f km2 from %s, %+.1f%%)\n", x$provenance$basin,
              x$area$delineated_km2, x$area$reference_km2, x$area$reference_source, x$area$err_pct))
  cat("  forcing:", if (is.null(x$forcing)) "not added" else paste(x$forcing_source, paste(range(x$forcing$date), collapse = " to ")), "\n")
  cat("  attributes:", if (is.null(x$static)) "not added" else "added", "\n")
  invisible(x)
}

#' Add daily basin-mean climate forcing
#'
#' @param basin A `wsva_basin`.
#' @param source Forcing source; currently "gridmet".
#' @param start,end Forcing period.
#' @return `basin` with `forcing` (forcing contract columns, R/forcing.R).
#' @export
add_forcing <- function(basin, source = "gridmet", start = wsva_default_period()$start,
                        end = wsva_default_period()$end) {
  source <- match.arg(source, "gridmet")
  years <- seq(as.integer(format(as.Date(start), "%Y")), as.integer(format(as.Date(end), "%Y")))
  nc_ok <- all(file.exists(wsva_path("raw", "gridmet_conus", sprintf("pr_%d.nc", years))))
  if (nc_ok) {
    extract_gridmet_bulk(basin$polygon, years = years)
    gm <- read_gridmet_bulk(basin$id, start, end)
    basin$forcing_source <- "GridMET (national files)"
  } else {
    gm <- get_gridmet_cells(basin$polygon, start = start, end = end)
    basin$forcing_source <- "GridMET (climateR)"
  }
  basin$forcing <- gridmet_basin_mean(gm)
  basin
}

#' Add basin attributes from public datasets
#'
#' Terrain and hypsometry (3DEP via elevatr), soil water storage (gNATSGO),
#' the Jennings rain/snow threshold, NLCD land cover and crop coefficients.
#'
#' @param basin A `wsva_basin`.
#' @param soil_depth_cm Soil profile depth for `swc_max_mm` (100 or 150).
#' @param nlcd_year NLCD year.
#' @return `basin` with `static`, `hypso`, `landcover`.
#' @export
add_basin_attributes <- function(basin, soil_depth_cm = 150, nlcd_year = 2019) {
  lc <- get_basin_landcover(basin$polygon, year = nlcd_year)
  basin$landcover <- lc
  basin$static <- get_basin_static(basin$polygon, soil_depth_cm = soil_depth_cm) %>%
    dplyr::mutate(area_km2 = basin$area$reference_km2) %>%
    dplyr::bind_cols(basin_kc(lc))
  basin$hypso <- get_basin_hypsometry(basin$polygon)
  basin
}

#' Example basin: Clear Creek above Clear Creek Reservoir, Colorado
#'
#' A ready-to-fit `wsva_basin` (flow, GridMET forcing and attributes already
#' added) for examples and vignettes, so they run without downloads. Clear
#' Creek (CDSS station CCACCRCO; USGS 07086500 until 1995, operated by the
#' Colorado Division of Water Resources since) is a 174 km2, snowmelt-
#' dominated GAGES-II Reference basin in the Sawatch Range. Water years
#' 2000-2016. Built by `data-raw/example_basin.R` in the source repository.
#'
#' @return A `wsva_basin`.
#' @export
#' @examples
#' b <- example_basin()
#' b
#' check_basin(b)
example_basin <- function() readRDS(wsva_extdata("example_clear_creek.rds"))
