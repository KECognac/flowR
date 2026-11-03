# Live web-service checks (USGS, CDSS, StreamStats, SSURGO, NLCD, elevation).
# Off by default; run with:
#   Sys.setenv(WSVA_NETWORK_TESTS = "true"); devtools::test(filter = "network")

skip_if_not(identical(Sys.getenv("WSVA_NETWORK_TESTS"), "true"), "network tests off (set WSVA_NETWORK_TESTS=true)")
skip_on_cran()
withr_dir <- tempfile("wsva_cache_"); old <- options(wsva.data_dir = withr_dir)
on.exit(options(old), add = TRUE)

# Clear Creek above Clear Creek Reservoir, CO: GAGES-II Reference basin,
# USGS 07086500 until 1995, operated by Colorado DWR since (CDSS CCACCRCO)
test_that("CDSS and USGS give the same flow where both published", {
  skip_if_not_installed("cdssr")
  cd <- flow_cdss("CCACCRCO", start = "1990-10-01", end = "1995-09-29")
  us <- flow_usgs("07086500", start = "1990-10-01", end = "1995-09-29")
  m <- merge(cd, us, by = "date")
  m <- m[stats::complete.cases(m$q_cms.x, m$q_cms.y), ]
  expect_gt(nrow(m), 1500)
  expect_equal(mean(m$q_cms.x), mean(m$q_cms.y), tolerance = 0.01)
  expect_equal(flow_meta(cd)$usgs_site_no, "07086500")
})

test_that("StreamStats delineation matches the published drainage area", {
  b <- delineate_basin(-106.2776, 39.01826, method = "streamstats", state = "CO", id = "clear_ck")
  expect_equal(b$area_km2, 174.1, tolerance = 0.03)
})

test_that("SSURGO, NLCD and elevation services return plausible basin values", {
  skip_if_not_installed("soilDB"); skip_if_not_installed("FedData"); skip_if_not_installed("elevatr")
  b <- delineate_basin(-106.2776, 39.01826, method = "streamstats", state = "CO", id = "clear_ck")
  soil <- basin_soil_storage(b)
  expect_true(soil$aws0150_mm > soil$aws0100_mm, soil$aws0150_mm < 400)
  lc <- get_basin_landcover(b)
  expect_equal(sum(lc$pct), 100, tolerance = 0.02)
  ter <- basin_terrain(b)
  expect_gt(ter$elev_m, 3000)                                 # high-elevation Sawatch Range basin
})
