# Sub-goal 01: gate-vocab-align (ID-091)

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table showing a command-driven full-lane run reaching ship WITHOUT any hand-recorded gate + a negative control (removing one phase owner's record re-blocks the gate). Rung 2.
**Design:** obvious
**Depends on:** none
Model: sonnet
**Branch:** fix/orchfin-01-gate-vocab
**PR base:** main

## Outcome

Verified reality (2026-07-06): the vocabulary is ALREADY single-sourced (both the required-set and the recorded names pass through `normalize_phase()` and the full-lane required-set is derived live from the `WORKFLOW.md` matrix, not hardcoded). So this is NOT a spelling typo. The real defect is a **recording gap**: three names in the full-lane required-set have NO `/kit:*` command that records them, so a full-lane run driven purely by the commands is BLOCKED at ship until the operator hand-records them:
- `build` , `commands/execute.md` (the Build phase owner) calls `gate-ledger.sh record` zero times (self-admitted in `WORKFLOW.md`).
- `design-critique` , its owner `commands/devs-team.md` records `review`, which the enforcer's required-set does not accept for the literal `design-critique` token.
- `design-record` , no command records it at all.

Outcome: a command-driven full-lane run reaches ship with NO hand-recorded gate. Fix direction (pin it): make each phase owner record its own gate name (`execute.md`→`build`; `devs-team.md`→also `design-critique`; the design-record owner→`design-record`); for any required name that genuinely has no phase owner, relax it OUT of the required-set with a one-line `WORKFLOW.md` note rather than leaving a permanent hand-record tax. Do NOT restructure the vocabulary.

## Quality bar

One list of gate names, referenced by both the enforcer and the recorders. A newcomer reading `ship-gate.sh` and `execute.md` sees the same vocabulary, not two dialects.

## How to close the loop

- Enumerate the recorded names (`bash lib/gate/gate-ledger.sh required full` vs grep `gate-ledger.sh record` across `commands/`); confirm the 3 gaps (`build`, `design-critique`, `design-record`).
- Close each gap per the pinned direction: add the `record` call to each phase owner, or relax the name from the required-set with a `WORKFLOW.md` note if it has no owner.
- Add/extend a test that asserts EVERY full-lane required name is recorded by some command (no required name with no recorder).
- Prove it end to end: run a full-lane sequence through the commands and reach ship with NO hand-recorded gate. Capture the run-table.

**Done =** a command-driven full-lane run reaches ship with zero hand-recorded gates (the recording-gap test passes), AND the negative control (removing one phase owner's `record` call) re-blocks the gate, both in a captured run-table.

**Kit-adopted repo? Record the gates.** Run from dwarves-kit cwd. `bash lib/classify/lane-classify.sh classify "align ship-gate required-gate vocabulary"` → likely `normal`; build+verify, then:
```bash
rid=$(bash lib/gate/gate-ledger.sh rid)
bash lib/gate/gate-ledger.sh record "$rid" build  ran "<test run-table>"
bash lib/gate/gate-ledger.sh record "$rid" review ran "<proof-of-done path>"
```

## Handoff on completion

1. Flip this sub-goal's ROADMAP box to `[x]` + record PR #.
2. Overwrite `HANDOFF.md` with the next sub-goal (02) + its first concrete action + `file:line` pointers.
3. Append durable invariants to `DECISIONS.md`.
4. Report in the records, then EXIT.

## Scope edges

**In:** the phase-owner commands' `gate-ledger.sh record` calls (`execute.md`, `devs-team.md`, the design-record owner) and, only if a required name has no owner, its membership in the `WORKFLOW.md` full-lane required-set.
**Out:** the gate MECHANICS, `normalize_phase()`, the vocabulary/naming itself (already single-sourced).
**Not:** renaming gates, restructuring the lane matrix, adding a new gate, refactoring gate-ledger.

## Where to look

The ship enforcement path (`hooks/ship-gate.sh`, `lib/gate/gate-ledger.sh`), the command recorders (`commands/`), the lane→required-gate mapping.

## PR body

Closes the full-lane gate RECORDING gap (ID-091): `build`, `design-critique`, and `design-record` are in the required-set but no `/kit:*` command records them, so a command-driven full-lane run is blocked at ship. Each phase owner now records its gate (or the ownerless name is relaxed from the required-set). The vocabulary was already single-sourced; this is a recording fix, not a rename. Verify: a command-driven full-lane run reaches ship with no hand-recorded gate (run-table in the PR). Part of the `orchestrator-finish` mega, see `_meta/megagoals/orchestrator-finish/ROADMAP.md`.

## Notes
