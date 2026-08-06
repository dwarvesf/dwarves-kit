# Sub-goal 01: emit gate-ledger start in the automated mega dispatch

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table , a run dispatched through the automated mega/execute path carries a `START` line (lane + type recorded), so `lane-telemetry.sh report` counts it under its real lane, NOT `?`. Negative control: the pre-fix dispatch produced a `?` (untracked) run.
**Depends on:** none. FIRST: this is the root cause blinding the whole measurement layer (eval metrics 1/2/4/7 were NULL because ~60% of runs had no START).
Model: sonnet
Effort: high
**Branch:** feat/kit-clean-01-startwire
**PR base:** master

## Outcome

The automated mega-goal / execute dispatch records each sub-goal run's routing facts. Today `commands/assign.md` (the hand-run intake) calls `gate-ledger.sh start <rid> <lane> <classified> <type>` correctly, but the automated `commands/mega.md` sub-goal dispatch does NOT , so every run that went through the mega loop is untracked (`?` lane/type), which is why the SPEC-073 eval could not measure lane/type/skip/escape rates (it filed them NULL, ID-085). Fix: the automated dispatch emits the same `start` call assign.md already makes, so mega-dispatched runs are as measurable as hand-run ones.

## Quality bar

Copy the mechanism that already works (`commands/assign.md`'s start call), do not invent a new one. The START line must carry the SAME fields (chosen lane, classified lane, type, ctype, repo) so the existing `lane-telemetry.sh` readers parse it unchanged. Do not touch the record/override/check verbs , only the missing `start` at dispatch time.

## How to close the loop

Kit-adopted repo (dwarves-kit): read `AGENTS.md` + `WORKFLOW.md` first; classify the lane with `bash lib/lane-classify.sh classify "<task>"`; record each phase via `lib/gate-ledger.sh record` before the push (the ship-gate enforces it). Cross-repo: drive via `lib/` + `gate-ledger` directly, NOT `/kit:*` (they bind to cwd).

```
cd dwarves-kit
grep -n 'gate-ledger.sh start' commands/assign.md   # the reference call
grep -n 'gate-ledger.sh start' commands/mega.md      # AFTER the fix: present
# proof: simulate a mega-dispatched run, confirm it carries a START
bash tests/test-<start-wiring>.sh                     # a dispatched run -> START line, not '?'
```

Proof run-table at `docs/verification/mega-start-wiring.md`. Pin a test that a dispatched run records START (and that a run WITHOUT the wiring is `?` , the negative control).

**Done =** the automated `commands/mega.md` dispatch calls `gate-ledger.sh start` per sub-goal (mirroring assign.md), a pinned test proves a dispatched run carries a START line with lane/type (not `?`), and the ship-gate gates are recorded.

## Handoff on completion

1. Flip 01's ROADMAP box, PR # + SHA.
2. HOT `HANDOFF.md`: next = 02 (detectors) or 04 (merge-mark); first action = classify the lane from the board row.
3. WARM `DECISIONS.md`: where the start call was wired + why mega.md (not execute.md, if that's the finding).
4. Report IN records, EXIT.

## Scope edges

**In:** the missing `gate-ledger.sh start` call in the automated dispatch path + its test.
**Out:** the detectors (02); fixture pollution (03); the merge-mark (04); the classifier (05).
**Not:** a new telemetry schema; changing the START line format; re-running the SPEC-073 eval (that needs days of real usage , a filed follow-up, not this wave).

## Where to look

`commands/mega.md` (the automated sub-goal dispatch), `commands/assign.md` (~line 126, the correct `start` call to mirror), `commands/execute.md` (confirm whether it or mega.md owns the dispatch), `lib/gate-ledger.sh` `start()`, dwarves-kit board ID-085, `docs/research/2026-07-02-effectiveness-eval.md` (metric 3, the finding).

## PR body

Emit `gate-ledger start` in the automated mega/execute dispatch so mega-dispatched runs carry a START line (mirrors assign.md). Root cause of the SPEC-073 eval's 90%-untracked finding (ID-085, `#kit-telem-followup`). Verify: `bash tests/test-<start-wiring>.sh`. Proof: `docs/verification/mega-start-wiring.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telem-cleanup/ROADMAP.md`.

## Notes

<empty>
