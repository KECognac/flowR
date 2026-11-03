# Basin-mean elevation, slope and (circular-mean) aspect

Basin-mean elevation, slope and (circular-mean) aspect

## Usage

``` r
basin_terrain(basin, dem = basin_dem(basin))
```

## Arguments

- basin:

  sf polygon.

- dem:

  SpatRaster of elevation (m).

## Value

One-row tibble: elev_m, slope_deg, aspect_deg.
