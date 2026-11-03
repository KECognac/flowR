# Tests for model specs, check_basin(), fit_models() and the wsva_fit methods --
# offline, on a synthetic basin whose "observed" flow comes from GR4J.
# Run: devtools::test(filter = "fit")

skip_if_not(requireNamespace("airGR", quietly = TRUE) && requireNamespace("TUWmodel", quietly = TRUE),
            "airGR or TUWmodel not installed")

synthetic_wsva_basin <- function(n_years = 12, seed = 5) {
  set.seed(seed)
  date <- seq(as.Date("1990-10-01"), by = "day", length.out = round(365.25 * n_years))
  n <- length(date)
  doy <- as.integer(format(date, "%j"))
  tm <- 6 + 12 * sin(2 * pi * (doy - 110) / 365) + stats::rnorm(n, 0, 2)
  wet <- 1 + 0.4 * sin(2 * pi * seq_len(n) / (365.25 * 5))            # multi-year wet/dry cycle
  forcing <- tibble::tibble(date = date, prcp_mm = ifelse(stats::runif(n) < 0.3, stats::rexp(n, 1 / (8 * wet)), 0),
                            tmin_c = tm - 6, tmax_c = tm + 6, tmean_c = tm,
                            srad_wm2 = 180 + 120 * sin(2 * pi * (doy - 80) / 365),
                            rhmin_pct = 40, rhmax_pct = 90, wind_ms = 3)
  static <- tibble::tibble(id = "syn", lat = 45, lon = -110, elev_m = 2000, slope_deg = 10, aspect_deg = 180,
                           swc_max_mm = 150, jtemp_c = 1, area_km2 = 100, kc_dormant = 0.5, kc_growing = 1)
  hypso <- seq(1000, 3000, length.out = 101)
  pet <- prepare_forcing(forcing, static)$pet_mm
  q <- gr_run(gr_setup(forcing, pet, hypso, 2000), list(X1 = 400, X2 = 0, X3 = 80, X4 = 1.5, C1 = 0.5, C2 = 4))
  q[stats::runif(n) < 0.02] <- NA                                     # a few missing days
  flow <- flow_from_df(tibble::tibble(date = date, q = q), q_col = "q", units = "mm", area_km2 = 100, id = "syn")
  square <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(matrix(
    c(-110, 45, -109.87, 45, -109.87, 45.09, -110, 45.09, -110, 45), ncol = 2, byrow = TRUE))), crs = 4326))
  b <- suppressWarnings(wsva_basin(flow, polygon = square, area_km2 = 100))
  b$forcing <- forcing; b$forcing_source <- "synthetic"
  b$static <- static; b$hypso <- hypso
  b
}

test_that("model specs: built-ins, lookup by id, and user registration", {
  m <- wsva_models()
  expect_equal(unname(vapply(m, `[[`, "", "id")), c("wbm", "gr4j", "gr5j", "gr6j", "hbv"))
  expect_s3_class(m[[1]], "wsva_model")
  expect_named(wsva_models(c("hbv", "gr4j")), c("HBV (TUWmodel)", "CemaNeige-GR4J"))
  expect_error(wsva_models("nope"), "Unknown model")
  expect_error(register_model(wsva_model("gr4j", "x", gr_bounds(), function(x, n_layers) identity)), "built-in")
})

test_that("check_basin flags a record that is too short to cross-validate", {
  b <- synthetic_wsva_basin(n_years = 6)
  ck <- check_basin(b, k_folds = 5)
  expect_equal(ck$status[ck$check == "record length"], "fail")
  expect_error(fit_models(b, models = "gr4j", n_evals = 10), "record length")
  expect_equal(check_basin(synthetic_wsva_basin())$status[1], "ok")
})

test_that("fit_models fits, caches, and its methods work", {
  old <- options(wsva.data_dir = tempfile("wsva_fit_")); on.exit(options(old))
  b <- synthetic_wsva_basin()
  # A user model: one linear reservoir on rain + melt-free P - 0.5 PET
  register_model(wsva_model(
    id = "linres", name = "Linear reservoir", bounds = param_bounds(k = c(1, 100), f = c(0.1, 1)),
    build = function(x, n_layers) function(p) route_ihacres(pmax(x$daily$prcp_mm - 0.5 * x$daily$pet_mm, 0) * p$f,
                                                              tau_q = p$k, tau_s = p$k, vs = 0)))
  t0 <- Sys.time()
  fit <- suppressMessages(fit_models(b, models = c("gr4j", "hbv", "linres"), n_evals = 80, k_folds = 3))
  t_first <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  expect_s3_class(fit, "wsva_fit")
  expect_setequal(names(fit$results), c("gr4j", "hbv", "linres"))

  s <- summary(fit)
  expect_true(all(c("gr4j", "hbv", "linres", "mean", "doy_climatology") %in% s$skill$id))
  expect_gt(s$skill$kge[s$skill$id == "gr4j"], 0.9)                  # GR4J recovers its own flow
  expect_true(all(s$skill$kge_worst <= s$skill$kge))
  expect_equal(nrow(s$contrast), 3)
  expect_output(print(fit), "median test KGE")
  expect_output(print(s), "Opposite-climate")

  cf <- coef(fit)
  expect_setequal(unique(cf$model), c("gr4j", "hbv", "linres"))
  expect_equal(nrow(coef(fit, "blocked")), 3 * (6 + 15 + 2))

  oos <- predict(fit)
  expect_equal(nrow(oos), nrow(b$forcing))
  expect_true(all(c("obs", "gr4j", "hbv", "linres", "mean") %in% names(oos)))
  # New forcing: warmer by 2 C -> more PET -> less flow; first year is spin-up
  hot <- b$forcing; hot$tmin_c <- hot$tmin_c + 2; hot$tmax_c <- hot$tmax_c + 2; hot$tmean_c <- hot$tmean_c + 2
  p0 <- predict(fit, forcing = b$forcing); p2 <- predict(fit, forcing = hot)
  expect_true(all(is.na(p2$gr4j[1:365])))
  expect_lt(mean(p2$gr4j, na.rm = TRUE), mean(p0$gr4j, na.rm = TRUE))
  expect_true(all(p0$hbv >= 0, na.rm = TRUE))

  skip_if_not_installed("ggplot2")
  for (t in c("hydrograph", "fdc", "seasonal", "annual", "skill", "contrast", "params"))
    expect_s3_class(plot(fit, type = t), "ggplot")

  # Cache: a second identical call reads results instead of calibrating
  t0 <- Sys.time()
  fit2 <- suppressMessages(fit_models(b, models = c("gr4j", "hbv", "linres"), n_evals = 80, k_folds = 3))
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), t_first / 2)
  expect_equal(fit2$metrics, fit$metrics)
  rm("linres", envir = WSVAflowR:::.wsva_registry)
})
