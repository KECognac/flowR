# GridMET forcing -------------------------------------------------------------------
# Abatzoglou (2013), 1/24 degree (~4 km) daily, 1979-present, via climateR.
# Values are cached per grid cell (not only as a basin mean) so the same
# download feeds lumped models now and distributed models later.
#
# Note on timing: a GridMET "day" is the 24 h ending ~12 UTC for
# precipitation, while USGS daily means are local calendar days. Routing
# models absorb this with a lag/delay parameter; keep it in mind for ML
# sequence alignment.

# GridMET short names -> flowR column names and unit conversions
gridmet_vars <- tibble::tribble(
  ~gridmet, ~flowr,        ~convert,
  "pr",     "prcp_mm",     function(x) x,
  "tmmn",   "tmin_c",      function(x) x - 273.15,
  "tmmx",   "tmax_c",      function(x) x - 273.15,
  "srad",   "srad_wm2",    function(x) x,
  "vs",     "wind_ms",     function(x) x,
  "rmin",   "rhmin_pct",   function(x) x,
  "rmax",   "rhmax_pct",   function(x) x,
  "sph",    "sph_kgkg",    function(x) x,
  "pet",    "pet_ref_mm",  function(x) x   # ASCE Penman-Monteith grass reference ET
)

#' Cell-level GridMET for a basin, cached in multi-year chunks
#'
#' @param basin sf polygon (single feature) with a site_no column.
#' @param start,end Date bounds.
#' @param vars GridMET short names (see `gridmet_vars`).
#' @param chunk_years Years per request/cache file.
#' @param cache_dir Directory for parquet chunks (one subfolder per site).
#' @return list(cells = cell weights table, data = long tibble of
#'   cell x date values in flowR units).
#' @export
get_gridmet_cells <- function(basin, start = "1980-10-01", end = "2024-09-30",
                              vars = c("pr", "tmmn", "tmmx", "srad", "vs", "rmin", "rmax", "pet"),
                              chunk_years = 5,
                              cache_dir = wsva_path("raw", "gridmet")) {

  stopifnot(nrow(basin) == 1)
  site_dir <- file.path(cache_dir, basin$site_no)
  dir.create(site_dir, showWarnings = FALSE, recursive = TRUE)
  start <- as.Date(start); end <- as.Date(end)

  chunk_starts <- seq(start, end, by = paste(chunk_years, "years"))
  chunk_ends <- pmin(c(chunk_starts[-1] - 1, end), end)

  cell_file <- file.path(site_dir, "cells.csv")
  out <- vector("list", length(chunk_starts))

  for (i in seq_along(chunk_starts)) {
    f <- file.path(site_dir, sprintf("gridmet_%s_%s.parquet", chunk_starts[i], chunk_ends[i]))
    if (file.exists(f)) {
      out[[i]] <- arrow::read_parquet(f)
      next
    }
    message(basin$site_no, ": GridMET ", chunk_starts[i], " to ", chunk_ends[i])
    r <- climateR::getGridMET(AOI = basin, varname = vars,
                              startDate = as.character(chunk_starts[i]),
                              endDate = as.character(chunk_ends[i]))

    # Cells touching the basin, weighted by covered area (fraction x cell area)
    if (!file.exists(cell_file)) {
      template <- r[[1]][[1]]
      cov <- exactextractr::exact_extract(template, sf::st_transform(basin, terra::crs(template)),
                                          include_cell = TRUE, include_xy = TRUE,
                                          progress = FALSE)[[1]]
      cell_area <- terra::cellSize(template, unit = "km")[cov$cell][, 1]
      cells <- tibble::tibble(cell = cov$cell, x = cov$x, y = cov$y,
                              coverage_fraction = cov$coverage_fraction,
                              cell_area_km2 = cell_area) %>%
        dplyr::mutate(weight = coverage_fraction * cell_area_km2 / sum(coverage_fraction * cell_area_km2))
      readr::write_csv(cells, cell_file)
    }
    cells <- readr::read_csv(cell_file, show_col_types = FALSE)

    chunk <- purrr::imap(r, function(rv, nm) {
      short <- sub("_.*$", "", names(rv)[1])
      lut <- gridmet_vars[gridmet_vars$gridmet == short, ]
      vals <- terra::values(rv)[cells$cell, , drop = FALSE]
      dates <- as.Date(terra::time(rv))
      tibble::tibble(cell = rep(cells$cell, times = length(dates)),
                     date = rep(dates, each = nrow(cells)),
                     var = lut$flowr,
                     value = lut$convert[[1]](as.vector(vals)))
    }) %>%
      dplyr::bind_rows() %>%
      tidyr::pivot_wider(names_from = var, values_from = value)

    arrow::write_parquet(chunk, f)
    out[[i]] <- chunk
  }

  list(cells = readr::read_csv(cell_file, show_col_types = FALSE),
       data = dplyr::bind_rows(out))
}

#' Area-weighted basin-mean daily GridMET forcing
#'
#' @param gm Output of `get_gridmet_cells()`.
#' @return Tibble: date plus one column per variable, and tmean_c.
#' @export
gridmet_basin_mean <- function(gm) {
  gm$data %>%
    dplyr::inner_join(dplyr::select(gm$cells, cell, weight), by = "cell") %>%
    dplyr::group_by(date) %>%
    dplyr::summarize(dplyr::across(-c(cell, weight), ~ sum(.x * weight, na.rm = TRUE) / sum(weight[!is.na(.x)]),
                                   .names = "{.col}"),
                     .groups = "drop") %>%
    dplyr::mutate(tmean_c = (tmin_c + tmax_c) / 2) %>%
    dplyr::arrange(date)
}
