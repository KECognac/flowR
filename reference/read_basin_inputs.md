# Read a prepared basin's daily table, static attributes and hypsometry

Read a prepared basin's daily table, static attributes and hypsometry

## Usage

``` r
read_basin_inputs(site_no)
```

## Arguments

- site_no:

  Basin id (folder under `wsva_path("processed")`).

## Value

list(daily = forcing + q_mm with eto_mm/pet_mm, static, hypso)
