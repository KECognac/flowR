# Process-model registry ------------------------------------------------------------
# One entry per calibratable process model. Each entry gives its calibration
# bounds and a `build(x)` that turns a basin's inputs into a closure
# function(params) -> daily streamflow (mm/day), aligned with x$daily.
#
# `x` is list(daily, static, hypso) as returned by read_basin_inputs(): the
# daily table must satisfy the forcing contract in R/forcing.R and carry
# pet_mm. Because build() only reads the forcing contract, the same
# calibrated parameters can drive a model with any climate source:
#   fn_hist <- spec$build(read_basin_inputs(site))
#   cal     <- calibrate_model(fn_hist, spec$bounds, obs, ...)
#   x_fut   <- x_hist; x_fut$daily <- prepare_forcing(future_daily, x_hist$static)
#   q_fut   <- spec$build(x_fut)(cal$best)

# Parameters as a plain numeric vector in `names` order, from a named list or
# vector (robust to inner names, which unlist() would mangle)
.par_vector <- function(par, names) {
  missing <- setdiff(names, names(par))
  if (length(missing)) stop("Missing parameter(s): ", paste(missing, collapse = ", "))
  vapply(names, function(n) as.numeric(par[[n]])[1], numeric(1))
}

#' Calibration bounds for WBM + IHACRES routing (the ranges notebook 03 uses)
#' @export
wbm_ihacres_bounds <- function() {
  param_bounds(
    hock         = c(0.5, 8),     # degree-day melt factor (mm C-1 day-1)
    jtemp_offset = c(-3, 3),      # shift on the rain/snow threshold (C)
    soil_mult    = c(0.1, 5),     # multiplier on soil water capacity
    tau_q        = c(0.5, 30),    # quickflow recession (days)
    tau_s        = c(10, 400),    # slowflow recession (days)
    vs           = c(0.05, 0.95), # fraction of runoff routed through the slow store
    loss         = c(0, 0.5),     # fraction lost to deep groundwater
    delay        = c(0, 2),       # routing lag (whole days)
    .integer = "delay"
  )
}

#' WBM (Penman-Monteith x Kc) + IHACRES routing as a calibration closure
#' @param daily Daily forcing meeting the forcing contract.
#' @param static One-row static table (`get_basin_static()` + `basin_kc()`).
#' @export
wbm_ihacres_model <- function(daily, static) {
  wbm_pars <- c("hock", "jtemp_offset", "soil_mult")
  function(p) {
    wb <- wbm_run(daily, c(as.list(static), p[wbm_pars]), pet_method = "penman_monteith")
    route_ihacres(wb$runoff, tau_q = p$tau_q, tau_s = p$tau_s, vs = p$vs,
                  loss = p$loss, delay = p$delay)
  }
}

#' Define a process model for `fit_models()`
#'
#' A model spec says how to turn a basin's inputs into a simulation closure
#' and what to calibrate. Built-in specs: `wsva_models()`. Add your own with
#' `register_model()`.
#'
#' @param id Short id used in `fit_models(models = ...)` (e.g. "gr4j").
#' @param name Display name.
#' @param bounds Calibration bounds (`param_bounds()`).
#' @param build `function(x, n_layers)` returning `function(params)` ->
#'   daily flow (mm/day) aligned with `x$daily`. `x` is list(daily, static,
#'   hypso); `x$daily` meets the forcing contract (R/forcing.R) and has
#'   `pet_mm`.
#' @param requires Columns of `x$daily` the model reads (checked before fitting).
#' @param n_evals_mult Multiplier on the DDS budget (more parameters, more runs).
#' @param package Package the model needs (checked when it is used), or NA.
#' @param reference Citation.
#' @return A `wsva_model`.
#' @export
wsva_model <- function(id, name, bounds, build, requires = c("prcp_mm", "tmean_c", "pet_mm"),
                       n_evals_mult = 1, package = NA_character_, reference = NA_character_) {
  stopifnot(is.character(id), length(id) == 1, is.function(build), all(c("param", "lower", "upper") %in% names(bounds)))
  structure(list(id = id, name = name, bounds = bounds, build = build, requires = requires,
                 n_evals_mult = n_evals_mult, package = package, reference = reference),
            class = "wsva_model")
}

#' @export
print.wsva_model <- function(x, ...) {
  cat(sprintf("<wsva_model> %s (%s): %d parameters%s\n", x$name, x$id, sum(x$bounds$lower < x$bounds$upper),
              if (!is.na(x$package)) paste0(", needs ", x$package) else ""))
  if (!is.na(x$reference)) cat("  ", x$reference, "\n")
  invisible(x)
}

.wsva_registry <- new.env(parent = emptyenv())

#' Register a user-defined model so `fit_models()` can use it
#' @param spec A `wsva_model`.
#' @return The spec, invisibly.
#' @export
register_model <- function(spec) {
  stopifnot(inherits(spec, "wsva_model"))
  if (spec$id %in% names(.builtin_models())) stop("'", spec$id, "' is a built-in model id")
  assign(spec$id, spec, envir = .wsva_registry)
  invisible(spec)
}

.builtin_models <- function() {
  gr <- function(m, ref) wsva_model(
    id = tolower(m), name = paste0("CemaNeige-", m), bounds = gr_bounds(m),
    requires = c("prcp_mm", "tmean_c", "tmin_c", "tmax_c", "pet_mm"), package = "airGR", reference = ref,
    build = function(x, n_layers = 5) {
      su <- gr_setup(x$daily, x$daily$pet_mm, x$hypso, x$static$elev_m, n_layers, model = m)
      function(p) gr_run(su, p)
    })
  list(
    wbm = wsva_model(
      id = "wbm", name = "WBM + IHACRES", bounds = wbm_ihacres_bounds(),
      requires = c(forcing_required_vars()[-1], "tmean_c"),
      reference = "Thornthwaite-Mather water balance (NPS WBM) + IHACRES routing (Jakeman & Hornberger 1993)",
      build = function(x, n_layers = 5) wbm_ihacres_model(x$daily, x$static)),
    gr4j = gr("GR4J", "Perrin et al. 2003, J. Hydrol. 279:275; CemaNeige: Valery et al. 2014"),
    gr5j = gr("GR5J", "Le Moine 2008; Pushpalatha et al. 2011, J. Hydrol. 411:66"),
    gr6j = gr("GR6J", "Pushpalatha et al. 2011, J. Hydrol. 411:66"),
    hbv = wsva_model(
      id = "hbv", name = "HBV (TUWmodel)", bounds = hbv_bounds(), n_evals_mult = 2,
      requires = c("prcp_mm", "tmean_c", "tmin_c", "tmax_c", "pet_mm"), package = "TUWmodel",
      reference = "Parajka et al. 2007, Hydrol. Process. 21:435",
      build = function(x, n_layers = 5) {
        su <- hbv_setup(x$daily, x$daily$pet_mm, x$hypso, x$static$elev_m, n_layers)
        function(p) hbv_run(su, p)
      })
  )
}

#' Available process models (built-in and registered)
#'
#' @param ids Optional model ids to return (default: all).
#' @param n_layers Elevation bands for CemaNeige and HBV, baked into each
#'   spec's `build(x)`.
#' @return Named list (by display name) of `wsva_model` specs; each has
#'   `build(x)`, `bounds`, `n_evals_mult` and the fields of `wsva_model()`.
#' @export
wsva_models <- function(ids = NULL, n_layers = 5) {
  all <- c(.builtin_models(), mget(ls(.wsva_registry), envir = .wsva_registry))
  if (!is.null(ids)) {
    bad <- setdiff(ids, names(all))
    if (length(bad)) stop("Unknown model id(s): ", paste(bad, collapse = ", "),
                          ". Available: ", paste(names(all), collapse = ", "))
    all <- all[ids]
  }
  specs <- lapply(all, function(s) {
    b <- s$build
    s$build <- function(x) b(x, n_layers = n_layers)
    s
  })
  stats::setNames(specs, vapply(specs, `[[`, "", "name"))
}
