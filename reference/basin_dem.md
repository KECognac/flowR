# Digital elevation model for a basin (cached GeoTIFF, CONUS Albers)

Digital elevation model for a basin (cached GeoTIFF, CONUS Albers)

## Usage

``` r
basin_dem(basin, z = NULL)
```

## Arguments

- basin:

  sf polygon.

- z:

  elevatr zoom level; default by basin area (10: ~60 m below 2,000 km2;
  9: ~120 m below 20,000 km2; 8 above).

## Value

SpatRaster (m) covering the basin plus a 2 km buffer.
