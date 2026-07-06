# Sub-goal 03: wire-mega

**Merge policy:** auto
**Time budget:** 2-3 hours
**Proof:** run-table showing a `[mega]` key read via the resolver + the goal-file>project>kit-root precedence for default_model/over_test. Rung 2.
**Design:** obvious
**Depends on:** 01 (the resolver)
Model: sonnet
**Branch:** feat/harness-ops-03-mega
**PR base:** main

## Outcome

The `[mega]` config section is live, read when `/kit:mega` + `orchestrate.sh` scaffold/run: `wave_cap`, `tier4_close`, `multiplexer`, `merge_autonomy`, `mega_merge_posture` resolve through the config layer (env var still wins). `default_model` and `over_test` are GLOBAL fallbacks with precedence: per-sub-goal goal-file field (`Model:`/`Done-mode:`) > project `.kit.toml` > kit-root `kit.toml` > hardcoded. This is the layer that lets a different-harness adopter set one default without touching every goal file.

## How to close the loop

- In `orchestrate.sh` (and `commands/mega.md`'s resolution where applicable), route the existing env-var knobs through the resolver as the middle layer.
- For `default_model`/`over_test`: the per-goal-file field still wins; config supplies the fallback when the field is absent.
- Test: a project `.kit.toml` `[mega] wave_cap=3` is honored; `WAVE_CAP=5` env overrides it; a goal file with no `Model:` picks up `[mega] default_model`, a goal file WITH `Model: opus` keeps opus. Capture the run-table.

**Done =** `[mega]` keys resolve through the config layer with env>project>kit-root>default, and default_model/over_test honor goal-file>project>kit-root>hardcoded (captured run-table).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; overwrite HANDOFF.md → next; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** `[mega]` resolution in orchestrate.sh + the default_model/over_test fallback chain.
**Out:** the orchestrator's run mechanics, `[ledger]` (02), the goal-file `Model:` parse (unchanged, still wins).
**Not:** changing any default's value, adding new mega knobs, touching hooks.

## PR body

Wires the `[mega]` config section through the resolver; default_model/over_test become global fallbacks under the per-goal-file fields. Verify: the wave_cap + model-precedence run-table. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
