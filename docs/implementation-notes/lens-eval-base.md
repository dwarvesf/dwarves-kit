# Implementation notes: lens-eval-base

Spec: `docs/specs/SPEC-325-lens-eval-base.md`. Delta from the spec only.

## Review

Fresh critique+review verdict: **SOLID / SHIP**. Zero criticals. Four LOW findings, all test
hardening (no behavior change), folded in before shipping:

| Kind | Note |
|---|---|
| Hardening test | `bm3` gained a positive assertion that `retire-any` (the `fewer` signal that never leaks) really shows a 1/1-vs-0/1 gap and PASSes, not just that the run prints no note. The spec's "One still shows a gap" row was previously proven only by the note's absence. |
| Hardening test, mutation-killing | `bm6`: `"STUB_MISS_CALLS=2 3" STUB_LEAK_CALLS=4 --samples 3` on `$ONEFEWER` ties treatment and control at 1/3, a minority, not the majority `t_hit` requires. Hand-verified: replacing the majority test `[ $((h * 2)) -gt "$samples" ]` with `[ "$h" -gt 0 ]` at the `t_hit` assignment turned this row RED (`majority-gate-at-n-gt-1: no note line`) without changing any other row; restored and confirmed green again before committing. |
| Hardening test, mutation-killing | `bm7`: a case with `heartbeat-any` (ties via the leak) and `never-any` (pattern `zzz-none`, matches nothing in either arm) in the same run. Hand-verified: moving `t_hit=0` out of the per-signal loop body (declaring it once before the `while` instead of resetting it every iteration) let `never-any` inherit `heartbeat-any`'s stale hit status and wrongly print the note; that mutation turned `per-signal-t-hit-reset: no note line` RED. Restored and confirmed green. |
| Hardening test, mutation-killing | An assertion that the `note:` line's line number is lower than the `samples:` line's, added right after `bm1`. Hand-verified: moving the note's `if` block to after the `summary` call turned this row RED without moving anything else. Restored and confirmed green. |
| Tradeoff | Verifying test 1 (retire-any) is a strengthening assertion, not tied to one named mutation the way tests 2-4 are; it makes the existing "one still shows a gap" case's premise checkable instead of only inferred from the note's absence. |
| Tradeoff | The two multi-line comments the review flagged (the `fewer_nogap` credit rationale, the note-print gate rationale) were trimmed to one line each. Pure wording; the negative control still pins the same single mutation (`fewer_nogap` increment removed) and now also turns the new ordering assertion red, since a base ref that never carries a note also has no note line to compare against the samples line. |

## Deviations

None from the spec's Contract. The hardening round only added tests and trimmed comments; the
scoring logic, the note's wording, the exit-code contract, and the README rule are unchanged
from what SPEC-325 originally validated.

## Not covered by a test

- A live `lens-eval.sh` run against a real base ref. Out of scope per the dispatch instruction
  (no model spend for this change); the offline stub suite is the primary flow for the feature
  itself (arithmetic over already-scored hit counts), not a stand-in for a live lens eval.
- A second, independently pinned negative control per hardening finding. Each finding was
  hand-verified once (mutate, confirm red, restore, confirm green) as part of building the test,
  per the coordinator's ask; only the original `fewer_nogap`-increment mutation is pinned as the
  proof-of-done's reproducible negative control, and it now also kills the new ordering row.

## Test count

105 -> 111 assertions in `tests/test-lens-eval.sh` (6 added: the retire-any row, the note-ordering
check, and two assertions each for the majority-gate and per-signal-reset cases).
