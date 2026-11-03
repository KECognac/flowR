# Benchmark predictors ---------------------------------------------------------------
# A model is only skillful relative to a simple baseline (Schaefli & Gupta
# 2007; Seibert et al. 2018; Knoben et al. 2020). The day-of-year
# climatology is the standard lower benchmark: it captures the mean seasonal
# cycle and nothing else.

#' Day-of-year mean flow, estimated only from training days
#'
#' @param obs Observed series.
#' @param dates Dates aligned with `obs`.
#' @param train_idx Logical/integer index of days allowed to inform the benchmark.
#' @param smooth_days Width of the circular moving-average window (odd).
#' @return Numeric vector aligned with `dates`.
#' @export
benchmark_doy_climatology <- function(obs, dates, train_idx, smooth_days = 31) {
  if (is.logical(train_idx)) train_idx <- which(train_idx)
  doy <- pmin(as.integer(format(as.Date(dates), "%j")), 365)   # fold Dec 31 of leap years into 365
  clim <- tapply(obs[train_idx], factor(doy[train_idx], levels = 1:365), mean, na.rm = TRUE)
  clim <- as.numeric(clim)
  half <- smooth_days %/% 2
  padded <- c(utils::tail(clim, half), clim, utils::head(clim, half))
  smoothed <- as.numeric(stats::filter(padded, rep(1 / smooth_days, smooth_days), sides = 2))
  smoothed <- smoothed[(half + 1):(half + 365)]
  smoothed[doy]
}
