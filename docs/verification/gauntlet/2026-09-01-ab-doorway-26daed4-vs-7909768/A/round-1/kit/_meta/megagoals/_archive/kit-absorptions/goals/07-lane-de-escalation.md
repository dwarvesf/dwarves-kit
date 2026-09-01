# Sub-goal 07: lane-de-escalation (the ship-time "consider tiny" nudge)

**Merge policy:** auto
**Time budget:** 1-1.5 hours of loop work
**Proof:** run-table: fire fixture (chosen lane >= normal, final diff under the floor -> nudge line captured + ledger action line logged); no-fire fixture (large diff -> silence); the no-block NC (a nudged ship still exits 0 and pushes).
**Design:** obvious
**Depends on:** none in this stack (chain position after 06)
Model: sonnet
**Branch:** `feat/lane-de-escalation`
**PR base:** `feat/kit-pitch`

## Outcome

ID-257 kit half: escalation stops being one-way. At ship time, when the CHOSEN lane was `normal`/`full` but the final diff stayed under a size floor (changed-lines threshold, named tunable), print one advisory line ("this shipped as <lane> but the diff is tiny-sized; consider `tiny` next time") and append a ledger `action` line so the observatory's misroute query has data. Advisory only, never blocks, mirrors quiz-gate's always-exit-0 posture. NO gate cuts here (Han's rule: no numbers, no verdict; this CREATES the numbers).

## Quality bar

One nudge line + one ledger line; zero effect on the ship outcome. The size floor is a named default, overridable, documented next to the lane matrix.

## How to close the loop

- Fire fixture: small-diff ship on lane normal -> nudge captured + `action` ledger line present.
- No-fire fixture: large diff -> no output (captured).
- No-block NC: the nudged ship's exit code is 0 and the push proceeds (asserted).
- Kit-adopted: run the lane, record gates before push.

**Done =** fire + no-fire + no-block all captured/asserted; the ledger action line format documented.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 09-mega-mirror-sync (after 08 merges in the dotfiles stack; check its PR state). 3. `DECISIONS.md`: the size floor chosen + rationale. 4. EXIT.

## Scope edges

**In:** `commands/ship.md` (one advisory step), the size-floor doc line, tests.
**Out:** lane-classify heuristics; the lane matrix; the skill-side decompose rule (rode sub-goal 02).
**Not:** auto-reclassification; blocking anything; touching escalation-UP logic.

## Where to look

`research/2026-07-04-scaling-the-harness-audit.md` (the wrapper-cost analysis in ID-257's row); WORKFLOW.md lane matrix; quiz-gate.sh for the advisory exit-0 posture.

## PR body

Ship-time de-escalation nudge: advisory line + ledger action when a normal/full ship's diff stayed tiny-sized. Never blocks. Feeds the misroute query. Stacked; review after kit-pitch. Covers ID-257 (kit half).

## Notes

