# SPEC-073: Telemetry + feedback-loop + proof-of-done effectiveness evaluation (design)

Status: VALIDATED (design complete; EXECUTION PARKED until 3-5 days of real-usage
data exist, per the 2026-06-10 retro decision and the operator's 2026-06-10 intake
answer: "design eval now, run later")
Date: 2026-06-11
Lane: full (classified: full)
Type: eval
Board: ID-067

## Question under evaluation

Is the kit's measurement layer (lane telemetry SPEC-061/062, run legibility
SPEC-063, proof-of-done convention SPEC-016-adjacent) actually closing the loop:
does recorded data change decisions, or is it ceremony?

## Evaluation design

### Data window

Earliest valid start: 3-5 days of REAL work after PR #55 (rid standardization)
merges, because pre-#55 ledgers carry mirror rids that poison the untracked
metric. Runs before that merge are EXCLUDED from every denominator below.

### Metrics + thresholds (decided now so the data cannot argue later)

| # | Metric | Source | Healthy | Action if unhealthy |
|---|--------|--------|---------|---------------------|
| 1 | lane misroute rate (chosen != classified, either direction) | `lane-telemetry.sh report` | < 15% of tracked runs | each misfire -> truth-table row (SPEC-060 method) or an accepted-noise line; 3+ same-pair misfires -> classifier rule work |
| 2 | type misroute rate | report `tmis` | < 15% | same disposition contract |
| 3 | untracked-run rate (gates but no START) | report headline | < 10% post-#55 | if mostly mirrors persist, ID-072 amend-path gets priority; if new runs, the assign wiring failed: bug lane |
| 4 | gate skip rate per lane x phase | ledgers, awk over GATE lines | no phase chronically (>50%) skipped within a lane | a chronically-skipped required gate = wrong matrix cell: propose lane x phase downgrade in WORKFLOW, do not silently keep skipping |
| 5 | override count | report | ~0 | any override -> retro item by definition |
| 6 | review findings curve (findings per review, by lens count) | spec Review sections + ledger review records | single-lens not always-0; multi-lens keeps finding disjoint classes | always-0 lens = dull lens (re-prompt or drop); multi-lens stops paying -> relax the lib/hooks escalation rule |
| 7 | escaped-defect rate (debug runs with escaped-from=<spec>) | `lane-telemetry.sh report` (escaped-defect section; _escapes is internal, not a subcommand) | trending down per spec generation | each escape names the test-plan row that should have caught it -> test-design-standard amendment |
| 8 | proof-of-done friction | count of proof-gate BLOCKED lines vs legit ships in ship-gate.log | blocks are true positives | false-positive blocks -> proof-ledger classify fix (the SPEC-071 registry floor should have removed the doc-task class) |
| 9 | boardless + shipped-incomplete counts | misfires | 0 boardless; shipped-incomplete only with retro-note | recurrence after the SPEC-069 detectors = the detector is advisory-blind: consider promoting to warn-at-assign |
| 10 | full-lane ceremony cost on kit-machinery work | wall-clock + phase counts of wave-1 runs (rids: rid-branch-slug, gate-ledger-fixes, classifier-anchors, wave1-doc-cluster) vs defect yield | reviews keep catching HIGHs at this size | if 2+ consecutive full-lane kit-machinery runs yield zero review findings above LOW, propose a hard-gate carve-out for `<=2-file` machinery diffs |

### Method

1. Freeze the window: `lane-telemetry.sh report` filtered to runs whose first
   ledger timestamp >= the #55 merge date. NOTE (doc-verified): `--since` does
   not exist yet; implement it as the eval's first step (tiny, one awk guard in
   _rows) or filter by date manually , the design pins the WINDOW, not the flag.
2. Pull metrics 1-3, 5, 9 from `report` + `misfires` verbatim (no hand counting).
3. Metrics 4, 7, 8, 10: one awk pass over `logs/runs/*.log` + `ship-gate.log`
   (commands recorded in the run when executed, so the eval is reproducible).
4. Metric 6: read the Review sections of every spec shipped in the window.
5. Write the report to `docs/retro/EVAL-<date>-telemetry.md` with one disposition
   line per unhealthy metric: (a) fix + pin, (b) board row, or (c) accepted noise
   , the SPEC-061 retro disposition contract, applied to the measurement layer
   itself.

### Acceptance criteria (for the EXECUTION, later)

- AC1: every metric has a number + threshold verdict + disposition line.
- AC2: zero hand-counted numbers (every figure traces to a command in the report).
- AC3: at least one decision changes as a result (a rule, a matrix cell, a
  threshold, or an explicit "measurement layer is ceremony-free, keep") , an eval
  that cannot change anything was not an eval.

### Trigger

The operator says "run the telemetry eval" OR the next `/kit:retro` lands 3-5+
days after #55 merges, whichever first. The retro's Step 1d sweep then uses this
design instead of improvising.

## Verification (of this design doc)

Doc-verified 2026-06-11: every named surface checked against live code; two
overclaims found and corrected (--since flag, escapes subcommand). Remaining
claims verified: report/misfires/trace exist, ship-gate.log exists, retro Step 1d
exists, no parser consumes the Type loops cell.

Meta pins: the doc exists with the metrics table + parked status + an honest
data-window note (no phantom flags).

## Review

Date: 2026-06-11. Single doc-verifier lens (no machinery touched). Verdict:
FAIL:fixable -> 2 overclaims corrected in-branch (--since flag did not exist;
escapes was not a subcommand) -> re-verified clean. SHIP.
