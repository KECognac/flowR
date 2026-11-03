# Kling-Gupta efficiency (Gupta et al. 2009); `components = TRUE` returns r, alpha, beta

Kling-Gupta efficiency (Gupta et al. 2009); `components = TRUE` returns
r, alpha, beta

## Usage

``` r
kge(obs, sim, components = FALSE)
```

## Arguments

- obs, sim:

  Observed and simulated values (pairs with an NA are dropped).

- components:

  If TRUE, return a tibble with KGE and its r, alpha (variability ratio)
  and beta (bias ratio) components.
