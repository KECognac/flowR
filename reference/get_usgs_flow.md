# Daily mean discharge for one USGS gauge

Downloads (or reads from cache) the daily-mean discharge record and
returns a complete daily series: days with no published value are NA
rows rather than missing rows. Provisional and estimated values are kept
but flagged so they can be excluded from calibration/evaluation if
desired.

## Usage

``` r
get_usgs_flow(
  site_no,
  start = NULL,
  end = NULL,
  area_km2 = NULL,
  cache_dir = wsva_path("raw", "usgs"),
  refresh = FALSE
)
```

## Arguments

- site_no:

  Site number (with or without "USGS-").

- start, end:

  Date bounds (character or Date). NULL = full record.

- area_km2:

  Optional drainage area; if given, adds q_mm (mm/day).

- cache_dir:

  Directory for cached csv files. NULL disables caching.

- refresh:

  If TRUE, re-download even when a cache file exists.

## Value

Tibble: site_no, date, q_cfs, q_cms, (q_mm), approval_status, qualifier,
estimated (logical).
