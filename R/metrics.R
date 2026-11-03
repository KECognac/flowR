# Goodness-of-fit metrics -------------------------------------------------------------
# All metrics drop pairs where either obs or sim is NA and return NA when
# they can't be computed (no data, zero variance). Calibration code decides
# how to penalize NA, so the metric itself never returns a magic number.
#
# Interpretation guides: Moriasi et al. (2007, 2015); Knoben et al. (2019)
# note KGE > -0.41 beats the mean-flow benchmark, so KGE and NSE values are
# not directly comparable.

.pairs <- function(obs, sim) {
  stopifnot(length(obs) == length(sim))
  ok <- !is.na(obs) & !is.na(sim)
  list(o = obs[ok], s = sim[ok])
}

#' Nash-Sutcliffe efficiency (1 = perfect, 0 = as good as the mean)
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @export
nse <- function(obs, sim) {
  x <- .pairs(obs, sim)
  den <- sum((x$o - mean(x$o))^2)
  if (length(x$o) < 2 || den == 0) return(NA_real_)
  1 - sum((x$o - x$s)^2) / den
}

#' NSE of log flows (emphasizes low flows); `eps` avoids log(0)
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @param eps Offset added before the log so zero flows are defined; default 1% of mean observed flow.
#' @export
log_nse <- function(obs, sim, eps = NULL) {
  if (is.null(eps)) eps <- 0.01 * mean(obs, na.rm = TRUE)
  nse(log(obs + eps), log(pmax(sim, 0) + eps))
}

#' Kling-Gupta efficiency (Gupta et al. 2009); `components = TRUE` returns r, alpha, beta
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @param components If TRUE, return a tibble with KGE and its r, alpha (variability ratio) and beta (bias ratio) components.
#' @export
kge <- function(obs, sim, components = FALSE) {
  x <- .pairs(obs, sim)
  if (length(x$o) < 2 || stats::sd(x$o) == 0 || mean(x$o) == 0) return(NA_real_)
  r <- stats::cor(x$o, x$s)
  alpha <- stats::sd(x$s) / stats::sd(x$o)
  beta <- mean(x$s) / mean(x$o)
  val <- 1 - sqrt((r - 1)^2 + (alpha - 1)^2 + (beta - 1)^2)
  if (components) return(c(kge = val, r = r, alpha = alpha, beta = beta))
  val
}

#' Percent bias; positive = model underestimates (Moriasi sign convention)
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @export
pbias <- function(obs, sim) {
  x <- .pairs(obs, sim)
  if (length(x$o) == 0 || sum(x$o) == 0) return(NA_real_)
  100 * sum(x$o - x$s) / sum(x$o)
}

#' RMSE / standard deviation of observations
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @export
rsr <- function(obs, sim) {
  x <- .pairs(obs, sim)
  den <- sqrt(sum((x$o - mean(x$o))^2))
  if (length(x$o) < 2 || den == 0) return(NA_real_)
  sqrt(sum((x$o - x$s)^2)) / den
}

#' Coefficient of determination (squared Pearson r)
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @export
r2 <- function(obs, sim) {
  x <- .pairs(obs, sim)
  if (length(x$o) < 2 || stats::sd(x$s) == 0) return(NA_real_)
  stats::cor(x$o, x$s)^2
}

#' Error metrics: root mean square error, mean absolute error, sum of squared errors
#'
#' @param obs,sim Observed and simulated values; pairs with an NA are dropped.
#' @return A number (NA if no complete pairs).
#' @name error_metrics
NULL

#' @rdname error_metrics
#' @export
rmse <- function(obs, sim) { x <- .pairs(obs, sim); if (!length(x$o)) NA_real_ else sqrt(mean((x$s - x$o)^2)) }
#' @rdname error_metrics
#' @export
mae  <- function(obs, sim) { x <- .pairs(obs, sim); if (!length(x$o)) NA_real_ else mean(abs(x$s - x$o)) }
#' @rdname error_metrics
#' @export
sse  <- function(obs, sim) { x <- .pairs(obs, sim); if (!length(x$o)) NA_real_ else sum((x$s - x$o)^2) }

#' All metrics in one row, for comparing models on a common evaluation set
#' @param obs,sim Observed and simulated values (pairs with an NA are dropped).
#' @export
eval_metrics <- function(obs, sim) {
  k <- kge(obs, sim, components = TRUE)
  tibble::tibble(
    n = sum(!is.na(obs) & !is.na(sim)),
    nse = nse(obs, sim), kge = unname(k[1]), kge_r = unname(k[2]),
    kge_alpha = unname(k[3]), kge_beta = unname(k[4]),
    log_nse = log_nse(obs, sim), pbias = pbias(obs, sim),
    rsr = rsr(obs, sim), r2 = r2(obs, sim), rmse = rmse(obs, sim), mae = mae(obs, sim)
  )
}
