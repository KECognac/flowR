# Day-of-year mean flow, estimated only from training days

Day-of-year mean flow, estimated only from training days

## Usage

``` r
benchmark_doy_climatology(obs, dates, train_idx, smooth_days = 31)
```

## Arguments

- obs:

  Observed series.

- dates:

  Dates aligned with `obs`.

- train_idx:

  Logical/integer index of days allowed to inform the benchmark.

- smooth_days:

  Width of the circular moving-average window (odd).

## Value

Numeric vector aligned with `dates`.
