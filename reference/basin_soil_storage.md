# Soil available water storage from gNATSGO (SSURGO + STATSGO2)

Map units come from the gNATSGO 30 m grid
([`soilDB::mukey.wcs()`](http://ncss-tech.github.io/soilDB/reference/mukey.wcs.md));
each map unit's component-weighted available water storage (`muaggatt`
aws0100wta, aws0150wta, in cm, already truncated at bedrock) comes from
Soil Data Access and is area-weighted over the basin. Map units without
a value (water, rock outcrop, urban land) are left out of the mean, and
their share is reported.

## Usage

``` r
basin_soil_storage(basin, res = NULL)
```

## Arguments

- basin:

  sf polygon.

- res:

  Grid resolution (m); default 30 m, coarser for large basins so the web
  request stays small.

## Value

One-row tibble: aws0100_mm, aws0150_mm, soil_frac_with_data.
