# Basin-mean rain/snow temperature threshold (Jennings et al. 2018)

Basin-mean rain/snow temperature threshold (Jennings et al. 2018)

## Usage

``` r
basin_jennings(
  basin,
  path = getOption("wsva.jennings_path", system.file("extdata",
    "jennings2018_temp50.tif", package = "WSVAflowR"))
)
```

## Arguments

- basin:

  sf polygon.

- path:

  The Jennings 50% rain-snow threshold raster
  (`jennings_et_al_2018_file4_temp50_raster.tif` on Dryad). Default: the
  copy shipped in `inst/extdata`, or `getOption("wsva.jennings_path")`.

## Value

Threshold (deg C).
