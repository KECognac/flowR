# Available process models (built-in and registered)

Available process models (built-in and registered)

## Usage

``` r
wsva_models(ids = NULL, n_layers = 5)
```

## Arguments

- ids:

  Optional model ids to return (default: all).

- n_layers:

  Elevation bands for CemaNeige and HBV, baked into each spec's
  `build(x)`.

## Value

Named list (by display name) of `wsva_model` specs; each has `build(x)`,
`bounds`, `n_evals_mult` and the fields of
[`wsva_model()`](https://kecognac.github.io/flowR/reference/wsva_model.md).
