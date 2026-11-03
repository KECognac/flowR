# IHACRES-style linear routing ----------------------------------------------------
# Two parallel linear reservoirs (quick and slow) applied to effective
# rainfall / lumped runoff, after the `expuh` unit hydrograph in hydromad:
#   Andrews F, Guillaume J, Vervoort W, Buzacott A (2021). hydromad.
#   https://github.com/josephguillaume/hydromad
# Each store is a first-order recursive filter: X[t] = a X[t-1] + b U[t],
# with a = exp(-1/tau) and b = v (1 - a), so the unit hydrograph of each store
# integrates to v and total volume is conserved (before losses).
# Inputs and outputs are in the same depth units (mm/day in flowR).

.linear_store <- function(u, tau, v, init = 0) {
  a <- exp(-1 / tau)
  as.numeric(stats::filter(v * (1 - a) * u, a, method = "recursive", init = init))
}

.lag_fill0 <- function(x, k) if (k > 0) c(rep(0, k), x[seq_len(length(x) - k)]) else x

#' Route runoff through quick and slow linear stores with optional losses
#'
#' Port of `runoff_routing_gw()`, taking a numeric vector rather than a data
#' frame so it composes with any upstream runoff model.
#'
#' @param runoff Numeric vector of runoff (no NA).
#' @param tau_q,tau_s Quick and slow recession time constants (time steps).
#' @param vs Fraction of runoff entering the slow store (0-1).
#' @param loss Fraction lost to deep groundwater (0-1).
#' @param slow_only If TRUE, losses come only from the slow store (capped at
#'   `max_loss` per step); otherwise from both.
#' @param delay Whole-time-step lag applied to all components.
#' @param baseflow Constant added to total flow (e.g. spring inflow).
#' @param return_components If TRUE return a tibble of components.
#' @return Numeric vector of routed flow, or a tibble with q_quick, q_slow,
#'   q_loss, q_total.
#' @param max_loss Maximum loss per time step when `slow_only = TRUE`.
#' @export
route_ihacres <- function(runoff, tau_q, tau_s, vs, loss = 0, slow_only = FALSE,
                          max_loss = Inf, delay = 0, baseflow = 0,
                          return_components = FALSE) {
  stopifnot(tau_q > 0, tau_s > 0, vs >= 0, vs <= 1, !anyNA(runoff))
  xq <- .linear_store(runoff, tau_q, 1 - vs)
  xs <- .linear_store(runoff, tau_s, vs)

  if (slow_only) {
    xg <- pmin(loss * xs, max_loss)
    xs <- xs - xg
  } else {
    xg <- loss * (xq + xs)
    xq <- (1 - loss) * xq
    xs <- (1 - loss) * xs
  }

  k <- round(delay)
  xq <- .lag_fill0(xq, k); xs <- .lag_fill0(xs, k); xg <- .lag_fill0(xg, k)
  q <- xq + xs + baseflow

  if (!return_components) return(q)
  tibble::tibble(q_quick = xq, q_slow = xs, q_loss = xg, q_total = q)
}

#' Route rain- and melt-derived runoff through separate stores
#'
#' Port of `runoff_routing_snow_fun()`. Total runoff is split into rain and
#' melt portions by the share of rain vs. melt in that day's water input;
#' rain runoff gets quick + slow stores and melt runoff a single slow store.
#'
#' FIX: the original computed the melt store's gain from the rain slow-store
#' recession (alpha_s_rain) instead of the melt recession, so melt volume was
#' not conserved whenever tau_s_melt != tau_s_rain.
#'
#' @param runoff,rain,melt Numeric vectors of equal length (no NA).
#' @param tau_q_rain,tau_s_rain,vs_rain Rain quick/slow stores.
#' @param tau_s_melt Melt store time constant.
#' @param delay Whole-time-step lag.
#' @param return_components If TRUE return a tibble of components.
#' @export
route_ihacres_snow <- function(runoff, rain, melt, tau_q_rain, tau_s_rain, vs_rain,
                               tau_s_melt, delay = 0, return_components = FALSE) {
  stopifnot(length(runoff) == length(rain), length(rain) == length(melt))
  melt_frac <- ifelse(rain + melt > 0, melt / (rain + melt), 0)
  ro_melt <- melt_frac * runoff
  ro_rain <- runoff - ro_melt

  xqr <- .linear_store(ro_rain, tau_q_rain, 1 - vs_rain)
  xsr <- .linear_store(ro_rain, tau_s_rain, vs_rain)
  xsm <- .linear_store(ro_melt, tau_s_melt, 1)

  k <- round(delay)
  xqr <- .lag_fill0(xqr, k); xsr <- .lag_fill0(xsr, k); xsm <- .lag_fill0(xsm, k)
  q <- xqr + xsr + xsm

  if (!return_components) return(q)
  tibble::tibble(q_quick_rain = xqr, q_slow_rain = xsr, q_slow_melt = xsm, q_total = q)
}
