# Using your own gauge: USGS, Colorado DWR, or a csv file

The code in this vignette downloads data, so it is shown but not run
when the package is built.

``` r

library(WSVAflowR)
options(wsva.data_dir = "~/flow_data")   # downloads and caches go here
```

## Flow from any source

Every flow source returns the same table (daily `date`, `q_cms`, `flag`)
plus metadata such as the station name, location and drainage area.

``` r

q <- flow_usgs("01154000")                      # USGS Water Data APIs (dataRetrieval)
q <- flow_cdss("CCACCRCO")                      # Colorado DWR / CDSS (cdssr)
q <- flow_from_csv("my_gauge.csv", date_col = "Date", q_col = "Flow_cfs", units = "cfs",
                   date_format = "%m/%d/%Y", id = "my_gauge", lon = -105.27, lat = 40.01)
q <- flow_from_df(my_data_frame, date_col = "date", q_col = "q", units = "cms")
```

Units can be `"cfs"`, `"cms"` (m³/s) or `"mm"` (mm/day over the basin,
which needs `area_km2`). Negative values are dropped, and missing days
stay missing: nothing is gap-filled.

## A watershed

[`wsva_basin()`](https://kecognac.github.io/flowR/reference/wsva_basin.md)
needs a watershed polygon. Give one, or let it delineate the watershed
upstream of the gauge:

``` r

b <- wsva_basin(q)                       # delineate at the gauge location in the flow metadata
b <- wsva_basin(q, outlet = c(-105.27, 40.01))
b <- wsva_basin(q, polygon = sf::st_read("my_watershed.gpkg"))
b <- wsva_basin_usgs("01154000")         # USGS gauges: USGS flow + the NLDI basin for the site
```

Delineation uses USGS StreamStats (state elevation-derived flow
networks), falling back to NHDPlus through the NLDI:

``` r

ws <- delineate_basin(-106.2776, 39.01826, method = "streamstats")
```

Always compare the watershed with a published drainage area. The flow is
converted to mm/day with a **reference area**: the area in the flow
metadata, else the GAGES-II or USGS area when the station has a USGS id,
else the delineated area.
[`wsva_basin()`](https://kecognac.github.io/flowR/reference/wsva_basin.md)
warns when the delineated area is more than 20% off; a large mismatch
usually means the outlet snapped to the wrong stream.

## Climate and basin attributes

``` r

b <- add_forcing(b)                      # GridMET, 1980-10-01 to 2024-09-30 by default
b <- add_basin_attributes(b)
```

| Attribute | Source |
|----|----|
| Elevation, slope, aspect, hypsometry | AWS Terrain Tiles (USGS 3DEP in the US) via elevatr |
| Soil water storage (WBM soil bucket) | gNATSGO (SSURGO + STATSGO2) via soilDB; 0-150 cm by default |
| Rain/snow temperature threshold | Jennings et al. (2018), shipped with the package |
| Land cover and crop coefficients | NLCD 2019 via FedData |

Potential evapotranspiration is never taken from a dataset’s own
product: it is always computed from temperature, humidity, radiation and
wind (FAO-56 Penman-Monteith × land-cover crop coefficient), so
historical and projected climate go through one method.

## Things to watch for

- **Human influence.** Many state-operated gauges, including many
  Colorado DWR stations, sit below diversions or reservoirs. The models
  simulate natural flow, so water management shows up as model error.
  [`check_basin()`](https://kecognac.github.io/flowR/reference/check_basin.md)
  reports the GAGES-II class when the station has a USGS id; otherwise
  you need to check.
- **Record length.** Cross-validation needs at least two complete water
  years per fold (ten for the default five folds) inside the forcing
  period.
- **Seasonal records.** Stations that only report in summer still work:
  scoring uses only observed days, and the models run on continuous
  forcing.
- **Coverage.** GridMET covers the contiguous US.

## Then fit

``` r

check_basin(b)
fits <- fit_models(b)
summary(fits)
plot(fits)
saveRDS(fits, "my_gauge_fits.rds")
```
