# Heat load index (McCune & Keon 2002, as used by Lutz et al. 2010)

Scales PET for slope/aspect. Returns ~1 for flat ground at mid
latitudes.

## Usage

``` r
heat_load_index(lat, slope_deg, aspect_deg)
```

## Arguments

- lat:

  Latitude (degrees).

- slope_deg, aspect_deg:

  Slope and aspect (degrees).
