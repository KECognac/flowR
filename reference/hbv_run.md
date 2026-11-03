# Run TUWmodel and return simulated flow (mm/day)

Run TUWmodel and return simulated flow (mm/day)

## Usage

``` r
hbv_run(setup, par, return_components = FALSE)
```

## Arguments

- setup:

  Output of
  [`hbv_setup()`](https://kecognac.github.io/flowR/reference/hbv_setup.md).

- par:

  Named list or vector with the 15
  [`hbv_bounds()`](https://kecognac.github.io/flowR/reference/hbv_bounds.md)
  parameters.

- return_components:

  If TRUE, return a tibble with q, q0, q1, q2, basin-mean swe, soil
  moisture and AET.
