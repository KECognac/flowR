# Donor basins for the pseudo-ungauged target ---------------------------------------
# Target: 03460000 Cataloochee Creek near Cataloochee, NC (Great Smoky
# Mountains National Park, 127 km2). It is withheld from all training; the
# regional model is trained on donor basins only and scored at the target
# (the regional LSTM that used this is archived in archive/lstm/).
#
# Donor pool: the other CAMELS basins. Three ways of choosing N donors:
#   similar - closest in standardized climate/topography/vegetation/soil/
#             geology attributes (CAMELS, nothing derived from streamflow)
#   nearest - closest gauges by great-circle distance
#   random  - a fixed random ordering
# Donor sets are nested: the N = 10 set is the first 10 of the N = 25 set, etc.
#
# CAMELS attributes are used only to choose donors (they have to be chosen
# before downloading their data). Model inputs are computed by flowR's own
# pipeline, so they could be computed the same way for any ungauged basin.
#
# Output: config/donors_<target>.csv (all ranked donors) with a `needed`
# flag for basins in any strategy's largest set.

source(here::here("scripts/00_setup.R"))

target <- "03460000"
n_sizes <- c(10, 25, 50, 100)

camels <- read_camels()
donors <- rank_donors(camels, target, seed = 1)

n_max <- max(n_sizes)
donors <- donors %>%
  mutate(needed = rank_similar <= n_max | rank_nearest <= n_max | rank_random <= n_max)

readr::write_csv(donors, here::here("config", paste0("donors_", target, ".csv")))
message(sum(donors$needed), " donor basins needed for N up to ", n_max)

purrr::walk(n_sizes, function(n) {
  u <- with(donors, unique(site_no[rank_similar <= n | rank_nearest <= n | rank_random <= n]))
  message(sprintf("N = %3d: %3d unique donors across strategies", n, length(u)))
})
