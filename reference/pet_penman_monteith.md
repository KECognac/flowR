# FAO-56 Penman-Monteith grass reference ET

FIX (vs. NPS WBM): uses observed shortwave radiation when supplied (the
original always used clear-sky radiation); Tmin is raised to the 4th
power in net longwave (the original omitted ^4); actual vapor pressure
uses RHmin/RHmax with the correct arguments.

## Usage

``` r
pet_penman_monteith(
  doy,
  lat,
  elev_m,
  tmin_c,
  tmax_c,
  srad_wm2 = NULL,
  rhmin_pct = NULL,
  rhmax_pct = NULL,
  wind_ms = 2,
  wind_height = 2
)
```

## Arguments

- doy:

  Day of year.

- lat:

  Latitude (degrees).

- elev_m:

  Elevation (m), for atmospheric pressure.

- tmin_c, tmax_c:

  Daily minimum and maximum temperature (C).

- srad_wm2:

  Daily mean shortwave (W m-2). If NULL, clear-sky Rso is used
  (overestimates PET on cloudy days).

- rhmin_pct, rhmax_pct:

  Relative humidity (%). If NULL, ea = es(Tmin).

- wind_ms:

  Wind speed (m/s); scalar or vector.

- wind_height:

  Measurement height (m). GridMET wind is 10 m.
