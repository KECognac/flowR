# Cell-level GridMET for a basin, cached in multi-year chunks

Cell-level GridMET for a basin, cached in multi-year chunks

## Usage

``` r
get_gridmet_cells(
  basin,
  start = "1980-10-01",
  end = "2024-09-30",
  vars = c("pr", "tmmn", "tmmx", "srad", "vs", "rmin", "rmax", "pet"),
  chunk_years = 5,
  cache_dir = wsva_path("raw", "gridmet")
)
```

## Arguments

- basin:

  sf polygon (single feature) with a site_no column.

- start, end:

  Date bounds.

- vars:

  GridMET short names (see `gridmet_vars`).

- chunk_years:

  Years per request/cache file.

- cache_dir:

  Directory for parquet chunks (one subfolder per site).

## Value

list(cells = cell weights table, data = long tibble of cell x date
values in flowR units).
