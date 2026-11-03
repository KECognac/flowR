# Add basin attributes from public datasets

Terrain and hypsometry (3DEP via elevatr), soil water storage (gNATSGO),
the Jennings rain/snow threshold, NLCD land cover and crop coefficients.

## Usage

``` r
add_basin_attributes(basin, soil_depth_cm = 150, nlcd_year = 2019)
```

## Arguments

- basin:

  A `wsva_basin`.

- soil_depth_cm:

  Soil profile depth for `swc_max_mm` (100 or 150).

- nlcd_year:

  NLCD year.

## Value

`basin` with `static`, `hypso`, `landcover`.
