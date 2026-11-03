# Path inside the WSVAflowR data directory

Path inside the WSVAflowR data directory

## Usage

``` r
wsva_path(...)
```

## Arguments

- ...:

  Path components, as for
  [`file.path()`](https://rdrr.io/r/base/file.path.html).

## Value

A file path under `getOption("wsva.data_dir")` (default
`tools::R_user_dir("WSVAflowR", "cache")`). Nothing is created.
