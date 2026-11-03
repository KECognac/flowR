# Checks a basin should pass before models are fit

Checks a basin should pass before models are fit

## Usage

``` r
check_basin(basin, k_folds = 5, min_obs_frac = 0.8)
```

## Arguments

- basin:

  A `wsva_basin` with forcing
  ([`add_forcing()`](https://kecognac.github.io/flowR/reference/add_forcing.md)).

- k_folds:

  Cross-validation folds (needs at least 2 water years each).

- min_obs_frac:

  Water years with less observed flow are not scored.

## Value

Tibble: check, status ("ok", "warn", "fail"), detail.
