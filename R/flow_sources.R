# Flow sources -------------------------------------------------------------------
# Every flow source returns the same standard flow table, so models never
# depend on where flow came from:
#
#   tibble(date, q_cms, flag)   complete daily series (missing days are NA)
#   attr(x, "flow_meta")        list(source, id, name, lon, lat,
#                                    usgs_site_no, reported_area_km2)
#
# Discharge is stored in m3/s; it is converted to basin depth (mm/day) only
# once the basin area is known (`flow_to_mm()`).

.cfs_to_cms <- 0.0283168466

#' Build a standard flow table (internal constructor)
#'
#' @param date,q_cms,flag Vectors of equal length.
#' @param meta Named list of metadata (see file header).
#' @param start,end Optional bounds for the complete daily series.
#' @noRd
.flow_table <- function(date, q_cms, flag = NA_character_, meta = list(), start = NULL, end = NULL) {
  x <- tibble::tibble(date = as.Date(date), q_cms = as.numeric(q_cms), flag = as.character(flag)) %>%
    dplyr::filter(!is.na(date)) %>%
    dplyr::distinct(date, .keep_all = TRUE) %>%
    dplyr::arrange(date)
  if (!is.null(start)) x <- dplyr::filter(x, date >= as.Date(start))
  if (!is.null(end)) x <- dplyr::filter(x, date <= as.Date(end))
  if (!nrow(x)) stop("No flow data in the requested period")
  x <- complete_daily(x, start = start, end = end)
  x$q_cms[!is.na(x$q_cms) & x$q_cms < 0] <- NA       # negative discharge is not physical here
  defaults <- list(source = NA_character_, id = NA_character_, name = NA_character_,
                   lon = NA_real_, lat = NA_real_, usgs_site_no = NA_character_,
                   reported_area_km2 = NA_real_)
  attr(x, "flow_meta") <- utils::modifyList(defaults, meta)
  class(x) <- c("wsva_flow", class(x))
  x
}

#' Metadata of a standard flow table
#' @param flow Output of a `flow_*()` function.
#' @export
flow_meta <- function(flow) attr(flow, "flow_meta")

#' @export
print.wsva_flow <- function(x, ...) {
  m <- flow_meta(x)
  obs <- !is.na(x$q_cms)
  cat(sprintf("<wsva_flow> %s %s (%s)\n", m$id %||% "", m$name %||% "", m$source %||% "user"))
  cat(sprintf("  %s to %s, %d days, %.0f%% observed\n", min(x$date), max(x$date), nrow(x), 100 * mean(obs)))
  if (!is.na(m$reported_area_km2)) cat(sprintf("  reported drainage area %.1f km2\n", m$reported_area_km2))
  invisible(x)
}

#' Add basin-depth flow (mm/day) to a flow table
#'
#' @param flow Standard flow table.
#' @param area_km2 Drainage area used for normalization.
#' @return `flow` with a `q_mm` column.
#' @export
flow_to_mm <- function(flow, area_km2) {
  stopifnot(length(area_km2) == 1, is.finite(area_km2), area_km2 > 0)
  flow$q_mm <- flow$q_cms * 86400 / (area_km2 * 1e6) * 1000
  flow
}

#' Daily flow from the USGS Water Data APIs
#'
#' @param site_no USGS site number.
#' @param start,end Period (default: whole record).
#' @param cache_dir Cache for the raw download (see `get_usgs_flow()`).
#' @return Standard flow table; `flag` holds "estimated" or the approval status.
#' @export
flow_usgs <- function(site_no, start = NULL, end = NULL, cache_dir = wsva_path("raw", "usgs")) {
  site_no <- usgs_site_no(site_no)
  q <- get_usgs_flow(site_no, start = start, end = end, cache_dir = cache_dir)
  meta <- list(source = "USGS", id = site_no, usgs_site_no = site_no)
  info <- tryCatch(list_usgs_gauges(sites = site_no), error = function(e) NULL)
  if (!is.null(info) && nrow(info)) {
    xy <- sf::st_coordinates(info[1, ])
    meta <- c(meta, list(name = info$name[1], lon = xy[1], lat = xy[2],
                         reported_area_km2 = info$drainage_area_km2[1]))
  }
  flag <- ifelse(q$estimated %in% TRUE, "estimated", q$approval_status)
  .flow_table(q$date, q$q_cfs * .cfs_to_cms, flag, meta, start, end)
}

#' Daily flow from Colorado's Decision Support Systems (CDSS / DWR)
#'
#' Uses the `cdssr` package (surface-water station time series), which covers
#' stations operated by the Colorado Division of Water Resources as well as
#' USGS and other cooperators. Many DWR stations sit below diversions or
#' reservoirs; check that a station's flow is close to natural before using
#' it for calibration.
#'
#' @param abbrev CDSS station abbreviation (e.g. "CCACCRCO").
#' @param start,end Period.
#' @param cache_dir Cache directory (csv per station).
#' @param refresh Re-download even if cached.
#' @return Standard flow table; `flag` holds the CDSS flag columns joined.
#' @export
flow_cdss <- function(abbrev, start = wsva_default_period()$start, end = wsva_default_period()$end,
                      cache_dir = wsva_path("raw", "cdss"), refresh = FALSE) {
  if (!requireNamespace("cdssr", quietly = TRUE)) stop("flow_cdss() needs the cdssr package")
  f <- file.path(cache_dir, paste0(abbrev, "_", start, "_", end, ".csv"))
  fm <- file.path(cache_dir, paste0(abbrev, "_meta.rds"))
  if (file.exists(f) && file.exists(fm) && !refresh) {
    q <- readr::read_csv(f, col_types = "Ddc", progress = FALSE)
    meta <- readRDS(fm)
  } else {
    raw <- suppressMessages(cdssr::get_sw_ts(abbrev = abbrev, start_date = as.character(start),
                                             end_date = as.character(end), timescale = "day"))
    if (!nrow(raw)) stop("CDSS returned no daily data for ", abbrev)
    if (!all(raw$meas_unit %in% c("cfs", "CFS"))) stop("Unexpected CDSS units: ", paste(unique(raw$meas_unit), collapse = ", "))
    flags <- raw[, intersect(c("flag_a", "flag_b", "flag_c", "flag_d"), names(raw)), drop = FALSE]
    q <- tibble::tibble(date = as.Date(raw$datetime), q_cfs = as.numeric(raw$value),
                        flag = apply(flags, 1, function(r) paste(stats::na.omit(r[nzchar(r)]), collapse = "")))
    st <- suppressMessages(cdssr::get_sw_stations(abbrev = abbrev))
    meta <- list(source = "CDSS", id = abbrev, name = st$station_name[1],
                 lon = st$longitude[1], lat = st$latitude[1],
                 usgs_site_no = if (!is.na(st$usgs_site_id[1]) && nzchar(st$usgs_site_id[1])) st$usgs_site_id[1] else NA_character_,
                 data_source = st$data_source[1])
    dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
    readr::write_csv(q, f)
    saveRDS(meta, fm)
  }
  q$flag[q$flag == ""] <- NA
  .flow_table(q$date, q$q_cfs * .cfs_to_cms, q$flag, meta, start, end)
}

#' Standard flow table from a user data frame
#'
#' @param df Data frame with a date column and a discharge column.
#' @param date_col,q_col Column names.
#' @param units "cfs", "cms" (m3/s) or "mm" (mm/day; needs `area_km2`).
#' @param area_km2 Drainage area, required for `units = "mm"`; also stored as
#'   the reported area.
#' @param id,name,lon,lat Optional gauge metadata (the outlet location is
#'   needed to delineate a watershed from the gauge).
#' @param date_format Optional format for character dates (e.g. "%m/%d/%Y").
#' @param flag_col Optional column of quality flags.
#' @return Standard flow table.
#' @export
flow_from_df <- function(df, date_col = "date", q_col, units = c("cfs", "cms", "mm"), area_km2 = NULL,
                         id = NA_character_, name = NA_character_, lon = NA_real_, lat = NA_real_,
                         date_format = NULL, flag_col = NULL) {
  units <- match.arg(units)
  stopifnot(date_col %in% names(df), q_col %in% names(df))
  d <- df[[date_col]]
  d <- if (inherits(d, "Date")) d else if (inherits(d, "POSIXt")) as.Date(d) else
    tryCatch(if (is.null(date_format)) as.Date(d) else as.Date(as.character(d), format = date_format),
             error = function(e) as.Date(rep(NA_character_, length(d))))
  if (anyNA(d[!is.na(df[[date_col]])])) stop("Some dates could not be parsed; set `date_format`")
  q <- as.numeric(df[[q_col]])
  q_cms <- switch(units,
    cfs = q * .cfs_to_cms,
    cms = q,
    mm = {
      if (is.null(area_km2)) stop("units = \"mm\" needs area_km2")
      q / 1000 * area_km2 * 1e6 / 86400
    })
  flag <- if (!is.null(flag_col)) df[[flag_col]] else NA_character_
  .flow_table(d, q_cms, flag, list(source = "user", id = id, name = name, lon = lon, lat = lat,
                                   reported_area_km2 = area_km2 %||% NA_real_))
}

#' Standard flow table from a csv file
#'
#' @param path csv file.
#' @param ... Passed to `flow_from_df()` (date_col, q_col, units, ...).
#' @param skip Lines to skip before the header.
#' @export
flow_from_csv <- function(path, ..., skip = 0) {
  df <- readr::read_csv(path, skip = skip, show_col_types = FALSE, progress = FALSE)
  flow_from_df(df, ...)
}
