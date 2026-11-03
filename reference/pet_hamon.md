# Hamon (1963) PET, in the form given by Lu et al. (2005)

FIX: the NPS WBM version used (T + 273.3) inside the exponent of the
saturation vapor pressure term; the Tetens form is exp(17.27 T / (T +
237.3)). The typo underestimated PET by roughly 15% at 20 C.

## Usage

``` r
pet_hamon(doy, lat, tmean_c)
```

## Arguments

- doy:

  Day of year.

- lat:

  Latitude (degrees).

- tmean_c:

  Daily mean temperature (C).
