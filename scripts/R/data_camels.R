# CAMELS attributes ---------------------------------------------------------------
# Addor et al. (2017, HESS 21:5293), Newman et al. (2015, HESS 19:209): 671
# minimally disturbed CONUS basins (HCDN-2009 subset). flowR uses CAMELS as
# a curated basin list and a source of reference attributes; forcing comes
# from GridMET and model inputs from flowR's own pipeline, so every input
# can be computed the same way for an ungauged basin.
#
# Expects the attribute text files (camels_name.txt, camels_topo.txt, ...)
# in data/raw/camels/ (download from NCAR RAL/GDEX; CC BY 4.0).
#
# camels_hydro.txt holds streamflow signatures (q_mean, baseflow_index, ...).
# They are derived from observed flow, so they must never be model inputs
# or donor-similarity criteria for ungauged prediction; `read_camels()`
# drops them unless `include_hydro = TRUE`.

#' Read and join the CAMELS attribute tables
#'
#' @param dir Folder with the camels_*.txt files.
#' @param include_hydro Include flow-derived signatures (reference only).
#' @return Tibble, one row per gauge, keyed by site_no (8-digit character).
read_camels <- function(dir = wsva_path("raw", "camels"), include_hydro = FALSE) {
  groups <- c("name", "topo", "clim", "soil", "vege", "geol", if (include_hydro) "hydro")
  tabs <- lapply(groups, function(g) {
    readr::read_delim(file.path(dir, paste0("camels_", g, ".txt")), delim = ";",
                      col_types = readr::cols(gauge_id = "c", .default = readr::col_guess()),
                      progress = FALSE, show_col_types = FALSE) %>%
      dplyr::mutate(gauge_id = .pad0(gauge_id, 8))
  })
  Reduce(function(a, b) dplyr::left_join(a, b, by = "gauge_id"), tabs) %>%
    dplyr::rename(site_no = gauge_id) %>%
    dplyr::mutate(gauge_name = trimws(gauge_name),
                  huc_02 = .pad0(huc_02, 2))
}

#' Attributes used to rank donor basins by physical similarity
#'
#' Climate, topography, vegetation, soils, and geology only; nothing derived
#' from streamflow. Area is log-transformed.
camels_similarity_vars <- function() {
  c("p_mean", "pet_mean", "aridity", "p_seasonality", "frac_snow", "high_prec_freq",
    "elev_mean", "slope_mean", "log_area", "frac_forest", "lai_max", "lai_diff",
    "soil_depth_pelletier", "max_water_content", "sand_frac", "clay_frac",
    "carbonate_rocks_frac", "geol_permeability")
}

#' Rank candidate donor basins for a pseudo-ungauged target
#'
#' @param camels Output of `read_camels()`.
#' @param target site_no of the target (withheld from the donor pool).
#' @param exclude Extra site_nos to exclude (e.g. basins nested with the target).
#' @param vars Similarity attributes (z-scored across the CAMELS pool).
#' @param seed Seed for the random ordering.
#' @return Tibble of donors with distance_km, similarity distance, and the
#'   rank of each donor under each strategy ("similar", "nearest", "random").
rank_donors <- function(camels, target, exclude = character(), vars = camels_similarity_vars(), seed = 1) {
  x <- dplyr::mutate(camels, log_area = log(area_gages2))
  stopifnot(target %in% x$site_no, all(vars %in% names(x)))
  z <- scale(as.matrix(x[, vars]))
  z[is.na(z)] <- 0                              # missing attribute = pool mean
  t_i <- which(x$site_no == target)
  sim_dist <- sqrt(rowSums(sweep(z, 2, z[t_i, ])^2))
  geo_km <- geosphere_km(x$gauge_lat, x$gauge_lon, x$gauge_lat[t_i], x$gauge_lon[t_i])
  set.seed(seed)
  donors <- tibble::tibble(site_no = x$site_no, gauge_name = x$gauge_name, huc_02 = x$huc_02,
                           area_km2 = x$area_gages2, distance_km = geo_km, similarity_dist = sim_dist,
                           random_key = stats::runif(nrow(x))) %>%
    dplyr::filter(site_no != target, !site_no %in% exclude)
  donors %>%
    dplyr::mutate(rank_similar = rank(similarity_dist, ties.method = "first"),
                  rank_nearest = rank(distance_km, ties.method = "first"),
                  rank_random = rank(random_key, ties.method = "first")) %>%
    dplyr::select(-random_key) %>%
    dplyr::arrange(rank_similar)
}

# Great-circle distance (km) from many points to one point
geosphere_km <- function(lat, lon, lat0, lon0) {
  to_rad <- pi / 180
  dlat <- (lat - lat0) * to_rad; dlon <- (lon - lon0) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat * to_rad) * cos(lat0 * to_rad) * sin(dlon / 2)^2
  6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
}

# Left-pad ids with zeros to width n (CAMELS drops leading zeros)
.pad0 <- function(x, n) {
  x <- trimws(as.character(x))
  ifelse(nchar(x) < n, paste0(strrep("0", pmax(n - nchar(x), 0)), x), x)
}
