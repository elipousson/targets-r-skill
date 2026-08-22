---
name: targets-r
description: Modern patterns for reproducible analysis pipelines with the targets R package, and auditing existing pipelines for problems. Use this skill when writing `_targets.R`, defining targets, debugging pipeline failures, running individual targets safely, configuring storage, or integrating Quarto/R Markdown. Also use it whenever the user asks to review, audit, analyze, or improve an existing targets pipeline — e.g. "is my _targets.R any good", "why is this pipeline slow", "clean up this pipeline", "check this for anti-patterns" — even if they don't name the targets package explicitly, as long as a `_targets.R` file or `tar_target()`/`tar_plan()` calls are involved. Covers `tar_target()`, the tarchetypes factories, dynamic and static branching, error handling, cycle debugging, cloud and CAS repositories, and a structured pipeline-audit checklist.
license: CC-BY-4.0
metadata:
  author: Ulrich Atz
  r_version: ">= 4.1.0"
  targets_version: ">= 1.12.0"
  tarchetypes_version: ">= 0.14.1"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, mcp__r-btw__*, mcp__ide__getDiagnostics
---

# Building Pipelines with targets

A target is a pipeline step that runs R code and caches its result. `tar_make()` hashes each target's code, arguments, and upstream dependencies, then skips anything still up to date.

## Reference files

Consult the appropriate reference file for detailed patterns and examples:

| Topic | Reference file | When to consult |
|-------|----------------|-----------------|
| **Targets** | [targets.md](references/targets.md) | `tar_target()`, formats, file tracking, tarchetypes factories |
| **Branching** | [branching.md](references/branching.md) | Dynamic `map()`/`cross()`, static `tar_map()`, `tar_combine()` |
| **Debugging** | [debugging.md](references/debugging.md) | `tar_workspace()`, `tar_igraph()`, browser(), cycles |
| **Performance** | [performance.md](references/performance.md) | Memory, batching, parallel via crew, cloud + CAS |
| **Literate** | [literate.md](references/literate.md) | Quarto, R Markdown, Typst/LaTeX compilation |
| **Factories** | [factories.md](references/factories.md) | Writing your own target-factory function (not just using tarchetypes' built-in ones) when the same `tar_target()` boilerplate keeps repeating |
| **Auditing** | [audit.md](references/audit.md) | Reviewing an existing pipeline for anti-patterns, untracked outputs, dead code, and performance issues — includes how to read `tarborist` IDE diagnostics if available |

For requests that span multiple topics (e.g. "set up a parallel pipeline that renders a Quarto report"), read several files.

## Core principles

1. **Functions live in `R/`, targets live in `_targets.R`.** Source with `tar_source()`.
2. **Targets return one saveable value and avoid side effects** (unless `format = "file"`).
3. **Track every input file.** Use `tar_file_read()` rather than reading a literal path inside a target.
4. **Prefer tarchetypes factories** (`tar_qs()`, `tar_file()`, `tar_parquet()`) to passing `format = "..."` manually. If the same multi-target boilerplate (e.g. "track a URL, then read it") keeps repeating with no tarchetypes equivalent, write your own factory instead of copy-pasting — see [factories.md](references/factories.md).
5. **Read the NEWS before relying on any behavior** — `targets` ships breaking-ish default changes roughly every minor release.

## Quick reference

### Minimum viable pipeline

```r
library(targets)
library(tarchetypes)

tar_source()
tar_option_set(packages = "tidyverse", format = "qs")

list(
  tar_file_read(raw, "data/raw.csv", read = readr::read_csv(!!.x)),
  tar_target(clean, clean_data(raw)),
  tar_target(model, fit_model(clean)),
  tar_quarto(report, "report.qmd")
)
```

### Directory layout

```
project/
├── _targets.R          # Pipeline (required)
├── _targets.yaml       # Optional config, multi-project support
├── R/                  # Functions sourced by tar_source()
│   ├── clean.R
│   ├── model.R
│   └── report.R
├── data/               # Input data
├── report.qmd          # Literate document
└── _targets/           # Auto-generated store (gitignore _targets/objects/)
    ├── meta/meta       # Metadata; commit this if you want teammates to share skip state
    └── objects/        # Target outputs
```

### Essential commands

| Command | Purpose |
|---------|---------|
| `tar_make()` | Run the pipeline |
| `tar_outdated()` | What will run next? |
| `tar_read(x)` / `tar_load(x)` | Return / attach a target |
| `tar_manifest()` | List targets + commands |
| `tar_visnetwork()` | Interactive dependency graph |
| `tar_igraph()` | Graph object for `igraph::find_cycle()` |
| `tar_validate()` | Check pipeline validity |
| `tar_prune()` | Delete stored targets no longer in pipeline |

`tar_make()`'s progress line reads `260+, 12738-` — 260 targets built this run, 12,738 skipped because they were already up to date. A run that's mostly `-` is `targets` doing its job, not a sign something's wrong.

Multi-project setups: `_targets.yaml` can hold settings (`store`, `script`, etc.) for multiple named projects. `Sys.setenv(TAR_PROJECT = "project_name")` switches which one `tar_make()` and friends use by default — it's a project *name* from the YAML, not a literal file path. `TAR_CONFIG` overrides which YAML file gets read at all (default `_targets.yaml`).

### Running targets safely

Preview before running anything:

```r
tar_manifest()          # list every target and its command
tar_outdated()          # what would rerun
```

Scope `tar_make()` to specific targets instead of rebuilding everything:

```r
tar_make(names = c("clean_data", "model"))
tar_make(names = starts_with("plot_"))        # tidyselect helpers work
tar_make(names = "report", shortcut = TRUE)   # rebuild report only, skip upstream
```

`shortcut = TRUE` rebuilds only the named targets even if upstream is invalidated. Handy for rerunning a downstream report without recomputing expensive ancestors.

Scope invalidation and deletion the same way:

```r
tar_invalidate(names = "model")                 # force rerun, keep stored value
tar_delete(names = c("model", "fit"))           # drop stored value
tar_prune()                                     # drop only stale targets no longer in pipeline
```

Never pass `everything()` to `tar_invalidate()` or `tar_delete()` reflexively. Use a name vector.

Protect expensive targets with a cue that only invalidates on demand:

```r
tar_target(
  slow_model,
  fit_slow(data),
  cue = tar_cue(mode = "never")   # runs only when manually invalidated
)
```

For a toggle you flip instead of remembering to invalidate manually, make the mode conditional on an option or env var:

```r
tar_target(
  slow_model,
  fit_slow(data),
  cue = tar_cue(mode = if (getOption("pipeline.dev_mode", FALSE)) "never" else "thorough")
)
```

Useful when iterating on downstream targets and you don't want an expensive upstream step rerunning on every `tar_make()`.

Avoid `tar_destroy()` when a scoped command will do:

| Goal | Command |
|------|---------|
| Drop one target's stored value | `tar_delete(names = x)` |
| Drop stale targets no longer in pipeline | `tar_prune()` |
| Clear error metadata | `tar_destroy(destroy = "meta_errors")` |
| Clear workspaces | `tar_destroy(destroy = "workspaces")` |
| Clear progress | `tar_destroy(destroy = "meta_progress")` |

`tar_destroy()` prompts interactively by default. Do not pass `ask = FALSE` casually.

### Error strategies

| `error =` | Behavior |
|-----------|----------|
| `"stop"` (default) | Abort the whole pipeline |
| `"continue"` | Keep going; mark failed targets as errored |
| `"null"` | Return `NULL` from failed target, keep going |
| `"abridge"` | Let running targets finish; start no new ones |
| `"trim"` | Let running targets finish; start new ones only on healthy parts of the graph |

### Memory options (targets >= 1.11)

| `memory =` | Behavior |
|------------|----------|
| `"auto"` (default) | Transient, except persistent for non-dynamic targets that feed a `pattern` |
| `"transient"` | Unload after each target completes |
| `"persistent"` | Keep in memory to end of pipeline |

## Best practices

1. **Name targets as nouns** (`clean_data`), **functions as verbs** (`clean_data()`). The collision is fine because one is a value and the other is a callable.
2. **Pass data as function arguments**, never via globals. `targets` hashes function bodies, not the calling environment.
3. **Wrap closures.** `purrr::safely()`, `Vectorize()`, and `Rcpp::cppFunction()` hide code from static analysis; wrap them in named R functions so changes get tracked.
4. **Batch tiny work.** A hundred branches of 100 items beats 10,000 targets.
5. **Keep the store small.** Use `butcher::butcher()` or `lean = TRUE` (fixest) to slim model objects before returning.
6. **Compile external docs last.** Put Typst/LaTeX targets at the tail with `cue = tar_cue(mode = "always")`. Ordering is guaranteed and the skip logic rarely pays off for fast compiles.
7. **Verify before running.** `tar_validate()` + `tar_outdated()` catches most mistakes before you spend CPU time.

## Anti-patterns

| Avoid | Do instead |
|-------|------------|
| Global variables inside a target command | Pass data as function arguments |
| Side effects in regular targets | Use `format = "file"` for outputs |
| `tar_target(..., format = "file")` | `tar_file()` or `tar_file_read()` |
| `tar_target(..., format = "qs")` | `tar_qs()` |
| `tar_target(..., format = "file_fast")` | `tar_file()` (the `"file_fast"` format is deprecated) |
| Setting `memory = "transient"` reflexively | Trust `memory = "auto"` unless profiling says otherwise |
| Setting `priority` | Gone since targets 1.10.1, silently ignored |
| Millions of tiny targets | Batch: 100 branches of 100 items, not 10,000 branches |
| Separate file-tracking target + reading target | `tar_file_read()` (one call) |
| Storing full model objects | `butcher::butcher()`, `lean = TRUE` (fixest), or return only the slice you need |
| `devtools::load_all()` for a local package | `install.packages()` + `imports = "pkg"` |
| Reading a literal file path inside a target | Track the file with `tar_file()` so changes invalidate downstream targets |
| Closures inside `tar_target()` commands | Define named functions in `R/` so targets can hash them |
| Storing a live connection/handle as a target's value (DB connection, API client, pins board object) | Store connection *parameters* and reconnect inside each target that needs it — live resources (sockets, external pointers, auth tokens with short lifetimes) don't survive serialization reliably, and a cached stale connection can fail silently downstream |

## Auditing an existing pipeline

When asked to review, audit, analyze, or improve a pipeline someone already wrote, produce a **findings report** — don't edit files unless the user explicitly asks you to apply fixes. The goal is to give them something they can act on selectively, not a diff they have to accept wholesale.

1. **Start with the structural pass, before anything itemized.** Is the pipeline organized in a way that reflects how the project's author thinks about the work — plans/files grouped by data source, by stage, by output, with branching used where the work is genuinely repeated and avoided where it isn't — or does the grouping look accidental? Is there a consistent scheme for where custom functions and other files live in the repository, and are those functions reasonably scoped (not doing too much, not fed an excessive number of inputs)? Do target and plan names share a vocabulary (e.g. a `read_`/`prep_`/`combine_` prefix convention marking pipeline stage, or `_out`/`_sf`/`_board_out` suffixes marking output shape or destination), and does every name in the file actually follow it? This pass belongs first in the report — it's what tells the user whether the pipeline is fundamentally sound and just needs spot fixes, or needs a reorganization before the itemized fixes are worth doing. See [audit.md](references/audit.md) for the full checklist and the sources behind these criteria.
2. **Read the whole pipeline.** `_targets.R`, everything under `R/` (or wherever `tar_source()` points), and `_targets.yaml` if present. Skim before judging — a pattern that looks wrong in isolation (e.g. a hardcoded path) may be intentional given the project's scale or deployment target.
3. **If `mcp__ide__getDiagnostics` is available, call it — it's free.** The `tarborist` VS Code/Positron extension (activates automatically on any workspace containing `_targets.R`) runs tree-sitter-based static analysis and publishes diagnostics tagged `"source": "tarborist"`: dependency cycles and unresolved target references, no R session required. Treat it as a fast pre-check, not ground truth — see [audit.md](references/audit.md) for how to tell a real finding from one of its known static-analysis blind spots (e.g. dynamic `tar_source()` paths cascade into false "unresolved symbol" warnings for everything defined in the un-resolvable file). If the tool isn't available, skip this step; it's a bonus, not a requirement.
4. **Run live diagnostics if you have R execution available** (an IDE R session, `Rscript -e`, or an MCP R tool). These catch things static reading can't:
   - `tar_manifest()` — every target and its command, useful for spotting duplicated logic
   - `tar_outdated()` — is the store actually in sync with the code, or is something stale
   - `tar_validate()` — catches malformed pipelines before you spend effort analyzing them
   - `tar_igraph()` + `igraph::find_cycle()` — dependency cycles the author may not know about
   If no R session is available, say so and proceed with a static read — don't block the audit on it.
5. **Check against the anti-patterns table above**, then the fuller checklist in [audit.md](references/audit.md) — it covers things that table doesn't: untracked side-effect outputs, dead/commented-out code, external-data freshness policy, error-handling gaps around network calls, and inconsistent storage conventions.
6. **Report findings, structural overview first**, using the template in audit.md: organization/naming/dead-code assessment, then itemized findings ranked by impact — what's wrong, why it matters (not just "this is an anti-pattern" — explain the concrete failure mode), and a specific fix. Group itemized findings by severity, not by file order, so the user can triage.
7. **Don't manufacture findings.** A short, accurate report beats a long one padded with nitpicks. If the pipeline is in good shape, say so plainly.

## Example

```r
library(targets)
library(tarchetypes)

tar_source()
tar_option_set(
  packages = "tidyverse",
  format = "qs",
  controller = crew::crew_controller_local(workers = 4)
)

list(
  tar_file_read(
    raw_data,
    "data/penguins.csv",
    read = readr::read_csv(!!.x, show_col_types = FALSE)
  ),
  tar_target(clean_data, clean_penguins(raw_data)),
  tar_target(species, unique(clean_data$species)),
  tar_target(
    species_model,
    fit_species_model(clean_data, species),
    pattern = map(species),
    iteration = "list"
  ),
  tar_target(
    coefs,
    purrr::map_dfr(species_model, broom::tidy, .id = "species")
  ),
  tar_quarto(report, "report.qmd")
)
```
