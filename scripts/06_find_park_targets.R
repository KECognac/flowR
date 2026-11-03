# Candidate pseudo-ungauged targets: small Reference gauges in or near National Parks
# --------------------------------------------------------------------------------
# A pseudo-ungauged target is a gauged basin that is withheld from all
# training, so ungauged predictions can be scored against real observations.
# Criteria:
#   - GAGES-II CLASS == "Ref", CONUS, active in 2009, >= 19 of 20 years of
#     record 1990-2009
#   - drainage area 10-300 km2 (small; GridMET cells are ~16 km2, so basins
#     under ~20 km2 are covered by only one or two cells)
#   - gauge inside a National Park (UNIT_TYPE == "National Park") or within
#     `buffer_km` of its boundary
#   - USGS daily discharge record continuing to the present
# For each candidate the NLDI basin is delineated to report the share of the
# basin inside the park (higher = more protected) and to check the area.
#
# Output: data/processed/park_target_candidates.csv

source(here::here("scripts/00_setup.R"))

buffer_km <- 5
nps_shp <- here::here("data", "raw", "nps", "nps_boundary.shp")
if (!file.exists(nps_shp)) {
  # NPS Land Resources Division unit boundaries (IRMA DataStore, public)
  dir.create(dirname(nps_shp), showWarnings = FALSE, recursive = TRUE)
  zip <- file.path(dirname(nps_shp), "nps_boundary.zip")
  utils::download.file("https://irma.nps.gov/DataStore/DownloadFile/733895", zip, mode = "wb", quiet = TRUE)
  utils::unzip(zip, exdir = dirname(nps_shp))
}

parks <- sf::st_read(nps_shp, quiet = TRUE) %>%
  sf::st_make_valid() %>%
  filter(UNIT_TYPE == "National Park") %>%
  select(unit_code = UNIT_CODE, park = UNIT_NAME) %>%
  sf::st_transform(5070)

gages <- get_gagesii_points() %>%
  filter(class == "Ref", !state %in% c("AK", "HI", "PR"), active09, flyrs1990 >= 19,
         drain_sqkm >= 10, drain_sqkm <= 300) %>%
  sf::st_transform(5070)

# Distance from each gauge to the nearest National Park (0 = inside)
nearest <- sf::st_nearest_feature(gages, parks)
gages$unit_code <- parks$unit_code[nearest]
gages$park <- parks$park[nearest]
gages$dist_km <- as.numeric(sf::st_distance(gages, parks[nearest, ], by_element = TRUE)) / 1000
cand <- filter(gages, dist_km <= buffer_km)
message(nrow(cand), " small Reference gauges within ", buffer_km, " km of a National Park")

# Current record from the USGS Water Data APIs
usgs <- list_usgs_gauges(sites = cand$site_no) %>% sf::st_drop_geometry()
cand <- cand %>%
  left_join(select(usgs, site_no, usgs_name = name, begin, end), by = "site_no")

# Share of each basin inside its park
cand$pct_basin_in_park <- NA_real_
cand$nldi_area_km2 <- NA_real_
for (i in seq_len(nrow(cand))) {
  b <- tryCatch(get_gauge_basin(cand$site_no[i]), error = function(e) NULL)
  if (is.null(b)) next
  b <- sf::st_transform(b, 5070)
  park_i <- parks[parks$unit_code == cand$unit_code[i], ]
  inside <- suppressWarnings(sf::st_intersection(sf::st_geometry(b), sf::st_union(park_i)))
  cand$nldi_area_km2[i] <- as.numeric(sf::st_area(b)) / 1e6
  cand$pct_basin_in_park[i] <- if (length(inside)) 100 * sum(as.numeric(sf::st_area(inside))) / as.numeric(sf::st_area(b)) else 0
}

out <- cand %>%
  sf::st_drop_geometry() %>%
  transmute(site_no, station_name = coalesce(usgs_name, station_name), park, unit_code, state,
            ecoregion, drain_sqkm, nldi_area_km2, dist_km, pct_basin_in_park, hcdn_2009,
            begin, end, current = !is.na(end) & end >= as.Date("2024-09-30")) %>%
  arrange(desc(current), desc(pct_basin_in_park))

readr::write_csv(out, here::here("data", "processed", "park_target_candidates.csv"))
print(as.data.frame(out))
