# Build a basin from flow data and a watershed (given or delineated)

Build a basin from flow data and a watershed (given or delineated)

## Usage

``` r
wsva_basin(
  flow,
  polygon = NULL,
  outlet = NULL,
  id = NULL,
  name = NULL,
  area_km2 = NULL,
  delineation = "auto",
  state = NULL
)
```

## Arguments

- flow:

  Standard flow table
  ([`flow_usgs()`](https://kecognac.github.io/flowR/reference/flow_usgs.md),
  [`flow_cdss()`](https://kecognac.github.io/flowR/reference/flow_cdss.md),
  [`flow_from_df()`](https://kecognac.github.io/flowR/reference/flow_from_df.md),
  [`flow_from_csv()`](https://kecognac.github.io/flowR/reference/flow_from_csv.md)).

- polygon:

  Optional sf watershed. If NULL, the watershed is delineated upstream
  of `outlet` with
  [`delineate_basin()`](https://kecognac.github.io/flowR/reference/delineate_basin.md).

- outlet:

  Optional c(lon, lat); default from the flow metadata.

- id, name:

  Optional; default from the flow metadata.

- area_km2:

  Reference drainage area for converting flow to mm/day. Default: the
  reported area in the flow metadata, else the published GAGES-II / USGS
  area when the station has a USGS id, else the delineated area.

- delineation, state:

  Passed to
  [`delineate_basin()`](https://kecognac.github.io/flowR/reference/delineate_basin.md).

## Value

A `wsva_basin`.
