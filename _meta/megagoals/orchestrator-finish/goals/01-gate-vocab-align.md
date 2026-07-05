# Sub-goal 01: gate-vocab-align (ID-091)

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table + one named negative control (a command recording an unknown gate name is caught). Rung 2.
**Design:** obvious
**Depends on:** none
Model: sonnet
**Branch:** fix/orchfin-01-gate-vocab
**PR base:** main

## Outcome

The required-gate vocabulary is single-sourced: the names `hooks/ship-gate.sh` enforces via `gate-ledger.sh check full` are EXACTLY the names the `/kit:*` commands actually record. No phantom `build` gate that no command emits; no `review` vs `design-critique` split where the enforcer and the recorder disagree. A lane that records its gates honestly passes the ship-gate; a lane that skips a real gate is caught.

## Quality bar

One list of gate names, referenced by both the enforcer and the recorders. A newcomer reading `ship-gate.sh` and `execute.md` sees the same vocabulary, not two dialects.

## How to close the loop

- Enumerate the gate names each `/kit:*` command records (grep `gate-ledger.sh record` across `commands/`) and the names `ship-gate.sh` requires (its `check full` required-set). Diff the two sets.
- Fix the mismatch at the source: align the required-set to the recorded names (drop `build` if `execute.md` records nothing named `build`; unify `review`/`design-critique`).
- Add/extend a test that asserts the two sets are consistent (no required name that no command records; no recorded gate the enforcer silently ignores).
- Run it and the existing gate tests; capture the command + exit + a stdout slice as the run-table row.

**Done =** `gate-ledger.sh check full`'s required-set matches the gate names `/kit:*` commands record (the consistency test passes), AND the negative control (a fabricated unknown gate name) is rejected, both shown in a captured run-table.

**Kit-adopted repo? Record the gates.** Run from dwarves-kit cwd. `bash lib/lane-classify.sh classify "align ship-gate required-gate vocabulary"` → likely `normal`; build+verify, then:
```bash
rid=$(bash lib/gate-ledger.sh rid)
bash lib/gate-ledger.sh record "$rid" build  ran "<test run-table>"
bash lib/gate-ledger.sh record "$rid" review ran "<proof-of-done path>"
```

## Handoff on completion

1. Flip this sub-goal's ROADMAP box to `[x]` + record PR #.
2. Overwrite `HANDOFF.md` with the next sub-goal (02) + its first concrete action + `file:line` pointers.
3. Append durable invariants to `DECISIONS.md`.
4. Report in the records, then EXIT.

## Scope edges

**In:** the required-gate name set in `hooks/ship-gate.sh` / `lib/gate/gate-ledger.sh`, and the recorded names in `commands/*.md`.
**Out:** the gate MECHANICS (how a gate runs), the lane matrix in `WORKFLOW.md`.
**Not:** renaming gates for aesthetics, adding a new gate, refactoring gate-ledger.

## Where to look

The ship enforcement path (`hooks/ship-gate.sh`, `lib/gate/gate-ledger.sh`), the command recorders (`commands/`), the lane→required-gate mapping.

## PR body

Aligns the ship-gate required-gate vocabulary with the names `/kit:*` commands actually record (ID-091): no phantom `build`, no `review`/`design-critique` split. Verify: the gate-vocab consistency test (run-table in the PR). Part of the `orchestrator-finish` mega, see `_meta/megagoals/orchestrator-finish/ROADMAP.md`.

## Notes
