# Sub-goal 04: kit-stop-tax

**Merge policy:** auto
**Time budget:** 3-4 hours of loop work
**Proof:** run-table from the kit test suite (new tests for resolution memory + the override rejection, all green with real stdout) + a before/after note on hook behavior
**Depends on:** none
Effort: medium
**Branch:** fix/cc-hyg-04-stop-tax (repo: dwarvesf/dwarves-kit)
**PR base:** master (dwarves-kit default branch; verify with `gh repo view`)

## Outcome

The two measured kit taxes are gone (closes ID-238 + ID-239):

1. **slop-cleaner Stop hook** gains resolution memory: a flagged file is reported once per session (or once until its content hash changes), never 19 consecutive times. Evidence: 8,483-8,526 runs/30d at p50 ~497ms (p95 5.4s, max 11.5s), same 7 files re-flagged for days, ~70 min/month wall-clock. If memory is not worth the complexity, dropping the hook is an acceptable outcome; decide from the data, state why in the spec.
2. **session-state-save** frequency decided: keep every-Stop, or debounce; state the reasoning (8,483 x 271ms ~= 38 min/month).
3. **proof-gate override** rejects an override whose unproofed remainder touches source files (docs/deploy-inert only), OR demands a per-file exclusion list + an auto-filed backlog row per excluded source file. Evidence: the single recorded override (2026-07-01, rtk-611) shipped a broken source change reverted 9h later.

## Quality bar

Kit-grade: behavior change lands with tests in the same PR, and the full kit guard suite stays green. The hook gets FASTER and quieter, not smarter and heavier.

## How to close the loop

- Work in dwarves-kit (`~/workspace/tieubao/dwarves-kit`, deployed copy at `~/.claude/dwarves-kit`). Cross-repo: lane via `lib/lane-classify.sh` + spec + spec-validate + gate-ledger, never /kit:*.
- New tests: (a) slop-cleaner flags a file, second Stop with unchanged content stays silent, content change re-flags; (b) proof-ledger override on a batch touching a source file is rejected/demands the exclusion list. Run the kit's full test suite; capture the run-table (command + exit 0 + stdout slice).

**Done =** both new behaviors covered by green tests AND the full kit suite passes, proven by the committed run-table.

## Handoff on completion

1. Flip the ROADMAP box + PR #. 2. Overwrite HANDOFF.md (next: 05). 3. Append to DECISIONS.md (esp. the keep/drop and debounce decisions). 4. Exit immediately.

## Scope edges

**In:** slop-cleaner.sh, session-state-save.sh, proof-gate.sh/proof-ledger.sh override path, their tests.
**Out:** the other Stop hooks (em-dash-fix, secret-guard-stop, citation-guard: measured cheap enough), gate-ledger durability (kit-telemetry SG-01 owns it), anti-rationalization.sh.
**Not:** no rewriting the hook framework, no new config surface beyond what the fix needs, no touching kit-telemetry's scope.

## Where to look

dwarves-kit `hooks/` (slop-cleaner, session-state-save) and `lib/` (proof-gate, proof-ledger); its tests/ layout; research/2026-07-02-process-benchmark.md sections 1 and 5 for the numbers.

## PR body

One-line outcome; the run-table; the keep/drop + debounce decisions in two lines; link to ops-toolkit `_meta/megagoals/cc-hygiene/ROADMAP.md`; closes ops-toolkit ID-238 + ID-239 (cross-post one line to the kit board, riding this PR per the ID-235 rule).

## Notes

