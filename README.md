# targets-r-skill

An LLM skill for the [`targets`](https://docs.ropensci.org/targets/) R package using `targets` >= 1.12.0 and `tarchetypes` >= 0.14.1.

## What does it do?

When you ask an LLM to write a `_targets.R` file, it draws on training data that mixes drake idioms, pre-1.10 `targets` patterns, and current best practice. This skill pins the model to the current API so it produces pipelines that match the 1.11-era defaults (`memory = "auto"`, `retrieval = "auto"`, deprecated `priority`, `error = "trim"`) and uses the modern tarchetypes factories (`tar_file_read()`, `tar_qs()`, `tar_nanoparquet()`).

The skill covers: `tar_target()` and option setup, storage formats (including the new `format = "auto"`), dynamic and static branching, debugging with `tar_workspace()` and `tar_igraph()`, cloud and CAS repositories, Quarto and R Markdown integration with `tar_quarto()` / `tar_render()`, Typst/LaTeX compilation patterns, and anti-patterns specific to `targets`.

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
git clone https://github.com/statzhero/targets-r-skill.git ~/.agents/skills/targets-r
```

If you prefer not to use the terminal, download the ZIP, unzip it, and move the folder to `~/.agents/skills/targets-r/` or `.agents/skills/targets-r/` inside your project.

### Other LLMs

Paste the contents of `SKILL.md` into your system prompt or attach it as context. The reference files in `references/` can be appended when you need coverage of a specific topic.

## Test the skill

After installing, try this prompt:

```
/targets-r Write me a _targets.R that reads data/sales.csv, fits a linear
model per region using dynamic branching, combines the coefficients, and
renders report.qmd.
```

The skill should produce a pipeline using `tar_file_read()`, `pattern = map(region)`, and `tar_quarto()`, with `tar_option_set(format = "qs", error = "trim")`.

## References

| Topic | Source |
|-------|--------|
| targets user manual | https://books.ropensci.org/targets/ |
| targets reference | https://docs.ropensci.org/targets/ |
| tarchetypes reference | https://docs.ropensci.org/tarchetypes/ |
| NEWS (targets) | https://github.com/ropensci/targets/blob/main/NEWS.md |
| NEWS (tarchetypes) | https://github.com/ropensci/tarchetypes/blob/main/NEWS.md |

## Changelog

- **2026-04-17** — Renamed to `targets-r`. Restructured to match the `tidy-r` skill template: slimmer `SKILL.md` plus topical reference files. Audited against `targets` 1.12.0 and `tarchetypes` 0.14.1; removed deprecated `priority` and `file_fast` patterns, added `error = "trim"`, `tar_igraph()`, `memory = "auto"`, CAS repositories, and the `tar_quarto()` / `tar_tangle()` additions from recent tarchetypes releases.
- **2026-03-12** — Initial release as `write-targets`.

## License

MIT • Ulrich Atz ([ulrichatz](https://bsky.app/profile/ulrichatz.org))
