# NLCD land-cover percentages over a basin polygon

NLCD land-cover percentages over a basin polygon

## Usage

``` r
get_basin_landcover(basin, year = 2019)
```

## Arguments

- basin:

  sf polygon.

- year:

  NLCD year (2019 matches the Kc table's land-cover basis).

## Value

Tibble: nlcd_code, pct (sums to ~100).
