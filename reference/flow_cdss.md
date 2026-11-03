# Daily flow from Colorado's Decision Support Systems (CDSS / DWR)

Uses the `cdssr` package (surface-water station time series), which
covers stations operated by the Colorado Division of Water Resources as
well as USGS and other cooperators. Many DWR stations sit below
diversions or reservoirs; check that a station's flow is close to
natural before using it for calibration.

## Usage

``` r
flow_cdss(
  abbrev,
  start = wsva_default_period()$start,
  end = wsva_default_period()$end,
  cache_dir = wsva_path("raw", "cdss"),
  refresh = FALSE
)
```

## Arguments

- abbrev:

  CDSS station abbreviation (e.g. "CCACCRCO").

- start, end:

  Period.

- cache_dir:

  Cache directory (csv per station).

- refresh:

  Re-download even if cached.

## Value

Standard flow table; `flag` holds the CDSS flag columns joined.
