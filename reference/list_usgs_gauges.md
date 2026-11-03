# List USGS gauges with daily discharge records

Supply one of `sites`, `aoi`, or `state_name`. Returns one row per
monitoring location that has a daily-mean discharge time series, with
the period of record and drainage area.

## Usage

``` r
list_usgs_gauges(
  sites = NULL,
  aoi = NULL,
  state_name = NULL,
  parameter_code = "00060",
  statistic_id = "00003"
)
```

## Arguments

- sites:

  Character vector of site numbers (with or without "USGS-").

- aoi:

  An sf object; gauges inside it are returned.

- state_name:

  Full state name(s), e.g. "Maine".

- parameter_code:

  Default "00060" (discharge, ft3/s).

- statistic_id:

  Default "00003" (daily mean).

## Value

sf points (EPSG:4326) with site_no, name, begin, end, n_years,
drainage_area_km2.
