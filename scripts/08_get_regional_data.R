# Data for the regional experiment: target + donor basins ------------------------
# Part 1 (this script, no GridMET needed): for the target and every donor
# flagged `needed` in config/donors_<target>.csv,
#   - NLDI basin polygon (area checked against CAMELS / GAGES-II)
#   - USGS daily discharge (Water Data APIs) normalized to mm/day
#   - NLCD 2019 land cover, basin crop coefficients, static WBM parameters,
#     hypsometry
# then a nesting check: donors whose basin contains the target gauge, or
# whose gauge lies in the target basin, are dropped from the donor pool
# (their flow would partly *be* the target's flow).
#
# Part 2 (scripts/09_extract_gridmet.R) extracts GridMET from the national
# files once they are downloaded.
#
# Everything is cached per basin, so the script can be re-run to fill gaps.
# Output: data/processed/<site_no>/{flow.csv, static.csv, hypsometry.csv},
#         config/donors_<target>.csv gains area and nesting columns.

source(here::here("scripts/00_setup.R"))

target <- "03460000"
donor_file <- here::here("config", paste0("donors_", target, ".csv"))
donors <- readr::read_csv(donor_file, col_types = readr::cols(site_no = "c", huc_02 = "c"), show_col_types = FALSE)
camels <- read_camels()
sites <- c(target, donors$site_no[donors$needed])
period <- flowr_period

prepare_basin <- function(site) {
  out_dir <- here::here("data", "processed", site)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  area_ref <- camels$area_gages2[camels$site_no == site]

  basin <- get_gauge_basin(site)
  if (!file.exists(file.path(out_dir, "flow.csv"))) {
    flow <- get_usgs_flow(site, start = period$start, end = period$end, area_km2 = area_ref)
    readr::write_csv(dplyr::select(flow, date, q_cfs, q_mm, approval_status, estimated),
                     file.path(out_dir, "flow.csv"))
  }
  if (!file.exists(file.path(out_dir, "static.csv"))) {
    static <- get_basin_static(basin) %>%
      dplyr::mutate(area_km2 = area_ref) %>%
      dplyr::bind_cols(basin_kc(get_basin_landcover(basin)))
    readr::write_csv(static, file.path(out_dir, "static.csv"))
  }
  if (!file.exists(file.path(out_dir, "hypsometry.csv"))) {
    readr::write_csv(tibble::tibble(pct = 0:100, elev_m = get_basin_hypsometry(basin)),
                     file.path(out_dir, "hypsometry.csv"))
  }
  tibble::tibble(site_no = site, nldi_area_km2 = basin$area_km2, camels_area_km2 = area_ref)
}

status <- purrr::map_dfr(sites, function(site) {
  r <- tryCatch(prepare_basin(site), error = function(e) {
    message(site, " FAILED: ", conditionMessage(e))
    tibble::tibble(site_no = site, nldi_area_km2 = NA_real_, camels_area_km2 = NA_real_,
                   error = conditionMessage(e))
  })
  r
})

# Nesting check against the target ----------------------------------------------
target_basin <- sf::st_transform(get_gauge_basin(target), 5070)
gauge_pts <- camels %>%
  dplyr::filter(site_no %in% sites) %>%
  sf::st_as_sf(coords = c("gauge_lon", "gauge_lat"), crs = 4326) %>%
  sf::st_transform(5070)
target_pt <- gauge_pts[gauge_pts$site_no == target, ]
nested <- purrr::map_lgl(setdiff(sites, target), function(site) {
  f <- here::here("data", "raw", "basins", paste0(site, "_basin.gpkg"))
  if (!file.exists(f)) return(NA)
  b <- sf::st_transform(sf::st_read(f, quiet = TRUE), 5070)
  donor_pt <- gauge_pts[gauge_pts$site_no == site, ]
  lengths(sf::st_intersects(target_pt, b)) > 0 ||           # donor is downstream of target
    lengths(sf::st_intersects(donor_pt, target_basin)) > 0   # donor is upstream of target
})
nest_tbl <- tibble::tibble(site_no = setdiff(sites, target), nested_with_target = nested)

donors <- donors %>%
  dplyr::select(-dplyr::any_of(c("nldi_area_km2", "camels_area_km2", "area_err_pct", "nested_with_target", "error"))) %>%
  dplyr::left_join(status, by = "site_no") %>%
  dplyr::left_join(nest_tbl, by = "site_no") %>%
  dplyr::mutate(area_err_pct = 100 * (nldi_area_km2 - camels_area_km2) / camels_area_km2)
readr::write_csv(donors, donor_file)

ok <- status %>% dplyr::filter(!is.na(nldi_area_km2))
message(sprintf("%d of %d basins prepared; %d nested with target; %d with NLDI area off by >10%%",
                nrow(ok), length(sites), sum(nest_tbl$nested_with_target, na.rm = TRUE),
                sum(abs(donors$area_err_pct) > 10, na.rm = TRUE)))
