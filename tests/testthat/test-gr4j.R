# Tests for the GR4J + CemaNeige wrapper -- no network needed; requires airGR.
# Run: devtools::test() (all) or devtools::test(filter = "gr4j")

skip_if_not(requireNamespace("airGR", quietly = TRUE), "airGR not installed")

synthetic <- function(n_years = 6, seed = 11) {
  set.seed(seed)
  date <- seq(as.Date("2000-10-01"), by = "day", length.out = round(365.25 * n_years))
  doy <- as.integer(format(date, "%j"))
  tm <- 6 + 12 * sin(2 * pi * (doy - 110) / 365) + stats::rnorm(length(date), 0, 2)
  tibble::tibble(date = date, prcp_mm = ifelse(stats::runif(length(date)) < 0.3, stats::rexp(length(date), 1 / 8), 0),
                 tmean_c = tm, tmin_c = tm - 6, tmax_c = tm + 6)
}

test_that("CemaNeige-GR4J runs, is non-negative, and conserves water without exchange", {
  d <- synthetic()
  hypso <- seq(1000, 3000, length.out = 101)
  pet <- rep(1.5, nrow(d))
  su <- gr4j_setup(d, pet, hypso, z_inputs = 2000)
  q <- gr4j_run(su, list(X1 = 300, X2 = 0, X3 = 100, X4 = 2, C1 = 0.5, C2 = 4))
  expect_length(q, nrow(d))
  expect_true(all(q >= 0))
  expect_lt(sum(q), sum(d$prcp_mm))            # X2 = 0: no water gained, some lost to ET
  # negative exchange (X2 < 0) removes water
  q_loss <- gr4j_run(su, list(X1 = 300, X2 = -2, X3 = 100, X4 = 2, C1 = 0.5, C2 = 4))
  expect_lt(sum(q_loss), sum(q))
})

test_that("bounds cover the six CemaNeige-GR4J parameters", {
  expect_equal(gr4j_bounds()$param, c("X1", "X2", "X3", "X4", "C1", "C2"))
})
