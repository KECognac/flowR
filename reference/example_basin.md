# Example basin: Clear Creek above Clear Creek Reservoir, Colorado

A ready-to-fit `wsva_basin` (flow, GridMET forcing and attributes
already added) for examples and vignettes, so they run without
downloads. Clear Creek (CDSS station CCACCRCO; USGS 07086500 until 1995,
operated by the Colorado Division of Water Resources since) is a 174
km2, snowmelt- dominated GAGES-II Reference basin in the Sawatch Range.
Water years 2000-2016. Built by `data-raw/example_basin.R` in the source
repository.

## Usage

``` r
example_basin()
```

## Value

A `wsva_basin`.

## Examples

``` r
b <- example_basin()
b
#> <wsva_basin> CCACCRCO CLEAR CREEK ABOVE CLEAR CREEK RESERVOIR, CO.
#>   flow: CDSS, 1999-10-01 to 2016-09-30, 100% observed
#>   watershed: StreamStats (CO), 173.6 km2 (reference 174.1 km2 from GAGES-II, -0.3%)
#>   forcing: GridMET (national files) 1999-10-01 to 2016-09-30 
#>   attributes: added 
check_basin(b)
#> # A tibble: 5 × 3
#>   check           status detail                                                 
#>   <chr>           <chr>  <chr>                                                  
#> 1 record length   ok     16 water years with >= 80% observed flow inside the fo…
#> 2 drainage area   ok     watershed 173.6 km2 vs reference 174.1 km2 (-0.3%, GAG…
#> 3 runoff ratio    ok     Q/P = 0.47                                             
#> 4 human influence ok     GAGES-II class: Ref                                    
#> 5 basin size      ok     174 km2                                                
```
