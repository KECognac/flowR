# Plot a `wsva_fit`

Plot a `wsva_fit`

## Usage

``` r
# S3 method for class 'wsva_fit'
plot(
  x,
  type = c("overview", "hydrograph", "fdc", "seasonal", "annual", "skill", "contrast",
    "params"),
  years = 2,
  log = FALSE,
  ...
)
```

## Arguments

- x:

  A `wsva_fit`.

- type:

  "overview" (hydrographs, flow duration, seasonal cycle, annual flow),
  or one of "hydrograph", "fdc", "seasonal", "annual", "skill",
  "contrast", "params".

- years:

  Recent water years in the hydrograph.

- log:

  Log-scale hydrograph.

- ...:

  Unused.

## Value

A ggplot (or a patchwork for "overview").
