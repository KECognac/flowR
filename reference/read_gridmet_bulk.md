# Read bulk-extracted cell-level GridMET for one basin

Read bulk-extracted cell-level GridMET for one basin

## Usage

``` r
read_gridmet_bulk(
  site_no,
  start = NULL,
  end = NULL,
  out_dir = wsva_path("raw", "gridmet_bulk")
)
```

## Arguments

- site_no:

  Basin id.

- start, end:

  Optional date bounds.

- out_dir:

  Root folder written by
  [`extract_gridmet_bulk()`](https://kecognac.github.io/flowR/reference/extract_gridmet_bulk.md).

## Value

list(cells, data) in the same shape as
[`get_gridmet_cells()`](https://kecognac.github.io/flowR/reference/get_gridmet_cells.md),
so it can be passed to
[`gridmet_basin_mean()`](https://kecognac.github.io/flowR/reference/gridmet_basin_mean.md).
