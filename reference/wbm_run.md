# Run the water balance model

Run the water balance model

## Usage

``` r
wbm_run(
  forcing,
  params,
  pet_method = c("oudin", "hamon", "penman_monteith", "gridmet"),
  ros = FALSE,
  init = list(snowpack = 0, soil = 0, storage = 0)
)
```

## Arguments

- forcing:

  Daily tibble with date, prcp_mm, tmean_c; plus tmin_c, tmax_c,
  srad_wm2, rhmin_pct, rhmax_pct, wind_ms for Penman-Monteith, or
  pet_ref_mm for `pet_method = "gridmet"`. Must be gap-free.

- params:

  Named list or one-row data frame: site parameters plus any of
  [`wbm_default_params()`](https://kecognac.github.io/flowR/reference/wbm_default_params.md)
  to override.

- pet_method:

  "oudin", "hamon", "penman_monteith" (FAO-56 grass reference ET
  computed from the forcing), or "gridmet" (GridMET's precomputed ASCE
  grass reference ET). The two reference-ET methods require kc_dormant
  and kc_growing in `params`.

- ros:

  If TRUE, add rain-on-snow melt enhancement (hock + 0.0125 x rain).

- init:

  list(snowpack, soil, storage) initial states in mm.

## Value

Tibble of daily fluxes and states (mm): rain, snow, melt, snowpack,
pet_ref (ETo or the raw Oudin/Hamon PET), kc, pet, aet, soil, excess,
storage, direct, runoff, deficit.
