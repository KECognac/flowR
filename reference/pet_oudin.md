# Oudin et al. (2005) temperature/radiation PET

PE = Ra / lambda \* (T + 5) / 100 for T \> -5 C, else 0. As in the NPS
WBM, PET is set to 0 when snowpack \> `snow_thresh` mm (snow-covered
ground).

## Usage

``` r
pet_oudin(doy, lat, tmean_c, snowpack = NULL, heat_load = 1, snow_thresh = 2)
```

## Arguments

- doy:

  Day of year.

- lat:

  Latitude (degrees).

- tmean_c:

  Daily mean temperature (C).

- snowpack:

  Optional snowpack (mm SWE) series.

- heat_load:

  Multiplier (e.g.
  [`heat_load_index()`](https://kecognac.github.io/flowR/reference/heat_load_index.md)
  x shade coefficient).

- snow_thresh:

  Snowpack (mm SWE) above which PET is zero.
