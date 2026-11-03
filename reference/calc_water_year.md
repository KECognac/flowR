# Water year for a vector of dates

Water year for a vector of dates

## Usage

``` r
calc_water_year(dates, start_month = 10)
```

## Arguments

- dates:

  Date vector (or anything
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html) accepts).

- start_month:

  Integer 1-12, month the water year starts. Default 10 (October), so
  2020-10-01 is water year 2021.

## Value

Integer vector of water years.
