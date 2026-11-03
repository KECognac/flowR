# Simulate flow from a `wsva_fit`

Without `forcing`, returns the out-of-sample (blocked CV) series. With
`forcing`, runs each model with its full-record parameters on that
forcing: the step used for climate projections. The forcing must meet
the forcing contract
([`forcing_required_vars()`](https://kecognac.github.io/flowR/reference/forcing_required_vars.md));
PET is computed from it with the basin's crop coefficients, exactly as
in calibration.

## Usage

``` r
# S3 method for class 'wsva_fit'
predict(
  object,
  forcing = NULL,
  models = names(object$results),
  warmup_years = 1,
  ...
)
```

## Arguments

- object:

  A `wsva_fit`.

- forcing:

  Optional daily basin-mean forcing table.

- models:

  Model ids (default: all in the fit).

- warmup_years:

  Leading years returned as NA (spin-up).

- ...:

  Unused.

## Value

Tibble: date, one column per model (mm/day), and `mean`.

## Details

Model states start empty, so the first `warmup_years` of the output are
set to NA: supply forcing that starts at least that long before the
period of interest.
