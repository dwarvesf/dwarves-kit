# Telemetry + feedback-loop + proof-of-done effectiveness eval (SPEC-073, executed)

Date: 2026-07-02
Executes: SPEC-073 (design VALIDATED 2026-06-11, parked for real data)
Board: dwarves-kit ID-067; kit-telemetry mega-goal SG-02
Corpus: 10 run ledgers at the durable path (SG-01 migrated:
`${XDG_STATE_HOME:-~/.local/state}/dwarves-kit/logs`) = 8 `kit-harden-*` + `kit-telem-01-ledger`
+ `plugin-native-operate-contract`; plus `ops-toolkit/research/2026-07-02-process-effectiveness-audit.md`
(the 60-day proof/review evidence, CONSUMED not re-derived).

## Question under evaluation (SPEC-073)

Is the kit's measurement layer (lane telemetry SPEC-061/062, run legibility SPEC-063,
proof-of-done) actually closing the loop, does recorded data change decisions, or is it
ceremony?

## Data window (SPEC-073)

All 10 corpus runs are post-#55 (earliest ledger `plugin-native-operate-contract`
2026-07-01T14:23Z; the 8 kit-harden runs 2026-07-02T06:05-07:35Z; `kit-telem-01-ledger`
08:43-09:08Z), so the #55 window includes every run. N is small (10 runs, only 1 with a
START line), so several metrics resolve to an **honest null** (SPEC-073's "criterion not
measurable at N beats a vibes verdict"). The `--since` flag SPEC-073 flagged as absent is
still absent and unneeded here (the whole corpus is in-window).

## Per-criterion verdicts

Every figure traces to a command (SPEC-073 AC2); commands listed under the table.

| # | Metric | Number (source) | Threshold | Verdict | Disposition (cited) |
|---|--------|-----------------|-----------|---------|---------------------|
| 1 | lane misroute rate | 0 of 1 tracked run misrouted; 9/10 untracked so unmeasurable (`report` headline `lane-misrouted: 0`) | <15% | **NULL (not measurable)** | N=1 tracked run; no rule action. Root cause is metric 3, not routing. Re-run after ≥5 START-tracked runs exist. |
| 2 | type misroute rate | 0 of 1 (`report` `type-misrouted: 0`) | <15% | **NULL** | same as #1. |
| 3 | untracked-run rate (gates, no START) | **9/10 = 90%** (`report` `untracked (no START): 9`) | <10% | **UNHEALTHY (dominant finding)** | NEW runs, not mirrors -> "assign wiring failed" branch. The kit-harden execution recorded gates via `record` but never called `gate-ledger.sh start`. Fix: the mega/execute path must emit `start` per sub-goal. **-> board row (fix, kit).** |
| 4 | gate skip rate per lane×phase | 8 `grill skipped` (expected: tiny/lite-lane intake) + tail phases thin (test-plan 4/9, design 2/9), all on untracked "?" lanes (`awk` over runs) | no phase chronically >50% skipped WITHIN a lane | **NULL (lane unknown)** | can't attribute a skip to a lane when 9/10 runs have no START. Unblocked by fixing #3. `grill skipped` is legitimate (SPEC-058 tiny-exempt), not a defect. |
| 5 | override count | **11 overrides, all one run, one identical reason** (`awk`: `plugin-native-operate-contract :: "docs-only draft spec..."` ×11) | ~0 | **UNHEALTHY -> ALREADY FIXED** | This IS the blanket override ID-082 named. **SG-01 (PR #112) now rejects it** (`override` exit 65 on a reason reused across gates). Closed-loop: the eval's worst finding is the one this wave already fixed. |
| 6 | review findings curve (multi-lens vs single) | multi-lens keeps finding disjoint classes (audit Miner B: SPEC-028 3 layers/3 distinct catches; token-optim-v3 round-2 caught a regression round-1 fixes introduced; SG-01 here: security lens found 2 PoC'd BLOCKERs arch+coverage missed) | multi-lens keeps paying; always-0 lens = dull | **HEALTHY** | keep the SPEC-069 lib/hooks multi-lens escalation. No lens observed always-0. Evidence: audit lines 18, 26, 89 + this run's review section. |
| 7 | escaped-defect rate | 0 `escaped-from` markers in corpus (`report` has no escaped-defect section) | trending down | **NULL (no bug runs yet)** | no debug/bug runs in the corpus to trace. Re-check once a bug run indicts a shipped spec. |
| 8 | proof-of-done friction | 5 proof-gate BLOCKED + 2 ship-gate BLOCKED in ~36h, all true positives (audit line 22/89; `ship-gate.log`) | blocks are true positives | **HEALTHY (forcing function)** | proof-of-done works AS A GATE TOKEN, read once at the push it justifies; no evidence of post-merge re-reads (audit line 22). Keep as gate; do not expect it to be a re-read document. |
| 9 | boardless + shipped-incomplete | boardless: 1 (`kit-telem-01-ledger`); shipped-incomplete: 1 (`kit-telem-01-ledger`, full) (`misfires`) | 0 boardless; shipped-incomplete only with retro-note | **UNHEALTHY (2 detector edges)** | (a) boardless: the rid `kit-telem-01-ledger` is not a literal string in its board row (row keys on `ID-082`/`PR #112`), so the detector false-flags a tracked run. (b) shipped-incomplete: a full-lane NON-UI change leaves the `ui-design` (lite) phase un-disposed, tripping the detector. **-> board rows (2 detector refinements, kit).** |
| 10 | full-lane ceremony cost on kit-machinery | dwarves-kit median 34.9% process lines/PR vs ops-toolkit 83.8%; reviews still catching HIGHs at this size (audit Miner C, line 104-106; SG-01 security BLOCKERs) | reviews keep catching HIGHs | **HEALTHY (no carve-out warranted)** | full-lane on kit-machinery still yields real catches (SG-01: 2 security BLOCKERs on a ~500-line diff). Do NOT carve out a lighter lane for small machinery diffs yet. |

### Commands (SPEC-073 AC2, zero hand-counted numbers)
```
bash lib/telemetry/lane-telemetry.sh report        # metrics 1,2,3,4(headline),5(count),9,10-denominator
bash lib/telemetry/lane-telemetry.sh misfires      # metric 9 (boardless + shipped-incomplete + downgrades)
awk -F' [|] ' '$2=="GATE"{print $3" "$4}' runs/*.log | sort | uniq -c   # metric 4 per-phase
awk -F' [|] ' '$2=="GATE"&&$4=="override"{print FILENAME" "$5}' runs/*.log | uniq -c  # metric 5
```
Metrics 6, 8, 10 cite `ops-toolkit/research/2026-07-02-process-effectiveness-audit.md`
(lines 18, 22, 26, 89, 104-106) + `ship-gate.log`, per SPEC-073's "where the ops audit
already answered a criterion, cite and move on."

## Bonus finding (not a SPEC-073 metric): completeness.log fixture pollution

`misfires` shows 9 identical `LANE-CHECK downgrade ... "add user authentication with jwt
sessions"` lines in the real `completeness.log`. That string is a TEST FIXTURE
(test-lane-escalation / test-hooks); those writes reached the real durable log because some
lane-classify `check` invocations ran without `DWARVES_KIT_LOG_DIR` set. This is telemetry
hygiene noise, not 9 real misroutes. **-> board row (tests must always set
`DWARVES_KIT_LOG_DIR`; or `check` should no-op its write when stdout is not a TTY / under a
test guard).**

## SPEC-073 execution acceptance criteria

- **AC1 (every metric has number + threshold verdict + disposition):** met, table above.
- **AC2 (zero hand-counted numbers):** met, every figure cites a command or an audit line.
- **AC3 (at least one decision changes):** met, multiple:
  1. Ban blanket overrides, DONE in SG-01 (metric 5).
  2. Emit `gate-ledger start` per sub-goal in the mega/execute path (metric 3), board row.
  3. Refine the boardless + shipped-incomplete detectors (metric 9), board rows.
  4. Stop test fixtures polluting the real completeness.log (bonus), board row.
  And a KEEP decision: the review stack + proof-as-gate are ceremony-free, keep (6, 8, 10).

## Ranked fix list (impact-ordered, for board intake)

1. **[HIGH] `start` wiring**, 90% untracked-run rate blinds metrics 1/2/4/7. The mega/
   execute path must call `gate-ledger.sh start <rid> <lane> <classified> <type>` per
   sub-goal. Until then, lane/type/skip telemetry is unmeasurable. (metric 3)
2. **[MED] boardless detector: match the run to its board row by PR/ID, not raw rid**, a tracked run is false-flagged today. (metric 9a)
3. **[MED] shipped-incomplete: treat lite phases (ui-design on non-UI work) as disposed**, or require an explicit `ui-design skipped` record for non-UI full-lane runs. (metric 9b)
4. **[LOW] test-fixture pollution of completeness.log**, tests must set
   `DWARVES_KIT_LOG_DIR`. (bonus)
5. **[none] KEEP**, review stack (6), proof-as-gate (8), full-lane on machinery (10),
   dispatch (audit line 26): ceremony-free, no change.

## Honest limits

Small N (10 runs, 1 START-tracked), single window, LLM-over-records like the parent audit.
The dominant finding (metric 3) is itself the reason the finer metrics can't yet be judged;
once `start` fires per sub-goal, re-run this eval on a START-complete corpus. The proof/
review/dispatch halves rest on the parent audit's evidence, which is a judge-over-records
audit, not a controlled A/B (audit line 48).
