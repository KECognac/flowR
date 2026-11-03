# Fitting several models to one basin -------------------------------------------------
#   fits <- fit_models(b)                 # all built-in models, blocked CV +
#                                         # climate-contrast test + full-record fit
#   summary(fits); plot(fits); coef(fits)
#   predict(fits, forcing = future_forcing)

#' Checks a basin should pass before models are fit
#'
#' @param basin A `wsva_basin` with forcing (`add_forcing()`).
#' @param k_folds Cross-validation folds (needs at least 2 water years each).
#' @param min_obs_frac Water years with less observed flow are not scored.
#' @return Tibble: check, status ("ok", "warn", "fail"), detail.
#' @export
check_basin <- function(basin, k_folds = 5, min_obs_frac = 0.8) {
  stopifnot(inherits(basin, "wsva_basin"))
  row <- function(check, status, detail) tibble::tibble(check = check, status = status, detail = detail)
  out <- list()
  if (is.null(basin$forcing)) return(row("forcing", "fail", "no forcing: run add_forcing()"))
  d <- dplyr::left_join(basin$forcing, dplyr::select(basin$flow, date, q_mm), by = "date")
  d$wy <- calc_water_year(d$date)
  wy_obs <- tapply(!is.na(d$q_mm), d$wy, mean)
  n_wy <- sum(wy_obs[-1] >= min_obs_frac)                 # first water year is warm-up
  out$record <- row("record length", if (n_wy >= 2 * k_folds) "ok" else "fail",
                    sprintf("%d water years with >= %.0f%% observed flow inside the forcing period (need %d)",
                            n_wy, 100 * min_obs_frac, 2 * k_folds))
  e <- basin$area$err_pct
  out$area <- row("drainage area", if (abs(e) <= 10) "ok" else "warn",
                  sprintf("watershed %.1f km2 vs reference %.1f km2 (%+.1f%%, %s)", basin$area$delineated_km2,
                          basin$area$reference_km2, e, basin$area$reference_source))
  full_wy <- names(wy_obs)[wy_obs >= min_obs_frac][-1]
  dd <- d[d$wy %in% full_wy, ]
  qp <- sum(dd$q_mm, na.rm = TRUE) / sum(dd$prcp_mm[!is.na(dd$q_mm)])
  out$budget <- row("runoff ratio", if (is.finite(qp) && qp < 0.9) "ok" else "warn",
                    sprintf("Q/P = %.2f%s", qp, if (is.finite(qp) && qp >= 0.9)
                      " (high: precipitation undercatch, wrong area or imported water?)" else ""))
  cls <- basin$screening$gagesii_class %||% NA
  out$screen <- row("human influence", if (isTRUE(cls == "Ref")) "ok" else "warn",
                    if (is.na(cls)) "not screened (not a GAGES-II gauge): check for diversions and regulation"
                    else paste("GAGES-II class:", cls))
  out$size <- row("basin size", if (basin$area$reference_km2 <= 2000) "ok" else "warn",
                  sprintf("%.0f km2%s", basin$area$reference_km2,
                          if (basin$area$reference_km2 > 2000) " (large for lumped models)" else ""))
  dplyr::bind_rows(out)
}

# Model inputs from a basin: forcing + PET + observed flow, static, hypsometry
.basin_inputs <- function(basin) {
  daily <- prepare_forcing(basin$forcing, basin$static) %>%
    dplyr::left_join(dplyr::select(basin$flow, date, q_mm), by = "date") %>%
    dplyr::mutate(wy = calc_water_year(date))
  list(daily = daily, static = basin$static, hypso = basin$hypso)
}

#' Calibrate and evaluate several process models on one basin
#'
#' Every model gets the same forcing, PET, folds and calibration algorithm
#' (DDS). For each model:
#'   * blocked water-year cross-validation (out-of-sample skill and a
#'     continuous out-of-sample series),
#'   * optionally the climate-contrast (differential split-sample) test,
#'   * optionally one calibration on all scored years: the parameters
#'     `predict()` uses with new forcing (e.g. climate projections).
#'
#' Results are cached per model and design under
#' `wsva_path("fits", <basin id>)`, keyed by everything that affects them,
#' so re-running only fits what changed.
#'
#' @param basin A `wsva_basin`. Forcing and attributes are added if missing.
#' @param models Model ids (see `names(.builtin_models())` / `wsva_models()`).
#' @param cv Evaluation designs: "blocked" and/or "climate_contrast".
#' @param objective function(obs, sim) to maximize (default `kge`).
#' @param n_evals DDS model runs per calibration (scaled by each model's
#'   `n_evals_mult`).
#' @param k_folds Blocked folds.
#' @param contrast_frac Fraction of water years in each climate-contrast group.
#' @param min_obs_frac Water years with less observed flow are not scored.
#' @param fit_full Also calibrate on all scored years.
#' @param n_layers Elevation bands for CemaNeige and HBV.
#' @param n_cores Folds calibrated in parallel.
#' @param seed Base seed.
#' @param cache Reuse cached results.
#' @return A `wsva_fit`.
#' @export
fit_models <- function(basin, models = c("wbm", "gr4j", "gr5j", "gr6j", "hbv"),
                       cv = c("blocked", "climate_contrast"), objective = kge, n_evals = 1000,
                       k_folds = 5, contrast_frac = 1 / 3, min_obs_frac = 0.8, fit_full = TRUE,
                       n_layers = 5, n_cores = 1, seed = 1, cache = TRUE) {
  stopifnot(inherits(basin, "wsva_basin"))
  cv <- match.arg(cv, c("blocked", "climate_contrast"), several.ok = TRUE)
  if (!"blocked" %in% cv) stop("cv must include \"blocked\" (it provides the out-of-sample series)")
  objective_name <- paste(deparse(substitute(objective)), collapse = "")
  if (is.null(basin$forcing)) { message("Adding forcing"); basin <- add_forcing(basin) }
  if (is.null(basin$static)) { message("Adding basin attributes"); basin <- add_basin_attributes(basin) }

  checks <- check_basin(basin, k_folds, min_obs_frac)
  if (any(checks$status == "fail"))
    stop("Basin failed checks:\n", paste0("  ", checks$check[checks$status == "fail"], ": ",
                                          checks$detail[checks$status == "fail"], collapse = "\n"), call. = FALSE)

  specs <- wsva_models(models, n_layers = n_layers)
  for (s in specs) {
    if (!is.na(s$package) && !requireNamespace(s$package, quietly = TRUE)) stop(s$name, " needs the ", s$package, " package")
  }
  x <- .basin_inputs(basin)
  for (s in specs) {
    miss <- setdiff(s$requires, names(x$daily))
    if (length(miss)) stop(s$name, " needs forcing column(s): ", paste(miss, collapse = ", "))
  }
  obs <- x$daily$q_mm
  folds <- list(
    blocked = make_blocked_folds(x$daily$date, k = k_folds, warmup_years = 1, min_obs_frac = min_obs_frac, obs = obs),
    climate_contrast = if ("climate_contrast" %in% cv)
      make_climate_contrast_folds(x$daily, frac = contrast_frac, warmup_years = 1, min_obs_frac = min_obs_frac))
  scored <- folds$blocked$role[folds$blocked$fold == 1] %in% c("train", "test")

  cache_dir <- wsva_path("fits", basin$id)
  data_hash <- rlang::hash(list(x, deparse(objective), n_layers, seed))   # deparse: stable across sessions
  cached <- function(what, spec, n, fn) {
    key <- rlang::hash(list(data_hash, what, spec$bounds, n, if (what %in% names(folds)) folds[[what]]))
    f <- file.path(cache_dir, sprintf("%s_%s_%s.rds", spec$id, what, substr(key, 1, 12)))
    if (cache && file.exists(f)) return(readRDS(f))
    t0 <- Sys.time()
    r <- fn()
    r$minutes <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
    saveRDS(r, f)
    r
  }

  results <- lapply(specs, function(s) {
    fn <- s$build(x)
    n <- round(n_evals * s$n_evals_mult)
    out <- list()
    for (design in cv) {
      message(sprintf("%s: %s", s$name, design))
      out[[design]] <- cached(design, s, n, function()
        cross_validate_model(fn, s$bounds, obs, folds[[design]], objective = objective, n_evals = n,
                             n_cores = n_cores, seed = seed))
    }
    if (fit_full) {
      message(sprintf("%s: full record", s$name))
      out$full <- cached("full", s, n, function()
        calibrate_model(fn, s$bounds, obs, score_idx = scored, objective = objective, n_evals = n, seed = seed))
    }
    out
  })
  names(results) <- vapply(specs, `[[`, "", "id")

  # Continuous out-of-sample series (blocked CV) + benchmarks
  oos_of <- function(sims) { v <- rep(NA_real_, length(obs)); v[match(sims$date, x$daily$date)] <- sims$sim; v }
  oos <- tibble::tibble(date = x$daily$date, wy = x$daily$wy, obs = obs)
  for (id in names(results)) oos[[id]] <- oos_of(results[[id]]$blocked$sims)
  if (length(results) > 1) oos$mean <- rowMeans(as.matrix(oos[names(results)]))
  doy <- rep(NA_real_, length(obs))
  for (f in unique(folds$blocked$fold)) {
    fd <- folds$blocked[folds$blocked$fold == f, ]
    b <- benchmark_doy_climatology(obs, x$daily$date, train_idx = fd$role == "train")
    doy[fd$role == "test"] <- b[fd$role == "test"]
  }
  oos$doy_climatology <- doy

  # Metrics: per model, design, fold (the mean and the benchmark on blocked folds)
  contrast_names <- if (!is.null(folds$climate_contrast)) dplyr::distinct(folds$climate_contrast, fold, contrast)
  metrics <- dplyr::bind_rows(lapply(names(results), function(id) dplyr::bind_rows(lapply(cv, function(design) {
    m <- dplyr::mutate(results[[id]][[design]]$metrics, model = id, design = design, .before = 1)
    if (design == "climate_contrast") m <- dplyr::left_join(m, contrast_names, by = "fold")
    m
  }))))
  extra <- intersect(c("mean", "doy_climatology"), names(oos))
  metrics <- dplyr::bind_rows(metrics, dplyr::bind_rows(lapply(extra, function(col)
    dplyr::bind_rows(lapply(unique(folds$blocked$fold), function(f) {
      te <- folds$blocked$role[folds$blocked$fold == f] == "test"
      dplyr::mutate(eval_metrics(obs[te], oos[[col]][te]), model = col, design = "blocked", fold = f,
                    set = "test", .before = 1)
    })))))

  structure(list(
    basin = list(id = basin$id, name = basin$name, area = basin$area, provenance = basin$provenance,
                 screening = basin$screening, polygon = basin$polygon, outlet = basin$outlet,
                 forcing_source = basin$forcing_source),
    inputs = x, models = specs, results = results, oos = oos, metrics = metrics, checks = checks,
    settings = list(models = models, cv = cv, objective = objective_name, n_evals = n_evals, k_folds = k_folds,
                    contrast_frac = contrast_frac, min_obs_frac = min_obs_frac, fit_full = fit_full,
                    n_layers = n_layers, seed = seed),
    version = as.character(utils::packageVersion("WSVAflowR"))
  ), class = "wsva_fit")
}
