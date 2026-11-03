# Daily flow from the USGS Water Data APIs

Daily flow from the USGS Water Data APIs

## Usage

``` r
flow_usgs(
  site_no,
  start = NULL,
  end = NULL,
  cache_dir = wsva_path("raw", "usgs")
)
```

## Arguments

- site_no:

  USGS site number.

- start, end:

  Period (default: whole record).

- cache_dir:

  Cache for the raw download (see
  [`get_usgs_flow()`](https://kecognac.github.io/flowR/reference/get_usgs_flow.md)).

## Value

Standard flow table; `flag` holds "estimated" or the approval status.
