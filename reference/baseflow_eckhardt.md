# Eckhardt (2005) two-parameter recursive digital filter

`b[t] = ((1 - BFImax) a b[t-1] + (1 - a) BFImax q[t]) / (1 - a BFImax)`,
constrained to `0 <= b[t] <= q[t]`. NA discharge carries the previous
baseflow forward and returns NA for that day.

## Usage

``` r
baseflow_eckhardt(q, alpha = 0.98, bfi_max = 0.8, bf_0 = NULL)
```

## Arguments

- q:

  Daily discharge (any units).

- alpha:

  Recession constant (typically 0.95-0.99).

- bfi_max:

  Maximum baseflow index: ~0.80 perennial/porous aquifers, ~0.50
  ephemeral, ~0.25 perennial hard-rock (Eckhardt 2005).

- bf_0:

  Initial baseflow; default `q[1] * bfi_max`.

## Value

Tibble: q, baseflow, quickflow.
