# Performance, storage, and scaling

## Memory strategy

Defaults changed in targets 1.11. The old "always set `memory = "transient"`" advice is no longer needed.

```r
tar_option_set(
  memory    = "auto",      # default since 1.11
  retrieval = "auto",      # default since 1.11
  storage   = "worker"     # default
)
```

### What `memory = "auto"` does

- Treats most targets as **transient** (unload after use).
- Treats **non-dynamic targets that feed a `pattern`** as **persistent**, to avoid rereading the same upstream object once per branch.

You rarely need to override this. Set `memory = "persistent"` explicitly only when you know a value will be consumed many times in a tight loop that `targets` cannot see.

### `retrieval = "auto"` does the same thing for workers

Dynamic branches reading a non-dynamic upstream target load the value on `"main"` once, then hand it to workers. Otherwise workers load their own dependencies.

## Garbage collection

Default is `garbage_collection = 0` (off). Set to a positive integer to run `base::gc()` every *n* targets in each R process:

```r
tar_option_set(garbage_collection = 20)
```

## Keep the store small

Large model objects dominate target stores. Strategies:

- `feols(..., lean = TRUE)` (fixest) — drops fitted values and residuals.
- `butcher::butcher(model)` — strips model guts that are not needed for prediction.
- Return only the slice you need (coefficients, predictions, tidy tibble).
- `tar_prune()` after refactors — deletes stored objects no longer in the pipeline.
- `tar_delete(x)` — remove one target's stored value.
- `tar_destroy()` — nuke `_targets/` entirely (prompt before running).

## Parallel execution via crew

```r
tar_option_set(
  controller = crew::crew_controller_local(workers = 4)
)
tar_make()
```

`crew` auto-scales workers and integrates with `memory = "auto"` / `retrieval = "auto"`. For HPC, swap in `crew.cluster::crew_controller_slurm()` or similar.

## Scheduling: `priority` is gone

`priority` was deprecated on 2025-04-08 (targets 1.10.1). The new scheduling algorithm is 10x faster on dynamic pipelines but does not respect priorities. Do not set `priority` in new code — it is silently ignored.

## Cloud storage

Store target objects on S3 or GCS:

```r
tar_option_set(
  repository = "aws",
  resources  = tar_resources(
    aws = tar_resources_aws(bucket = "my-bucket", prefix = "targets")
  )
)
```

Since targets 1.11:

- `format = "file"` targets with a cloud `repository` **keep the local file** after running. Earlier versions deleted it.
- `repository_meta` defaults to `"local"`, so metadata stays on your machine unless you opt in.
- `tar_workspace_download()` fetches workspaces saved in the cloud for post-hoc debugging.

## Content-addressable storage (CAS)

Added in 1.10. Good for deduplication and for sharing caches across machines:

```r
cas <- tar_repository_cas_local("~/targets-cas")
tar_option_set(repository = cas)

# Periodic cleanup of unreferenced objects
tar_repository_cas_local_gc("~/targets-cas")
```

Define custom backends with `tar_repository_cas(upload, download, exists, list, cost)`.

## When the store is the bottleneck

- Use `format = "qs"` (or `tar_qs()`) instead of `rds`.
- Use `tar_parquet()` / `tar_nanoparquet()` for large data frames.
- Use `"file_fast"` replacement: just `tar_file()` — it picks the fastest timestamp check for your file system automatically.
- Increase batch size so each target does more work (lowers per-target overhead).

## Reporters

targets 1.11.4 made the **terse** reporter the default in non-interactive sessions. In interactive sessions the **balanced** reporter (progress bar + per-target messages) is the default. Override:

```r
tar_make(reporter = "verbose")  # terse | balanced | verbose | summary | null | forecast
```

## Performance checklist

- `tar_option_set(format = "qs")`.
- `tar_option_set(error = "trim")` for long pipelines.
- Batch small computations.
- Slim models before returning them.
- `tar_prune()` after refactors.
- Run `tar_outdated()` before `tar_make()` to spot surprises.
