# Train / test splits for time series -------------------------------------------
# Streamflow is strongly autocorrelated, so random row-wise splits leak
# information between train and test. Every split here is made on whole
# water years in contiguous blocks, with an optional buffer of excluded
# days on each side of a test block. Process models run on the full record
# (they need continuous state); splits only decide which days count toward
# the objective. ML models should use the same labels to choose training
# samples, and the buffer should be at least the input sequence length.
#
# Every model in flowR should be scored with the splits produced here, so
# results are comparable across methods.

#' Fixed warm-up / calibration / validation / test periods by water year
#'
#' @param dates Date vector covering the full model run.
#' @param warmup_years Number of leading water years excluded from scoring.
#' @param cal,val,test Length-2 integer vectors of first/last water year.
#'   `val` and `test` may be NULL.
#' @return Tibble: date, wy, period ("warmup", "cal", "val", "test", or "unused").
#' @export
make_period_split <- function(dates, warmup_years = 1, cal, val = NULL, test = NULL) {
  wy <- calc_water_year(dates)
  wys <- sort(unique(wy))
  warm <- utils::head(wys, warmup_years)
  in_range <- function(r) if (is.null(r)) rep(FALSE, length(wy)) else wy >= r[1] & wy <= r[2]
  period <- dplyr::case_when(
    wy %in% warm ~ "warmup",
    in_range(test) ~ "test",
    in_range(val) ~ "val",
    in_range(cal) ~ "cal",
    TRUE ~ "unused"
  )
  tibble::tibble(date = as.Date(dates), wy = wy, period = period)
}

#' Blocked k-fold cross-validation on contiguous water-year blocks
#'
#' Water years after the warm-up are cut into `k` contiguous blocks. In fold
#' i, block i is "test", days within `buffer_days` of the test block are
#' "buffer" (excluded from training), and everything else is "train".
#'
#' @param dates Date vector covering the full model run.
#' @param k Number of folds.
#' @param warmup_years Leading water years never scored.
#' @param buffer_days Days excluded either side of each test block.
#' @param min_obs_frac Optional: with `obs`, drop water years with less than
#'   this fraction of observed days before forming blocks.
#' @param obs Optional observation vector aligned with `dates`.
#' @return Long tibble: fold, date, wy, role ("train", "test", "buffer", "warmup").
#' @export
make_blocked_folds <- function(dates, k = 5, warmup_years = 1, buffer_days = 0,
                               min_obs_frac = 0, obs = NULL) {
  dates <- as.Date(dates)
  wy <- calc_water_year(dates)
  wys <- sort(unique(wy))
  warm <- utils::head(wys, warmup_years)
  scored <- setdiff(wys, warm)
  if (!is.null(obs) && min_obs_frac > 0) {
    frac <- tapply(!is.na(obs), wy, mean)
    scored <- scored[frac[as.character(scored)] >= min_obs_frac]
  }
  if (length(scored) < k) stop("Fewer scoreable water years (", length(scored), ") than folds (", k, ")")
  block <- stats::setNames(cut(seq_along(scored), k, labels = FALSE), scored)

  purrr::map_dfr(seq_len(k), function(i) {
    test_wy <- as.integer(names(block)[block == i])
    is_test <- wy %in% test_wy
    test_dates <- range(dates[is_test])
    near <- !is_test & ((dates >= test_dates[1] - buffer_days & dates < test_dates[1]) |
                          (dates <= test_dates[2] + buffer_days & dates > test_dates[2]))
    role <- dplyr::case_when(
      wy %in% warm ~ "warmup",
      is_test ~ "test",
      near ~ "buffer",
      wy %in% scored ~ "train",
      TRUE ~ "unused"
    )
    tibble::tibble(fold = i, date = dates, wy = wy, role = role)
  })
}

#' Differential split-sample test: calibrate in one climate, test in another
#'
#' Klemes (1986, Hydrol. Sci. J. 31:13) proposed calibrating on climatically
#' contrasting periods to test whether a model transfers to a changed
#' climate -- the closest historical check on using a model with climate
#' projections. Water years after the warm-up are ranked by annual
#' precipitation, annual mean temperature, and time. Each contrast trains
#' on one extreme fraction of years and tests on the opposite extreme:
#'   1 wet -> dry, 2 dry -> wet, 3 cool -> warm, 4 warm -> cool,
#'   5 early -> late (calibrate on the first years, test on the most recent).
#' Years in the middle are "unused". Process models still run the whole
#' record; only scoring is restricted.
#'
#' @param daily Daily tibble with date, prcp_mm, tmean_c (and q_mm if
#'   `min_obs_frac` > 0).
#' @param frac Fraction of scoreable water years in each extreme group.
#' @param warmup_years Leading water years never scored.
#' @param min_obs_frac Water years with less than this fraction of observed
#'   flow days are not ranked or scored.
#' @return Long tibble: fold, contrast, date, wy, role ("train", "test",
#'   "warmup", "unused"), in the same layout as make_blocked_folds().
#' @export
make_climate_contrast_folds <- function(daily, frac = 1 / 3, warmup_years = 1, min_obs_frac = 0.8) {
  dates <- as.Date(daily$date)
  wy <- calc_water_year(dates)
  wys <- sort(unique(wy))
  warm <- utils::head(wys, warmup_years)
  annual <- tibble::tibble(wy = wy, p = daily$prcp_mm, t = daily$tmean_c,
                           has_q = if ("q_mm" %in% names(daily)) !is.na(daily$q_mm) else TRUE) %>%
    dplyr::filter(!wy %in% warm) %>%
    dplyr::group_by(wy) %>%
    dplyr::summarize(p = sum(p), t = mean(t), obs = mean(has_q), n = dplyr::n(), .groups = "drop") %>%
    dplyr::filter(n >= 365, obs >= min_obs_frac)
  n_g <- floor(nrow(annual) * frac)
  if (n_g < 3) stop("Too few complete water years for a ", round(frac, 2), " split")
  lo <- function(v) annual$wy[order(v)][seq_len(n_g)]
  hi <- function(v) annual$wy[order(-v)][seq_len(n_g)]
  contrasts <- list(
    "wet -> dry"     = list(train = hi(annual$p), test = lo(annual$p)),
    "dry -> wet"     = list(train = lo(annual$p), test = hi(annual$p)),
    "cool -> warm"   = list(train = lo(annual$t), test = hi(annual$t)),
    "warm -> cool"   = list(train = hi(annual$t), test = lo(annual$t)),
    "early -> late"  = list(train = lo(annual$wy), test = hi(annual$wy))
  )
  purrr::imap_dfr(unname(contrasts), function(cn, i) {
    role <- dplyr::case_when(wy %in% warm ~ "warmup", wy %in% cn$test ~ "test",
                             wy %in% cn$train ~ "train", TRUE ~ "unused")
    tibble::tibble(fold = i, contrast = names(contrasts)[i], date = dates, wy = wy, role = role)
  })
}
