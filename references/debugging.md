# Debugging targets pipelines

Pipelines run in isolated `callr` R processes, so the usual `browser()` tricks need some setup.

## Inspect what failed

```r
tar_errored()                                  # names of errored targets
tar_meta(fields = error,    complete_only = TRUE)  # error messages
tar_meta(fields = warnings, complete_only = TRUE)  # warnings
tar_traceback(target_name)                     # full traceback
tar_load_everything()                          # load every stored target into the global env for quick poking-around
```

## Reproduce the failure interactively

### Method 1. Load the saved workspace

After a failure, `targets` saves a workspace for the errored target:

```r
tar_workspace(target_name)
# Dependencies are now loaded in the global env.
# Run the body of the failing target directly.
```

Force workspace saving for every errored target:

```r
tar_option_set(workspace_on_error = TRUE)
```

List available workspaces:

```r
tar_workspaces()
```

### Method 2. Rebuild manually

Restart R first, then:

```r
tar_load_globals()
tar_load(upstream_dep)
my_function(upstream_dep)
```

### Method 3. Drop the callr wrapper

For `browser()` to work, run in the current R session:

```r
tar_make(callr_function = NULL, use_crew = FALSE, as_job = FALSE)
```

## Breakpoints

Insert `browser()` in your function, then:

```r
tar_make(callr_function = NULL)
```

## Targeted debug mode

Only debug one target:

```r
tar_option_set(
  debug = "problem_target",
  cue   = tar_cue(mode = "never")
)

tar_make(callr_function = NULL)
```

## Cycle detection

When `tar_make()` complains about a cycle, `tar_igraph()` + `igraph::find_cycle()` names the culprits (targets >= 1.12, igraph >= 2.2):

```r
igraph::find_cycle(tar_igraph())
# Returns the sequence of target/function names in the cycle.
```

## Error-handling strategies

| `error =` | When to use |
|-----------|-------------|
| `"stop"` | Development, strict pipelines |
| `"continue"` | Report-style pipelines where you want all partial results |
| `"null"` | Dependent targets should receive `NULL` instead of failing |
| `"abridge"` | Graceful shutdown with one global error |
| `"trim"` | Long pipelines where unrelated branches should keep going |

`error = "trim"` (new in 1.10) is usually what you want for multi-branch pipelines: currently running targets finish, and queued targets still run as long as they are not downstream of the error and not sibling branches of the failed dynamic target.

### Recovering from transient errors (flaky network calls, rate limits)

Pipelines with many `tar_url_read()`/API-backed targets will occasionally hit a timeout or a rate limit that isn't a real bug — it's just a bad moment to ask that endpoint for data. Treat these as expected, not exceptional:

1. Set `error = "continue"` (globally via `tar_option_set()`, or per-target on the network-dependent ones) so one flaky call doesn't abort work that has nothing to do with it.
2. Run `tar_make()`. Targets that hit a transient failure are marked errored; everything else completes.
3. Run `tar_make()` again. `targets` only reruns what's still outdated — i.e. the targets that errored — so this is a cheap retry, not a full rebuild. If the failures were genuinely transient, this second pass usually finishes them.
4. If a target keeps failing across retries, reduce parallelism for that section of the pipeline (fewer `crew` workers hitting the same endpoint at once) before assuming it's a code bug.

### Custom error handling inside a target

```r
tar_target(
  risky,
  tryCatch(
    risky_operation(data),
    error = function(e) {
      warning("failed: ", conditionMessage(e))
      NULL
    }
  )
)
```

## Verify before running

```r
tar_validate()                     # static check
tar_outdated()                     # what will run?
tar_visnetwork()                   # dependency graph (browser)
tar_manifest() |> select(name, command)
tar_deps(my_function)              # what this function depends on
```

## Common problems

### "Target not found"

- Spelling mismatch in `tar_target()`.
- Target not in the final list returned by `_targets.R`.
- `tar_validate()` catches both.

### "I changed a function and nothing reran"

- The change was inside a closure that `targets` cannot inspect. Wrap it in a named function in `R/`.
- The function is namespaced (`pkg::fn()`) but `imports = "pkg"` is not set.
- You edited a file that `tar_source()` is not reading. Check `list.files("R", recursive = TRUE)`.

### "Hash changed for no reason"

- `ggplot2::theme_set()` or other global state mutated inside a target.
- A dependency package upgraded and its function body changed.
- Non-deterministic RNG. Targets seeds are reproducible; user RNG inside `tar_target()` must use a fixed seed for reproducibility.

### Changes in a package not detected

```r
tar_option_set(
  packages = "mypackage",
  imports  = "mypackage"   # track function bodies in mypackage
)
```

### Stale metadata after package upgrade

```r
tar_invalidate(target_name)
tar_make()

# or for a clean slate
tar_delete(target_name)
```

### "Pipeline hangs on a parallel worker"

- `storage = "worker"` plus a network file system with slow stat calls blocks the main process. Try `storage = "main"` for fragile storage backends.
- A `format = "file"` target returned a path that does not exist yet because the write happened on a worker with eventual consistency. Write synchronously.

### "Workers cannot find packages"

Each worker loads the packages listed in `tar_option_get("packages")`. If a worker has a different library path than the host, pass `library = .libPaths()` in `tar_option_set()` or set `R_LIBS_USER` in the worker environment.

### "Timestamps not trusted"

If you see `trust_object_timestamps` in your config, replace it with `trust_timestamps` (targets 1.10). Leave it unset unless you are on a file system with 2-second timestamp precision.
