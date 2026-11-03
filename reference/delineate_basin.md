# Delineate the watershed upstream of an outlet point

Delineate the watershed upstream of an outlet point

## Usage

``` r
delineate_basin(
  lon,
  lat,
  method = c("auto", "streamstats", "nldi"),
  state = NULL,
  id = sprintf("pt_%.5f_%.5f", lon, lat),
  cache_dir = wsva_path("raw", "basins"),
  timeout = 180
)
```

## Arguments

- lon, lat:

  Outlet location (decimal degrees, WGS84).

- method:

  "streamstats" (default) or "nldi". With "auto", StreamStats is tried
  first and NLDI is the fallback.

- state:

  Two-letter state code for StreamStats; looked up from the point (US
  Census geocoder) if NULL.

- id:

  Identifier stored with the basin and used for the cache file.

- cache_dir:

  Directory for cached GeoPackages. NULL disables caching.

- timeout:

  Seconds to wait for StreamStats.

## Value

sf polygon (EPSG:4326) with id, area_km2, method, outlet_lon, outlet_lat
(the snapped outlet).
