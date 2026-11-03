# Baseflow separation ---------------------------------------------------------------

#' Eckhardt (2005) two-parameter recursive digital filter
#'
#' `b[t] = ((1 - BFImax) a b[t-1] + (1 - a) BFImax q[t]) / (1 - a BFImax)`,
#' constrained to `0 <= b[t] <= q[t]`. NA discharge carries the previous
#' baseflow forward and returns NA for that day.
#'
#' @param q Daily discharge (any units).
#' @param alpha Recession constant (typically 0.95-0.99).
#' @param bfi_max Maximum baseflow index: ~0.80 perennial/porous aquifers,
#'   ~0.50 ephemeral, ~0.25 perennial hard-rock (Eckhardt 2005).
#' @param bf_0 Initial baseflow; default `q[1] * bfi_max`.
#' @return Tibble: q, baseflow, quickflow.
#' @export
baseflow_eckhardt <- function(q, alpha = 0.98, bfi_max = 0.8, bf_0 = NULL) {
  n <- length(q)
  bf <- rep(NA_real_, n)
  first <- which(!is.na(q))[1]
  if (is.na(first)) return(tibble::tibble(q = q, baseflow = bf, quickflow = bf))
  prev <- if (is.null(bf_0)) q[first] * bfi_max else min(bf_0, q[first])
  bf[first] <- prev
  c1 <- (1 - bfi_max) * alpha
  c2 <- (1 - alpha) * bfi_max
  den <- 1 - alpha * bfi_max
  for (t in seq.int(first + 1, length.out = max(0, n - first))) {
    if (is.na(q[t])) next
    prev <- max(min((c1 * prev + c2 * q[t]) / den, q[t]), 0)
    bf[t] <- prev
  }
  tibble::tibble(q = q, baseflow = bf, quickflow = q - bf)
}
