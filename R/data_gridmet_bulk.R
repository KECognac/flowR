# Bulk GridMET (national files) -------------------------------------------------------
# For many basins, downloading the CONUS GridMET netCDF files once (one file
# per variable per calendar year, ~60-200 MB each) and extracting locally is
# far faster than per-basin OPeNDAP requests. Files come from the University
# of Idaho Northwest Knowledge Network THREDDS/HTTP server.
#
# Extraction writes the same per-basin, cell-level parquet layout as
# get_gridmet_cells(), so gridmet_basin_mean() and the rest of the pipeline
# work unchanged.

gridmet_bulk_url <- function(var, year) {
  sprintf("https://www.northwestknowledge.net/metdata/data/%s_%d.nc", var, year)
}

#' Download national GridMET files
#'
#' Uses curl::multi_download(), which runs the transfers concurrently in one
#' process (forked parallel downloads are unreliable on macOS), a few files at a time, and resumes
#' partial files on re-run. Files that fail are reported, and the function can
#' simply be called again.
#'
#' @param vars GridMET short names.
#' @param years Calendar years.
#' @param dir Destination folder.
#' @param n_parallel Files downloaded at once (the server allows ~2).
#' @param max_passes Retry passes for failed files.
#' @return Tibble of var, year, path, ok.
#' @export
download_gridmet_conus <- function(vars = c("pr", "tmmn", "tmmx", "srad", "vs", "rmin", "rmax", "pet"),
                                   years = 1980:2024,
                                   dir = wsva_path("raw", "gridmet_conus"),
                                   n_parallel = 2, max_passes = 3) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  jobs <- expand.grid(var = vars, year = years, stringsAsFactors = FALSE)
  jobs$path <- file.path(dir, sprintf("%s_%d.nc", jobs$var, jobs$year))
  jobs$url <- gridmet_bulk_url(jobs$var, jobs$year)
  done_marker <- paste0(jobs$path, ".done")
  # The server accepts only ~2 connections at a time (more time out), so
  # download in pairs and make extra passes for anything that failed.
  for (pass in seq_len(max_passes)) {
    todo <- which(!file.exists(done_marker))
    if (!length(todo)) break
    for (batch in split(todo, ceiling(seq_along(todo) / n_parallel))) {
      res <- curl::multi_download(jobs$url[batch], jobs$path[batch], resume = TRUE, progress = FALSE,
                                  connecttimeout = 120)
      ok <- res$success & res$status_code %in% c(200, 206)
      file.create(done_marker[batch][ok])
      for (i in which(!ok)) message("FAIL ", basename(jobs$path[batch][i]), ": ", res$error[i] %||% res$status_code[i])
      message(sum(file.exists(done_marker)), " of ", nrow(jobs), " files complete")
    }
  }
  jobs$ok <- file.exists(done_marker)
  tibble::as_tibble(jobs[, c("var", "year", "path", "ok")])
}

# Layer dates of a national GridMET file. terra doesn't parse its time axis,
# but layer names carry it: "<var>_day=29219" = days since 1900-01-01.
.gridmet_nc_dates <- function(r) {
  t <- terra::time(r)
  if (!anyNA(t)) return(as.Date(t))
  as.Date("1900-01-01") + as.integer(sub(".*day=", "", names(r)))
}

#' Extract cell-level GridMET for many basins from the national files
#'
#' Cells touching each basin are found once (they are the same in every
#' file); then each national file is read once and the union of needed cells
#' is pulled out, so cost scales with the number of files, not basins.
#' Output per basin: <out_dir>/<site_no>/cells.csv and one parquet per year
#' (cell, date, flowR-named variables in flowR units).
#'
#' @param basins sf polygons with a site_no column.
#' @param years Calendar years to extract.
#' @param vars GridMET short names (files must exist in `nc_dir`).
#' @param nc_dir Folder of national files from `download_gridmet_conus()`.
#' @param out_dir Output root.
#' @export
extract_gridmet_bulk <- function(basins, years = 1980:2024,
                                 vars = c("pr", "tmmn", "tmmx", "srad", "vs", "rmin", "rmax", "pet"),
                                 nc_dir = wsva_path("raw", "gridmet_conus"),
                                 out_dir = wsva_path("raw", "gridmet_bulk")) {
  nc <- function(v, y) file.path(nc_dir, sprintf("%s_%d.nc", v, y))
  template <- terra::rast(nc(vars[1], years[1]))[[1]]
  area <- terra::cellSize(template, unit = "km")

  # Cells and area weights per basin (computed once, cached)
  cells <- lapply(seq_len(nrow(basins)), function(i) {
    site <- basins$site_no[i]
    f <- file.path(out_dir, site, "cells.csv")
    if (file.exists(f)) return(readr::read_csv(f, show_col_types = FALSE))
    dir.create(dirname(f), showWarnings = FALSE, recursive = TRUE)
    cov <- exactextractr::exact_extract(template, sf::st_transform(basins[i, ], terra::crs(template)),
                                        include_cell = TRUE, include_xy = TRUE, progress = FALSE)[[1]]
    tab <- tibble::tibble(cell = cov$cell, x = cov$x, y = cov$y,
                          coverage_fraction = cov$coverage_fraction,
                          cell_area_km2 = area[cov$cell][, 1]) %>%
      dplyr::mutate(weight = coverage_fraction * cell_area_km2 / sum(coverage_fraction * cell_area_km2))
    readr::write_csv(tab, f)
    tab
  })
  names(cells) <- basins$site_no
  all_cells <- sort(unique(unlist(lapply(cells, `[[`, "cell"))))

  for (y in years) {
    out_files <- file.path(out_dir, basins$site_no, sprintf("gridmet_%d.parquet", y))
    if (all(file.exists(out_files))) next
    vals <- lapply(vars, function(v) {
      r <- terra::rast(nc(v, y))
      lut <- gridmet_vars[gridmet_vars$gridmet == v, ]
      m <- as.matrix(terra::extract(r, all_cells))           # cells x days
      list(name = lut$flowr, values = lut$convert[[1]](m), dates = .gridmet_nc_dates(r))
    })
    dates <- vals[[1]]$dates
    stopifnot(all(vapply(vals, function(v) identical(v$dates, dates), logical(1))))
    for (i in seq_len(nrow(basins))) {
      if (file.exists(out_files[i])) next
      idx <- match(cells[[i]]$cell, all_cells)
      tab <- tibble::tibble(cell = rep(cells[[i]]$cell, times = length(dates)),
                            date = rep(dates, each = length(idx)))
      for (v in vals) tab[[v$name]] <- as.vector(v$values[idx, , drop = FALSE])
      arrow::write_parquet(tab, out_files[i])
    }
    message("GridMET ", y, " extracted for ", nrow(basins), " basins")
  }
  invisible(out_files)
}

#' Read bulk-extracted cell-level GridMET for one basin
#'
#' @return list(cells, data) in the same shape as `get_gridmet_cells()`, so
#'   it can be passed to `gridmet_basin_mean()`.
#' @param site_no Basin id.
#' @param start,end Optional date bounds.
#' @param out_dir Root folder written by `extract_gridmet_bulk()`.
#' @export
read_gridmet_bulk <- function(site_no, start = NULL, end = NULL,
                              out_dir = wsva_path("raw", "gridmet_bulk")) {
  d <- file.path(out_dir, site_no)
  data <- dplyr::bind_rows(lapply(sort(list.files(d, pattern = "^gridmet_\\d{4}\\.parquet$", full.names = TRUE)),
                                  arrow::read_parquet))
  if (!is.null(start)) data <- dplyr::filter(data, date >= as.Date(start))
  if (!is.null(end)) data <- dplyr::filter(data, date <= as.Date(end))
  list(cells = readr::read_csv(file.path(d, "cells.csv"), show_col_types = FALSE), data = data)
}
