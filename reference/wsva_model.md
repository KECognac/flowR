# Define a process model for `fit_models()`

A model spec says how to turn a basin's inputs into a simulation closure
and what to calibrate. Built-in specs:
[`wsva_models()`](https://kecognac.github.io/flowR/reference/wsva_models.md).
Add your own with
[`register_model()`](https://kecognac.github.io/flowR/reference/register_model.md).

## Usage

``` r
wsva_model(
  id,
  name,
  bounds,
  build,
  requires = c("prcp_mm", "tmean_c", "pet_mm"),
  n_evals_mult = 1,
  package = NA_character_,
  reference = NA_character_
)
```

## Arguments

- id:

  Short id used in `fit_models(models = ...)` (e.g. "gr4j").

- name:

  Display name.

- bounds:

  Calibration bounds
  ([`param_bounds()`](https://kecognac.github.io/flowR/reference/param_bounds.md)).

- build:

  `function(x, n_layers)` returning `function(params)` -\> daily flow
  (mm/day) aligned with `x$daily`. `x` is list(daily, static, hypso);
  `x$daily` meets the forcing contract (R/forcing.R) and has `pet_mm`.

- requires:

  Columns of `x$daily` the model reads (checked before fitting).

- n_evals_mult:

  Multiplier on the DDS budget (more parameters, more runs).

- package:

  Package the model needs (checked when it is used), or NA.

- reference:

  Citation.

## Value

A `wsva_model`.
