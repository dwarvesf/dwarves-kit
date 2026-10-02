# Implementation notes: gate-false-positive-relief (SPEC-384)

The delta from `docs/specs/SPEC-384-gate-false-positive-relief.md`. Decisions in the spec's Decision Log are referenced, not restated.

## Decisions

| Decision | Why |
|---|---|
| Both retro action items from `docs/retro/RETRO-2026-10-02-observe-cost-dedup.md` ship as one spec with separate tasks | One incident (#877's `lib/session/` false positive) caused both; one validation round instead of two. |
| `middleware/session-store.js` is not pinned as a must-stay-full path, although the lead's brief listed it | It classifies `normal` today; pinning it would widen the hard-path set, and the brief said narrow only (spec DEC-2). |
| Validation R6 W1, lead ruling (binding for TASK-2): `override-lane` refuses with exit 64, writing nothing, when any gate the lane requires has a `skipped` line in the run log; it names each such gate and its recorded reason | A `skipped` line is a recorded refusal (`design-record skipped "critical: ..."`, `Validate skipped "NEEDS REVISION ..."`); one lane-wide call must never paper over it. The single-gate `override` stays the deliberate way to clear one. Add an AC9-style test row. |
| Validation R6 W2: `override_lane` reads kit-root lanes with the in-script prefix form (`LANES_KIT_ONLY="$kl" required`), as `check()` does; Grounding S5 is relabelled as code-traced, not a live sample | `gate-ledger.sh:69` resets `LANES_KIT_ONLY` unconditionally, so an env-var sample repeats the project count. |
| Validation R6 W3: relabel the T2 diagram as a flowchart | One actor through steps; cosmetic. |
| `docs/FEATURES.md` regenerated in the spec commit | Adding the spec made the registry stale, which `tests/test-meta.sh` reports as a failure. |
| Round 1 fold: T1 replaced by `[lanes] not_hard_paths` per the lead's brief; round 1's DEC-2 (strict narrowing) is moot, the `middleware/session-store.js` row above stands as history | The pattern narrowing had recall holes (spec DEC-1). |
| Fold, not settled by the brief: entries are repo-scoped (`owner/repo:prefix/`), matched against the repo's `origin`; the kit entry is `dwarvesf/dwarves-kit:lib/session/`, not bare `lib/session/` | The kit root `kit.toml` ships to every consumer. A bare `lib/session/` would exempt a consumer's own `lib/session/` auth code. No origin, or a fork's origin, exempts nothing (safe side). |
| Fold, not settled by the brief: the reader uses `_ld_operator_file` then the pinned `_ld_kit_file` (`kit_config_get_root`'s order), not `kit_config_get_root` itself | `kit_config_root` follows `KIT_CONFIG_ROOT`/`DWARVES_KIT` from the environment; lane-data pins the kit root on purpose (Grounding S4). |
| Fold, "auth only or named kinds; pick and justify": auth only, no kind field, so the "unknown kind refuses" rail has nothing to refuse | Spec DEC-9: the only observed false positive is auth. |
| Fold, refines the binding `skipped` ruling above: a gate whose only skips read exactly `repo lane override (.kit.toml)` is not a refusal, and it STILL gets an override line | The brief says "treated as disposed", but `check --kit-lanes` counts only ran/override; Grounding S6 shows the floor check fails without the line. Every other skip reason (including `incomplete: ...`) is a refusal unless a later ran/override exists. |
| Fold: the "project-only lane" case is unreachable (`lane_resolve` accepts only the five kit lane names); the kit-root half still falls back to empty on a non-zero exit, and AC8 pins `mega` as unknown | Grounding S5. |
| Fold: ACTION reason uses `tr '=' ':'`, not a sha | Spec DEC-11: the full reason is on every GATE line already. |
| Fold: the telemetry counter prints only when n > 0 | Keeps every existing `report` pin byte-stable. |
| Fold: tasks split into five (knob, classifier, override-lane, counter, docs) with declared dependencies | Round 1 C2 and R4 W6. |
| Fold: AC8's empty-rid case uses `@@@`, not `///` | `runid` maps `/` to `-`, so `///` becomes `---`, a valid rid. |

## Open questions for the operator

| Question | Default taken |
|---|---|
| Should `override-lane` appear in the ship-gate's block message? | No (spec DEC-4): discoverability would invite reaching for it before checking the classifier. |
