# Fixed warm-up / calibration / validation / test periods by water year

Fixed warm-up / calibration / validation / test periods by water year

## Usage

``` r
make_period_split(dates, warmup_years = 1, cal, val = NULL, test = NULL)
```

## Arguments

- dates:

  Date vector covering the full model run.

- warmup_years:

  Number of leading water years excluded from scoring.

- cal, val, test:

  Length-2 integer vectors of first/last water year. `val` and `test`
  may be NULL.

## Value

Tibble: date, wy, period ("warmup", "cal", "val", "test", or "unused").
