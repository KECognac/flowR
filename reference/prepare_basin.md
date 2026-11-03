# Build the processed model inputs for one gauge

Build the processed model inputs for one gauge

## Usage

``` r
prepare_basin(
  x,
  start = wsva_default_period()$start,
  end = wsva_default_period()$end,
  soil_depth_cm = 150,
  overwrite = FALSE
)
```

## Arguments

- x:

  A USGS site number, or a `wsva_basin` from
  [`wsva_basin()`](https://kecognac.github.io/flowR/reference/wsva_basin.md)
  (any flow source).

- start, end:

  Study period (default
  [`wsva_default_period()`](https://kecognac.github.io/flowR/reference/wsva_default_period.md)).

- soil_depth_cm:

  Soil profile depth for `swc_max_mm` (100 or 150).

- overwrite:

  Rebuild files that already exist.

## Value

list(info, basin (sf polygon), daily, static, hypso). `info` has id,
name, flow_source, basin_method, gagesii_class, hcdn_2009, ref_area_km2,
ref_area_source, delineated_area_km2, area_err_pct, gridmet_source, lon,
lat.
