# WSVAflowR

Multi-model streamflow simulation for gauged basins, built for comparing
models fairly and then driving them with a changed climate.

Give it a gauge, from USGS, Colorado DWR (CDSS) or your own csv, and
WSVAflowR delineates the watershed, gathers GridMET climate and basin
attributes from public datasets, and calibrates five process models on
the same forcing and the same tests:

| Model | Snow | Soil and runoff | Routing |
|----|----|----|----|
| WBM + IHACRES | degree-day, Jennings rain/snow threshold | Thornthwaite-Mather bucket | two linear stores + loss |
| CemaNeige-GR4J / GR5J / GR6J | CemaNeige, elevation bands | production store, groundwater exchange | unit hydrograph + routing store (+ exponential store in GR6J) |
| HBV (TUWmodel) | degree-day with snow correction, elevation bands | soil moisture with nonlinear runoff | upper / lower stores + triangular routing |

Each model is tested on held-out water years (blocked cross-validation)
and in a different climate (calibrate on wet years, test on dry ones,
and so on), then calibrated on the full record so
[`predict()`](https://rdrr.io/r/stats/predict.html) can run it with any
new forcing. Potential evapotranspiration is always computed from the
meteorological variables (FAO-56 Penman-Monteith × land-cover crop
coefficients), so historical and projected climate use one method.

``` r

library(WSVAflowR)
b <- wsva_basin_usgs("01154000")         # or wsva_basin(flow_cdss("CCACCRCO")), flow_from_csv(...)
b <- add_forcing(b)
b <- add_basin_attributes(b)
fits <- fit_models(b)
summary(fits)
plot(fits)
predict(fits, forcing = warmer_forcing)
```

Start with
[`vignette("getting-started")`](https://kecognac.github.io/flowR/articles/getting-started.md),
which runs on a bundled example basin without downloads.

## Installation

``` r

# install.packages("remotes")
remotes::install_github("mikejohnson51/climateR")   # GridMET access
remotes::install_github("KECognac/flowR")             # repository to be renamed WSVAflowR
```

The rain/snow threshold raster of Jennings et al. (2018) must be added
by hand once (Dryad blocks scripted downloads): download
`jennings_et_al_2018_file4_temp50_raster.tif` from
<https://doi.org/10.5061/dryad.c9h35> and save it as
`inst/extdata/jennings2018_temp50.tif`, or point
`options(wsva.jennings_path = ...)` at your copy.
