# Area-weighted basin dormant and growing-season Kc

Area-weighted basin dormant and growing-season Kc

## Usage

``` r
basin_kc(landcover, kc_table = read_kc_table())
```

## Arguments

- landcover:

  Output of
  [`get_basin_landcover()`](https://kecognac.github.io/flowR/reference/get_basin_landcover.md).

- kc_table:

  Output of
  [`read_kc_table()`](https://kecognac.github.io/flowR/reference/read_kc_table.md).

## Value

One-row tibble: kc_dormant, kc_growing, pct_covered (share of the basin
whose class has a Kc; weights are renormalized over it).
