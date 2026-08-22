# targets-r-skill

An LLM skill for the [`targets`](https://docs.ropensci.org/targets/) R package using `targets` >= 1.12.0 and `tarchetypes` >= 0.14.1.

## What does it do?

When you ask an LLM to write a `_targets.R` file, it draws on training data that mixes drake idioms, pre-1.10 `targets` patterns, and current best practice. This skill gives the model a structured reference for the current API so it produces pipelines that match the 1.11-era defaults and uses the modern tarchetypes factories.

The skill covers: `tar_target()` and option setup, storage formats (including `format = "auto"`), dynamic and static branching, debugging with `tar_workspace()` and `tar_igraph()`, scoped `tar_make()` / `tar_invalidate()` / `tar_destroy()` for safe reruns, cloud and CAS repositories, Quarto and R Markdown integration with `tar_quarto()` / `tar_render()`, Typst/LaTeX compilation patterns, and anti-patterns specific to `targets`.

## Installation

### Claude Code (one command)

Clone directly into your skills directory:

```bash
git clone https://github.com/statzhero/targets-r-skill.git ~/.claude/skills/targets-r
```

That's it. The skill is available immediately as `/targets-r` in any Claude Code session.

If you prefer not to use the terminal, you can add skills from the Claude desktop app:

1. Download the repository as a ZIP from GitHub.
2. Open the Claude desktop app and switch to the **Code** tab.
3. Click **Customize** in the left sidebar, then select **Skills**.
4. Click the **+** button, choose **Upload a skill**, and select the ZIP file.

### Codex

Clone into your user skills directory (available across all projects):

```bash
git clone https://github.com/statzhero/targets-r-skill.git ~/.codex/skills/targets-r
```

If you prefer not to use the terminal, download the ZIP, unzip it, and move the folder to `~/.codex/skills/targets-r/` or `.codex/skills/targets-r/` inside your project.


## Test the skill

After installing, try this prompt in your CLI:

```
/targets-r Write a _targets.R that reads data/raw.csv, cleans it, and fits a linear model.
```

The skill should produce a pipeline using `tar_file_read()` and `tar_option_set(format = "qs")`.

## Acknowledgements

Will Landau's `targets` manual and NEWS files are the authoritative source for most of what this skill encodes. The structure borrows from the [`tidy-r-skill`](https://github.com/statzhero/tidy-r-skill) template.

## References

| Topic | Source |
|-------|--------|
| targets user manual | https://books.ropensci.org/targets/ |
| targets reference | https://docs.ropensci.org/targets/ |
| tarchetypes reference | https://docs.ropensci.org/tarchetypes/ |
| NEWS (targets) | https://github.com/ropensci/targets/blob/main/NEWS.md |
| NEWS (tarchetypes) | https://github.com/ropensci/tarchetypes/blob/main/NEWS.md |
| Carpentries Incubator targets-workshop | https://carpentries-incubator.github.io/targets-workshop/ |
| Modeling data workflows with targets | https://seanfobbe.com/posts/2023-11-12_modeling-data-workflows-with-targets/ |
| Lessons from a large targets pipeline (cloud/spatial-heavy) | https://github.com/mdsumner/targeted-learning/blob/main/README.md |
| R Targetopia contributing guide (target factories) | https://wlandau.github.io/targetopia/contributing.html#target-factories |

## License

MIT • Ulrich Atz ([ulrichatz](https://bsky.app/profile/ulrichatz.org))
