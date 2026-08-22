# Writing a custom target factory

Everything else in this skill is about *using* tarchetypes factories (`tar_qs()`, `tar_file_read()`, `tar_url_read()`-in-tarchetypes, etc.) — functions that take simple inputs and expand into one or more `tar_target()` calls. This file is about *writing your own*, which is worth doing once you notice the same `tar_target()` boilerplate repeated across a pipeline (several near-identical URL-tracking-plus-read pairs, several file-plus-parse pairs) rather than copy-pasting it again.

Sourced from Will Landau's [R Targetopia contributing guide](https://wlandau.github.io/targetopia/contributing.html#target-factories) — that page is written for people contributing packages to the Targetopia ecosystem, but the design principles apply just as well to a one-off factory living in a project's own `R/` directory.

## What a target factory is

A function that accepts simple, domain-specific inputs, calls `tar_target_raw()` (not `tar_target()` — the raw version takes a pre-built expression rather than doing its own non-standard evaluation, which is what lets a factory construct commands programmatically), and returns a **list of target objects**. The point is to hide low-level pipeline configuration behind an interface that matches how the user actually thinks about the problem — "read this URL and parse it as JSON," not "build a `tar_target_raw()` call with these fourteen arguments."

## Design principles

**Expose what users legitimately need to control, not pipeline internals.** Arguments like `priority`, `cue`, `error`, `memory` are reasonable to expose since different call sites genuinely want different values. Arguments like `command`, `pattern`, `deps`, or `string` should not be user-facing — those are `tar_target_raw()`'s own low-level machinery, and exposing them defeats the point of having a friendlier interface on top.

**Default exposed arguments from `tar_option_get()`**, not from a hardcoded literal, so a factory-built target respects whatever the pipeline set globally with `tar_option_set()` unless the caller overrides it locally:

```r
my_factory <- function(
  name,
  command,
  error = targets::tar_option_get("error"),
  memory = targets::tar_option_get("memory"),
  cue = targets::tar_option_get("cue")
) {
  ...
}
```

**Bake in smart, situational defaults** the factory's whole reason for existing is to encode — e.g. `deployment = "main"` for a factory that always reads local files (it cannot run on a remote worker), `format = "file"` for one that tracks an input path, a specific serialization format matched to what the factory always produces.

**Return a list of `tar_target_raw()` calls**, even when the factory only builds one target — keeps the calling convention uniform, and lets a factory grow from one target to several (e.g. "track the URL" plus "read what it points to") without changing its call sites. Users should be able to end `_targets.R` with a single factory call (or a few) producing the pipeline's full target list, while still being free to add ordinary `tar_target()` calls downstream for anything the factory doesn't cover.

## Metaprogramming mechanics

Building a factory means capturing the caller's *expression* rather than evaluating their arguments immediately — that's what lets `command` in a factory call look like ordinary R code (including `!!` tidy-eval placeholders) instead of a quoted string. The core tools:

- `substitute()` — captures the argument as an unevaluated expression.
- `targets::tar_tidy_eval()` — resolves `!!`/`!!!` placeholders inside that expression against a supplied environment, mirroring how `tar_target()` itself handles tidy evaluation.
- `deparse()` — turns an expression into a string, useful for building target names from unquoted symbols.
- `tarchetypes::tar_sub()` / `tarchetypes::tar_eval()` — higher-level helpers for the kind of substitution `tar_map()`-style static branching needs internally.

## Branching inside a factory

**Static branching**: build it with `tar_map()`/`tar_combine_raw()` internally, but keep the *caller's* inputs simple — e.g. the factory takes a character vector of model names, and internally calls `tar_map()` to expand that into one target per model. The caller never writes `tar_map()` themselves.

**Dynamic branching**: the factory can construct the `pattern` argument itself via metaprogramming, but users should control things like batch count or reps-per-batch — not be handed the ability to set `pattern` directly. If they need that level of control, they should be writing `tar_target()` themselves instead of using the factory.

## Testing a factory

- `tar_test()` (from `targets`, not plain `testthat::test_that()`) — runs the test in a temporary directory so it doesn't leave `_targets/` artifacts or mutate global options behind.
- Validate results end-to-end: `tar_script()` to write a throwaway pipeline using the factory, `tar_make()` to run it, `tar_read()` to check the output.
- Validate structure without running anything: `tar_manifest()` for target count/commands/settings, `tar_network()` for whether dependencies came out connected the way you expect.
- `callr_function = NULL` speeds up `tar_make()` in tests by skipping the subprocess — but then the test runs in the same process as everything else, so it's more sensitive to whatever's already in that environment.
- Mark slow tests `testthat::skip_on_cran()` if the factory ships in a package with CRAN's check-time budget in mind.

## Recognizing one while auditing

A pipeline can have custom factories in its own `R/` without the author ever calling them that — watch for a function that calls `tar_target_raw()` (directly or via `tar_target()`) and returns a list of target objects, typically named with a `tar_*` prefix by convention. Two things worth checking once you've spotted one:

- Does it actually behave like a factory — return target objects, get called at the top level of a plan — or does the `tar_*` name just look like one while it's actually an ordinary helper function? A `tar_*`-prefixed function that isn't a factory is a small but real instance of the naming-vocabulary problem covered in [audit.md](audit.md): the name promises something the function doesn't deliver.
- If it is a real factory and used pervasively, that's a good sign — it means repeated boilerplate got consolidated instead of copy-pasted. If a near-identical factory exists but is never called anywhere in the pipeline, treat it like any other dead code (see audit.md's dead-code section) rather than assuming it's load-bearing just because it looks like infrastructure.
