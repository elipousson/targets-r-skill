# Auditing an existing pipeline

A checklist for reviewing a `_targets.R` someone already wrote, plus the report template to use when presenting findings. Pair this with the anti-patterns table in `SKILL.md` — that table covers `targets`-API misuse; this file covers everything else that makes a pipeline hard to trust or maintain.

## Checklist

### Structural overview (do this first, and put it first in the report)

Before looking for individual bugs, form a judgment about the pipeline as a whole. This section of the report is often more useful to the user than the itemized findings below it — it tells them whether they're looking at a fundamentally sound pipeline that needs spot fixes, or one where the itemized fixes aren't worth doing until the structure is sorted out.

**Organization** covers four things — pipeline structure, branching, file layout, and function scoping. Background reading, if you want more depth than the summary below: the [Carpentries targets-workshop organization lesson](https://carpentries-incubator.github.io/targets-workshop/instructor/organization.html) and [Sean Fobbe's "Modeling Data Workflows with targets"](https://seanfobbe.com/posts/2023-11-12_modeling-data-workflows-with-targets/).

- *Pipeline structure.* Do the plans (`tar_plan()` objects) and source files group targets the way the project's author actually thinks about the work — by data source, by pipeline stage, by output — or does the grouping look like it accreted over time without a plan? A single sprawling file mixing unrelated concerns (data ingestion, transformation, and export all interleaved) is a different finding than "well-organized but one section drifted." Sanity-check for dangling targets and whether every target is connected to the upstream/downstream targets it conceptually belongs with — a good pipeline's dependency graph should read as a legible story, not a tangle.
- *Branching.* Is `pattern = map()`/`cross()` (or static `tar_map()`) used where the pipeline has genuinely repeated, homogeneous work — and, just as importantly, *avoided* where it would hurt more than help? A single target containing explicit internal parallelism (e.g. a `crew`/`future` call over a heavy bottleneck step) is often the right call over fragmenting that bottleneck into many branches, since excess branches add scheduling overhead and can make the workflow diagram harder to read for little benefit. See "Batching opportunities" below for how to spot *missed* branching opportunities specifically.
- *File organization.* Is there a deliberate, consistent scheme for where code lives — custom functions under `R/` (whether that's one file per function or a couple of grouped files like `R/functions.R` / `R/packages.R`), sub-pipeline definitions sourced from a clearly-named directory, miscellaneous non-target files kept out of the main `_targets.R`? The specific convention matters less than whether it's applied consistently and `_targets.R` stays focused on defining the pipeline rather than accumulating helper logic inline.
- *Function scoping.* Custom functions back every target, and their argument count is a decent proxy for whether a target is doing too much. A rule of thumb worth citing: no more than about three inputs per target — fewer and you're often better off inlining, many more and the target becomes fragile and hard to reason about. But argument count isn't the only lens: it's also reasonable to split a target when it's long-running and only part of it is failure-prone, when part of it changes often during development, when a sub-result needs frequent standalone inspection, or when a piece of logic is generic enough to be reused elsewhere — and reasonable to merge targets when none of those apply and the split just adds bookkeeping overhead.

**Naming vocabulary.** Look for prefix/suffix conventions and check whether they're actually followed consistently:
- Stage prefixes on plan names: `read_*` for ingestion, `prep_*` for transformation, `combine_*` for joins/merges, or whatever vocabulary this project has settled on.
- Shape/destination suffixes on target names: `_sf` for spatial objects, `_out` for a file-writing target, `_board_out` for a pins-board upload, `_list` for a list-column or list-of-frames intermediate, `_dict`/`_xwalk` for reference/crosswalk data.
- Once you've identified the vocabulary from the majority pattern, flag the targets that break it — not because deviation is inherently wrong, but because an inconsistent name is a small tax on every future reader trying to guess what a target holds without reading its command.

### Reading tarborist diagnostics (if available)

If `mcp__ide__getDiagnostics` returns entries with `"source": "tarborist"`, that's the `tarborist` extension's tree-sitter static analysis of the pipeline — it only checks two things: **dependency cycles** and **unresolved target references**. Both are worth surfacing as findings when real. But it has a specific, predictable blind spot: it resolves `tar_source()` calls by reading the literal string argument. When the argument is an expression instead — `tar_source(fs::path("_tar_components"))`, `tar_source(here::here("R"))`, anything built at runtime — tarborist can't see what's in that file, and it will report every plan or function defined there as an "unresolved symbol" everywhere it's later used, even though the pipeline runs fine.

The tell: an early diagnostic reading `Could not statically resolve tar_source() path expression` at the `tar_source()` call site, followed by a cluster of `unresolved symbol` warnings for names that plausibly come from that source file. Don't report those cascading warnings as pipeline bugs — verify by grepping the sourced directory for the symbol name (or just checking the final pipeline runs) before treating any "unresolved symbol" as real. Cycle diagnostics don't have this failure mode and can be trusted directly.

tarborist also has editor-only features this skill can't query from a terminal session — a target dependency heatmap (by descendant count, output size, or runtime, sourced from live `_targets/meta/meta` data) and a "Refresh Pipeline Index" / "Organize Pipeline by DAG" command. If the user has the pipeline open in Positron or VS Code, it's worth suggesting they glance at the heatmap themselves for a size/runtime hotspot check you can't do from diagnostics alone — but don't claim to have seen it.

### Untracked side effects

The single most common real-world bug: a target calls `sf::write_sf()`, `arrow::write_parquet()`, `openxlsx2::wb_save()`, or similar directly, without `format = "file"` and without returning the output path.

```r
# Looks fine, silently isn't:
tar_target(
  report_out,
  sf::write_sf(data, "output.gpkg")   # returns `data` invisibly, not a path
)
```

Consequences: `targets` can't hash the output, can't detect if someone deletes or edits `output.gpkg` outside the pipeline, and `tar_outdated()` won't flag it as stale. Fix: `format = "file"` and return the path, or use a tarchetypes factory (`tar_file()`) that does this for you. If several targets in the pipeline all write-then-return-invisibly the same way, that's a strong signal to write one small wrapper function that writes the file and returns its path, rather than repeating the fix at every call site.

### Output path conventions

Look for inconsistency: some targets write to a `files/` subdirectory, others to the working directory root; some derive the filename from a variable, others hardcode it twice (once in the target, once in a comment). Inconsistency here usually means someone changed the convention partway through the project and didn't do a pass to reconcile old targets — worth naming as one finding rather than N separate ones.

### Dead and commented-out code

Large commented-out `tar_target()` blocks, alternate versions of a filename left as comments above the active one, `# FIXME` / `# TODO` comments that reference problems the surrounding code doesn't actually fix. A little of this is normal in active development; a lot of it is a maintenance-debt signal worth calling out as a single "clean up accumulated dead code" finding with a list of locations, rather than flagging each block individually.

Also check for dead functions in `R/` — defined but never called, easy to miss because nothing fails at runtime (`tar_source()` loads the file, the unused function just sits there). Run the bundled script rather than eyeballing it:

```bash
bash <skill-path>/scripts/find_unused_functions.sh R .
```

It flags functions whose name appears nowhere else in the project's `.R`/`.Rmd`/`.qmd` files. This is a plain-text heuristic, not a parser — it will misfire on functions called via `do.call()`/`get()`, S3 methods dispatched by naming convention, or functions kept intentionally for external/future use. Treat every hit as "worth asking about," not "definitely delete." Cross-check anything surprising against recent git history — a function that was just superseded by a renamed replacement (`git log -p -- R/`) is a much stronger signal than one that's simply unreferenced with no clear explanation.

### External-data freshness

Targets that call out to Google Sheets, Airtable, ArcGIS REST services, or other live external sources with no cue policy: by default they only rerun when their code changes, which means the pipeline can silently serve stale external data indefinitely. Ask whether that's intentional. If not, point at `tar_cue(mode = "always")` for cheap external reads, or `tar_age()` for time-based invalidation — but don't recommend either reflexively; `mode = "never"` combined with a documented manual-refresh step is a legitimate choice for expensive or rate-limited sources.

### Error handling around network calls

Pipelines that read from multiple external APIs (ArcGIS, Airtable, SharePoint, Google Sheets) with the default `error = "stop"` mean one flaky endpoint aborts the entire run, including unrelated downstream work that had nothing to do with the failing target. Check whether `error = "trim"` or per-target `error = "continue"` on the network-dependent targets would let the rest of the pipeline finish. This is a suggestion, not a default recommendation — some pipelines genuinely want to halt on any missing input.

### Naming and organization consistency

Mixing `tar_target(name, command)` and `tar_plan()`'s implicit `name = command` shorthand is fine (both are valid `tarchetypes` idioms) — don't flag it as a bug. Do flag it if the mixing looks accidental rather than stylistic, e.g. one form used for 90% of targets and the other for a lone outlier with no apparent reason.

### Batching opportunities

Many near-identical `tar_target()` calls that differ only in a filter condition, a source URL, or a column selection are a candidate for dynamic branching (`pattern = map(...)`). Don't recommend this reflexively — heterogeneous transformations (different renames, different joins per item) are often clearer written out explicitly than forced into a branching pattern. Recommend it when the repeated targets are genuinely doing the same operation over different inputs.

### Storage format tuning

Big `sf`/data-frame targets stored with the default format (`rds`) instead of `qs` or a parquet-based tarchetypes factory. Check `tar_option_set()` for a project-wide `format` before flagging individual targets — the fix is usually one line at the top, not N edits.

## Report template

```markdown
## Pipeline audit: <path to _targets.R>

<one-sentence overall assessment>

### Structural overview

**Organization**
- Pipeline structure: <is the grouping into plans/files coherent, or accidental — any dangling or oddly-connected targets>
- Branching: <used where it fits, avoided where it doesn't — or "n/a, no repeated homogeneous work to branch over">
- File layout: <is there a consistent scheme for where code/data live, and is _targets.R itself kept focused>
- Function scoping: <are target-backing functions reasonably sized/argument-counted, or doing too much>

**Naming:** <the vocabulary you found (prefixes/suffixes), and which targets break it>

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

Rank by consequence, not by how many instances exist — one untracked-output bug that silently serves stale data outranks ten stylistic inconsistencies. Cite target names or `file:line`, not vague references like "several targets."
