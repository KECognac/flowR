# Calibrate a model with DDS

Calibrate a model with DDS

## Usage

``` r
calibrate_model(
  model_fn,
  bounds,
  obs,
  score_idx,
  objective = kge,
  maximize = TRUE,
  n_evals = 1000,
  r = 0.2,
  seed = 1
)
```

## Arguments

- model_fn:

  function(par) -\> numeric vector aligned with `obs`.

- bounds:

  Output of
  [`param_bounds()`](https://kecognac.github.io/flowR/reference/param_bounds.md).

- obs:

  Observed series.

- score_idx:

  Integer or logical index of days used in the objective.

- objective:

  function(obs, sim) -\> numeric. Default `kge`.

- maximize:

  TRUE for efficiencies (NSE/KGE), FALSE for errors.

- n_evals:

  Total model runs. ~1000 is enough for ~8 parameters; scale up with the
  number of free parameters.

- r:

  DDS perturbation size as a fraction of each parameter range.

- seed:

  RNG seed for reproducibility.

## Value

list(best = named list of all parameters, value = objective, trace =
best-so-far objective per evaluation)
