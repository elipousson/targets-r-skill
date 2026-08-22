# Reproducible dependencies

`renv` works with a `targets` project the same way it works with any other R project, with one exception: `renv`'s dependency crawler (`renv::dependencies()`) finds packages via `library()`/`require()`/`pkg::fun()` calls in source files. It has no special knowledge of `tar_option_set(packages = ...)` or `tar_target(..., packages = ...)` — the two places a `targets` pipeline most commonly declares dependencies — so those go undetected by default.

## `tar_renv()` bridges the gap

```r
targets::tar_renv()
```

Writes `_targets_packages.R` (default path), one `library(pkg)` call per line, covering:

- Every package listed in a `packages` argument, at `tar_option_set()` or on an individual `tar_target()`.
- Whatever package a target's `format` requires (`format = "qs"` pulls in `qs`, `format = "parquet"` pulls in `arrow`/`nanoparquet`, etc.).
- Anything you pass explicitly via `tar_renv(extras = c(...))` — packages `targets` has no way to infer, like a Shiny app's UI dependencies.

`renv` then crawls this file like any other script and picks the packages up. **Never hand-edit `_targets_packages.R`** — it's regenerated wholesale every time `tar_renv()` runs, so re-run it (not patch it) whenever the pipeline's dependencies change.

## Workflow

```r
# after writing/updating tar_option_set(packages = ...) or format= choices
targets::tar_renv()      # regenerate _targets_packages.R
renv::init()             # first time only — sets up the project-local library
renv::snapshot()         # record current package versions into renv.lock
```

On a fresh clone (or in CI): `renv::restore()` reinstalls exactly what `renv.lock` pins. `tar_renv()`'s own job stops at making dependencies *visible* to `renv` — `renv::init()`/`snapshot()`/`restore()` are still the user's responsibility to call, same as on a non-`targets` project. See the [renv introduction](https://rstudio.github.io/renv/articles/renv.html) for the full workflow and `renv::status()` for checking project-library health.

Re-run `tar_renv()` + `renv::snapshot()` together whenever a dependency is added, removed, or its `format` changes — a stale `_targets_packages.R` means `renv` silently stops seeing a package the pipeline actually needs, and the next `renv::restore()` on a clean machine won't install it.

## Performance note

`renv`'s project-init and sync checks run before every `tar_make()` and can add real overhead, especially over a slow network filesystem. If that's noticeable, confirm at the [renv config docs](https://rstudio.github.io/renv/reference/config.html) that it's safe for your setup, then set `RENV_CONFIG_SANDBOX_ENABLED=false` and `RENV_CONFIG_SYNCHRONIZED_CHECK=false` in your user-level `.Renviron`. If you disable the sync check, run `renv::status()` periodically by hand instead of relying on it happening automatically.

## A lighter option for small or exploratory pipelines

Full `renv` — a project-local library, a lockfile, an init/snapshot/restore workflow — earns its overhead on anything shared, long-lived, or run in CI. For a small, single-author, or exploratory pipeline, a cheaper alternative is a helper that installs whatever's missing, called once before the pipeline runs:

```r
install_pkgs <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) install.packages(missing)
}
install_pkgs(c("targets", "tarchetypes", "dplyr"))
```

This doesn't pin versions or isolate a project library — it just gets a fresh clone from "nothing installed" to "runnable" in one call, no `renv` machinery involved. Reach for it when the dependency footprint is small and reproducible *presence* matters more than reproducible *versions*; move to `renv` once that stops being true — multiple contributors, a CI run that needs to match production, or output that needs to be reproducible months later.
