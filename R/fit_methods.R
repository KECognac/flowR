# Methods for `wsva_fit` --------------------------------------------------------------

.model_label <- function(fit, ids) {
  lab <- c(stats::setNames(vapply(fit$models, `[[`, "", "name"), vapply(fit$models, `[[`, "", "id")),
           mean = "Model mean", doy_climatology = "DOY climatology")
  unname(ifelse(ids %in% names(lab), lab[ids], ids))
}

#' @export
print.wsva_fit <- function(x, ...) {
  b <- x$basin
  cat(sprintf("<wsva_fit> %s %s\n", b$id, b$name %||% ""))
  cat(sprintf("  %s flow; %s watershed, %.1f km2; forcing %s\n", b$provenance$flow, b$provenance$basin,
              b$area$reference_km2, b$forcing_source %||% ""))
  cat(sprintf("  models: %s\n  designs: %s%s\n", paste(.model_label(x, names(x$results)), collapse = ", "),
              paste(x$settings$cv, collapse = ", "), if (x$settings$fit_full) " + full-record calibration" else ""))
  s <- summary(x)$skill
  cat("  median test KGE (blocked CV):",
      paste(sprintf("%s %.2f", s$model, s$kge), collapse = "; "), "\n")
  invisible(x)
}

#' Skill summary of a `wsva_fit`
#'
#' @param object A `wsva_fit`.
#' @param ... Unused.
#' @return A `summary.wsva_fit`: list(skill = blocked-CV medians per model
#'   (plus model mean and day-of-year climatology), contrast = climate-contrast
#'   medians per model (if run), checks).
#' @export
summary.wsva_fit <- function(object, ...) {
  test <- dplyr::filter(object$metrics, set == "test")
  skill <- test %>%
    dplyr::filter(design == "blocked") %>%
    dplyr::group_by(id = model) %>%
    # kge_worst before kge: summarize() sees each new column in later expressions
    dplyr::summarize(kge_worst = min(kge), kge = stats::median(kge), nse = stats::median(nse),
                     log_nse = stats::median(log_nse), pbias = stats::median(pbias), .groups = "drop") %>%
    dplyr::relocate(kge_worst, .after = pbias) %>%
    dplyr::arrange(dplyr::desc(kge)) %>%
    dplyr::mutate(model = .model_label(object, id), .before = 1)
  contrast <- NULL
  if ("climate_contrast" %in% object$settings$cv) {
    contrast <- test %>%
      dplyr::filter(design == "climate_contrast") %>%
      dplyr::left_join(dplyr::select(skill, id, kge_blocked = kge), by = c("model" = "id")) %>%
      dplyr::group_by(id = model) %>%
      dplyr::summarize(kge_drop = stats::median(kge_blocked - kge), worst_abs_pbias = max(abs(pbias)),
                       worst_contrast = contrast[which.max(abs(pbias))], abs_pbias = stats::median(abs(pbias)),
                       kge = stats::median(kge), .groups = "drop") %>%
      dplyr::relocate(kge, kge_drop, abs_pbias, .before = worst_abs_pbias) %>%
      dplyr::arrange(abs_pbias) %>%
      dplyr::mutate(model = .model_label(object, id), .before = 1)
  }
  structure(list(skill = skill, contrast = contrast, checks = object$checks, basin = object$basin),
            class = "summary.wsva_fit")
}

#' @export
print.summary.wsva_fit <- function(x, ...) {
  cat(sprintf("%s %s\n\n", x$basin$id, x$basin$name %||% ""))
  cat("Held-out water years (blocked CV, median over folds; pbias > 0 = under-prediction):\n")
  print(as.data.frame(dplyr::select(x$skill, -id)), digits = 2, row.names = FALSE)
  if (!is.null(x$contrast)) {
    cat("\nOpposite-climate tests (median over contrasts):\n")
    print(as.data.frame(dplyr::select(x$contrast, -id)), digits = 2, row.names = FALSE)
  }
  warn <- x$checks[x$checks$status != "ok", ]
  if (nrow(warn)) cat("\nChecks:\n", paste0("  ", warn$check, ": ", warn$detail, collapse = "\n"), "\n")
  invisible(x)
}

#' Calibrated parameters of a `wsva_fit`
#'
#' @param object A `wsva_fit`.
#' @param which "full" (all-years calibration, used by `predict()`) or
#'   "blocked" (one set per CV fold).
#' @param ... Unused.
#' @return Tibble: model, (fold), param, value.
#' @export
coef.wsva_fit <- function(object, which = c("full", "blocked"), ...) {
  which <- match.arg(which)
  dplyr::bind_rows(lapply(names(object$results), function(id) {
    r <- object$results[[id]]
    if (which == "full") {
      if (is.null(r$full)) stop("Fit has no full-record calibration (fit_full = FALSE)")
      tibble::tibble(model = id, param = names(r$full$best), value = unlist(r$full$best))
    } else {
      tidyr::pivot_longer(dplyr::select(r$blocked$params, -objective), -fold, names_to = "param") %>%
        dplyr::mutate(model = id, .before = 1)
    }
  }))
}

#' Simulate flow from a `wsva_fit`
#'
#' Without `forcing`, returns the out-of-sample (blocked CV) series. With
#' `forcing`, runs each model with its full-record parameters on that
#' forcing: the step used for climate projections. The forcing must meet
#' the forcing contract (`forcing_required_vars()`); PET is computed from it
#' with the basin's crop coefficients, exactly as in calibration.
#'
#' Model states start empty, so the first `warmup_years` of the output are
#' set to NA: supply forcing that starts at least that long before the
#' period of interest.
#'
#' @param object A `wsva_fit`.
#' @param forcing Optional daily basin-mean forcing table.
#' @param models Model ids (default: all in the fit).
#' @param warmup_years Leading years returned as NA (spin-up).
#' @param ... Unused.
#' @return Tibble: date, one column per model (mm/day), and `mean`.
#' @export
predict.wsva_fit <- function(object, forcing = NULL, models = names(object$results), warmup_years = 1, ...) {
  if (is.null(forcing)) return(dplyr::select(object$oos, date, obs, dplyr::any_of(c(models, "mean", "doy_climatology"))))
  x <- object$inputs
  x$daily <- prepare_forcing(forcing, x$static)
  out <- tibble::tibble(date = as.Date(x$daily$date))
  for (id in models) {
    r <- object$results[[id]]
    if (is.null(r$full)) stop("Fit has no full-record calibration for ", id, " (fit_full = FALSE)")
    spec <- object$models[[which(vapply(object$models, `[[`, "", "id") == id)]]
    out[[id]] <- pmax(spec$build(x)(r$full$best), 0)
  }
  spin <- out$date < min(out$date) + round(365.25 * warmup_years)
  out[spin, models] <- NA
  if (length(models) > 1) out$mean <- rowMeans(as.matrix(out[models]))
  out
}

#' Plot a `wsva_fit`
#'
#' @param x A `wsva_fit`.
#' @param type "overview" (hydrographs, flow duration, seasonal cycle,
#'   annual flow), or one of "hydrograph", "fdc", "seasonal", "annual",
#'   "skill", "contrast", "params".
#' @param years Recent water years in the hydrograph.
#' @param log Log-scale hydrograph.
#' @param ... Unused.
#' @return A ggplot (or a patchwork for "overview").
#' @export
plot.wsva_fit <- function(x, type = c("overview", "hydrograph", "fdc", "seasonal", "annual", "skill",
                                      "contrast", "params"), years = 2, log = FALSE, ...) {
  type <- match.arg(type)
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("plot() needs ggplot2")
  gg <- ggplot2::ggplot; aes <- ggplot2::aes
  ids <- names(x$results)
  series_ids <- c(ids, intersect(c("mean", "doy_climatology"), names(x$oos)))
  pal <- c(wbm = "#1b6ca8", gr4j = "#459a74", gr5j = "#7fbf7b", gr6j = "#1b7837", hbv = "#dca237",
           mean = "#b02a24", doy_climatology = "grey55")
  extra <- setdiff(series_ids, names(pal))
  pal <- c(pal, stats::setNames(grDevices::hcl.colors(max(1, length(extra)), "Dark 3")[seq_along(extra)], extra))
  labs_all <- c(obs = "Observed", stats::setNames(.model_label(x, series_ids), series_ids))
  cols <- c(Observed = "black", stats::setNames(pal[series_ids], labs_all[series_ids]))
  theme <- ggplot2::theme_minimal(base_size = 10)
  title <- sprintf("%s %s", x$basin$id, x$basin$name %||% "")

  long <- x$oos %>%
    dplyr::select(date, wy, obs, dplyr::all_of(series_ids)) %>%
    tidyr::pivot_longer(-c(date, wy), names_to = "series", values_to = "q_mm") %>%
    dplyr::mutate(series = factor(labs_all[series], levels = names(cols)))
  scored <- x$oos$date[!is.na(x$oos$obs) & !is.na(x$oos[[ids[1]]])]
  sc <- dplyr::filter(long, date %in% scored)

  p_hydro <- function(log) {
    last <- max(x$oos$wy[!is.na(x$oos$obs) & !is.na(x$oos[[ids[1]]])])
    d <- dplyr::filter(long, wy > last - years, wy <= last, series != "DOY climatology")
    p <- gg(d, aes(date, q_mm, color = series)) + ggplot2::geom_line(linewidth = 0.35) +
      ggplot2::scale_color_manual(values = cols) +
      ggplot2::labs(x = NULL, y = "mm/day", color = NULL, title = paste0(title, ": out-of-sample estimates")) +
      theme + ggplot2::theme(legend.position = "top")
    if (log) p <- p + ggplot2::scale_y_log10()
    p
  }
  p_fdc <- function() {
    d <- sc %>% dplyr::filter(!is.na(q_mm)) %>% dplyr::group_by(series) %>%
      dplyr::mutate(exceedance = 1 - (rank(q_mm, ties.method = "first") - 0.5) / dplyr::n())
    gg(d, aes(exceedance, pmax(q_mm, 1e-3), color = series)) + ggplot2::geom_line() + ggplot2::scale_y_log10() +
      ggplot2::scale_color_manual(values = cols) +
      ggplot2::labs(x = "Exceedance probability", y = "mm/day (log)", color = NULL, title = "Flow duration") + theme
  }
  p_season <- function() {
    d <- sc %>%
      dplyr::mutate(month = factor(month.abb[as.integer(format(date, "%m"))], levels = month.abb[c(10:12, 1:9)])) %>%
      dplyr::group_by(series, month) %>% dplyr::summarize(q_mm = mean(q_mm, na.rm = TRUE), .groups = "drop")
    gg(d, aes(month, q_mm, color = series, group = series)) + ggplot2::geom_line() + ggplot2::geom_point(size = 0.8) +
      ggplot2::scale_color_manual(values = cols) +
      ggplot2::labs(x = NULL, y = "mm/day", color = NULL, title = "Mean monthly flow") + theme
  }
  p_annual <- function() {
    d <- sc %>% dplyr::filter(series != "DOY climatology") %>%
      dplyr::group_by(wy, series) %>% dplyr::summarize(q = sum(q_mm, na.rm = TRUE), n = dplyr::n(), .groups = "drop") %>%
      dplyr::filter(n >= 330)
    gg(d, aes(wy, q, color = series)) + ggplot2::geom_line() + ggplot2::scale_color_manual(values = cols) +
      ggplot2::labs(x = "Water year", y = "mm/year", color = NULL, title = "Annual flow") + theme
  }
  p_skill <- function() {
    d <- x$metrics %>% dplyr::filter(design == "blocked", set == "test") %>%
      tidyr::pivot_longer(c(kge, nse, log_nse), names_to = "metric") %>%
      dplyr::mutate(series = factor(labs_all[model], levels = rev(names(cols))))
    gg(d, aes(value, series, color = series)) + ggplot2::geom_vline(xintercept = 0, color = "grey70") +
      ggplot2::geom_point(alpha = 0.7) +
      ggplot2::stat_summary(fun = stats::median, geom = "point", shape = 124, size = 6) +
      ggplot2::facet_wrap(~ metric, scales = "free_x") + ggplot2::scale_color_manual(values = cols, guide = "none") +
      ggplot2::labs(x = "Test-fold score (bar = median)", y = NULL, title = title) + theme
  }
  p_contrast <- function() {
    if (!"climate_contrast" %in% x$settings$cv) stop("Fit has no climate-contrast results")
    d <- x$metrics %>% dplyr::filter(design == "climate_contrast", set == "test") %>%
      tidyr::pivot_longer(c(kge, pbias), names_to = "metric") %>%
      dplyr::mutate(series = factor(labs_all[model], levels = names(cols)))
    gg(d, aes(value, contrast, color = series)) + ggplot2::geom_point(position = ggplot2::position_dodge(0.6)) +
      ggplot2::facet_wrap(~ metric, scales = "free_x") + ggplot2::scale_color_manual(values = cols) +
      ggplot2::labs(x = "KGE / percent bias (positive = under-prediction)", y = NULL, color = NULL,
                    title = paste0(title, ": calibrate in one climate, test in the opposite")) + theme
  }
  p_params <- function() {
    d <- dplyr::bind_rows(lapply(ids, function(id) {
      b <- x$models[[which(vapply(x$models, `[[`, "", "id") == id)]]$bounds
      coef.wsva_fit(x, "blocked") %>% dplyr::filter(model == id) %>% dplyr::left_join(b, by = "param")
    })) %>% dplyr::mutate(scaled = (value - lower) / (upper - lower), series = labs_all[model])
    gg(d, aes(scaled, param)) + ggplot2::geom_point(color = "#1b6ca8", alpha = 0.7) +
      ggplot2::facet_grid(series ~ ., scales = "free_y", space = "free_y") +
      ggplot2::scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
      ggplot2::labs(x = "Position within calibration bounds", y = NULL, title = "Calibrated parameters (one point per fold)") + theme
  }

  switch(type,
    hydrograph = p_hydro(log), fdc = p_fdc(), seasonal = p_season(), annual = p_annual(),
    skill = p_skill(), contrast = p_contrast(), params = p_params(),
    overview = {
      if (!requireNamespace("patchwork", quietly = TRUE)) return(p_hydro(log))
      nl <- ggplot2::theme(legend.position = "none")
      patchwork::wrap_plots(p_hydro(FALSE), p_hydro(TRUE) + ggplot2::labs(title = NULL) + nl,
                            patchwork::wrap_plots(p_fdc() + nl, p_season() + nl), p_annual() + nl,
                            ncol = 1, heights = c(1.3, 0.9, 1, 0.9))
    })
}
