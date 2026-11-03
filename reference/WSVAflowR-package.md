# WSVAflowR: multi-model streamflow simulation for gauged basins

Builds model inputs for a stream gauge, calibrates and cross-validates
several process models on identical forcing and folds, and tests their
transfer to contrasting climates. See `dev/package_design.md` in the
source repository for the planned interface.

## Data directory

Downloads, caches and prepared basin inputs live under one directory:
`getOption("wsva.data_dir")`, defaulting to
`tools::R_user_dir("WSVAflowR", "cache")`. Set it once per session, e.g.
`options(wsva.data_dir = "~/flow_data")`.

## See also

Useful links:

- <https://github.com/KECognac/flowR>

- <https://kecognac.github.io/flowR/>

- Report bugs at <https://github.com/KECognac/flowR/issues>

## Author

**Maintainer**: Kristen Cognac <kristencognac@gmail.com>
