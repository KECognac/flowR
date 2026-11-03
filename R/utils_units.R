# Unit conversions ---------------------------------------------------------------
# Models in flowR work in area-normalized depth (mm/day) so basins of
# different sizes are directly comparable. Convert observed discharge once.

#' Discharge (ft3/s) to basin-average depth (mm/day)
#' @param q_cfs Discharge in cubic feet per second.
#' @param area_km2 Drainage area in km2.
#' @export
cfs_to_mm_day <- function(q_cfs, area_km2) {
  q_cfs * 0.0283168466 * 86400 / (area_km2 * 1e6) * 1000
}

#' Basin-average depth (mm/day) to discharge (m3/s)
#' @param q_mm Depth in mm/day.
#' @param area_km2 Drainage area in km2.
#' @export
mm_day_to_cms <- function(q_mm, area_km2) {
  q_mm / 1000 * area_km2 * 1e6 / 86400
}

#' Convert USGS ids to the "USGS-########" form used by the Water Data APIs
#' @param site_no Character vector of site numbers, with or without prefix.
#' @export
usgs_id <- function(site_no) {
  site_no <- as.character(site_no)
  ifelse(grepl("^USGS-", site_no), site_no, paste0("USGS-", site_no))
}

#' Strip the "USGS-" prefix
#' @param id Character vector of ids.
#' @export
usgs_site_no <- function(id) sub("^USGS-", "", as.character(id))
