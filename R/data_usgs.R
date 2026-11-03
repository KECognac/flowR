# USGS streamflow -------------------------------------------------------------------
# Built on the USGS Water Data APIs (api.waterdata.usgs.gov) through
# dataRetrieval's read_waterdata_*() functions. The legacy NWIS web services
# (readNWISdv, whatNWISdata, ...) are being decommissioned, so nothing here
# uses them. Requests are much faster and less rate-limited with a personal
# API token stored as API_USGS_PAT in ~/.Renviron
# (https://api.waterdata.usgs.gov/signup/).

#' List USGS gauges with daily discharge records
#'
#' Supply one of `sites`, `aoi`, or `state_name`. Returns one row per
#' monitoring location that has a daily-mean discharge time series, with the
#' period of record and drainage area.
#'
#' @param sites Character vector of site numbers (with or without "USGS-").
#' @param aoi An sf object; gauges inside it are returned.
#' @param state_name Full state name(s), e.g. "Maine".
#' @param parameter_code Default "00060" (discharge, ft3/s).
#' @param statistic_id Default "00003" (daily mean).
#' @return sf points (EPSG:4326) with site_no, name, begin, end, n_years,
#'   drainage_area_km2.
#' @export
list_usgs_gauges <- function(sites = NULL, aoi = NULL, state_name = NULL,
                             parameter_code = "00060", statistic_id = "00003") {

  if (is.null(sites) && is.null(aoi) && is.null(state_name)) {
    stop("Supply one of `sites`, `aoi`, or `state_name`.")
  }

  ts_args <- list(parameter_code = parameter_code,
                  statistic_id = statistic_id,
                  computation_period_identifier = "Daily")
  if (!is.null(sites)) ts_args$monitoring_location_id <- usgs_id(sites)
  if (!is.null(state_name)) ts_args$state_name <- state_name
  if (!is.null(aoi)) {
    aoi <- sf::st_transform(aoi, 4326)
    ts_args$bbox <- as.numeric(sf::st_bbox(aoi))
  }

  ts <- do.call(dataRetrieval::read_waterdata_ts_meta, ts_args)
  if (nrow(ts) == 0) return(ts)

  # A location can carry several 00060 series (e.g. sublocations); keep the
  # primary one, or the longest when none is flagged primary.
  ts <- ts %>%
    sf::st_drop_geometry() %>%
    dplyr::mutate(begin = as.Date(begin), end = as.Date(end)) %>%
    dplyr::group_by(monitoring_location_id) %>%
    dplyr::arrange(dplyr::desc(primary %in% "Primary"), dplyr::desc(end - begin),
                   .by_group = TRUE) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup() %>%
    dplyr::select(monitoring_location_id, time_series_id, begin, end, unit_of_measure)

  locs <- dataRetrieval::read_waterdata_monitoring_location(
    monitoring_location_id = ts$monitoring_location_id
  ) %>%
    dplyr::select(monitoring_location_id,
                  name = monitoring_location_name,
                  state_name, site_type, hydrologic_unit_code,
                  altitude_ft = altitude,
                  drainage_area_mi2 = drainage_area,
                  contributing_drainage_area_mi2 = contributing_drainage_area)

  out <- locs %>%
    dplyr::inner_join(ts, by = "monitoring_location_id") %>%
    dplyr::mutate(site_no = usgs_site_no(monitoring_location_id),
                  drainage_area_km2 = drainage_area_mi2 * 2.58998811,
                  n_years = as.numeric(end - begin) / 365.25,
                  .before = 1)

  if (!is.null(aoi)) {
    out <- out[lengths(sf::st_intersects(out, aoi)) > 0, ]
  }
  out
}

#' Daily mean discharge for one USGS gauge
#'
#' Downloads (or reads from cache) the daily-mean discharge record and returns
#' a complete daily series: days with no published value are NA rows rather
#' than missing rows. Provisional and estimated values are kept but flagged
#' so they can be excluded from calibration/evaluation if desired.
#'
#' @param site_no Site number (with or without "USGS-").
#' @param start,end Date bounds (character or Date). NULL = full record.
#' @param area_km2 Optional drainage area; if given, adds q_mm (mm/day).
#' @param cache_dir Directory for cached csv files. NULL disables caching.
#' @param refresh If TRUE, re-download even when a cache file exists.
#' @return Tibble: site_no, date, q_cfs, q_cms, (q_mm), approval_status,
#'   qualifier, estimated (logical).
#' @export
get_usgs_flow <- function(site_no, start = NULL, end = NULL, area_km2 = NULL,
                          cache_dir = wsva_path("raw", "usgs"),
                          refresh = FALSE) {

  site_no <- usgs_site_no(site_no)
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, paste0(site_no, "_dv_00060.csv"))

  if (!is.null(cache_file) && file.exists(cache_file) && !refresh) {
    q <- readr::read_csv(cache_file, col_types = "cDdcc", progress = FALSE)
  } else {
    time_arg <- if (is.null(start) && is.null(end)) NA_character_ else
      c(if (is.null(start)) ".." else as.character(start),
        if (is.null(end)) ".." else as.character(end))
    raw <- dataRetrieval::read_waterdata_daily(
      monitoring_location_id = usgs_id(site_no),
      parameter_code = "00060",
      statistic_id = "00003",
      time = time_arg,
      skipGeometry = TRUE
    )
    q <- tibble::tibble(site_no = site_no,
                        date = as.Date(raw$time),
                        q_cfs = as.numeric(raw$value),
                        approval_status = raw$approval_status,
                        qualifier = raw$qualifier) %>%
      dplyr::distinct(date, .keep_all = TRUE) %>%
      dplyr::arrange(date)
    if (!is.null(cache_file)) {
      dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
      readr::write_csv(q, cache_file)
    }
  }

  if (!is.null(start)) q <- dplyr::filter(q, date >= as.Date(start))
  if (!is.null(end)) q <- dplyr::filter(q, date <= as.Date(end))

  q <- complete_daily(q, start = start, end = end) %>%
    dplyr::mutate(site_no = site_no,
                  q_cms = q_cfs * 0.0283168466,
                  estimated = grepl("ESTIMATED", qualifier %||% ""),
                  .after = q_cfs)
  # Negative discharge (tidal/backwater artifacts) is not physical for these basins
  q$q_cfs[!is.na(q$q_cfs) & q$q_cfs < 0] <- NA
  if (!is.null(area_km2)) q$q_mm <- cfs_to_mm_day(q$q_cfs, area_km2)
  q
}
