# Calibrate and evaluate several process models on one basin

Every model gets the same forcing, PET, folds and calibration algorithm
(DDS). For each model:

- blocked water-year cross-validation (out-of-sample skill and a
  continuous out-of-sample series),

- optionally the climate-contrast (differential split-sample) test,

- optionally one calibration on all scored years: the parameters
  [`predict()`](https://rdrr.io/r/stats/predict.html) uses with new
  forcing (e.g. climate projections).

## Usage

``` r
fit_models(
  basin,
  models = c("wbm", "gr4j", "gr5j", "gr6j", "hbv"),
  cv = c("blocked", "climate_contrast"),
  objective = kge,
  n_evals = 1000,
  k_folds = 5,
  contrast_frac = 1/3,
  min_obs_frac = 0.8,
  fit_full = TRUE,
  n_layers = 5,
  n_cores = 1,
  seed = 1,
  cache = TRUE
)
```

## Arguments

- basin:

  A `wsva_basin`. Forcing and attributes are added if missing.

- models:

  Model ids (see `names(.builtin_models())` /
  [`wsva_models()`](https://kecognac.github.io/flowR/reference/wsva_models.md)).

- cv:

  Evaluation designs: "blocked" and/or "climate_contrast".

- objective:

  function(obs, sim) to maximize (default `kge`).

- n_evals:

  DDS model runs per calibration (scaled by each model's
  `n_evals_mult`).

- k_folds:

  Blocked folds.

- contrast_frac:

  Fraction of water years in each climate-contrast group.

- min_obs_frac:

  Water years with less observed flow are not scored.

- fit_full:

  Also calibrate on all scored years.

- n_layers:

  Elevation bands for CemaNeige and HBV.

- n_cores:

  Folds calibrated in parallel.

- seed:

  Base seed.

- cache:

  Reuse cached results.

## Value

A `wsva_fit`.

## Details

Results are cached per model and design under
`wsva_path("fits", <basin id>)`, keyed by everything that affects them,
so re-running only fits what changed.
