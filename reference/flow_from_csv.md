# Standard flow table from a csv file

Standard flow table from a csv file

## Usage

``` r
flow_from_csv(path, ..., skip = 0)
```

## Arguments

- path:

  csv file.

- ...:

  Passed to
  [`flow_from_df()`](https://kecognac.github.io/flowR/reference/flow_from_df.md)
  (date_col, q_col, units, ...).

- skip:

  Lines to skip before the header.
