# Daily Kc from a temperature phenology index

Growing-season weight g = 0 when the trailing `window`-day mean
temperature is at or below `t_lo`, 1 at or above `t_hi`, linear between;
Kc = kc_dormant + g (kc_growing - kc_dormant). The trailing mean keeps
single warm days in winter from switching the canopy on.

## Usage

``` r
kc_seasonal(tmean_c, kc_dormant, kc_growing, t_lo = 2, t_hi = 10, window = 15)
```

## Arguments

- tmean_c:

  Daily mean temperature.

- kc_dormant, kc_growing:

  Basin Kc values (from
  [`basin_kc()`](https://kecognac.github.io/flowR/reference/basin_kc.md)).

- t_lo, t_hi:

  Temperature ramp (deg C).

- window:

  Days in the trailing mean.

## Value

Numeric vector of daily Kc.
