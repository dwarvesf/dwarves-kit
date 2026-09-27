# Implementation notes: proof-verdict-hint (SPEC-330)

Delta log only; the spec carries the design.

## 2026-09-27 last_v anchors on line START, not a bulleted list item

Context: `check()`'s existing last-verdict-wins scan anchors on `^[[:space:]]*Verdict:`. A
first draft of the test fixtures wrote `- Verdict: PASS` (a Markdown bullet), matching the
convention used by an existing sibling test (`test-proof-override-order.sh`). Every real
`docs/verification/*.md` in this repo instead writes a bare `Verdict:` at the start of its own
line (see `docs/verification/advisor.md`), and only that shape is visible to the anchored
regex; a bulleted line is invisible to it (the greps that decide NEGATIVE CONTROL/green
presence are unanchored substring matches and do see it, so the near-miss condition looked
armed but `last_v` came back empty, and an empty `last_v` never matches
`FAIL|INCONCLUSIVE`, so every fixture spuriously PASSED instead of exercising the near-miss
path).
Decision: rewrote every test fixture in `tests/test-proof-verdict-hint.sh` to the real
convention (`Verdict:`/`Result:` at line start, no bullet).
Why: the fix under test only fires on the exact shape the gate already reads; a fixture in a
shape the gate does not read proves nothing.
Impact: none to `lib/gate/proof-ledger.sh` itself; a test-authoring correction only, caught by
running the new suite before trusting it (case1 initially came back exit 0 instead of the
expected 1, which is what surfaced the anchor mismatch).

## 2026-09-27 review round + reflect

Review: not dispatched as a separate `/kit:review` pass in this build step (see the gate-ledger
report in the session handoff for what remains open: `review`, `docs`, `ship`, `reflect`, plus
the earlier-phase `think`/`design`/`design-critique` gates, none recorded in this run). The
restructure from an `&&`-chain into named booleans is a mechanical, behavior-preserving
rewrite (confirmed by the full existing `tests/test-proof-*.sh` suite staying green and the
mechanised negctl.sh mutate-mode control going RED under the pre-fix `origin/master` copy),
so the residual risk is narrow, but a fresh-context review of the diff has not run.
