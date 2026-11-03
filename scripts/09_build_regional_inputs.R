# Regional experiment, part 2: GridMET + attributes for target and donors --------
# Run after scripts/08_get_regional_data.R and the national GridMET download
# (download_gridmet_conus()).
#   1. Extract cell-level GridMET for every basin from the national files
#   2. Basin-mean forcing joined with observed flow -> daily.parquet
#      (same layout as scripts/02_get_data.R; existing files are kept)
#   3. Static attributes for every basin (basin_attributes())
#
# Output: data/processed/<site_no>/daily.parquet,
#         data/processed/regional_attributes_<target>.csv

source(here::here("scripts/00_setup.R"))

target <- "03460000"
donors <- readr::read_csv(here::here("config", paste0("donors_", target, ".csv")),
                          col_types = readr::cols(site_no = "c", huc_02 = "c"), show_col_types = FALSE)
sites <- c(target, donors$site_no[donors$needed & !is.na(donors$nldi_area_km2)])
basins <- dplyr::bind_rows(lapply(sites, get_gauge_basin))

extract_gridmet_bulk(basins, years = 1980:2024)

attrs <- purrr::map_dfr(sites, function(site) {
  f <- here::here("data", "processed", site, "daily.parquet")
  if (file.exists(f)) {
    daily <- arrow::read_parquet(f)
  } else {
    forcing <- gridmet_basin_mean(read_gridmet_bulk(site, flowr_period$start, flowr_period$end))
    flow <- readr::read_csv(here::here("data", "processed", site, "flow.csv"), show_col_types = FALSE)
    daily <- forcing %>%
      dplyr::left_join(flow, by = "date") %>%
      dplyr::mutate(site_no = site, wy = calc_water_year(date), .before = 1)
    arrow::write_parquet(daily, f)
  }
  basin_attributes(site, daily)
})

readr::write_csv(attrs, here::here("data", "processed", paste0("regional_attributes_", target, ".csv")))
message(nrow(attrs), " basins with forcing and attributes; ",
        sum(!stats::complete.cases(attrs)), " with at least one missing attribute")
