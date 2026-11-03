# Blocked k-fold cross-validation on contiguous water-year blocks

Water years after the warm-up are cut into `k` contiguous blocks. In
fold i, block i is "test", days within `buffer_days` of the test block
are "buffer" (excluded from training), and everything else is "train".

## Usage

``` r
make_blocked_folds(
  dates,
  k = 5,
  warmup_years = 1,
  buffer_days = 0,
  min_obs_frac = 0,
  obs = NULL
)
```

## Arguments

- dates:

  Date vector covering the full model run.

- k:

  Number of folds.

- warmup_years:

  Leading water years never scored.

- buffer_days:

  Days excluded either side of each test block.

- min_obs_frac:

  Optional: with `obs`, drop water years with less than this fraction of
  observed days before forming blocks.

- obs:

  Optional observation vector aligned with `dates`.

## Value

Long tibble: fold, date, wy, role ("train", "test", "buffer", "warmup").
