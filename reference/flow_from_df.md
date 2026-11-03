# Standard flow table from a user data frame

Standard flow table from a user data frame

## Usage

``` r
flow_from_df(
  df,
  date_col = "date",
  q_col,
  units = c("cfs", "cms", "mm"),
  area_km2 = NULL,
  id = NA_character_,
  name = NA_character_,
  lon = NA_real_,
  lat = NA_real_,
  date_format = NULL,
  flag_col = NULL
)
```

## Arguments

- df:

  Data frame with a date column and a discharge column.

- date_col, q_col:

  Column names.

- units:

  "cfs", "cms" (m3/s) or "mm" (mm/day; needs `area_km2`).

- area_km2:

  Drainage area, required for `units = "mm"`; also stored as the
  reported area.

- id, name, lon, lat:

  Optional gauge metadata (the outlet location is needed to delineate a
  watershed from the gauge).

- date_format:

  Optional format for character dates (e.g. "%m/%d/%Y").

- flag_col:

  Optional column of quality flags.

## Value

Standard flow table.
