# Build HBV zone forcing once per basin

Build HBV zone forcing once per basin

## Usage

``` r
hbv_setup(daily, pet, hypso, z_inputs, n_layers = 5)
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

## Value

list(prec, airt, ep (time x zone matrices), area, z_layers)
