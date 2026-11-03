# WBM (Penman-Monteith x Kc) + IHACRES routing as a calibration closure

WBM (Penman-Monteith x Kc) + IHACRES routing as a calibration closure

## Usage

``` r
wbm_ihacres_model(daily, static)
```

## Arguments

- daily:

  Daily forcing meeting the forcing contract.

- static:

  One-row static table
  ([`get_basin_static()`](https://kecognac.github.io/flowR/reference/get_basin_static.md) +
  [`basin_kc()`](https://kecognac.github.io/flowR/reference/basin_kc.md)).
