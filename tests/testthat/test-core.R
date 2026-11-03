# Unit tests for the core functions -- no network needed.
# Run: devtools::test() (all) or devtools::test(filter = "core")


synthetic_forcing <- function(n_years = 3, seed = 42) {
  set.seed(seed)
  date <- seq(as.Date("2000-10-01"), by = "day", length.out = round(365.25 * n_years))
  doy <- as.integer(format(date, "%j"))
  tmean <- 8 + 12 * sin(2 * pi * (doy - 110) / 365) + stats::rnorm(length(date), 0, 3)
  prcp <- ifelse(stats::runif(length(date)) < 0.3, stats::rexp(length(date), 1 / 8), 0)
  tibble::tibble(date = date, prcp_mm = prcp, tmean_c = tmean,
                 tmin_c = tmean - 6, tmax_c = tmean + 6)
}
site <- list(lat = 45, elev_m = 800, slope_deg = 10, aspect_deg = 180,
             swc_max_mm = 150, jtemp_c = 1, kc_dormant = 0.5, kc_growing = 0.95)

test_that("water year rolls over in October", {
  expect_equal(calc_water_year(as.Date(c("2020-09-30", "2020-10-01"))), c(2020, 2021))
  expect_equal(calc_water_year(as.Date("2020-06-01"), start_month = 6), 2021)
})

test_that("unit conversion round-trips", {
  q_mm <- cfs_to_mm_day(100, 250)
  expect_equal(mm_day_to_cms(q_mm, 250), 100 * 0.0283168466)
})

test_that("metrics hit known values", {
  o <- c(1, 2, 3, 4, 5)
  expect_equal(nse(o, o), 1)
  expect_equal(kge(o, o), 1)
  expect_equal(nse(o, rep(mean(o), 5)), 0)
  expect_equal(pbias(o, o * 0.9), 10)
  expect_equal(nse(c(o, NA), c(o, 3)), 1)          # NA pairs dropped
  expect_true(is.na(nse(rep(2, 5), o)))             # zero variance -> NA
})

test_that("WBM closes the water balance for every PET method", {
  f <- synthetic_forcing()
  for (m in c("oudin", "hamon", "penman_monteith")) {
    for (ros in c(FALSE, TRUE)) {
      out <- wbm_run(f, c(site, return_rate = 0.3, direct_frac = 0.1),
                     pet_method = m, ros = ros)
      n <- nrow(out)
      resid <- sum(out$prcp) - sum(out$aet) - sum(out$runoff) -
        out$snowpack[n] - out$soil[n] - out$storage[n]
      expect_lt(abs(resid), 1e-6, label = paste(m, "ros", ros, "residual"))
      expect_true(all(out$soil >= -1e-9 & out$soil <= site$swc_max_mm + 1e-9))
      expect_true(all(out$snowpack >= -1e-9))
      expect_true(all(out$aet <= out$pet + 1e-9))
    }
  }
})

test_that("Kc follows the temperature ramp and is applied only to reference ET", {
  t <- c(rep(-5, 30), rep(20, 30))
  kc <- kc_seasonal(t, 0.4, 1.0, t_lo = 2, t_hi = 10, window = 5)
  expect_equal(kc[1:30], rep(0.4, 30))
  expect_equal(kc[40:60], rep(1.0, 21))
  expect_true(all(diff(kc[30:36]) >= 0))
  f <- synthetic_forcing()
  pm <- wbm_run(f, site, pet_method = "penman_monteith")
  expect_equal(pm$pet[pm$snowpack <= 2], (pm$pet_ref * pm$kc)[pm$snowpack <= 2])
  expect_true(all(pm$pet[pm$snowpack > 2] == 0))
  expect_true(all(pm$kc >= 0.5 - 1e-12 & pm$kc <= 0.95 + 1e-12))
  hm <- wbm_run(f, site, pet_method = "hamon")
  expect_true(all(hm$kc == 1))
  expect_error(wbm_run(f, site[setdiff(names(site), "kc_growing")], pet_method = "penman_monteith"), "kc_dormant")
})

test_that("basin Kc is the area-weighted class mean over classes with a Kc", {
  lc <- tibble::tibble(nlcd_code = c(41, 42, 99), pct = c(60, 30, 10))
  tab <- tibble::tibble(nlcd_code = c(41, 42), kc_dormant = c(0.4, 0.8), kc_growing = c(1.0, 0.9))
  k <- basin_kc(lc, tab)
  expect_equal(k$kc_dormant, (60 * 0.4 + 30 * 0.8) / 90)
  expect_equal(k$kc_growing, (60 * 1.0 + 30 * 0.9) / 90)
  expect_equal(k$pct_covered, 90)
})

test_that("WBM defaults keep runoff equal to excess water (return_rate = 1)", {
  out <- wbm_run(synthetic_forcing(), site)
  expect_equal(out$runoff, out$excess)
})

test_that("IHACRES routing conserves volume and lags correctly", {
  u <- c(10, rep(0, 2000))
  q <- route_ihacres(u, tau_q = 2, tau_s = 50, vs = 0.4)
  expect_equal(sum(q), 10, tolerance = 1e-6)
  comp <- route_ihacres(u, tau_q = 2, tau_s = 50, vs = 0.4, loss = 0.2, return_components = TRUE)
  expect_equal(sum(comp$q_total) + sum(comp$q_loss), 10, tolerance = 1e-6)
  q_lag <- route_ihacres(u, tau_q = 2, tau_s = 50, vs = 0.4, delay = 3)
  expect_equal(q_lag[4:100], q[1:97])
  expect_equal(q_lag[1:3], c(0, 0, 0))
})

test_that("snow routing conserves rain and melt volume separately", {
  n <- 3000
  rain <- c(5, rep(0, n - 1)); melt <- c(0, 0, 0, 7, rep(0, n - 4))
  runoff <- rain + melt
  comp <- route_ihacres_snow(runoff, rain, melt, tau_q_rain = 2, tau_s_rain = 30,
                             vs_rain = 0.3, tau_s_melt = 80, return_components = TRUE)
  expect_equal(sum(comp$q_quick_rain) + sum(comp$q_slow_rain), 5, tolerance = 1e-6)
  expect_equal(sum(comp$q_slow_melt), 7, tolerance = 1e-6)
})

test_that("Eckhardt baseflow stays between 0 and q", {
  q <- abs(stats::rnorm(500, 10, 5)); q[c(20, 21)] <- NA
  bf <- baseflow_eckhardt(q)
  ok <- !is.na(q)
  expect_true(all(bf$baseflow[ok] >= 0 & bf$baseflow[ok] <= q[ok]))
  expect_true(all(is.na(bf$baseflow[!ok])))
})

test_that("blocked folds never put a test day in training", {
  d <- seq(as.Date("1990-10-01"), as.Date("2010-09-30"), by = "day")
  folds <- make_blocked_folds(d, k = 5, warmup_years = 1, buffer_days = 30)
  expect_equal(sort(unique(folds$fold)), 1:5)
  # every scored day is test in exactly one fold
  tested <- folds %>% dplyr::filter(role == "test") %>% dplyr::count(date)
  expect_true(all(tested$n == 1))
  expect_equal(nrow(tested), sum(calc_water_year(d) > 1991))
  # test blocks are whole, contiguous water years
  for (f in 1:5) {
    td <- folds$date[folds$fold == f & folds$role == "test"]
    expect_equal(length(td), as.numeric(diff(range(td))) + 1)
    near <- folds$date[folds$fold == f & folds$role == "train"]
    expect_true(min(abs(outer(as.numeric(near), as.numeric(range(td)), "-"))) > 30)
  }
})

test_that("period split labels warm-up first", {
  d <- seq(as.Date("1990-10-01"), as.Date("2000-09-30"), by = "day")
  s <- make_period_split(d, warmup_years = 1, cal = c(1992, 1996), test = c(1997, 2000))
  expect_equal(unique(s$period[s$wy == 1991]), "warmup")
  expect_setequal(unique(s$period), c("warmup", "cal", "test"))
})

test_that("DDS calibration recovers known routing parameters, including an integer delay", {
  set.seed(3)
  u <- ifelse(stats::runif(1500) < 0.25, stats::rexp(1500, 1 / 10), 0)
  truth <- route_ihacres(u, tau_q = 3, tau_s = 60, vs = 0.35, delay = 2)
  model_fn <- function(p) route_ihacres(u, p$tau_q, p$tau_s, p$vs, delay = p$delay)
  b <- param_bounds(tau_q = c(0.5, 20), tau_s = c(10, 300), vs = c(0.05, 0.95),
                    delay = c(0, 4), .integer = "delay")
  cal <- calibrate_model(model_fn, b, truth, score_idx = 200:1500, objective = nse, n_evals = 800)
  expect_gt(cal$value, 0.99)
  expect_equal(cal$best$delay, 2)
  expect_lt(abs(cal$best$vs - 0.35), 0.05)        # vs trades off against tau_s
  expect_equal(names(cal$best), b$param)
  expect_true(all(diff(cal$trace) >= 0))          # best-so-far never gets worse
})

test_that("fixed parameters stay fixed and parallel CV matches serial CV", {
  set.seed(4)
  d <- seq(as.Date("1990-10-01"), as.Date("1998-09-30"), by = "day")
  u <- ifelse(stats::runif(length(d)) < 0.25, stats::rexp(length(d), 1 / 10), 0)
  obs <- route_ihacres(u, tau_q = 3, tau_s = 60, vs = 0.35)
  model_fn <- function(p) route_ihacres(u, p$tau_q, p$tau_s, p$vs)
  b <- param_bounds(tau_q = c(0.5, 20), tau_s = c(10, 300), vs = c(0.35, 0.35))
  folds <- make_blocked_folds(d, k = 3, warmup_years = 1)
  serial <- cross_validate_model(model_fn, b, obs, folds, n_cores = 1, objective = nse, n_evals = 150)
  par <- cross_validate_model(model_fn, b, obs, folds, n_cores = 2, objective = nse, n_evals = 150)
  expect_true(all(serial$params$vs == 0.35))
  expect_equal(serial$params, par$params)
  expect_equal(nrow(serial$traces), 3 * 150)
})
