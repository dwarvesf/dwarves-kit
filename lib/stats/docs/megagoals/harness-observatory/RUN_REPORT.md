# RUN_REPORT , harness-observatory mega-goal

> **Post-close (Han-approved):** both held PRs were approved and MERGED to `main` , #690 (SG-05, privacy gate) then #692 (SG-06, was #691, rebased onto main after #690 merged and the auto-closed #691 superseded). All 6 sub-goals are now on `main`; cockpit rows ID-245/248/251/255/260 flipped to shipped. The NEEDS-APPROVAL banner below is the pre-merge state, retained as the historical record.


**Objective (met):** close the OBSERVATORY half of the harness benchmark loop , gate-yield,
defect-correlation, deviation-rate, the numeric-only sessions/safety planes, the memory-hygiene
lens, and the `ledger digest` north-star scorecard, all running on REAL data.

**Terminus:** non-deployable local CLI lens. Build + merge IS the terminus, closed by the PAYOFF
RUN (the first real benchmark scorecard, below). 4 sub-goals merged to `main`; 2 HELD for Han
(the SG-05 privacy gate + the SG-06 final PR). Run mode: subagent-delegate, thin conductor,
strictly serial stacked chain (every sub-goal touches `tools/ledger-observatory/**`).

---

## Timeline (serial chain; wall-clock, newest at bottom)

```
        01  02  03  04  05  06                    model   min   PR     state
SG-01  ⣿⣿⣿·································· sonnet  ~21   #683   merged
SG-02  ····⣿⣿⣿⣿····················· sonnet  ~32   #684   merged
SG-03  ········⣿⣿⣿⣿················· sonnet  ~37   #687   merged
SG-04  ············⣿⣿⣿⣿⣿·········· sonnet  ~49   #688   merged
SG-05  ·················⣿⣿⣿⣿⣿····· sonnet  ~56   #690   HELD (gate)
SG-06  ······················⣿⣿⣿⣿⣿⣿ sonnet ~142*  #692   HELD (final)
        └─ actual: strictly serial (shared tool files) ────────────────┘

ghost   ⣿⣿⣿                                        wavefront projection (if file-partitioned):
wave    ····⣿⣿⣿⣿ ⣿⣿⣿⣿⣿(05) ⣿⣿⣿⣿⣿⣿(06)          01 → {02,05,06 parallel} → {03,04}
        ········⣿⣿⣿⣿(03) ⣿⣿⣿⣿⣿(04)              projected wall-clock ~½; NOT taken because
                                                    all six mutate tools/ledger-observatory/**
```

`*` SG-06's 142m spans a mid-run monthly-spend-limit KILL + resume + a docs-reconcile pass +
interleaved conductor recovery; its pure build was ~50m. The serial chain was a deliberate
correctness choice (one writer per shared tree), not a scheduling failure.

## Worker minutes + tokens by model

| Model | Sub-goals | Wall min | Subagent tokens | Tool uses |
|---|---|---|---|---|
| sonnet | 01,02,03,04,05,06 | ~337 (5.6h) | ~2.57M | 1144 |
| **totals** | **6** | **~337 worker-min** | **~2.57M** | **1144** |

Conductor (opus, this session): verification re-runs + merges + the SG-06 recovery + this close.
One infra incident (below) cost a multi-turn hard stop.

## Gate-coverage matrix (recorded per rid via gate-ledger.sh)

| gate           | 01 | 02 | 03 | 04 | 05 | 06 |
|----------------|----|----|----|----|----|----|
| grill          | s  | s  | s  | .  | .  | .  |
| think          | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| design         | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| design-critique| .  | .  | .  | ✓  | ✓  | ✓  |
| design-record  | .  | .  | .  | ✓  | ✓  | ✓  |
| spec           | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| validate       | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| test-plan      | .  | .  | .  | ✓  | ✓  | ✓  |
| build          | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| review         | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| docs           | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| ship           | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  |
| reflect        | ✓  | ✓  | ✓  | ✓  | o  | ✓  |
| lane           | normal | normal | normal | full | full | full |

✓ ran · s skipped (honest: home-turf, few unknowns) · o override · . not required for lane

## Callable-stack tree (what the loop built, one tool)

```
tools/ledger-observatory/  (read-only DuckDB lens; delete-and-rematerialize contract)
├── schemas.py      single-sourced (name,type) specs + assert_parity guards
├── adapters.py     read_kit_gates · read_git_fixes · read_impl_notes · read_sessions
│                   · read_safety · read_memories        (all pure reads, skip-safe)
├── materialize.py  rebuild -> DuckDB tables
├── anomalies.py    unknown_density · ceremony · token_runaway · serial_when_parallel
│                   · memory_hygiene           (PROPOSE-only, never auto-files)
└── cli.py  ledger { rebuild · tables · show · query · gate-yield · defect-correlation
                    · deviation-rate · anomalies · digest · memory-sweep }
```

---

## THE FIRST REAL BENCHMARK SCORECARD (payoff run, live ledgers, 2026-07-04)

**Materialized:** `kit_gates` 748 · `git_fixes` 9643 · `impl_notes` 233 · `sessions` 6710 ·
`safety` 5302 · `memories` 248.

### north-star digest (`ledger digest`)

| metric | value |
|---|---|
| sessions | 6,710 |
| input / output tokens | 130.9M / 207.8M |
| cache-read tokens | 44.2B |
| tool calls | 60,950 |
| errors | 4,262 |
| compactions | 58 |
| canary-drops (long-session drift) | 3,818 |
| shipped rids | 67 |
| bridged rids / coverage | 0 / 0.0% (honest-empty; see below) |
| cost-per-verified-outcome | null (no rid bridges on this corpus yet) |

### gate-yield (ceremony detector, real gate ledger)

| gate | ran | override | skipped | caught | override% |
|---|---|---|---|---|---|
| grill | 10 | 0 | 45 | 0 | 0.0 |
| spec | 80 | 2 | 0 | 0 | 2.4 |
| build | 80 | 1 | 0 | 0 | 1.2 |
| review | 68 | 1 | 3 | 0 | 1.4 |
| ship | 69 | 1 | 0 | **1** | 1.4 |
| test-plan | 49 | 3 | 4 | 0 | 5.4 |
| ui-design | 0 | 1 | 6 | 0 | 14.3 |

`ship` now carries the first real `caught=1` OUTCOME signal, so the **ceremony detector correctly
ABSTAINS at the default threshold** , the FP-negative-control working on live data, not a fixture.

### defect-correlation · deviation-rate · memory-lens (real)

- **defect-correlation:** ops-toolkit 0 rows; dwarves-kit 2 `fix-followed` (rid `dag-wavefront`,
  later `fix()` on `_meta/BACKLOG.md`). Honest yield: only ~1 of ~600 rids bridges by name today.
- **deviation-rate:** ops-toolkit 125 UNDER-SPECCED / 108 OTHER / 0 CLEAN / 0 SUSPECT (no
  zero-markers in the corpus yet; classifier proven correct on fixtures).
- **memory-lens:** 248 memories, **33 carrying dead refs (58 total)**; top: `hermes-family-topology`
  5, `trading/feedback_config_file_deletion` 5, `ops-toolkit/MEMORY` **3 (the MIGRATED tombstones,
  the goal-file-predicted catch)**. The `claude-guardrails` MEMORY prose-scratchpad correctly flags
  **0** (DEC-010 IS-IT-AN-INDEX gate, was a 39-orphan false positive). Hygiene anomaly honestly
  below the 0.15 default (13.3%); fires at a tuned 0.10-0.13 , mechanism live.
- **anomalies (default thresholds):** `unknown_density` + `token_runaway` fire; `ceremony`
  correctly abstains (ship caught=1).

### load-bearing negative controls (all green + falsifiable)

| sub-goal | NC | verdict |
|---|---|---|
| 01 | ceremony FP: a legit-skipped gate reported, not dropped/mislabeled | PASS, falsifiable |
| 02 | clean run with no later fix NOT flagged | PASS, falsifiable |
| 03 | honest-zero (zero-marker + no fix) = CLEAN, never SUSPECT | PASS, falsifiable |
| 04 | ceremony FP: reason-coded skips not proposed for cutting | PASS, falsifiable |
| 05 | **privacy: `FAKE-SECRET-a1b2c3` provably ABSENT from every materialized column** | PASS, falsifiable (independently re-scanned by conductor) |
| 06 | **never-delete: every memory file byte-identical after the sweep** | PASS, falsifiable |

---

## Totals

- **6/6 sub-goals shipped.** 4 merged to `main` (#683 #684 #687 #688); 2 HELD for Han (#690
  privacy gate, #692 final). SPEC-131..136 in the tool namespace.
- **Tests:** 266/266 across 10 green observatory suites (memory-lens 39/39). Two pre-existing
  `kit_runs`/`lane-telemetry.sh` bash-3.2 failures (`test-feedback` 30/9, `test-ledger-cli` 19/7)
  documented + untouched, root-caused by SG-04.
- **Every sub-goal over-tested** with a falsifiable load-bearing NC. A benchmark that lies is worse
  than none , so guardrails-39 (a stale pre-DEC-010 number my recovery briefly carried) was
  reconciled to the true 0 before this report.

## Lessons (non-obvious, for the ledger)

1. **Cross-mega collision on shared host state.** The sibling `kit-absorptions` mega deployed a
   syntactically-broken `secret-guard.sh` onto the shared `~/.claude/hooks/` surface mid-run; a
   line-1439 bash parse error gated EVERY Bash/Read/Edit until Han fixed it. The two runs' repos
   were disjoint but their HOOK surface was not. Serialize hook-touching runs, or the "disjoint"
   assumption is false.
2. **Checkpoint discipline paid off exactly as promised.** SG-06's worker was killed mid-tail by a
   monthly spend-limit; it had committed 6 phase boundaries, so the work was fully recoverable
   from git state. Resume + reconcile produced the correct DEC-010 result; the conductor's parallel
   recovery was harmlessly superseded.
3. **The real corpus corrects the fixture.** SG-06's three biggest design fixes (DEC-008/009/010,
   135 flagged units -> 33, ~80% junk removed) came from the FIRST real `memory-sweep`, not from
   either review pass. Probe real data before trusting the spec's shape.
4. **Emitter-before-reader is real.** `ship caught=1` appeared in the live ledger during THIS run,
   flipping the ceremony detector from "fires on everything" to "correctly abstains" , the loop
   observing its own tail close.
