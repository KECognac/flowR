# WSVAflowR package design (draft for review)

Working name **WSVAflowR**. Status: phases 1-4 (skeleton, data layer,
model interface, docs and CI) done 2026-11-03, in place in this
repository; phase 5 (projections) is next.

## Goal

A user who has daily flow data for a stream gauge, from USGS, Colorado DWR
(`cdssr`), or their own logger, can in a few lines:

1. delineate the watershed and gather climate and basin inputs
2. calibrate and cross-validate several process models
3. see how well each model does on held-out years and in a different climate
4. drive the calibrated models with downscaled climate projections and get
   streamflow change from every model and climate model

Scope for version 0.1: steps 1-3 for CONUS basins with GridMET. Step 4
(MACAv2-METDATA) comes next, on top of this structure. LSTMs are out of
scope (archived in `archive/lstm/`).

## User workflow

```r
library(WSVAflowR)

# 1. A basin: three ways in
b <- wsva_basin_usgs("01154000")                                # USGS gauge
b <- wsva_basin(outlet = c(-105.27, 40.01), flow = my_flow)      # any outlet point
b <- wsva_basin(polygon = my_sf, flow = cdss_flow, area_km2 = 145)  # own watershed

# 2. Inputs
b <- add_forcing(b, source = "gridmet")        # later: "maca", "daymet", "mrms"
b <- add_basin_attributes(b)                   # DEM, soils (SSURGO), land cover, Jennings
check_basin(b)                                 # water budget, area, record length, screening

# 3. Models
fits <- fit_models(b, models = c("wbm", "gr4j", "gr5j", "gr6j", "hbv"),
                   cv = c("blocked", "climate_contrast"))
summary(fits)                                  # skill table
plot(fits)                                     # the notebook-12 figure

# 4. Projections (after MACA)
proj <- project(fits, climate = "maca", gcms = "all", scenario = c("rcp45", "rcp85"),
                periods = list(hist = 1976:2005, mid = 2040:2069, late = 2070:2099))
summary(proj); plot(proj)
```

`my_flow` is a data frame with `date` and one of `q_cfs`, `q_cms` or
`q_mm`. Helpers convert from common sources:

```r
flow_usgs("01154000")
flow_cdss("CLAFTCCO")             # wraps cdssr; DWR station abbreviation
flow_from_csv("gauge.csv", date_col = "Date", q_col = "Q", units = "cfs")
```

## Core objects (S3)

| Class | Holds | Created by | Methods |
|---|---|---|---|
| `wsva_basin` | id, name, outlet point, polygon, area (reference + delineated), flow (date, q_mm), provenance (where each piece came from), forcing table, static attributes, hypsometry | `wsva_basin*()`, `add_forcing()`, `add_basin_attributes()` | `print`, `summary`, `plot` (map + record), `check_basin` |
| `wsva_forcing` | daily basin-mean table meeting the forcing contract, source, period, scenario/GCM if any | `forcing_gridmet()`, later `forcing_maca()` | `print`, `plot` |
| `wsva_fit` | per model: CV results (folds, metrics, out-of-sample series, parameters), full-record parameters, settings, package version | `fit_models()` | `print`, `summary`, `plot`, `predict(fit, forcing)`, `coef` |
| `wsva_projection` | per model × GCM × scenario × period: simulated flow and change signals | `project()` | `summary`, `plot` |

S3 rather than R6: plain lists that save with `saveRDS()` and inspect
easily, matching how the code already passes results around.

## Data layer: pluggable sources

Each source is a small function that returns a standard object, so new
sources are added without touching the models.

**Flow sources** return `tibble(date, q_mm)` plus metadata:

| Source | Function | Package |
|---|---|---|
| USGS Water Data APIs | `flow_usgs()` | dataRetrieval |
| Colorado DWR (CDSS) | `flow_cdss()` | cdssr |
| User data | `flow_from_df()`, `flow_from_csv()` | - |

**Basin delineation**:

| Input | Method |
|---|---|
| USGS site | NLDI basin by `nwissite` (current `get_gauge_basin()`) |
| Outlet point | NLDI split-catchment delineation from a lon/lat (`nhdplusTools::get_split_catchment()`); optional USGS StreamStats for state-calibrated delineation |
| Polygon | used as given |

Every route records the delineated area and compares it with a reported
drainage area when one exists (warning above 10-20%, as notebook 12 does).

**Forcing sources** return the forcing contract (`R/forcing.R`):
`date, prcp_mm, tmin_c, tmax_c, srad_wm2, rhmin_pct, rhmax_pct, wind_ms`.
PET is always computed by the package (Penman-Monteith x Kc), never taken
from the source.

| Source | Status |
|---|---|
| GridMET (climateR per basin; optional bulk national files) | have |
| MACAv2-METDATA | next (projections) |
| Daymet, MRMS, LOCA2 | later; Daymet and LOCA2 lack wind/humidity, so they need a documented PET fallback |

**Static attributes** (replacing the local NPS rasters):

| Attribute | Current | Package source |
|---|---|---|
| Elevation, slope, aspect, hypsometry | `elevation_cropped.tif` (local copy) | USGS 3DEP via `elevatr` (download per basin, cached) |
| Soil water storage (`swc_max_mm`) | `water_storage.tif`, 800 m CONUS (local copy) | SSURGO, gap-filled with STATSGO2 (gNATSGO) via `soilDB`: map-unit raster over the basin (`mukey.wcs()`) + available water storage from Soil Data Access, area-weighted |
| Rain/snow threshold (`jtemp_c`) | `merged_jennings2.tif` | Jennings et al. 2018, Dryad doi:10.5061/dryad.c9h35, CC0. `file4_temp50_raster.tif` is 0.8 MB, so it ships in `inst/extdata` |
| Land cover / Kc | NHDPlus `TOT_NLCD19_*` via the USGS site's COMID | NLCD 2019+ raster over the polygon (works for any basin), `config/kc_nlcd.csv` in `inst/extdata` |
| Soil texture / hydrologic group (regional attributes) | NHDPlus `TOT_*` | SSURGO via `soilDB` (later; only needed for ungauged work) |

## Model interface

The registry already exists (`flowr_process_models()`, `R/models.R`). For
the package each model becomes a spec object:

```r
wsva_model(
  id = "gr5j", name = "CemaNeige-GR5J",
  bounds = gr_bounds("GR5J"),
  build = function(basin) function(params) <daily q_mm>,
  requires = c("prcp_mm", "tmin_c", "tmax_c", "pet_mm"),   # checked before fitting
  n_evals_mult = 1,
  package = "airGR",                                       # Suggests; checked at use
  reference = "Pushpalatha et al. 2011, J. Hydrol. 411:66"
)
register_model(spec)      # users can add their own
```

`fit_models()`, CV, metrics and plotting treat every model the same way,
so adding VIC or a distributed model later means writing one spec.

## Calibration and evaluation

Kept as is: DDS on KGE; blocked water-year CV; climate-contrast (Klemes)
folds; out-of-sample series; day-of-year climatology benchmark;
full-record calibration saved for projections. Changes:

- Parallel folds through `future` / `furrr` instead of `mclapply` (Windows).
- Objective is a user option (KGE default; KGE on log flows or a combined
  objective later).
- Record-length and gap checks before fitting (as in notebook 12).

## Projections (design only; built after the restructure)

- Each GCM's future run is compared against **the same GCM's historical
  run**, both through the same calibrated model, not against GridMET. This
  cancels most of the GCM's remaining bias.
- Outputs: change in annual and seasonal flow, timing (centre of mass),
  low flows (7-day minimum), peaks; by model × GCM × scenario.
- Spread split into GCM, hydrologic-model and scenario contributions.
- Each basin's climate-contrast results travel with the projection as a
  confidence flag.
- Optional CO2 adjustment to Penman-Monteith surface resistance (Yang et
  al. 2019), off by default.

## Package infrastructure

- **Caching:** `tools::R_user_dir("WSVAflowR", "cache")` by default,
  configurable with `options(wsva.cache_dir = ...)`; no `here::here()` or
  project-folder assumptions.
- **Dependencies:** core `Imports`: dplyr, tibble, purrr, readr, sf, terra,
  exactextractr, arrow. `Suggests` (checked at use): airGR, TUWmodel,
  climateR, dataRetrieval, nhdplusTools, cdssr, soilDB, elevatr, ggplot2,
  patchwork, future/furrr.
- **License:** GPL-3 (airGR and TUWmodel are GPL). Check the license of the
  ported NPS WBM code before release.
- **Docs:** roxygen2 for every exported function; vignettes: "From a USGS
  gauge to five models", "Using your own flow data (CDSS example)",
  "Climate-contrast testing", later "Projections"; pkgdown site.
- **Tests:** testthat 3e; unit tests offline; network calls recorded with
  `httptest2`; a small bundled example basin (a few years of forcing +
  flow) so examples and vignettes run without downloads.
- **CI:** GitHub Actions `R CMD check` on macOS, Windows, Linux.
- **Name:** confirm "WSVAflowR" is free on CRAN and GitHub.

## Migration from this repo

| Now (`R/`) | Package |
|---|---|
| `data_usgs.R`, `data_basins.R`, `prepare_basin.R`, `data_gagesii.R` | `basin.R` (constructors), `flow_sources.R` (+ `flow_cdss`, CSV), `delineate.R` (+ point delineation) |
| `data_gridmet.R`, `data_gridmet_bulk.R`, `forcing.R` | `forcing_gridmet.R`, `forcing.R` (contract + PET) |
| `data_static.R`, `wbm_kc.R`, `basin_attributes.R` | `attributes.R` (3DEP, SSURGO, Jennings, NLCD) |
| `wbm.R`, `wbm_pet.R`, `routing_ihacres.R`, `gr.R`, `hbv.R`, `models.R` | `model_*.R` + `models.R` (spec + registry) |
| `calibrate.R`, `splits.R`, `metrics.R`, `benchmarks.R`, `baseflow.R` | unchanged, exported |
| `scripts/12_gauge_all_models.Rmd` | becomes the first vignette and `plot.wsva_fit()` |
| `scripts/03-11`, `data_camels.R`, regional scripts 06-09 | stay in a separate `analysis/` folder (not part of the package build) |

Suggested phases:

1. **Skeleton (done 2026-11-03):** DESCRIPTION, LICENSE (GPL-3), roxygen
   NAMESPACE (temporarily `exportPattern("^[^\\.]")`: every function not
   starting with `.` is exported), data directory option `wsva.data_dir`
   (`wsva_path()`), Kc tables in `inst/extdata`, tests in testthat 3e,
   notebooks load the package with `pkgload::load_all()` and keep their
   caches. `R CMD check`: 0 errors; remaining warnings are documentation
   gaps (14 helpers without help pages, some undocumented arguments), left
   for phase 4. `get_test_gauges()` moved to `scripts/00_setup.R`;
   `flowr_process_models()` renamed `wsva_models()`. Analysis-only R code
   (`data_camels.R`, regional attributes) is still in `R/`; it moves out in
   phase 2.
2. **Generalize the data layer (done 2026-11-03):** `flow_usgs()`,
   `flow_cdss()`, `flow_from_df()` / `flow_from_csv()` (standard flow
   table in m3/s); `delineate_basin()` (StreamStats primary; NLDI fallback,
   whose split-catchment service was down when tested, so the fallback runs
   to the bottom of the NHDPlus catchment and warns); `wsva_basin()`,
   `wsva_basin_usgs()`, `add_forcing()`, `add_basin_attributes()`;
   `prepare_basin()` takes a site number or any basin. Attributes from
   elevatr (3DEP), soilDB (gNATSGO `muaggatt` aws0150wta; root-zone AWS is
   not on Soil Data Access), FedData (NLCD) and the Jennings raster. On the
   5 test basins: soil storage 0-150 cm within 5% of the NPS raster on
   average (0-100 cm: 23%), Kc identical, mean elevation within 20 m; slope
   2-4x steeper on the ~60 m DEM (only used by Oudin PET). CAMELS and
   regional-attribute code moved to `scripts/R/`. The 5 test basins' cached
   inputs still come from the old rasters; rebuilding them
   (`scripts/02_get_data.R` with `overwrite = TRUE`) recalibrates the
   notebooks. **Pending:** the Jennings file must be downloaded by hand
   (Dryad blocks scripted downloads).
3. **Model specs and `fit_models()` (done 2026-11-03):** `wsva_model()` /
   `register_model()` / `wsva_models(ids)`; `check_basin()` (record length,
   area, runoff ratio, GAGES-II screening, size); `fit_models()` runs
   blocked CV, the climate-contrast test and a full-record calibration per
   model, cached under `wsva_path("fits", id)` by a hash of inputs and
   settings; `wsva_fit` methods `print`, `summary`, `coef`, `predict`
   (out-of-sample series, or new forcing with full-record parameters and a
   spin-up year blanked) and `plot` (overview, hydrograph, fdc, seasonal,
   annual, skill, contrast, params). Parallel folds: `mclapply` on
   macOS/Linux, `future.apply` on Windows if installed. Explicit exports
   (85 functions) replace `exportPattern()`. Notebook 12 now runs on this
   API. Not done: the `objective` choice is exposed but only KGE has been
   exercised; notebooks 03, 05 and 11 still use the lower-level functions.
4. **Docs and CI (done 2026-11-03):** every exported function documented
   (`R CMD check`: 0 errors, 0 warnings); bundled offline example basin
   (`example_basin()`, Clear Creek CO WY2000-2016, 145 KB, built by
   `data-raw/example_basin.R`); vignettes "getting-started" (runs live on
   the example basin, ~1 min), "your-flow-data" (USGS / CDSS / csv; shown,
   not run) and "custom-models" (registering a model); pkgdown config with
   a grouped reference and its own home page (`pkgdown/index.md`); GitHub
   Actions for `R CMD check` (macOS, Windows, Linux) and the pkgdown site
   (deploys to GitHub Pages on push to main). **Caveat:** the example
   basin's `jtemp_c` was taken from the old NPS Jennings raster; rebuild it
   with `data-raw/example_basin.R` once the Dryad file is in
   `inst/extdata`.
5. **Projections:** MACA forcing source, `project()`.

## Open decisions

1. ~~Repository~~: restructured in place (decided 2026-11-03). Rename the
   folder / GitHub repo to WSVAflowR when convenient.
2. ~~Soil storage depth~~: 0-150 cm (closest to the NPS raster; decided
   by comparison 2026-11-03). 0-100 cm available via `soil_depth_cm = 100`.
3. ~~CDSS test gauge~~: Clear Creek above Clear Creek Reservoir, CO
   (`CCACCRCO`): GAGES-II Reference, USGS 07086500 until 1995 and
   DWR-operated since, full 1981-2024 record in CDSS.
4. **Distribution:** CRAN eventually, or GitHub-only?
