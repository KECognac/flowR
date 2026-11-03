# Blocked cross-validation of a calibrated model

For each fold, calibrates on "train" days and scores both train and
test. Folds are independent, so they can run in parallel: forked
processes
([`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html)) on
macOS/Linux; on Windows, `future.apply` under the user's
[`future::plan()`](https://future.futureverse.org/reference/plan.html)
if installed, otherwise serially.

## Usage

``` r
cross_validate_model(model_fn, bounds, obs, folds, n_cores = 1, seed = 1, ...)
```

## Arguments

- model_fn, bounds, obs:

  As for
  [`calibrate_model()`](https://kecognac.github.io/flowR/reference/calibrate_model.md):
  parameters -\> simulated flow,
  [`param_bounds()`](https://kecognac.github.io/flowR/reference/param_bounds.md),
  observed flow.

- folds:

  Output of
  [`make_blocked_folds()`](https://kecognac.github.io/flowR/reference/make_blocked_folds.md)
  (dates must match `obs`).

- n_cores:

  Folds run at once.

- seed:

  Base seed; fold f uses seed + f, so results don't depend on n_cores.

- ...:

  Passed to
  [`calibrate_model()`](https://kecognac.github.io/flowR/reference/calibrate_model.md).

## Value

list(metrics = tibble per fold x set, params = tibble per fold, sims =
long tibble of out-of-fold test simulations, traces = tibble of
best-so-far objective per evaluation and fold)
