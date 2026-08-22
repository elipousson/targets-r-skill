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

**Gotcha: branching over a list-valued target can hand each branch an extra layer of nesting.** It depends on the upstream target's `iteration` setting, not on `map()` itself:

```r
tar_target(input, list(a = 1:3, b = 4:6, c = 7:9)),   # default iteration = "vector"
tar_target(out, show(input), pattern = map(input))
# each branch receives list(a = 1:3) / list(b = 4:6) / list(c = 7:9) — still wrapped in a length-1 list
```

A plain list has default `iteration = "vector"`, and slicing a list vector-style keeps each element wrapped in a length-1 list (`vctrs::vec_slice()` on a list returns a list). You either unwrap it in the function (`input[[1]]`), or — usually cleaner — declare the upstream target's own iteration so it hands off bare elements instead:

```r
tar_target(input, list(a = 1:3, b = 4:6, c = 7:9), iteration = "list"),
tar_target(out, show(input), pattern = map(input))
# each branch now receives the bare element directly: 1:3 / 4:6 / 7:9, no unwrapping needed
```

Verified empirically against targets 1.12 — this isn't cosmetic, it changes what the function body has to do with its argument. The same `iteration = "list"` you'd set on a *downstream* target to avoid `vec_c()` recombination (see below) is worth setting on the *upstream* target too, for exactly this reason, whenever it holds heterogeneous list elements meant to be branched over one at a time.

One exception: if the list is *named* and you want that name as an identifier (`names(model_spec)`), keep the upstream target at default vector iteration and unwrap manually — switching it to `iteration = "list"` strips the name along with the wrapping, since the bare element that comes through no longer carries it. See the provenance example below.

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

Provenance tracking — without it, a combined result loses track of which branch produced which row, which usually defeats the point of having branched at all:

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

`tar_name()` gives the branch's synthetic name, which is enough to distinguish branches but isn't necessarily meaningful. When the upstream list carries real identifiers, pull the identifier from the data itself instead (or in addition) — this is the case from the gotcha above where you deliberately keep the upstream target at default vector iteration so `names()` still works, and unwrap the value yourself:

```r
tar_target(
  model_spec,
  list(lm = "y ~ x", rf = "y ~ .")   # default iteration = "vector" — kept deliberately, see above
),
tar_target(
  fits,
  {
    model_name <- names(model_spec)   # "lm" / "rf" — only available because model_spec is still wrapped
    spec       <- model_spec[[1]]     # the formula string itself
    result <- fit_model(spec)
    result$model_name <- model_name
    result
  },
  pattern = map(model_spec)
)
```

### Dispatch tables: storing functions as branch-selectable data

When each branch needs genuinely different logic — not just different data — a tibble column can hold the functions themselves, selected and called with `do.call()`, instead of an `if`/`switch()` chain inside one shared function:

```r
tar_target(
  cleaning_dispatch,
  tibble::tibble(
    characteristic = c("Specific conductance", "Temperature, water"),
    cleaning_fxn    = c(clean_conductivity_data, clean_temperature_data)
  )
),
tar_target(
  cleaned,
  do.call(cleaning_dispatch$cleaning_fxn[[1]], list(cleaning_dispatch$characteristic[[1]])),
  pattern = map(cleaning_dispatch)
)
```

`targets` statically detects function symbols referenced anywhere in a command — including inside a list/tibble literal like this one — and tracks their bodies as dependencies automatically, the same as an ordinary function call. Nothing extra needs to be wired up for `clean_conductivity_data`/`clean_temperature_data` to be tracked, and each stays independently named, testable, and readable instead of living as a branch in a `switch()`.

**Verified caveat: this doesn't buy surgical invalidation for free.** `cleaning_dispatch` is a single, non-branched target — every branch of the downstream pattern depends on it as a whole. Tested empirically against targets 1.12: editing the body of just one of two dispatched functions, and separately adding an unrelated third row to the dispatch table, *both* rebuilt every existing branch of the downstream pattern rather than skipping the ones untouched by the change. Plain vector/list iteration rebuilds the whole pattern whenever its upstream target reruns for any reason — it does not diff row-by-row. If you want unaffected branches to actually skip when the dispatch table changes elsewhere, branch with `iteration = "group"` instead (see "Group" above): a stable `tar_group()` hash per group is what let a same-way-tested new-row addition leave existing branches alone in a side-by-side comparison, where default iteration rebuilt everything.

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
