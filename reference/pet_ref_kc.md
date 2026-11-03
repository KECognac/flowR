# Daily vegetation PET (mm) = FAO-56 Penman-Monteith ETo x seasonal Kc

The same PET wbm_run() uses with pet_method = "penman_monteith", minus
the WBM-specific snow rule, so other models (GR4J, ...) get identical
PET.

## Usage

``` r
pet_ref_kc(daily, static, kc_t_lo = 2, kc_t_hi = 10, kc_window = 15)
```

## Arguments

- daily:

  Daily GridMET forcing (tmin_c, tmax_c, tmean_c, srad_wm2, rhmin_pct,
  rhmax_pct, wind_ms at 10 m).

- static:

  One-row static table with lat, elev_m, kc_dormant, kc_growing.

- kc_t_lo, kc_t_hi, kc_window:

  Seasonal Kc settings, see
  [`kc_seasonal()`](https://kecognac.github.io/flowR/reference/kc_seasonal.md).
