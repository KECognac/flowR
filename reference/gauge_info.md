# What is known about a USGS gauge: name, GAGES-II screening, reference area

What is known about a USGS gauge: name, GAGES-II screening, reference
area

## Usage

``` r
gauge_info(site_no)
```

## Arguments

- site_no:

  USGS site number.

## Value

One-row tibble: site_no, name, gagesii_class (NA if not in GAGES-II),
hcdn_2009, ref_area_km2, ref_area_source, lat, lon.
