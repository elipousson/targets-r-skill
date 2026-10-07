# Literate programming with targets

Render reports as the final stage of a pipeline. Dependencies on upstream targets are detected automatically when you call `tar_read()` or `tar_load()` inside the document.

## Quarto

```r
# _targets.R
library(targets)
library(tarchetypes)

list(
  tar_target(model, fit_model(data)),
  tar_quarto(report, "report.qmd")
)
```

Inside `report.qmd`:

````qmd
```{r}
targets::tar_read(model)
```
````

`tar_quarto()` scans the `.qmd` source for `tar_read()` / `tar_load()` calls and adds those targets as dependencies. You do not list them manually.

### Single-file output path

`tar_quarto(output_file = "out/report.html", ...)` overrides the path Quarto would pick itself (tarchetypes >= 0.12).

### Repeated Quarto reports

`tar_quarto_rep()` renders the same `.qmd` with different parameters, producing one branch per row of a parameter table. For Quarto >= 1.9, `tar_quarto_files()` handles the new `quarto inspect` output format (0.14.1).

- **Output paths go in the parameter table.** `tar_quarto_rep()` has no `output_file` argument. Add an `output_file` column to `execute_params` (relative paths, 0.13.1+) to write each report straight to its final location. Don't move the rendered file afterwards in another target (see "Untracked side effects" in [audit.md](audit.md)).
- **There's a hidden parameters target.** `tar_quarto_rep(reports, ...)` also defines a `reports_params` target from `execute_params`, which the render branches depend on. It appears in `tar_manifest()` and has to be included in `names` for the first `tar_make(..., shortcut = TRUE)` (see the `shortcut` notes in SKILL.md).

### Rendering a Quarto website

`tar_quarto()` isn't limited to a single `.qmd` — point it at a directory containing a Quarto *project* (a `_quarto.yml` with `project: type: website`, or `type: book`) and it renders the whole multi-page site as one dependency-tracked target:

```r
tar_quarto(website, path = "analysis")
```

Every `.qmd` under `analysis/` gets scanned for `tar_read()`/`tar_load()` calls the same way a single-file target would, so the whole site rebuilds when any of its real upstream dependencies change — not just when a page's own source is edited.

One gotcha specific to this multi-page case: each page executes with *its own file's directory* as the working directory, not the pipeline's root where `_targets/` lives. A `tar_load()`/`tar_read()` call inside a sub-page one level below the project root can silently fail to find the store unless you redirect it:

````qmd
```{r}
withr::with_dir(here::here(), {
  targets::tar_load(penguins_clean)
})
```
````

A single-file `tar_quarto(report, "report.qmd")` target never hits this — Quarto has no separate project directory to execute from in that case.

### Quarto's `freeze` cache vs. targets' cache

`_quarto.yml`'s `execute: freeze: auto` is a second, independent caching layer: Quarto skips re-executing a document's code chunks when their source hasn't changed, on top of — not coordinated with — `targets`' own skip logic for the `tar_quarto()` target itself. This matters most in CI, where the `_targets/` store usually isn't available but a committed `_freeze/` directory still lets Quarto avoid rerunning expensive chunks. The trap: if a `_freeze/` snapshot goes stale relative to what an upstream target actually produced, Quarto can serve cached chunk output that no longer matches the current pipeline run. If you rely on `targets` alone to know when to rebuild, don't commit `_freeze/` — or clear it whenever a real upstream dependency changes.

### Project configurations

For subdirectory output with `_quarto.yml`:

```r
params_tbl$output_file <- file.path("reports", params_tbl$slug, "report.html")

tar_quarto_rep(
  reports,
  "report.qmd",
  execute_params = params_tbl
)
```

## R Markdown

```r
tar_render(report, "report.Rmd")
```

`tar_render_rep()` is the parameterized counterpart.

### `deployment` parameter

Both `tar_render()` and `tar_quarto()` accept `deployment` (0.13.1+). Set `deployment = "main"` to force rendering on the host rather than a parallel worker — useful when workers lack Pandoc or filesystem access to assets.

## Progress bars inside Quarto / R Markdown

tarchetypes 0.13.2 disables targets' internal progress bars during `tar_render()` / `tar_render_rep()` to avoid noisy HTML output. No action required on your side.

## External documents (Typst, LaTeX, Word)

For compile steps that are fast relative to the rest of the pipeline, make the compile target the last thing in the pipeline and always rebuild:

```r
tar_file(
  manuscript_pdf,
  command = {
    system2("typst", c("compile", "manuscript.typ"))
    "manuscript.pdf"
  },
  cue = tar_cue(mode = "always")
)
```

Three reasons this works:

1. Compilation is fast enough that skip logic rarely pays off.
2. It sits at the end of the graph, so upstream ordering is guaranteed.
3. You avoid the fragile task of listing every upstream asset.

### When skip logic matters

For slow LaTeX builds, declare upstream targets explicitly and track every source file:

```r
tar_file(
  manuscript_pdf,
  command = {
    # Force ordering by referencing upstream targets.
    tab_main; plot_main; plot_sensitivity

    system2("latexmk", c("-pdf", "manuscript.tex"))

    # Return every path that affects the output so targets hashes them all.
    c(
      "manuscript.pdf", "manuscript.tex", "references.bib",
      list.files("tables",  full.names = TRUE),
      list.files("figures", full.names = TRUE)
    )
  }
)
```

## `tar_tangle()` for extracted code

tarchetypes 0.14 adds `tar_tangle()`, which extracts R code from `.Rmd` / `.qmd` / `.Rnw` and tracks it as a target. Useful when you want the pipeline to depend on chunk contents without rendering the whole document.

## Auto-detection details

`tar_quarto()` and `tar_render()` use static analysis to find `targets::tar_read()` and `targets::tar_load()` calls. They miss:

- Calls hidden behind `do.call()` or dynamic symbol lookup.
- Calls in child documents that are not listed in the YAML frontmatter.

If auto-detection misses a dependency, pass it explicitly:

```r
tar_quarto(report, "report.qmd", deps = c("hidden_target"))
```

### Files the report uses: `extra_files`

File dependencies are detected separately from target dependencies. `tar_quarto()` and `tar_quarto_rep()` track the files `quarto inspect` reports: the document, files pulled in with `{{< include >}}`, and Quarto project files. Run `tarchetypes::tar_quarto_files("report.qmd")` to see the list. Not tracked:

- R scripts the document loads itself with `targets::tar_source()` or `source()`. The pipeline hashes functions only for target commands, so editing a helper the report calls doesn't rerun the report.
- Child documents rendered from R (`knitr::knit_child()`, or a path built in a chunk).
- Format extensions (`_extensions/`), templates, and data files read by literal path.

List these in `extra_files` (paths or directories) so changes to them rerun the report:

```r
tar_quarto(
  report,
  "reports/report.qmd",
  extra_files = c(
    "reports/_children",
    "reports/_extensions",
    "R/report-helpers.R"
  )
)
```

When reviewing a pipeline, compare the `extra_files` list with what the document actually sources. A helper missing from `extra_files` means the report target can stay "up to date" after the code it runs has changed.

### Harmless "object not found" messages from parameterized documents

To find `tar_read()` and `tar_load()` calls, tarchetypes tangles the document with `knitr::purl()`, and knitr evaluates chunk options such as `eval` while it does that. If a chunk option refers to `params` or to an object the document creates (e.g. `#| eval: !expr show_summary`), that object doesn't exist yet, so a message like this is printed whenever the pipeline is loaded (`tar_make()`, `tar_manifest()`, `tar_visnetwork()`), once per chunk:

```
Error in eval(x, envir = envir) : object 'show_summary' not found
```

These messages are harmless. The pipeline is still defined, and the report still renders with the option evaluated correctly ([ropensci/targets#256](https://github.com/ropensci/targets/issues/256)). Don't report them as a pipeline error or a defect in an audit. Don't rewrite `eval: !expr` options as `if ()` blocks just to silence them, unless the user asks. Before dismissing a message, check that its object name matches an `!expr` chunk option or a `params` reference in the document. To confirm the pipeline itself is fine, check that `tar_validate()` passes, that the report target appears in `tar_manifest()`, and that its build finished without an error in `tar_meta(fields = error)`.

One real consequence: knitr may leave a chunk out of the tangled script if its options can't be evaluated. If that chunk has the only `tar_read()` call for a target, the dependency may not be detected. Put `tar_read()`/`tar_load()` calls in chunks without conditional options (e.g. a setup chunk), or pass the target with `deps`.
