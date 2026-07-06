# Sub-goal 04: manifest-reconcile

**Merge policy:** auto
**Time budget:** 3-4 hours
**Proof:** run-table showing the 3-artifact chain coherent (repo-root default → install render → resolver read) + the hooks-only kit.toml lint still green. Rung 2 + a negative control (a hook reading kit.toml fails the lint).
**Design:** bearing
**Depends on:** 01
Model: sonnet
**Branch:** feat/harness-ops-04-manifest
**PR base:** main

## Outcome

The three artifacts that touch config form ONE coherent chain: the repo-root `kit.toml` is the shipped DEFAULT (promoted from `kit.toml.example`, full schema); `install.sh` renders the live install `~/.claude/dwarves-kit/kit.toml` from it + the `--with` module flags; the resolver reads the install config, overridden by the project `.kit.toml`. The existing `[modules]` install-manifest behavior is preserved; the new sections ([ledger]/[mega]/...) ride the same file. The `no-runtime-manifest-read` lint (test-install-modules, hooks-only scope) stays green and is CONFIRMED hooks-scoped, not all-runtime.

## Design

The reconciliation is design-bearing (2+ viable approaches: one merged kit.toml vs a separate runtime-config file). Pin: ONE kit.toml, sections read by commands not hooks. The spec's `## Design` block records the chain + why the lint stays satisfied (commands read, hooks don't). Link the config brief.

## How to close the loop

- Promote `kit.toml.example` → a real repo-root `kit.toml` (shipped default, full schema, status-tagged comments).
- Make `install.sh` render the install kit.toml FROM the repo-root default + `--with` (preserve the current `[modules]` manifest write; add the other sections).
- Confirm the resolver's kit-root path resolves to the install kit.toml (prod) / repo-root (dev).
- Verify the lint: `bash tests/test-install-modules.sh` still passes "no hooks/*.sh reads kit.toml"; add a negative control (a hook that reads kit.toml fails).
- Capture the run-table (install renders the full config; resolver reads it; lint green).

**Done =** the repo-root→install→resolver chain is coherent (captured run-table), the `[modules]` manifest still round-trips, and the hooks-only lint stays green with the NC (a hook reading kit.toml fails).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal/full; this touches install).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → 05; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** `install.sh` kit.toml render, the repo-root kit.toml, the resolver's kit-root resolution.
**Out:** the resolver logic (01), what each section MEANS (02/03).
**Not:** reversing the hooks-only lint, making hooks read config, a general install refactor.

## PR body

Reconciles the config manifest chain: repo-root kit.toml (default) → install render → resolver read (install←project), preserving the `[modules]` manifest and the hooks-only kit.toml lint. Verify: the chain run-table + the lint NC. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
