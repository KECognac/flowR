# Download national GridMET files

Uses curl::multi_download(), which runs the transfers concurrently in
one process (forked parallel downloads are unreliable on macOS), a few
files at a time, and resumes partial files on re-run. Files that fail
are reported, and the function can simply be called again.

## Usage

``` r
download_gridmet_conus(
  vars = c("pr", "tmmn", "tmmx", "srad", "vs", "rmin", "rmax", "pet"),
  years = 1980:2024,
  dir = wsva_path("raw", "gridmet_conus"),
  n_parallel = 2,
  max_passes = 3
)
```

## Arguments

- vars:

  GridMET short names.

- years:

  Calendar years.

- dir:

  Destination folder.

- n_parallel:

  Files downloaded at once (the server allows ~2).

- max_passes:

  Retry passes for failed files.

## Value

Tibble of var, year, path, ok.
