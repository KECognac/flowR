# Pad a daily data frame so every date between start and end has a row

Missing days are inserted with NA values (nothing is interpolated). Gap
filling is a modeling decision, so it is left to the caller.

## Usage

``` r
complete_daily(df, date_col = "date", start = NULL, end = NULL)
```

## Arguments

- df:

  Data frame with a Date column.

- date_col:

  Name of the date column. Default "date".

- start, end:

  Optional bounds; default to the range of `df`.
