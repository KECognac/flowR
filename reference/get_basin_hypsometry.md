# Basin hypsometry: 101 area-weighted elevation quantiles (min, 1%, ..., max)

Basin hypsometry: 101 area-weighted elevation quantiles (min, 1%, ...,
max)

## Usage

``` r
get_basin_hypsometry(basin, dem = basin_dem(basin))
```

## Arguments

- basin:

  sf polygon (single feature).

- dem:

  SpatRaster of elevation (m); default `basin_dem(basin)`.

## Value

Numeric vector of length 101, as required by airGR's HypsoData.
