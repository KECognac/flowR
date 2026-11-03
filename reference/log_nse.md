# NSE of log flows (emphasizes low flows); `eps` avoids log(0)

NSE of log flows (emphasizes low flows); `eps` avoids log(0)

## Usage

``` r
log_nse(obs, sim, eps = NULL)
```

## Arguments

- obs, sim:

  Observed and simulated values (pairs with an NA are dropped).

- eps:

  Offset added before the log so zero flows are defined; default 1% of
  mean observed flow.
