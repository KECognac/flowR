# Upstream basin for a USGS gauge from the NLDI

Uses the Network-Linked Data Index (NHDPlusV2-based) basin for the
gauge. Compare `area_km2` to the GAGES-II / USGS drainage area as a
sanity check: a large mismatch usually means the gauge is snapped to the
wrong flowline.

## Usage

``` r
get_gauge_basin(site_no, cache_dir = wsva_path("raw", "basins"))
```

## Arguments

- site_no:

  Site number (with or without "USGS-").

- cache_dir:

  Directory for cached GeoPackages. NULL disables caching.

## Value

sf polygon (EPSG:4326) with site_no and area_km2.
