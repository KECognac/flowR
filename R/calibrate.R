# Model-agnostic calibration and cross-validation --------------------------------
# Replaces test_model_fit(). Any parameterized model plugs in through a
# closure `model_fn(par)` that takes a named parameter list and returns a
# simulated series aligned with `obs`. Which days are scored is decided
# only by index vectors from splits.R, so every model sees the same
# train/test days. ML models (fit/predict rather than parameter search)
# will get a parallel interface that reuses the same fold tables.
#
# Search: Dynamically Dimensioned Search (DDS; Tolson & Shoemaker 2007,
# Water Resour. Res. 43, W01413). DDS is derivative-free, so it copes with
# the kinks that thresholds (snow, soil capacity) put in the objective,
# and it is designed for small evaluation budgets: early on it perturbs
# all parameters (global search), then progressively fewer (local
# refinement). Integer parameters are handled by rounding (discrete DDS).
# On a test fold it matched multi-start L-BFGS-B (KGE within ~0.01) with
# ~1/3 of the model runs.

#' Parameter bounds table
#' @param ... name = c(lower, upper). Equal bounds fix the parameter.
#' @param .integer Names of parameters that take whole-number values.
#' @export
param_bounds <- function(..., .integer = character()) {
  b <- list(...)
  stopifnot(all(.integer %in% names(b)))
  tibble::tibble(param = names(b),
                 lower = vapply(b, `[`, numeric(1), 1),
                 upper = vapply(b, `[`, numeric(1), 2),
                 integer = names(b) %in% .integer)
}

# DDS core: minimizes fn over [lo, hi]. Returns best x, value, and the
# best-so-far trace (one entry per evaluation, initial sampling included).
.dds <- function(fn, lo, hi, is_int, n_evals, r = 0.2) {
  k <- length(lo)
  rng <- hi - lo
  snap <- function(x) { x[is_int] <- round(x[is_int]); x }

  # Initial solution: best of a few uniform random points (Tolson & Shoemaker
  # recommend max(5, 0.5% of the budget))
  n_init <- max(5, ceiling(0.005 * n_evals))
  init <- lapply(seq_len(n_init), function(i) snap(stats::runif(k, lo, hi)))
  init_f <- vapply(init, fn, numeric(1))
  best <- which.min(init_f)
  x <- init[[best]]; fx <- init_f[best]
  trace <- c(cummin(init_f), numeric(max(0, n_evals - n_init)))

  for (i in seq_len(n_evals - n_init)) {
    # Probability of perturbing each parameter shrinks from 1 toward 0
    pick <- stats::runif(k) < 1 - log(i) / log(n_evals - n_init)
    if (!any(pick)) pick[sample.int(k, 1)] <- TRUE
    y <- x
    y[pick] <- y[pick] + r * rng[pick] * stats::rnorm(sum(pick))
    # Reflect off the bounds; clamp if the reflection overshoots
    y <- ifelse(y < lo, lo + (lo - y), y)
    y <- ifelse(y > hi, hi - (y - hi), y)
    y <- pmin(pmax(y, lo), hi)
    y <- snap(y)
    # Discrete DDS: a picked integer that rounded back to its old value moves by 1
    stuck <- pick & is_int & y == x
    if (any(stuck)) {
      step <- sample(c(-1, 1), sum(stuck), replace = TRUE)
      y[stuck] <- pmin(pmax(x[stuck] + step, lo[stuck]), hi[stuck])
    }
    fy <- fn(y)
    if (fy <= fx) { x <- y; fx <- fy }
    trace[n_init + i] <- fx
  }
  list(x = x, value = fx, trace = trace)
}

#' Calibrate a model with DDS
#'
#' @param model_fn function(par) -> numeric vector aligned with `obs`.
#' @param bounds Output of `param_bounds()`.
#' @param obs Observed series.
#' @param score_idx Integer or logical index of days used in the objective.
#' @param objective function(obs, sim) -> numeric. Default `kge`.
#' @param maximize TRUE for efficiencies (NSE/KGE), FALSE for errors.
#' @param n_evals Total model runs. ~1000 is enough for ~8 parameters;
#'   scale up with the number of free parameters.
#' @param r DDS perturbation size as a fraction of each parameter range.
#' @param seed RNG seed for reproducibility.
#' @return list(best = named list of all parameters, value = objective,
#'   trace = best-so-far objective per evaluation)
#' @export
calibrate_model <- function(model_fn, bounds, obs, score_idx, objective = kge,
                            maximize = TRUE, n_evals = 1000, r = 0.2, seed = 1) {
  set.seed(seed)
  if (is.logical(score_idx)) score_idx <- which(score_idx)
  if (is.null(bounds$integer)) bounds$integer <- FALSE
  free <- bounds$lower < bounds$upper
  fixed <- stats::setNames(as.list(bounds$lower[!free]), bounds$param[!free])
  full_par <- function(x) c(as.list(stats::setNames(x, bounds$param[free])), fixed)[bounds$param]
  sgn <- if (maximize) 1 else -1

  score <- function(par) {
    sim <- tryCatch(model_fn(par), error = function(e) NULL)
    if (is.null(sim) || length(sim) != length(obs) || any(!is.finite(sim[score_idx]))) return(NA_real_)
    objective(obs[score_idx], sim[score_idx])
  }
  # DDS minimizes; failed or undefined runs get a large penalty
  loss <- function(x) { v <- score(full_par(x)); if (is.na(v)) 1e6 else -sgn * v }

  res <- .dds(loss, bounds$lower[free], bounds$upper[free], bounds$integer[free],
              n_evals = n_evals, r = r)
  list(best = full_par(res$x), value = -sgn * res$value, trace = -sgn * res$trace)
}

#' Blocked cross-validation of a calibrated model
#'
#' For each fold, calibrates on "train" days and scores both train and test.
#' Folds are independent, so they can run in parallel: forked processes
#' (`parallel::mclapply`) on macOS/Linux; on Windows, `future.apply` under
#' the user's `future::plan()` if installed, otherwise serially.
#'
#' @param folds Output of `make_blocked_folds()` (dates must match `obs`).
#' @param n_cores Folds run at once.
#' @param seed Base seed; fold f uses seed + f, so results don't depend on
#'   n_cores.
#' @param ... Passed to `calibrate_model()`.
#' @return list(metrics = tibble per fold x set, params = tibble per fold,
#'   sims = long tibble of out-of-fold test simulations, traces = tibble of
#'   best-so-far objective per evaluation and fold)
#' @param model_fn,bounds,obs As for `calibrate_model()`: parameters -> simulated flow, `param_bounds()`, observed flow.
#' @export
cross_validate_model <- function(model_fn, bounds, obs, folds, n_cores = 1, seed = 1, ...) {

  run_fold <- function(f) {
    fd <- folds[folds$fold == f, ]
    stopifnot(nrow(fd) == length(obs))
    cal <- calibrate_model(model_fn, bounds, obs, score_idx = fd$role == "train",
                           seed = seed + f, ...)
    sim <- model_fn(cal$best)
    tr <- fd$role == "train"; te <- fd$role == "test"
    list(
      metrics = dplyr::bind_rows(
        dplyr::mutate(eval_metrics(obs[tr], sim[tr]), fold = f, set = "train", .before = 1),
        dplyr::mutate(eval_metrics(obs[te], sim[te]), fold = f, set = "test", .before = 1)
      ),
      params = tibble::as_tibble_row(c(fold = f, cal$best, objective = cal$value)),
      sims = tibble::tibble(fold = f, date = fd$date[te], obs = obs[te], sim = sim[te]),
      traces = tibble::tibble(fold = f, eval = seq_along(cal$trace), objective = cal$trace)
    )
  }

  fold_ids <- sort(unique(folds$fold))
  res <- .par_lapply(fold_ids, run_fold, n_cores)
  failed <- vapply(res, inherits, logical(1), "try-error")
  if (any(failed)) stop("Fold(s) ", paste(fold_ids[failed], collapse = ", "), " failed: ",
                        as.character(res[[which(failed)[1]]]))

  list(metrics = purrr::map_dfr(res, "metrics"),
       params = purrr::map_dfr(res, "params"),
       sims = purrr::map_dfr(res, "sims"),
       traces = purrr::map_dfr(res, "traces"))
}

# lapply over independent jobs, in parallel where the platform allows.
# Each job sets its own seed, so results don't depend on how it runs.
.par_lapply <- function(X, FUN, n_cores = 1) {
  if (n_cores <= 1 || length(X) <= 1) return(lapply(X, FUN))
  if (.Platform$OS.type != "windows") return(parallel::mclapply(X, FUN, mc.cores = min(n_cores, length(X))))
  if (requireNamespace("future.apply", quietly = TRUE))
    return(future.apply::future_lapply(X, function(x) try(FUN(x), silent = TRUE), future.seed = TRUE))
  lapply(X, FUN)
}
