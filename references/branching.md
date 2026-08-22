# Branching

Two flavors: **dynamic** (branches created at runtime from data) and **static** (branches declared at design time with `tar_map()`). Use dynamic for "lots of similar branches", static for "a handful of heterogeneous branches that deserve readable names".

## Dynamic branching

### `map()` — parallel iteration

One branch per element. With multiple args, iteration is parallel (i.e. `x[1]` pairs with `y[1]`), not Cartesian.

```r
tar_target(
  analysis,
  analyze(species, data),
  pattern = map(species, data)
)
```

### `cross()` — Cartesian product

One branch per combination:

```r
tar_target(
  grid_results,
  simulate(alpha, beta, seed),
  pattern = cross(alpha, beta, seed)
)
```

### Composing

```r
# Map within cross
pattern = cross(config, map(x, y))
```

### Selection

```r
pattern = slice(x, index = c(1, 3, 5))
pattern = head(x, n = 3)
pattern = tail(x, n = 3)
pattern = sample(x, n = 10)
```

## Iteration types

### Vector (default)

Branches combine with `vctrs::vec_c()`. Works for most atomic vectors and data frames.

```r
tar_target(
  summaries,
  summarise_group(data),
  pattern = map(data)
)
```

### List

For results that do not combine cleanly (plots, models, lists):

```r
tar_target(
  plots,
  make_plot(group_data),
  pattern = map(group_data),
  iteration = "list"
)
```

### Group

Branch over row groups of a data frame. The upstream target must carry a `tar_group` column:

```r
tar_target(
  grouped_data,
  data |> group_by(category) |> tar_group(),
  iteration = "group"
)

tar_target(
  by_category,
  analyse_group(grouped_data),
  pattern = map(grouped_data)
)
```

Branch order matches group order — a reliable 1:n guarantee, so branch 1 corresponds to group 1, branch 2 to group 2, and so on. Still, prefer carrying the group's identifying value through in the result itself (see "Provenance tracking" below) rather than relying solely on branch position — it's one less thing to get wrong if the grouping logic ever changes.

## Working with branch results

```r
tar_read(analysis)                # all branches combined
tar_read(analysis, branches = 1)  # one branch
tar_branch_names(analysis)        # branch identifiers
tar_branches(analysis)            # full branch-level metadata table
tar_name()                        # call inside a branch for its own name
```

Provenance tracking:

```r
tar_target(
  results,
  {
    result <- analyze(data)
    result$source_id <- tar_name()
    result
  },
  pattern = map(data)
)
```

## Static branching with `tar_map()`

Create multiple named targets from a template:

```r
tar_map(
  values = list(
    dataset = c("train", "test"),
    model   = c("lm", "rf")
  ),
  tar_target(fit,   fit_model(dataset, model)),
  tar_target(score, score_model(fit, dataset))
)
```

This produces `fit_train_lm`, `fit_train_rf`, `fit_test_lm`, `fit_test_rf`, and matching `score_*` targets.

### Combining branches

```r
tar_combine(
  all_scores,
  fit,
  command = dplyr::bind_rows(!!!.x, .id = "model")
)
```

Nest `tar_combine()` downstream of `tar_map()` to aggregate branches back into a single target.

## Batching — avoid millions of tiny targets

Each branch has overhead: a metadata row, a file on disk, a call to the controller. For 10,000 iterations, use 100 branches of 100 iterations:

```r
tar_target(batch_id, 1:100)

tar_target(
  results,
  run_batch(batch_id, items_per_batch = 100),
  pattern = map(batch_id)
)
```

`tarchetypes` provides higher-level patterns for this:

- `tar_map_rep()` — static branching with repeated runs per combination.
- `tar_rep()` — one target repeated with seeds.
- `tar_rep_index()` — current repeat index inside a batch.

## Notable additions (tarchetypes >= 0.13)

- `tar_skip()` now accepts `pattern`, so you can conditionally skip a dynamic branch.
- `tar_map_rep()` aggregates dynamic branches in parallel across static branches.
- `tar_map2*()` families accept `unlist` for flatter output structure.
- `tar_tangle()` (0.14) extracts R code from `.Rnw` / `.Rmd` / `.qmd` into a tracked target.
