# GR family + CemaNeige (airGR) ----------------------------------------------------
# Daily lumped conceptual models from INRAE, each coupled to the CemaNeige
# snow model and implemented in airGR (Coron et al. 2017):
#   GR4J (Perrin et al. 2003, J. Hydrol. 279:275): production store X1,
#     groundwater exchange X2, routing store X3, unit-hydrograph base X4.
#   GR5J (Le Moine 2008, PhD thesis; Pushpalatha et al. 2011, J. Hydrol.
#     411:66): GR4J + X5, a threshold that makes groundwater exchange
#     depend on the routing-store level (X2 * (S/X3 - X5)).
#   GR6J (Pushpalatha et al. 2011): GR5J + X6, an exponential store in
#     parallel with the routing store, aimed at low-flow recessions.
# CemaNeige (Valery et al. 2014, J. Hydrol. 517:1166) adds a 2-parameter
# degree-day snow model run on elevation bands, with temperature and
# precipitation extrapolated from the forcing elevation to each band.
#
# All three get the same forcing, the same PET (ETo x Kc), the same folds
# and the same DDS calibration as every other model, so differences
# reflect model structure.

#' GR models available through airGR in this package
#' @return c("GR4J", "GR5J", "GR6J")
#' @export
gr_models <- function() c("GR4J", "GR5J", "GR6J")

.gr_fun <- function(model) {
  switch(match.arg(model, gr_models()),
         GR4J = airGR::RunModel_CemaNeigeGR4J,
         GR5J = airGR::RunModel_CemaNeigeGR5J,
         GR6J = airGR::RunModel_CemaNeigeGR6J)
}

#' Default calibration bounds for CemaNeige-GR4J/5J/6J
#'
#' Ranges follow common airGR practice; X2 < 0 is a groundwater loss. X5 is
#' dimensionless in GR5J (0-1) and GR6J (-2 to 2, airGR's search range);
#' X6 is the GR6J exponential-store coefficient (mm).
#' @param model "GR4J", "GR5J" or "GR6J".
#' @export
gr_bounds <- function(model = "GR4J") {
  model <- match.arg(model, gr_models())
  b <- list(
    X1 = c(10, 3000),   # production store capacity (mm)
    X2 = c(-10, 5),     # groundwater exchange coefficient (mm/day)
    X3 = c(1, 1000),    # routing store capacity (mm)
    X4 = c(0.5, 10)     # unit hydrograph time base (days)
  )
  if (model == "GR5J") b$X5 <- c(0, 1)        # exchange threshold (fraction of X3)
  if (model == "GR6J") {
    b$X5 <- c(-2, 2)                          # exchange threshold (-)
    b$X6 <- c(0.1, 100)                       # exponential store coefficient (mm)
  }
  b$C1 <- c(0, 1)       # CemaNeige snowpack thermal-state weighting
  b$C2 <- c(0, 10)      # CemaNeige degree-day melt factor (mm C-1 day-1)
  do.call(param_bounds, b)
}

#' Build the airGR inputs and run options once per basin
#'
#' @param daily Gap-free daily tibble with date, prcp_mm, tmean_c, tmin_c, tmax_c.
#' @param pet Daily potential evaporation (mm), aligned with `daily`.
#' @param hypso 101 elevation quantiles (`get_basin_hypsometry()`).
#' @param z_inputs Elevation the forcing represents (basin-mean elevation for
#'   basin-mean GridMET).
#' @param n_layers CemaNeige elevation bands.
#' @param model "GR4J", "GR5J" or "GR6J".
#' @return list(model, inputs, run_options) for `gr_run()`.
#' @export
gr_setup <- function(daily, pet, hypso, z_inputs, n_layers = 5, model = "GR4J") {
  stopifnot(length(pet) == nrow(daily), !anyNA(pet), length(hypso) == 101)
  fun <- .gr_fun(model)
  dates <- as.POSIXct(format(daily$date), tz = "UTC")
  inputs <- airGR::CreateInputsModel(
    FUN_MOD = fun, DatesR = dates,
    Precip = daily$prcp_mm, PotEvap = pet,
    TempMean = daily$tmean_c, TempMin = daily$tmin_c, TempMax = daily$tmax_c,
    ZInputs = z_inputs, HypsoData = hypso, NLayers = n_layers, verbose = FALSE
  )
  # Run the whole record; the first water year is never scored, so it acts
  # as warm-up and airGR's own warm-up period is switched off.
  run_options <- suppressWarnings(airGR::CreateRunOptions(
    FUN_MOD = fun, InputsModel = inputs,
    IndPeriod_WarmUp = 0L, IndPeriod_Run = seq_len(nrow(daily)),
    Outputs_Sim = "Qsim", verbose = FALSE, warnings = FALSE
  ))
  list(model = model, inputs = inputs, run_options = run_options)
}

#' Run a CemaNeige-GR model and return simulated flow (mm/day)
#' @param setup Output of `gr_setup()`.
#' @param par Named list or vector with the model's X parameters, C1, C2.
#' @export
gr_run <- function(setup, par) {
  par <- .par_vector(par, gr_bounds(setup$model)$param)
  out <- .gr_fun(setup$model)(InputsModel = setup$inputs,
                               RunOptions = setup$run_options, Param = unname(par))
  out$Qsim
}

# GR4J names kept (internal) for notebook 05 and its tests
gr4j_bounds <- function() gr_bounds("GR4J")
gr4j_setup <- function(daily, pet, hypso, z_inputs, n_layers = 5) gr_setup(daily, pet, hypso, z_inputs, n_layers, "GR4J")
gr4j_run <- function(setup, par) gr_run(setup, par)
