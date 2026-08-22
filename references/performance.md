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

The one case worth setting `memory = "transient"` explicitly: a target that feeds a `pattern` (so `"auto"` keeps it persistent by default) is itself large enough to cause memory pressure. Forcing it transient trades a reread cost per branch for lower peak memory — worth it when the object is big and branches don't all need it loaded simultaneously.

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

**Format and repository are separate settings — don't combine them in one string.** Older code sometimes has `format = "aws_qs"`; that combined form is deprecated. Set them independently: `format = "qs", repository = "aws"`. This split is what lets you change *where* something is stored without changing *how* it's serialized.

**`format = "file"` needs a real local path.** It checks the path with `file.exists()`, which only understands the local filesystem — a GDAL virtual path like `/vsis3/bucket/key` will not work as a `format = "file"` target's return value, even though R functions that read it (e.g. via `sf`/`terra`) may happily accept that string. If a target's whole job is to produce something that only exists in cloud storage under a virtual path, a common workaround: write directly to the cloud, query the cloud for a content hash (e.g. S3 ETag), and store a small local marker file containing the remote path + hash as the `format = "file"` target's return value. `targets` then tracks changes to the marker (and therefore to the remote object) without needing the remote path itself to satisfy `file.exists()`.

For monitoring whether cloud-stored data changed *outside* the pipeline's control, a separate lightweight pipeline that re-queries current ETags and diffs them against what's stored in metadata is a reasonable pattern — a manual audit step distinct from the main build.

## Content-addressable storage (CAS)

Added in 1.10. Good for deduplication and for sharing caches across machines:

```r
cas <- tar_repository_cas_local("~/targets-cas")
tar_option_set(repository = cas)

# Periodic cleanup of unreferenced objects
tar_repository_cas_local_gc("~/targets-cas")
```

Define custom backends with `tar_repository_cas(upload, download, exists, list, cost)`.

**When CAS actually pays off**: multiple people or branches producing results without overwriting each other's stored objects, or needing to keep historical versions around for comparison. **When it doesn't**: large, frequently-changing outputs — you'll mostly pay the deduplication overhead without getting much deduplication, since the content rarely repeats.

## Aggregating branch outputs without loading everything into memory

If each dynamic branch writes its own Parquet file (`tar_parquet()` or a `format = "file"` target that writes one), you don't have to `tar_read()` and `dplyr::bind_rows()` every branch into memory to summarize across them. Point DuckDB at the branch outputs and let it stream through the files:

```r
tar_target(
  summary,
  {
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
    DBI::dbGetQuery(
      con,
      "SELECT category, count(*) FROM read_parquet(?) GROUP BY category",
      params = list(branch_files)
    )
  }
)
```

This scales to branch counts and per-branch sizes that would otherwise blow up memory if combined naively — the aggregation target's peak memory is bounded by DuckDB's query execution, not by holding every branch's data frame at once.

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

## Profiling a completed run with tar_meta()

After `tar_make()` runs — even partially, since a skipped target keeps the metadata from whenever it last actually ran — profiling data is already sitting in the metadata store with no extra instrumentation needed:

```r
meta <- tar_meta(fields = c(name, seconds, bytes, warnings, error))
meta[order(-meta$seconds), c("name", "seconds")]   # slowest targets
meta[order(-meta$bytes), c("name", "bytes")]        # largest stored objects
```

`seconds` is the runtime of the target's *last successful run*, which may predate the current `tar_make()` if the target was skipped as up to date — that's a feature here, not a caveat, since it means every target that has ever run carries real timing without needing a fresh full rebuild. `bytes` is the total size of everything stored at the target's path, so it reflects the *serialized* size (after whatever `format` is set), not necessarily in-memory size. Use the two together to tell slow-but-small targets (branching/parallelism candidates) apart from fast-but-large ones (`format`/`butcher::butcher()` candidates) instead of guessing from the code alone.

## Performance checklist

- `tar_option_set(format = "qs")`.
- `tar_option_set(error = "trim")` for long pipelines.
- Batch small computations.
- Slim models before returning them.
- `tar_prune()` after refactors.
- Run `tar_outdated()` before `tar_make()` to spot surprises.
