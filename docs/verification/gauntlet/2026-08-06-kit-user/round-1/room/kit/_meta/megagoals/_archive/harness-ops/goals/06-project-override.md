# Sub-goal 06: project-override

**Merge policy:** auto
**Time budget:** 2-4 hours
**Proof:** run-table showing a `<project>/.kit.toml` overriding a kit-root default end-to-end + per-project module enable. Rung 2.
**Design:** obvious
**Depends on:** 05
Model: sonnet
**Branch:** feat/harness-ops-06-override
**PR base:** main

## Outcome

The per-project override is wired end to end: a `<project>/.kit.toml` overrides the kit-root default for that project (the resolver already merges it; this closes the loop through adopt + module enablement). `/kit:adopt` optionally seeds a starter `.kit.toml`. Per-project module enable works for hook-modules by writing `<project>/.claude/settings.json` entries at adopt-time (command/skill modules are always available; only hook-modules need wiring).

## How to close the loop

- Confirm the resolver honors `<project>/.kit.toml` (from 01); add adopt support: `/kit:adopt` writes a starter `.kit.toml` (opt-in) + wires enabled hook-modules into `<project>/.claude/settings.json`.
- Test: a project `.kit.toml` `[modules] board=false` results in that project NOT wiring the board hook (settings.json check); a `[ledger]` override in the project is honored by a command reading it. Capture the run-table.

**Done =** a `<project>/.kit.toml` overrides kit-root defaults end-to-end (captured run-table), and per-project hook-module enable writes the right `<project>/.claude/settings.json` entries at adopt-time.

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → full; touches adopt).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → 07; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** `.kit.toml` end-to-end, `/kit:adopt` seed + per-project hook wiring.
**Out:** the resolver merge (01), the global install (04).
**Not:** runtime per-call module toggling (hybrid model = wired at adopt, not read per hook fire), a settings.json rewrite.

## PR body

Wires per-project override end to end: `<project>/.kit.toml` overrides kit-root; `/kit:adopt` seeds a starter + wires enabled hook-modules into the project's settings.json. Verify: the project-override + module-enable run-table. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
