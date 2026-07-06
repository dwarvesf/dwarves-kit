# Sub-goal 08: reserved-keys-guard

**Merge policy:** auto
**Time budget:** 1-2 hours
**Proof:** run-table showing a reserved/inert key ([features].auto_improvement, [team].*) is returned by the resolver with NO side-effect. Rung 2 (a negative control: flipping an inert key changes no behavior).
**Design:** obvious
**Depends on:** 01
Model: sonnet
**Branch:** feat/harness-ops-08-reserved
**PR base:** main

## Outcome

The forward-looking-but-not-built keys stay honestly inert: `[features]` (auto_improvement = designed-not-built, learning_ledger = external consumer skill) and all of `[team].*` (designed-not-built) are readable via the resolver but have NO live code path , flipping them changes nothing, and that is DOCUMENTED (status tags), not a silent no-op a user mistakes for a working toggle. A test proves it.

## How to close the loop

- Confirm no live code branches on `[features]`/`[team]` keys (grep for kit_config_get on those sections; there should be none, or only a documented placeholder).
- Add a test: set `[features] auto_improvement=true` and `[team] actor_identity=true` in a project `.kit.toml`; assert NO behavior changes (no hook wired, no command path taken) , they are inert by design.
- Confirm the kit.toml/kit.toml.example status tags mark these `[design]`/`[consumer]` so a reader knows they're inert.
- Capture the run-table (inert-key flip changes nothing).

**Done =** the reserved `[features]`/`[team]` keys are resolver-readable but inert (captured run-table where flipping one changes no behavior), and their status tags document them as not-yet-live.

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → next; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** the inert-key guard test, the status-tag documentation in kit.toml.
**Out:** actually building auto_improvement/learning_ledger/team (those are their own future work).
**Not:** wiring any reserved key to a live path, removing the reserved keys.

## PR body

Guards the forward-looking reserved keys (`[features]`, `[team].*`): resolver-readable but inert + documented, with a test proving an inert-key flip changes nothing. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
