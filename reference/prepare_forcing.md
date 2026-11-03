# Check a forcing table against the contract and add derived variables

Check a forcing table against the contract and add derived variables

## Usage

``` r
prepare_forcing(daily, static, kc_t_lo = 2, kc_t_hi = 10, kc_window = 15)
```

## Arguments

- daily:

  Daily basin-mean forcing (other columns, e.g. q_mm, are kept).

- static:

  One-row static table with lat, elev_m, kc_dormant, kc_growing.

- kc_t_lo, kc_t_hi, kc_window:

  Seasonal Kc settings
  ([`kc_seasonal()`](https://kecognac.github.io/flowR/reference/kc_seasonal.md)).

## Value

`daily` with tmean_c, eto_mm and pet_mm.
