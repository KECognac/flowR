# Build the bundled example basin (inst/extdata/example_clear_creek.rds) -------------
# Clear Creek above Clear Creek Reservoir, CO (CDSS CCACCRCO; USGS 07086500
# until 1995, Colorado DWR since): GAGES-II Reference, 174 km2, snowmelt-
# dominated. WY2000-2016 keeps the file small (~0.3 MB) while leaving enough
# water years for 5-fold cross-validation and the climate-contrast test.
#
# Needs network access the first time (CDSS, StreamStats, GridMET, 3DEP,
# SSURGO, NLCD) and the Jennings raster in inst/extdata (or
# options(wsva.jennings_path = ...)). Re-run after any change to those sources.

pkgload::load_all()
b <- wsva_basin(flow_cdss("CCACCRCO", start = "1999-10-01", end = "2016-09-30"))
b <- add_forcing(b, start = "1999-10-01", end = "2016-09-30")
b <- add_basin_attributes(b)
b$forcing <- dplyr::mutate(b$forcing, dplyr::across(where(is.double), ~ round(.x, 3)))
b$flow <- dplyr::mutate(b$flow, q_cms = round(q_cms, 4), q_mm = round(q_mm, 4))
b$polygon <- sf::st_simplify(sf::st_transform(b$polygon, 5070), dTolerance = 30) |> sf::st_transform(4326)
b$provenance$built <- format(Sys.Date())
b$provenance$jennings <- getOption("wsva.jennings_path", "inst/extdata/jennings2018_temp50.tif")
saveRDS(b, "inst/extdata/example_clear_creek.rds", compress = "xz")
message("example basin: ", round(file.size("inst/extdata/example_clear_creek.rds") / 1e3), " KB")
