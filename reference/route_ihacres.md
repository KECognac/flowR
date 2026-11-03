# Route runoff through quick and slow linear stores with optional losses

Port of `runoff_routing_gw()`, taking a numeric vector rather than a
data frame so it composes with any upstream runoff model.

## Usage

``` r
route_ihacres(
  runoff,
  tau_q,
  tau_s,
  vs,
  loss = 0,
  slow_only = FALSE,
  max_loss = Inf,
  delay = 0,
  baseflow = 0,
  return_components = FALSE
)
```

## Arguments

- runoff:

  Numeric vector of runoff (no NA).

- tau_q, tau_s:

  Quick and slow recession time constants (time steps).

- vs:

  Fraction of runoff entering the slow store (0-1).

- loss:

  Fraction lost to deep groundwater (0-1).

- slow_only:

  If TRUE, losses come only from the slow store (capped at `max_loss`
  per step); otherwise from both.

- max_loss:

  Maximum loss per time step when `slow_only = TRUE`.

- delay:

  Whole-time-step lag applied to all components.

- baseflow:

  Constant added to total flow (e.g. spring inflow).

- return_components:

  If TRUE return a tibble of components.

## Value

Numeric vector of routed flow, or a tibble with q_quick, q_slow, q_loss,
q_total.
