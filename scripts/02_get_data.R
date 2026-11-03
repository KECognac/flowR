# Build the model-ready dataset for each test gauge ------------------------------
# For each gauge, prepare_basin() gathers the NLDI basin, USGS daily flow,
# GridMET forcing, terrain (3DEP), soil water storage (SSURGO/gNATSGO), the
# Jennings rain/snow threshold, NLCD land cover and crop coefficients, and
# hypsometry. Everything is cached under data/, so re-running only downloads
# what's missing.
#
# Set overwrite = TRUE to rebuild existing inputs (e.g. after editing
# inst/extdata/kc_nlcd.csv). Rebuilt static inputs invalidate cached
# calibrations in the notebooks, which then recalibrate.
#
# Output: data/processed/<site_no>/daily.parquet, static.csv, hypsometry.csv,
#         gauge_info.csv

source(here::here("scripts/00_setup.R"))

overwrite <- FALSE
gauges <- get_test_gauges()

for (site in gauges$site_no) {
  message("== ", site)
  x <- prepare_basin(site, start = flowr_period$start, end = flowr_period$end, overwrite = overwrite)
  message(sprintf("  NLDI area %.1f km2 vs reference %.1f km2 (%+.1f%%); %d days, %.1f%% with observed flow",
                  x$info$delineated_area_km2, x$info$ref_area_km2, x$info$area_err_pct,
                  nrow(x$daily), 100 * mean(!is.na(x$daily$q_mm))))
}
