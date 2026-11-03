# Public-source basin attributes vs. the NPS WBM rasters ----------------------------
# Phase 2 of the package replaced three local NPS rasters with public data:
#   elevation_cropped.tif (1 km DEM)        -> AWS Terrain Tiles / 3DEP (elevatr, ~60 m)
#   water_storage.tif (800 m, cm)           -> gNATSGO available water storage (soilDB)
#   merged_jennings2.tif                    -> Jennings et al. 2018 (Dryad), shipped
# and NHDPlus TOT_NLCD19 land cover (USGS sites only) -> NLCD 2019 over the polygon.
# This script compares the two on the test basins and picks the SSURGO depth
# (0-100 or 0-150 cm) closest to the NPS soil raster.
#
# Output: data/processed/results/public_attributes/comparison.csv

source(here::here("scripts/00_setup.R"))

out_dir <- here::here("data", "processed", "results", "public_attributes")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
gauges <- get_test_gauges()

cmp <- purrr::map_dfr(gauges$site_no, function(site) {
  basin <- get_gauge_basin(site)
  old <- readr::read_csv(here::here("data", "processed", site, "static.csv"), show_col_types = FALSE)
  old_hyp <- readr::read_csv(here::here("data", "processed", site, "hypsometry.csv"), show_col_types = FALSE)$elev_m
  dem <- basin_dem(basin)
  ter <- basin_terrain(basin, dem)
  hyp <- get_basin_hypsometry(basin, dem)
  soil <- basin_soil_storage(basin)
  kc <- basin_kc(get_basin_landcover(basin))
  jt <- tryCatch(basin_jennings(basin), error = function(e) NA_real_)
  tibble::tibble(
    site_no = site, gauge = gauges$gauge_label[gauges$site_no == site],
    elev_old = old$elev_m, elev_new = ter$elev_m,
    elev_p10_old = old_hyp[11], elev_p10_new = hyp[11], elev_p90_old = old_hyp[91], elev_p90_new = hyp[91],
    slope_old = old$slope_deg, slope_new = ter$slope_deg,
    swc_old_mm = old$swc_max_mm, aws0100_mm = soil$aws0100_mm, aws0150_mm = soil$aws0150_mm,
    soil_frac_with_data = soil$soil_frac_with_data,
    kc_dormant_old = old$kc_dormant, kc_dormant_new = kc$kc_dormant,
    kc_growing_old = old$kc_growing, kc_growing_new = kc$kc_growing,
    jtemp_old = old$jtemp_c, jtemp_new = jt
  )
})
readr::write_csv(cmp, file.path(out_dir, "comparison.csv"))
print(as.data.frame(dplyr::select(cmp, -gauge)), digits = 3)

# Which SSURGO depth tracks the NPS soil raster? (mean absolute % difference)
err <- function(new) mean(abs(new - cmp$swc_old_mm) / cmp$swc_old_mm) * 100
message(sprintf("Soil storage vs NPS raster: 0-100 cm %.0f%% mean abs. difference, 0-150 cm %.0f%%",
                err(cmp$aws0100_mm), err(cmp$aws0150_mm)))
