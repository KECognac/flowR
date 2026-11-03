# Tests for flow sources, basin objects and attribute aggregation -- offline;
# synthetic rasters and polygons only. Live-service checks are in test-network.R.
# Run: devtools::test(filter = "data-layer")

square <- function(lon = -105, lat = 40, half_deg = 0.05, id = "sq") {
  m <- matrix(c(lon - half_deg, lat - half_deg, lon + half_deg, lat - half_deg, lon + half_deg, lat + half_deg,
                lon - half_deg, lat + half_deg, lon - half_deg, lat - half_deg), ncol = 2, byrow = TRUE)
  sf::st_sf(id = id, geometry = sf::st_sfc(sf::st_polygon(list(m)), crs = 4326))
}

test_that("flow_from_df converts units, parses dates and fills a complete daily series", {
  df <- data.frame(Date = c("10/01/2000", "10/02/2000", "10/04/2000"), Q = c(35.3147, -1, 70.6294))
  f <- flow_from_df(df, date_col = "Date", q_col = "Q", units = "cfs", date_format = "%m/%d/%Y", id = "g1")
  expect_s3_class(f, "wsva_flow")
  expect_equal(nrow(f), 4)                                   # Oct 3 inserted as NA
  expect_equal(f$q_cms[1], 1, tolerance = 1e-6)              # 35.3147 cfs = 1 m3/s
  expect_true(is.na(f$q_cms[2]))                             # negative discharge removed
  expect_true(is.na(f$q_cms[3]))
  expect_equal(flow_meta(f)$id, "g1")
  # mm/day round trip
  mm <- flow_from_df(data.frame(date = as.Date("2000-10-01") + 0:1, q = c(1, 2)), q_col = "q",
                     units = "mm", area_km2 = 86.4)
  expect_equal(mm$q_cms, c(1, 2))                            # 1 mm/day over 86.4 km2 = 1 m3/s
  expect_equal(flow_to_mm(mm, 86.4)$q_mm, c(1, 2))
  expect_error(flow_from_df(data.frame(date = "2000-13-45", q = 1), q_col = "q"), "date")
  expect_error(flow_from_df(data.frame(date = Sys.Date(), q = 1), q_col = "q", units = "mm"), "area_km2")
})

test_that("flow_from_csv reads a file the same way", {
  f <- tempfile(fileext = ".csv")
  readr::write_csv(data.frame(day = as.Date("2001-01-01") + 0:9, flow_cms = 1:10), f)
  x <- flow_from_csv(f, date_col = "day", q_col = "flow_cms", units = "cms")
  expect_equal(x$q_cms, 1:10)
})

test_that("wsva_basin uses the user polygon and the best available reference area", {
  poly <- square()
  a <- as.numeric(sf::st_area(sf::st_transform(poly, 5070))) / 1e6
  flow <- flow_from_df(data.frame(date = as.Date("2000-10-01") + 0:9, q = 1), q_col = "q", units = "cms",
                       id = "g2", lon = -105, lat = 40)
  b <- wsva_basin(flow, polygon = poly)
  expect_s3_class(b, "wsva_basin")
  expect_equal(b$area$reference_source, "delineated basin")
  expect_equal(b$area$reference_km2, a, tolerance = 1e-6)
  expect_equal(b$flow$q_mm, rep(86.4 / a, 10), tolerance = 1e-9)
  expect_equal(basin_id(b$polygon), "g2")
  # a reported area wins, and a large mismatch warns
  flow2 <- flow_from_df(data.frame(date = as.Date("2000-10-01") + 0:9, q = 1), q_col = "q", units = "cms",
                        id = "g3", area_km2 = a * 2)
  expect_warning(b2 <- wsva_basin(flow2, polygon = poly), "differs from the reference area")
  expect_equal(b2$area$reference_km2, a * 2)
  expect_error(wsva_basin(flow_from_df(data.frame(date = Sys.Date(), q = 1), q_col = "q", id = "g4")), "outlet")
})

test_that("terrain, hypsometry and Jennings aggregate correctly over a polygon", {
  poly <- sf::st_transform(square(half_deg = 0.1), 5070)
  bb <- sf::st_bbox(poly)
  dem <- terra::rast(xmin = bb[["xmin"]] - 3000, xmax = bb[["xmax"]] + 3000, ymin = bb[["ymin"]] - 3000,
                     ymax = bb[["ymax"]] + 3000, resolution = 100, crs = "EPSG:5070")
  terra::values(dem) <- terra::yFromCell(dem, seq_len(terra::ncell(dem))) - bb[["ymin"]]   # plane rising north
  ter <- basin_terrain(poly, dem)
  expect_equal(ter$aspect_deg, 180, tolerance = 1e-3)         # rises to the north, so it faces south
  expect_equal(ter$slope_deg, 45, tolerance = 0.5)            # 1 m per m
  hyp <- get_basin_hypsometry(poly, dem)
  expect_length(hyp, 101)
  expect_true(all(diff(hyp) >= 0))
  expect_equal(hyp[51], ter$elev_m, tolerance = 200)          # uniform slope: median ~ mean
  # Jennings: a constant raster gives the constant
  jt <- terra::rast(xmin = -110, xmax = -100, ymin = 35, ymax = 45, resolution = 0.5, crs = "EPSG:4326")
  terra::values(jt) <- 1.7
  f <- tempfile(fileext = ".tif"); terra::writeRaster(jt, f)
  expect_equal(basin_jennings(square(), path = f), 1.7, tolerance = 1e-6)   # float32 raster
  expect_error(basin_jennings(square(), path = ""), "dryad")
})

test_that("basin_kc weights crop coefficients by land-cover share", {
  lc <- tibble::tibble(nlcd_code = c(41, 71), pct = c(75, 25))
  kc <- basin_kc(lc, tibble::tibble(nlcd_code = c(41, 71), kc_dormant = c(0.4, 0.3), kc_growing = c(1, 0.8)))
  expect_equal(kc$kc_dormant, 0.375)
  expect_equal(kc$kc_growing, 0.95)
})
