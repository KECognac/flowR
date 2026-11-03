# Tests for the forcing contract, GR5J/GR6J, HBV, the model registry and the
# climate-contrast folds -- no network needed; requires airGR and TUWmodel.
# Run: devtools::test() (all) or devtools::test(filter = "conceptual")

skip_if_not(requireNamespace("airGR", quietly = TRUE) && requireNamespace("TUWmodel", quietly = TRUE),
            "airGR or TUWmodel not installed")

synthetic_basin <- function(n_years = 8, seed = 11) {
  set.seed(seed)
  date <- seq(as.Date("2000-10-01"), by = "day", length.out = round(365.25 * n_years))
  n <- length(date)
  doy <- as.integer(format(date, "%j"))
  tm <- 6 + 12 * sin(2 * pi * (doy - 110) / 365) + stats::rnorm(n, 0, 2)
  daily <- tibble::tibble(date = date, prcp_mm = ifelse(stats::runif(n) < 0.3, stats::rexp(n, 1 / 8), 0),
                          tmin_c = tm - 6, tmax_c = tm + 6,
                          srad_wm2 = 180 + 120 * sin(2 * pi * (doy - 80) / 365),
                          rhmin_pct = 40, rhmax_pct = 90, wind_ms = 3)
  static <- tibble::tibble(lat = 45, elev_m = 2000, kc_dormant = 0.5, kc_growing = 1)
  list(daily = prepare_forcing(daily, static), static = static, hypso = seq(1000, 3000, length.out = 101))
}

test_that("prepare_forcing enforces the contract and computes PET from met variables", {
  x <- synthetic_basin()
  expect_true(all(c("tmean_c", "eto_mm", "pet_mm") %in% names(x$daily)))
  expect_true(all(x$daily$eto_mm >= 0))
  expect_true(all(x$daily$pet_mm <= x$daily$eto_mm + 1e-9))          # Kc <= 1 here
  # warmer forcing -> more PET (the property projections rely on)
  hot <- x$daily; hot$tmin_c <- hot$tmin_c + 3; hot$tmax_c <- hot$tmax_c + 3; hot$tmean_c <- NULL
  expect_gt(mean(prepare_forcing(hot, x$static)$eto_mm), mean(x$daily$eto_mm))
  expect_error(prepare_forcing(dplyr::select(x$daily, -wind_ms), x$static), "wind_ms")
  # pet_ref_kc() is the same PET
  expect_equal(pet_ref_kc(x$daily, x$static), x$daily$pet_mm)
})

test_that("GR5J and GR6J run, are non-negative, and their extra parameters matter", {
  x <- synthetic_basin()
  for (m in c("GR5J", "GR6J")) {
    b <- gr_bounds(m)
    expect_equal(b$param[c(1:4, nrow(b) - 1, nrow(b))], c("X1", "X2", "X3", "X4", "C1", "C2"))
    su <- gr_setup(x$daily, x$daily$pet_mm, x$hypso, z_inputs = 2000, model = m)
    p <- stats::setNames(as.list((b$lower + b$upper) / 2), b$param)
    p$X2 <- 0
    q <- gr_run(su, p)
    expect_length(q, nrow(x$daily))
    expect_true(all(q >= 0))
    expect_lt(sum(q), sum(x$daily$prcp_mm))
    p2 <- p; p2$X5 <- b$lower[b$param == "X5"]; p2$X2 <- -1
    expect_false(isTRUE(all.equal(gr_run(su, p2), q)))
  }
  expect_equal(nrow(gr_bounds("GR5J")), 7)
  expect_equal(nrow(gr_bounds("GR6J")), 8)
})

test_that("HBV runs on elevation zones and closes the water balance", {
  x <- synthetic_basin()
  su <- hbv_setup(x$daily, x$daily$pet_mm, x$hypso, z_inputs = 2000)
  expect_equal(dim(su$prec), c(nrow(x$daily), 5))
  expect_true(all(diff(colMeans(su$airt)) < 0))                       # higher zones are colder
  b <- hbv_bounds()
  p <- stats::setNames(as.list((b$lower + b$upper) / 2), b$param)
  p$SCF <- 1
  out <- hbv_run(su, p, return_components = TRUE)
  expect_true(all(out$q >= 0))
  # P (zone-weighted) = Q + AET + change in storage; storage change is small over 8 years
  p_in <- sum(su$prec %*% su$area)
  expect_lt(sum(out$q) + sum(out$aet), p_in * 1.02)
  expect_gt(sum(out$q) + sum(out$aet), p_in * 0.85)
  # a larger snow correction factor adds water
  p_scf <- p; p_scf$SCF <- 1.5
  expect_gt(sum(hbv_run(su, p_scf)), sum(out$q))
})

test_that("every registered model builds, runs, and recovers its own flow by calibration", {
  x <- synthetic_basin()
  models <- wsva_models()
  expect_setequal(names(models), c("WBM + IHACRES", "CemaNeige-GR4J", "CemaNeige-GR5J",
                                   "CemaNeige-GR6J", "HBV (TUWmodel)"))
  x$static <- dplyr::mutate(x$static, swc_max_mm = 150, jtemp_c = 1, slope_deg = 10, aspect_deg = 180)
  for (nm in names(models)) {
    fn <- models[[nm]]$build(x)
    b <- models[[nm]]$bounds
    q <- fn(stats::setNames(as.list((b$lower + b$upper) / 2), b$param))
    expect_length(q, nrow(x$daily))
    expect_false(anyNA(q[-(1:30)]))
  }
  # parameter recovery for HBV: synthetic truth, calibrate, KGE near 1
  fn <- models[["HBV (TUWmodel)"]]$build(x)
  b <- hbv_bounds()
  truth <- stats::setNames(as.list(b$lower + 0.3 * (b$upper - b$lower)), b$param)
  obs <- fn(truth)
  cal <- calibrate_model(fn, b, obs, score_idx = 366:length(obs), objective = kge, n_evals = 600, seed = 1)
  expect_gt(cal$value, 0.95)
})

test_that("climate-contrast folds train and test on opposite extremes", {
  x <- synthetic_basin(n_years = 20, seed = 3)
  x$daily$q_mm <- 1
  f <- make_climate_contrast_folds(x$daily)
  expect_equal(sort(unique(f$fold)), 1:5)
  expect_true(all(table(f$fold) == nrow(x$daily)))
  ann <- x$daily %>% dplyr::mutate(wy = calc_water_year(date)) %>%
    dplyr::group_by(wy) %>% dplyr::summarize(p = sum(prcp_mm), t = mean(tmean_c))
  yrs <- function(i, r) unique(f$wy[f$fold == i & f$role == r])
  expect_lt(max(ann$p[ann$wy %in% yrs(1, "test")]), min(ann$p[ann$wy %in% yrs(1, "train")]))   # wet -> dry
  expect_lt(max(ann$t[ann$wy %in% yrs(3, "train")]), min(ann$t[ann$wy %in% yrs(3, "test")]))   # cool -> warm
  expect_lt(max(yrs(5, "train")), min(yrs(5, "test")))                                           # early -> late
  expect_length(intersect(yrs(2, "train"), yrs(2, "test")), 0)
  expect_false(min(f$wy) %in% f$wy[f$role %in% c("train", "test")])                              # warm-up never scored
})
