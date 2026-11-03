# HBV (TUWmodel) --------------------------------------------------------------------
# HBV-type conceptual model from TU Wien (TUWmodel; Parajka et al. 2007,
# Hydrol. Process. 21:435; structure after Bergstrom 1976). Per elevation
# zone: degree-day snow with a rain/snow transition between Ts and Tr and a
# snow correction factor; a soil-moisture store (FC) with a nonlinear
# runoff-production curve (BETA) and ET reduced below LPrat * FC. Runoff
# from all zones feeds an upper store (very fast flow above lsuz, fast
# flow), percolation (cperc) to a lower store (slow flow), and a triangular
# routing function (bmax, croute).
#
# Zones: the same equal-area elevation bands CemaNeige uses, with
# precipitation and temperature extrapolated by airGR's method (Valery et
# al. 2010), so HBV and the GR models see identical band forcing. PET is
# the basin ETo x Kc in every zone.

#' Default calibration bounds for TUWmodel (ranges from the TUWmodel docs /
#' Parajka et al. 2007)
#' @export
hbv_bounds <- function() {
  param_bounds(
    SCF    = c(0.9, 1.5),   # snow correction factor (-)
    DDF    = c(0, 5),       # degree-day factor (mm C-1 day-1)
    Tr     = c(1, 3),       # all rain above (C)
    Ts     = c(-3, 1),      # all snow below (C)
    Tm     = c(-2, 2),      # melt threshold (C)
    LPrat  = c(0, 1),       # ET at potential above LPrat * FC (-)
    FC     = c(10, 600),    # field capacity (mm)
    BETA   = c(0, 20),      # runoff-production nonlinearity (-)
    k0     = c(0.01, 2),    # very fast storage coefficient (days)
    k1     = c(2, 30),      # fast storage coefficient (days)
    k2     = c(30, 250),    # slow storage coefficient (days)
    lsuz   = c(1, 100),     # upper-store threshold for very fast flow (mm)
    cperc  = c(0, 8),       # percolation (mm/day)
    bmax   = c(0, 30),      # maximum routing base (days)
    croute = c(0, 50)       # routing scaling (days2/mm)
  )
}

#' Build HBV zone forcing once per basin
#'
#' @inheritParams gr_setup
#' @return list(prec, airt, ep (time x zone matrices), area, z_layers)
#' @export
hbv_setup <- function(daily, pet, hypso, z_inputs, n_layers = 5) {
  stopifnot(length(pet) == nrow(daily), !anyNA(pet))
  # Reuse airGR's elevation-band extrapolation (identical to CemaNeige)
  gr <- gr_setup(daily, pet, hypso, z_inputs, n_layers, model = "GR4J")$inputs
  list(prec = do.call(cbind, gr$LayerPrecip),
       airt = do.call(cbind, gr$LayerTempMean),
       ep = matrix(pet, nrow = length(pet), ncol = n_layers),
       area = rep(1 / n_layers, n_layers),
       z_layers = gr$ZLayers)
}

#' Run TUWmodel and return simulated flow (mm/day)
#'
#' @param setup Output of `hbv_setup()`.
#' @param par Named list or vector with the 15 `hbv_bounds()` parameters.
#' @param return_components If TRUE, return a tibble with q, q0, q1, q2,
#'   basin-mean swe, soil moisture and AET.
#' @export
hbv_run <- function(setup, par, return_components = FALSE) {
  par <- .par_vector(par, hbv_bounds()$param)
  out <- TUWmodel::TUWmodel(prec = setup$prec, airt = setup$airt, ep = setup$ep, area = setup$area,
                            param = matrix(par, nrow = length(par), ncol = length(setup$area)))
  q <- as.numeric(out$q)
  if (!return_components) return(q)
  zmean <- function(m) as.numeric(matrix(m, ncol = length(setup$area)) %*% setup$area)   # time x zone
  tibble::tibble(q = q, q0 = zmean(out$q0), q1 = zmean(out$q1), q2 = zmean(out$q2),
                 swe = zmean(out$swe), soil = zmean(out$moist), aet = zmean(out$eta))
}
