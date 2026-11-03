# Calibrated parameters of a `wsva_fit`

Calibrated parameters of a `wsva_fit`

## Usage

``` r
# S3 method for class 'wsva_fit'
coef(object, which = c("full", "blocked"), ...)
```

## Arguments

- object:

  A `wsva_fit`.

- which:

  "full" (all-years calibration, used by
  [`predict()`](https://rdrr.io/r/stats/predict.html)) or "blocked" (one
  set per CV fold).

- ...:

  Unused.

## Value

Tibble: model, (fold), param, value.
