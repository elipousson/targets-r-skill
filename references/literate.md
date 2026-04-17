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

```r
```{r}
targets::tar_read(model)
```
```

`tar_quarto()` scans the `.qmd` source for `tar_read()` / `tar_load()` calls and adds those targets as dependencies. You do not list them manually.

### Single-file output path

`tar_quarto(output_file = "out/report.html", ...)` overrides the path Quarto would pick itself (tarchetypes >= 0.12).

### Repeated Quarto reports

`tar_quarto_rep()` renders the same `.qmd` with different parameters, producing one branch per row of a parameter table. Use relative paths in the `output_file` column (0.13.1+). For Quarto >= 1.9, `tar_quarto_file()` handles the new `quarto inspect` output format (0.14.1).

### Project configurations

For subdirectory output with `_quarto.yml`:

```r
tar_quarto_rep(
  reports,
  "report.qmd",
  execute_params = params_tbl,
  output_file = file.path("reports", params_tbl$slug, "report.html")
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
