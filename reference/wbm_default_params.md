# Default WBM parameters

Site parameters (lat, elev_m, slope_deg, aspect_deg, swc_max_mm,
jtemp_c, and kc_dormant / kc_growing for reference-ET methods) come from
[`get_basin_static()`](https://kecognac.github.io/flowR/reference/get_basin_static.md)
and
[`basin_kc()`](https://kecognac.github.io/flowR/reference/basin_kc.md).
The rest are calibration knobs or fixed settings; with pet_method =
"oudin" these defaults reproduce the original NPS model.

## Usage

``` r
wbm_default_params()
```
