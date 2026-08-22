# Auditing an existing pipeline

A checklist for reviewing a `_targets.R` someone already wrote, plus the report template for presenting findings. Pairs with the anti-patterns table in `SKILL.md`, which covers `targets`-API misuse. This file stays scoped to what's specific to `targets`' dependency-tracking model — structure, stage/shape naming vocabulary, branching, storage, dependency shape. For refactoring judgment that applies to any R codebase — general naming and style, dead code, function design, profiling a slow function's internals — use the `r-skills:r-style-guide`, `r-skills:code-review`/`simplify`, and `r-skills:r-performance` skills instead of duplicating that ground here; each section below says so where it applies.

## Checklist

### Structural overview (do this first, and put it first in the report)

Form a judgment about the pipeline as a whole before hunting for individual bugs. This tells the user whether they're looking at a sound pipeline needing spot fixes, or one where itemized fixes aren't worth doing until the structure is sorted out first.

**Purpose.** Confirm you understood the pipeline in a few plain sentences: what feeds it, what it produces, the major stages between — e.g. "reads a dozen spatial layers from ArcGIS REST endpoints, combines them into one administrative-areas table, joins it against DGS asset data, and exports as GeoJSON/Shapefile/Parquet plus a Sharepoint pins board." Cheap to write, and the fastest way for the user to catch a misreading before it colors the rest of the report.

**Organization** — five angles. Background reading beyond the summary below: the [Carpentries targets-workshop organization lesson](https://carpentries-incubator.github.io/targets-workshop/instructor/organization.html) and [Sean Fobbe's "Modeling Data Workflows with targets"](https://seanfobbe.com/posts/2023-11-12_modeling-data-workflows-with-targets/).

- *Pipeline structure.* Do plans/files group targets the way the author actually thinks about the work — by data source, stage, output — or did the grouping accrete without one? Check for dangling targets and whether the dependency graph reads as a legible story. See "Dependency simplification" below for unnecessary coupling.
- *Naming.* Part of the same structural judgment, not a separate axis — names are how structure gets communicated before a reader traces the graph. Look for stage prefixes (`read_*`/`prep_*`/`combine_*`) and shape/destination suffixes (`_sf`/`_out`/`_board_out`/`_dict`), then flag targets that break the pattern. `r-skills:r-style-guide` covers general naming quality (`tmp`, `data2`, and the like) — worth flagging too, but that judgment isn't targets-specific.
- *Branching.* `pattern = map()`/`cross()`/`tar_map()` used where work is genuinely repeated, avoided where it isn't. Internal parallelism inside one target (`crew`/`future`) often beats fragmenting a bottleneck into many branches. See "Batching opportunities" below for missed branching specifically.
- *File organization.* A deliberate, consistently-applied scheme for where code lives — `R/`, sub-pipeline directories, `_targets.R` itself staying focused on pipeline definition rather than accumulating helper logic.
- *Function scoping.* Targets backed by reasonably-scoped functions; argument count is a rough proxy (roughly three inputs is a sane ceiling). General function-design judgment belongs to `r-skills:r-style-guide`; what's targets-specific is that scope also sets *rebuild granularity* — an oversized target reruns unrelated, possibly expensive work whenever any one part of it changes.

### Reading tarborist diagnostics (if available)

`mcp__ide__getDiagnostics` entries tagged `"source": "tarborist"` come from tree-sitter static analysis and check exactly two things: dependency cycles and unresolved target references. Known blind spot: it resolves `tar_source()` by reading a literal string argument, so an expression argument (`tar_source(fs::path("_tar_components"))`, `tar_source(here::here("R"))`) makes it report every symbol from that file as "unresolved" even though the pipeline runs fine. Tell: a `Could not statically resolve tar_source() path expression` diagnostic followed by a cluster of unresolved-symbol warnings for names plausibly from that file — verify by grepping the sourced directory before reporting any as real. Cycle diagnostics don't share this failure mode.

tarborist also has editor-only features unavailable from a terminal session — a dependency heatmap (descendant count, output size, runtime) and "Organize Pipeline by DAG." Worth suggesting the user check these themselves in Positron/VS Code; don't claim to have seen them.

### Untracked side effects

The most common real bug: a target calls `sf::write_sf()`/`arrow::write_parquet()`/`openxlsx2::wb_save()` directly, without `format = "file"` and without returning the path:

```r
tar_target(
  report_out,
  sf::write_sf(data, "output.gpkg")   # returns `data` invisibly, not a path
)
```

`targets` can't hash the output, can't detect out-of-pipeline edits or deletions, and `tar_outdated()` won't flag it stale. Fix: `format = "file"` and return the path, or a tarchetypes factory (`tar_file()`) that already does this. If several targets repeat the write-then-return-invisibly shape, that's a signal for one shared wrapper function, not N individual fixes.

### Output path conventions

Inconsistency — some targets write to `files/`, others to the working directory root; some derive the filename from a variable, others hardcode it — usually means the convention changed mid-project with no reconciliation pass. Name it as one finding, not N.

### Dead and commented-out code

Large commented-out `tar_target()` blocks, superseded-filename comments, `FIXME`/`TODO`s that don't match the surrounding code. A little is normal in active development; a lot is a maintenance-debt signal worth one combined finding rather than per-block flags. General dead-code judgment for ordinary R code belongs to `r-skills:code-review`/`simplify`; what's targets-specific is dead *functions* in `R/`, which don't error at runtime because `tar_source()` loads the file regardless of whether anything calls what's in it:

```bash
bash <skill-path>/scripts/find_unused_functions.sh R .
```

A plain-text heuristic, not a parser — misfires on `do.call()`/`get()` dispatch, S3 methods, or intentionally-kept exports. Treat a hit as "worth asking about," and check `git log -p -- R/` before assuming dead rather than just renamed.

### External-data freshness

Targets reading Google Sheets/Airtable/ArcGIS REST/other live sources with no cue policy only rerun when their *code* changes, so the pipeline can silently serve stale external data indefinitely. `tar_cue(mode = "always")` for cheap reads, `tar_age()` for time-based invalidation — but `mode = "never"` plus a documented manual-refresh step is a legitimate choice for expensive or rate-limited sources, so ask rather than assume.

### Error handling around network calls

Multiple external APIs under the default `error = "stop"` means one flaky endpoint aborts unrelated downstream work too. Check whether `error = "trim"` or per-target `error = "continue"` on the network-dependent targets would let the rest finish — see "Recovering from transient errors" in [debugging.md](debugging.md). A suggestion, not a default: some pipelines genuinely want to halt on any missing input.

### Live resources stored as target values

A target returning a connection, client, or handle rather than data — especially one downstream targets reuse as an argument — often *works* interactively but doesn't reliably survive `targets`' serialize-and-reload cycle, and a cached connection can be stale by the time a consumer uses it. Fix: store connection parameters, reconnect inside each consumer (see "Function design" in [targets.md](targets.md)). Raise it even when a code comment shows the author already knows the tradeoff — as a confirming note, not a rediscovered bug.

### API idiom mixing

Mixing `tar_target(name, command)` and `tar_plan()`'s `name = command` shorthand is fine — both are valid. Flag it only if the mixing looks accidental rather than stylistic: one form for 90% of targets, the other for a lone unexplained outlier.

### Inline command logic

A `command` reads best as a single function call. A multi-line block instead — several assignments, a long inline pipe — can't be unit-tested alone, can't be reused, and obscures the pipeline's shape when scanning `_targets.R`. The general "extract a function" judgment belongs to `r-skills:code-review`/`simplify`; what's targets-specific is why it's worth doing *here*: tarborist and `tar_test()` can only act on named functions, and this is the same fix as the closures anti-pattern in `SKILL.md`'s table, just triggered by inline complexity instead of an unnamed closure. Skip genuinely short glue code — one `|>` step, a one-line `if`.

### Target descriptions

`description = "..."` (a `tar_target()` argument, or a `tar_option_set()` default) is free metadata surfaced in `tar_manifest()`, `tar_visnetwork()` tooltips, and tarborist's heatmap. Suggest it where a target's purpose isn't obvious from name and command alone; skip it as a blanket rule on a small, clearly-named pipeline — that's padding, not documentation.

### Custom target factories

An `R/` function calling `tar_target_raw()` and returning a list of targets is a custom factory — check it against [factories.md](factories.md), including its note on `tar_*`-prefixed functions that look like factories but aren't. Cross-reference usage like the dead-code check above: used pervasively is a good sign, never called anywhere is dead code wearing an infrastructure shape.

### Batching opportunities

Near-identical `tar_target()` calls differing only in a filter condition, source URL, or column selection are a branching (`pattern = map(...)`) candidate — not reflexively; heterogeneous transformations are often clearer written out explicitly. Recommend it when the repeated targets genuinely do the same operation over different inputs.

### Dependency simplification

Unnecessary coupling in the dependency graph — distinct from batching above, which is about *repeated* work, not *unnecessary* structure:

- **Pass-through targets** that only rename, coerce, or lightly reformat a single upstream dependency, with nothing downstream needing that intermediate form on its own.
- **Over-broad dependencies** — a target consuming a whole upstream object for one column or element. If several consumers each pull the same narrow slice, compute it once instead, so unrelated upstream changes stop invalidating every consumer.
- **Chains that could flatten** — single-purpose targets that always run together, are never read individually, and don't correspond to a real caching or inspection checkpoint.

A judgment call, like "Function scoping" above — a pass-through target that shields a slow upstream step from downstream churn is earning its keep, not adding clutter. Recommend simplification when the extra nodes cost readability without buying caching, testability, or reuse in return.

### Storage format tuning

Big `sf`/data-frame targets on the default `rds` format instead of `qs` or a parquet-based factory. Check `tar_option_set()` for a project-wide `format` first — the fix is usually one line, not N.

### Runtime performance (only with the user's permission to run the pipeline)

Everything above is a static read plus read-only diagnostics (`tar_manifest()`, `tar_outdated()`, `tar_validate()`, `tar_igraph()`) — none execute a target's code. Measuring actual runtime or storage needs a real run, which has real consequences: network calls, file writes, cloud/pins-board uploads, wall-clock time. **Ask before running it, every time** — an audit request isn't standing permission. If declined, say in the report that performance was assessed statically only.

If permitted, every target that has run at least once already has profiling data — `seconds`/`bytes` persist across skips:

```r
meta <- tar_meta(fields = c(name, seconds, bytes, warnings, error))
meta[order(-meta$seconds), c("name", "seconds")]   # slowest first
meta[order(-meta$bytes), c("name", "bytes")]        # largest first
```

`tar_make()` first (still with permission) if the store is empty or mostly unbuilt. See "Profiling with tar_meta()" in [performance.md](performance.md). This identifies *which target* is slow; for profiling *why* a specific function is slow — line-level, `profvis`/`bench` — that's `r-skills:r-performance`, not this checklist.

Fold the numbers into findings already made rather than reporting a separate pass: a slow, unbatched target turns "Batching opportunities" from a guess into a measurement; a large `bytes` value on `rds` confirms "Storage format tuning"; a slow external-source target with no cue policy confirms "External-data freshness." Non-empty `warnings`/`error` are worth surfacing regardless, since they're free once pulled. A cited number ("`dgs_asset_list_file` took 340s, 220MB `rds`") is far more actionable than a structural guess — but never manufacture one by running the pipeline without asking first.

## Report template

```markdown
## Pipeline audit: <path to _targets.R>

<one-sentence overall assessment>

### Structural overview

**Purpose:** <inputs, outputs, and major stages, in a few plain sentences — confirms the pipeline was understood correctly before judging it>

**Organization**
- Pipeline structure: <is the grouping into plans/files coherent, or accidental — any dangling or oddly-connected targets>
- Naming: <the vocabulary you found (prefixes/suffixes), which targets break it or are simply unclear>
- Branching: <used where it fits, avoided where it doesn't — or "n/a, no repeated homogeneous work to branch over">
- File layout: <is there a consistent scheme for where code/data live, and is _targets.R itself kept focused>
- Function scoping: <are target-backing functions reasonably sized/argument-counted, or doing too much>

### High impact

**<short title>** — <target name(s) or file:line>
<what's wrong, and the concrete failure mode it causes — not just "this is an anti-pattern">
Fix: <specific, actionable>

### Medium impact

...same shape...

### Low impact / style

...same shape...

### What's working well
<brief — skip if nothing stands out, but don't omit this section only to pad the findings above>
```

Rank by consequence, not by instance count — one untracked-output bug that silently serves stale data outranks ten stylistic inconsistencies. Cite target names or `file:line`, not vague references like "several targets."
