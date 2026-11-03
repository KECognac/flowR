# Basin-mean static parameters for `wbm_run()` from public datasets

Basin-mean static parameters for
[`wbm_run()`](https://kecognac.github.io/flowR/reference/wbm_run.md)
from public datasets

## Usage

``` r
get_basin_static(basin, soil_depth_cm = 150)
```

## Arguments

- basin:

  sf polygon with an `id` or `site_no` column.

- soil_depth_cm:

  Depth of the available-water-storage profile that sets `swc_max_mm`:
  100 or 150.

## Value

One-row tibble: id, lat, lon, elev_m, slope_deg, aspect_deg, swc_max_mm,
jtemp_c, aws0100_mm, aws0150_mm, soil_frac_with_data.
