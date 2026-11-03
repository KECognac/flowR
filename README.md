# WSVAflowR

An R package (in development) for multi-model streamflow simulation at
gauged basins, built toward driving calibrated models with climate
projections. The package design and roadmap are in
[`dev/package_design.md`](dev/package_design.md).

It grew out of streamflow modeling experiments for gauged, least-disturbed basins:
lumped water balance + routing models now, then distributed models and other
routing schemes (e.g. VIC/RVIC-style), all evaluated on the same basins and
the same train/test splits. LSTM experiments are archived in `archive/lstm/`.

The repository holds both the package (`R/`, `tests/`, `inst/`, `DESCRIPTION`)
and the analyses that use it (`scripts/`, not part of the package build).

```r
# Use the package
devtools::install()            # or devtools::load_all() while developing
library(WSVAflowR)
options(wsva.data_dir = "~/flow_data")   # downloads + caches (default: tools::R_user_dir)

b <- wsva_basin_usgs("01154000")         # or wsva_basin(flow_cdss("CCACCRCO")), wsva_basin(flow_from_csv(...))
b <- add_forcing(b)                      # GridMET
b <- add_basin_attributes(b)             # 3DEP, SSURGO, Jennings, NLCD / Kc
fits <- fit_models(b)                    # WBM, GR4J/5J/6J, HBV: blocked CV, climate-contrast test, full fit
summary(fits); plot(fits)
q_future <- predict(fits, forcing = future_forcing)   # any forcing meeting forcing_required_vars()

# Develop
devtools::document(); devtools::test(); devtools::check()
pkgdown::build_site()          # documentation site in docs/ (git-ignored)
```

`scripts/00_setup.R` loads the package with `pkgload::load_all()` and sets
`wsva.data_dir` to this repo's git-ignored `data/`, so the notebooks keep
their existing caches.

## Layout

```
DESCRIPTION, NAMESPACE, LICENSE.md   package metadata (NAMESPACE and man/ from roxygen2)
R/                 package functions
  WSVAflowR-package.R  wsva_path() (data dir option), wsva_extdata(), wsva_default_period()
  data_usgs.R        list_usgs_gauges(), get_usgs_flow()  - USGS Water Data APIs
  data_gagesii.R     get_gagesii_points()                  - GAGES-II screening
  data_basins.R      get_gauge_basin()                     - NLDI basin polygons
  data_gridmet.R     get_gridmet_cells(), gridmet_basin_mean()
  flow_sources.R     flow_usgs(), flow_cdss(), flow_from_df(), flow_from_csv(), flow_to_mm()
  delineate.R        delineate_basin(): watershed from an outlet point (StreamStats / NLDI)
  attributes.R       basin_dem(), basin_terrain(), get_basin_hypsometry(), basin_soil_storage(),
                     basin_jennings(), get_basin_landcover(), get_basin_static() (public datasets)
  basin.R            wsva_basin(), wsva_basin_usgs(), add_forcing(), add_basin_attributes()
  wbm.R, wbm_pet.R   wbm_run() + PET methods (Oudin, Hamon, Penman-Monteith)
  routing_ihacres.R  route_ihacres(), route_ihacres_snow()
  baseflow.R         baseflow_eckhardt()
  metrics.R          nse(), kge(), log_nse(), pbias(), ..., eval_metrics()
  benchmarks.R       benchmark_doy_climatology()
  splits.R           make_period_split(), make_blocked_folds(), make_climate_contrast_folds()
  calibrate.R        param_bounds(), calibrate_model() (DDS), cross_validate_model()
  wbm_kc.R           read_kc_table(), basin_kc(), kc_seasonal(), pet_ref_kc()
  forcing.R          prepare_forcing(): forcing contract + self-computed PET (GridMET or projections)
  gr.R               gr_setup()/gr_run()/gr_bounds() for GR4J/5J/6J (airGR)
  hbv.R              hbv_setup(), hbv_run(), hbv_bounds() (TUWmodel, elevation zones)
  models.R           wsva_model(), register_model(), wsva_models(): model specs (built-in: wbm, gr4j, gr5j, gr6j, hbv)
  fit.R              check_basin(), fit_models(): calibrate + evaluate several models on one basin (cached)
  fit_methods.R      print / summary / coef / predict / plot for wsva_fit
  prepare_basin.R    gauge_info(), prepare_basin(): processed model inputs for any basin
  data_gridmet_bulk.R download_gridmet_conus(), extract_gridmet_bulk(), read_gridmet_bulk()
scripts/           analyses using the package (not part of the build)
  00_setup.R         load the package (pkgload::load_all) + scripts/R helpers
  R/                 analysis-only helpers: read_camels(), rank_donors(), basin_attributes()
  01_select_test_gauges.R
  02_get_data.R      download + build data/processed/<site>/
  03_wbm_ihacres_cv.Rmd  WBM + IHACRES: calibrate, cross-validate, plot, experiment log
  05_gr4j_cv.Rmd     CemaNeige-GR4J benchmark; compares all models
  06_find_park_targets.R  small Reference gauges in/near National Parks
  07_select_donors.R      rank CAMELS donors for the pseudo-ungauged target
  08_get_regional_data.R  donor basins, flow, land cover, nesting check
  09_build_regional_inputs.R  GridMET (national files) + attributes for donors
  11_process_models_cv.Rmd    WBM, GR4J/5J/6J, HBV: blocked CV + climate-contrast test
  12_gauge_all_models.Rmd     any gauge (USGS, CDSS or csv) -> all process models, out-of-sample comparison
  13_compare_public_attributes.R  public-source attributes vs the old NPS rasters
tests/testthat/test-core.R        unit tests (no network)
tests/testthat/test-gr4j.R        GR4J wrapper tests (needs airGR)
tests/testthat/test-conceptual.R  forcing contract, GR5J/6J, HBV, model registry, contrast folds
tests/testthat/test-fit.R         model specs, fit_models(), wsva_fit methods (offline)
tests/testthat/test-data-layer.R  flow sources, basin objects, attribute aggregation (offline)
tests/testthat/test-network.R     live USGS / CDSS / StreamStats / SSURGO / NLCD checks (WSVA_NETWORK_TESTS=true)
config/            analysis config (test gauges, donors); not in the package
archive/lstm/      archived LSTM code, notebooks and tests
dev/               package design notes
vignettes/         getting-started, your-flow-data, custom-models
data-raw/          builds the bundled example basin (inst/extdata/example_clear_creek.rds)
_pkgdown.yml, pkgdown/  documentation site config and home page
.github/workflows/ R CMD check and pkgdown site on GitHub Actions
inst/extdata/kc_nlcd.csv  crop coefficients by NLCD class (kc_nlcd_liu2017.csv: rejected alternative)
inst/extdata/jennings2018_temp50.tif  Jennings et al. 2018 rain/snow threshold (add manually, see Setup)
data/              git-ignored: raw downloads, caches, processed inputs, results
```

## Test basins

Five GAGES-II Reference, HCDN-2009 gauges, 170-530 km2, chosen to span
hydroclimates (currently one each in the Pacific NW, Rockies, Southwest,
Northeast, and Southeast). Gauges are identified everywhere by site number
and official USGS station name (`gauge_label` in `config/test_gauges.csv`),
so swapping one only means editing `picks` in
`scripts/01_select_test_gauges.R` and re-running scripts 01-02.

| site | USGS station name |
|---|---|
| 12054000 | DUCKABUSH RIVER NEAR BRINNON, WA |
| 09081600 | CRYSTAL RIVER ABV AVALANCHE CRK, NEAR REDSTONE, CO |
| 09510200 | SYCAMORE CREEK NEAR FORT MCDOWELL, AZ |
| 01055000 | Swift River near Roxbury, Maine |
| 02177000 | CHATTOOGA RIVER NEAR CLAYTON, GA |

## Evaluation conventions

- Models work in basin-average depth (mm/day); observed flow is normalized by
  the GAGES-II drainage area.
- Study period WY1981-WY2024; WY1981 is warm-up and never scored.
- Splits are whole, contiguous water-year blocks (`make_blocked_folds()`),
  never random days. Process models run the full record; folds only choose
  the scored days. ML models must use the same fold labels, with a buffer at
  least as long as the input sequence.
- Every model is reported against the day-of-year climatology benchmark fit
  on the same training years.
- Process models are also run through a differential split-sample test
  (`make_climate_contrast_folds()`, Klemes 1986): calibrate on wet / dry /
  cool / warm / early years, test on the opposite extreme, as a historical
  check on transfer to a changed climate.
- PET is always computed from the meteorological variables
  (`prepare_forcing()`: FAO-56 Penman-Monteith x seasonal Kc), never taken
  from a dataset's PET product, so GridMET and downscaled projections
  (MACAv2-METDATA, the planned target) go through the same method.

## Setup

R >= 4.4. Packages: arrow, climateR, dataRetrieval (>= 2.7.18, for the
`read_waterdata_*` functions), dplyr, exactextractr, ggplot2, here,
nhdplusTools, purrr, readr, sf, terra, tibble, tidyr, testthat; airGR for the GR models; TUWmodel for HBV;
elevatr (terrain), soilDB (SSURGO), FedData (NLCD), curl + jsonlite (StreamStats), cdssr (Colorado DWR).

A USGS API token (`API_USGS_PAT` in `~/.Renviron`, free at
https://api.waterdata.usgs.gov/signup/) avoids rate limits.

Basin attributes come from public datasets downloaded per basin: terrain
from AWS Terrain Tiles (USGS 3DEP), soil water storage from gNATSGO/SSURGO
(0-150 cm available water storage by default, which matches the old NPS raster
within 5%; `scripts/13_compare_public_attributes.R`), and NLCD 2019 land cover.
The Jennings et al. (2018) rain/snow threshold raster ships with the package
but must be added once by hand, because Dryad blocks scripted downloads:
download `jennings_et_al_2018_file4_temp50_raster.tif` from
https://doi.org/10.5061/dryad.c9h35 (CC0) and save it as
`inst/extdata/jennings2018_temp50.tif`.

```r
source("scripts/02_get_data.R")        # first run ~1 h (GridMET)
rmarkdown::render("scripts/03_wbm_ihacres_cv.Rmd")   # ~15 min/gauge first time; cached after
rmarkdown::render("scripts/03_wbm_ihacres_cv.Rmd", params = list(pet_method = "gridmet"))
rmarkdown::render("scripts/05_gr4j_cv.Rmd")   # ~30 s
rmarkdown::render("scripts/11_process_models_cv.Rmd")   # ~1 h first time (mostly the WBM); cached after
# any gauge, all process models (~10-15 min; downloads its data first)
rmarkdown::render("scripts/12_gauge_all_models.Rmd", params = list(site_no = "01154000"),
                  output_dir = "data/processed/results/gauge_01154000")
testthat::test_file("tests/test_core.R")
```

## Provenance and changes from the MORA workflow

The WBM, routing, metric, and baseflow functions are ported from the
MORA Paradise WSVA project (originally the Thoma NPS water balance model,
ARC 2019 / MGS 2021, with CSU additions). Changes:

- WBM is generic (no park inputs), mm throughout (no inch conversion), one
  pass per state variable (~20 ms for 44 years).
- Fixed: Hamon PET used T + 273.3 in the vapor-pressure exponent (Tetens
  uses T + 237.3), underestimating PET ~15% at 20 C.
- Fixed: Penman-Monteith ignored observed shortwave (always clear-sky),
  omitted ^4 on Tmin in net longwave, and called `actual_vp()` with
  missing arguments.
- Fixed: `PET_mult` was applied in the soil update but not to W - PET or AET.
- Fixed: `runoff_routing_snow_fun()` used the rain slow-store recession for
  the melt store's gain, so melt volume wasn't conserved.
- Metrics return NA (not -9999 / 1e10) when undefined; calibration handles
  penalties.
- `test_model_fit()` replaced by `calibrate_model()` / `cross_validate_model()`
  (DDS search, folds in parallel),
  which take any `model_fn(par)` closure.
- USGS data uses the Water Data APIs (`read_waterdata_*`); the legacy NWIS
  functions (`readNWISdv`, `whatNWISdata`) are not used.

## Regional / ungauged experiment

Pseudo-ungauged target: 03460000 Cataloochee Creek near Cataloochee, NC
(Great Smoky Mountains National Park, 127 km2), withheld from all training.
Donors come from CAMELS (Addor et al. 2017; Newman et al. 2015); CAMELS
attribute text files go in `data/raw/camels/`. CAMELS attributes are used
only to choose donors; model inputs come from flowR's own pipeline (GridMET
from the national files, DEM, NLCD, soils), so they can be computed for any
basin. Run 07 -> 08 -> `download_gridmet_conus()` (~40 GB; the server allows
~2 connections, so this takes several hours) -> 09. The regional LSTM
notebook that used these inputs (10) and its results are archived in
`archive/lstm/`; the donor and attribute pipeline is kept for future
ungauged methods.
