# Time utilities ---------------------------------------------------------------

#' Water year for a vector of dates
#'
#' @param dates Date vector (or anything `as.Date()` accepts).
#' @param start_month Integer 1-12, month the water year starts. Default 10
#'   (October), so 2020-10-01 is water year 2021.
#' @return Integer vector of water years.
#' @export
calc_water_year <- function(dates, start_month = 10) {
  dates <- as.Date(dates)
  yr <- as.integer(format(dates, "%Y"))
  mo <- as.integer(format(dates, "%m"))
  if (start_month == 1) return(yr)
  yr + as.integer(mo >= start_month)
}

#' Pad a daily data frame so every date between start and end has a row
#'
#' Missing days are inserted with NA values (nothing is interpolated). Gap
#' filling is a modeling decision, so it is left to the caller.
#'
#' @param df Data frame with a Date column.
#' @param date_col Name of the date column. Default "date".
#' @param start,end Optional bounds; default to the range of `df`.
#' @export
complete_daily <- function(df, date_col = "date", start = NULL, end = NULL) {
  d <- as.Date(df[[date_col]])
  start <- as.Date(if (is.null(start)) min(d, na.rm = TRUE) else start)
  end <- as.Date(if (is.null(end)) max(d, na.rm = TRUE) else end)
  full <- tibble::tibble(!!date_col := seq(start, end, by = "day"))
  df[[date_col]] <- d
  dplyr::left_join(full, df, by = date_col)
}
