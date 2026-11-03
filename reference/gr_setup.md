# Build the airGR inputs and run options once per basin

Build the airGR inputs and run options once per basin

## Usage

``` r
gr_setup(daily, pet, hypso, z_inputs, n_layers = 5, model = "GR4J")
```

## Arguments

- daily:

  Gap-free daily tibble with date, prcp_mm, tmean_c, tmin_c, tmax_c.

- pet:

  Daily potential evaporation (mm), aligned with `daily`.

- hypso:

  101 elevation quantiles
  ([`get_basin_hypsometry()`](https://kecognac.github.io/flowR/reference/get_basin_hypsometry.md)).

- z_inputs:

  Elevation the forcing represents (basin-mean elevation for basin-mean
  GridMET).

- n_layers:

  CemaNeige elevation bands.

- model:

  "GR4J", "GR5J" or "GR6J".

## Value

list(model, inputs, run_options) for
[`gr_run()`](https://kecognac.github.io/flowR/reference/gr_run.md).
