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
| Fold 2 supersedes two fold-1 rows: entries are host-qualified (`github.com/dwarvesf/dwarves-kit:lib/session/`), and the layers are a UNION of overlay and pinned kit root, not first-non-empty | Lead's fold 2 brief (C1, R5 W2). Edge 5 now says the overlay never needs to restate the kit entry. |
| Fold 2, not settled by the brief: the repo id needs exactly three components after normalization (scheme, userinfo, port, `.git`, trailing `/` stripped; scp form converted); GitLab subgroup URLs get no id | "Reject ids with extra path components" taken literally; such a repo gets no exemption, the safe side. |
| Fold 2, not settled by the brief: `EXEMPT` lines are written for every path floor exempts, not only when the exemption flipped the verdict | Deciding "changed the result" needs a second floor pass; the superset costs one log line per exempted path and hides nothing. |
| Fold 2, refines the brief's "any later ran/override disposes": any ran/override line disposes a gate whatever its position in the ledger | The same bullet says "matching `check()`", and `check()` ignores order. A later-only rule would refuse runs `check()` already passes. |
| Fold 2: the `.kit.toml` skip is exempt only for a gate in the kit-root set and absent from the project-resolved set | R2 W5, made checkable: that is exactly the set `start()` writes the string for. AC13 seeds the string on `build` to show it refuses elsewhere. |
| Fold 2: an operator overlay counts as "tracked" when `git ls-files --error-unmatch` succeeds from the file's own directory, in addition to the realpath-inside-`<root>` test | Covers an overlay committed in some other repo the agent controls, not only the repo under check. |
| Fold 2 (optional item taken): a one-segment prefix (`lib/`) is accepted with one warning | Cheap, and it flags the broadest entries without blocking a deliberate one. |
| Fold 2: round 2's TASK-3a and TASK-3b are TASK-2 and TASK-4; every task is renumbered so numbers follow the phase order | C3 and the brief's renumbering line. |
| Fold 2: the kit repo's `.kit.toml` comment ("nothing here can remove one") stays true for the project file; TASK-7 rewords it to name `not_hard_paths` as root-only rather than deleting the claim | The project file still cannot remove a hard path; only the root layers can. |
| Fold 2: the spec is marked not dispatch-eligible | `gate_touches` marks root files (`kit.toml`, `.kit.toml`, `hooks/ship-gate.sh`, ADR files) as unprovable `?` entries. |

## Open questions for the operator

| Question | Default taken |
|---|---|
| Should `override-lane` appear in the ship-gate's block message? | No (spec DEC-4): discoverability would invite reaching for it before checking the classifier. |
