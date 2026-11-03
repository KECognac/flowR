# Add daily basin-mean climate forcing

Add daily basin-mean climate forcing

## Usage

``` r
add_forcing(
  basin,
  source = "gridmet",
  start = wsva_default_period()$start,
  end = wsva_default_period()$end
)
```

## Arguments

- basin:

  A `wsva_basin`.

- source:

  Forcing source; currently "gridmet".

- start, end:

  Forcing period.

## Value

`basin` with `forcing` (forcing contract columns, R/forcing.R).
