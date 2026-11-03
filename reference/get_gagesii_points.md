# GAGES-II gauge points with classification attributes

Downloads the 9,322-gauge point shapefile (~0.7 MB) on first use.

## Usage

``` r
get_gagesii_points(dir = wsva_path("raw", "gagesii"), ref_only = FALSE)
```

## Arguments

- dir:

  Directory to store the shapefile.

- ref_only:

  If TRUE, keep only CLASS == "Ref" gauges.

## Value

sf points with site_no, class, ecoregion, drain_sqkm, hcdn_2009, ...
