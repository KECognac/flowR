# Select the shared GAGES-II test gauges ------------------------------------------
# One least-disturbed basin per region, used to test every model in flowR.
# Screening criteria (all must hold):
#   - GAGES-II CLASS == "Ref" and in HCDN-2009
#   - active in 2009 with a complete 1990-2009 record (FLYRS1990 == 20)
#   - drainage area 100-2,500 km2 (big enough for 4 km GridMET, small
#     enough to treat as a single lumped unit)
# Within those, gauges were picked by hand to span hydroclimates (currently
# one each in the Pacific NW, Rockies, Southwest, Northeast, Southeast).
# To swap a gauge, edit `picks` and re-run to rewrite config/test_gauges.csv;
# every downstream script and notebook labels gauges by site number and
# official USGS station name, so nothing else needs to change.

source(here::here("scripts/00_setup.R"))

gages <- get_gagesii_points()

candidates <- gages %>%
  filter(class == "Ref", hcdn_2009, active09, flyrs1990 >= 20,
         drain_sqkm > 100, drain_sqkm < 2500)

picks <- c("12054000", "09081600", "09510200", "01055000", "02177000")

stopifnot(all(picks %in% candidates$site_no))

# Official station name, current record, and drainage area from the USGS
# Water Data APIs; GAGES-II supplies the drainage area used to normalize flow.
usgs <- list_usgs_gauges(sites = picks) %>% sf::st_drop_geometry()

test_gauges <- tibble::tibble(site_no = picks) %>%
  left_join(select(usgs, site_no, station_name = name, drainage_area_km2, begin, end),
            by = "site_no") %>%
  left_join(sf::st_drop_geometry(candidates) %>%
              select(site_no, state, ecoregion, drain_sqkm, lat_gage, lng_gage),
            by = "site_no") %>%
  mutate(gauge_label = paste(site_no, station_name), .after = station_name)

dir.create(here::here("config"), showWarnings = FALSE)
readr::write_csv(test_gauges, here::here("config", "test_gauges.csv"))
print(test_gauges, width = Inf)
