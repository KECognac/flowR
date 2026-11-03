# Extract cell-level GridMET for many basins from the national files

Cells touching each basin are found once (they are the same in every
file); then each national file is read once and the union of needed
cells is pulled out, so cost scales with the number of files, not
basins. Output per basin: \<out_dir\>/\<site_no\>/cells.csv and one
parquet per year (cell, date, flowR-named variables in flowR units).

## Usage

``` r
extract_gridmet_bulk(
  basins,
  years = 1980:2024,
  vars = c("pr", "tmmn", "tmmx", "srad", "vs", "rmin", "rmax", "pet"),
  nc_dir = wsva_path("raw", "gridmet_conus"),
  out_dir = wsva_path("raw", "gridmet_bulk")
)
```

## Arguments

- basins:

  sf polygons with a site_no column.

- years:

  Calendar years to extract.

- vars:

  GridMET short names (files must exist in `nc_dir`).

- nc_dir:

  Folder of national files from
  [`download_gridmet_conus()`](https://kecognac.github.io/flowR/reference/download_gridmet_conus.md).

- out_dir:

  Output root.
