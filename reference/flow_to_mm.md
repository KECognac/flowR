# Add basin-depth flow (mm/day) to a flow table

Add basin-depth flow (mm/day) to a flow table

## Usage

``` r
flow_to_mm(flow, area_km2)
```

## Arguments

- flow:

  Standard flow table.

- area_km2:

  Drainage area used for normalization.

## Value

`flow` with a `q_mm` column.
