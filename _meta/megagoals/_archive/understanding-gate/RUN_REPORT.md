# RUN REPORT , understanding-gate mega-goal

**Run date:** 2026-07-03 -> 2026-07-04 · **Work repo:** `dwarvesf/dwarves-kit` · **Mode:** subagent-delegate (thin conductor)
**Outcome:** 6 sub-goals built + verified. 5 merged to master; SG-06 (docs) HELD as the final PR for Han. TIER-4 close surfaced one real cross-sub-goal bug , fixed, merged, re-verified. **Terminus reached: build + merge + held final PR.**

## Gate zero
ADR-0031 (understanding gate) verified **Accepted** (dwarves-kit #146) before any code. This run EXECUTED the ADR; it did not re-decide it.

## PRs (audit target dwarvesf/dwarves-kit)

| PR | Sub-goal | Spec | Model | State | NCs |
|----|----------|------|-------|-------|-----|
| #149 | 01 design-record | SPEC-122 | sonnet | merged `8c1f13e` | refuse-empty · obvious-collapse |
| #148 | 02 significance-classifier | SPEC-123 | sonnet | merged `ce880ce` | anti-fatigue-wave · impl-note-feed · determinism (6) |
| #150 | 03 /kit:explain | SPEC-124 | opus | merged `2cb2238` | grounded-in-diff (load-bearing) |
| #151 | 04 quiz-gate | SPEC-125 | opus | merged `c3de8e7` | grounded · wiring · never-must-pass (6) |
| #152 | 05 weekend-batch | SPEC-126 | sonnet | merged `77815c2` | already-paid-excluded · skill-reuse |
| #154 | TIER-4 fix: debt-ledger seam | , | sonnet | merged `220abd8` | mark-paid-exits-0 · reason-injection RED->GREEN |
| **#153** | **06 docs-wiring** | **SPEC-127** | **sonnet** | **HELD (final)** | **over-claim** |

## Timeline (relative wall-clock; ⣿ = active worker-minutes)

```
WAVE 1  parallel  {01,02,03}
  01 design    sonnet ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿ 24.1m  #149
  02 signif    sonnet ⣿⣿⣿⣿⣿⣿⣇       13.4m  #148
  03 explain   OPUS   ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇  23.7m  #150
                  └ integrate: SPEC-122 3-way collision -> 122/123/124; #148 dropped-renumber repaired at #150
WAVE 2  parallel  {04,05}
  04 quiz      OPUS   ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇   21.7m  #151
  05 weekend   sonnet ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿ 24.4m  #152 (+ dotfiles skill)
                  └ integrate: gate-ledger debt-verb seam auto-merged; both suites re-run green
WAVE 3  final     06
  06 docs      sonnet ⣿⣿⣿⣿⣿⣿⣿⣿⣇     18.6m  #153 HELD
                  └ no-orphan sweep caught a REAL over-claim (record verb) + wired 4 orphan CI tests
TIER-4  parallel  5 lenses (read-only)
  integ-verify OPUS   ⣿⣿  4.0m   PASS (objective satisfied end-to-end)
  security     OPUS   ⣿⣿  4.3m   SECURE + 1 LOW
  architecture OPUS   ⣿⣿⣇ 5.0m   HIGH: debt-ledger seam (reproduced)
  test-cover   sonnet ⣿⣿  4.5m   8/10 (5/6 NCs mutation-confirmed)
  advisor      OPUS   ⣿   3.0m   #1 seam + #2 record-orphan + 6 over-suggests
FIX     serial    debt-ledger response seam
  fix          sonnet ⣿⣿⣿⣿⣿⣿⣇     14.5m  #154 merged
                  └ conductor reproduced exit-64 live; fix re-verified (mark-paid exits 0)
```

Ghost lane (ideal wavefront, no rework): waves 1->2->3 would close at ~24+24+19 = ~67 worker-min critical path; actual added a ~14.5m fix loop after TIER-4 (the seam the parallel builds could not see per-sub-goal). The rework was the point of TIER-4, not a miss.

## Worker-minutes by model

| Model | Workers | Minutes |
|-------|---------|---------|
| opus | 03, 04, integ-verify, security, architecture, advisor | ~61.7 |
| sonnet | 01, 02, 05, 06, test-coverage, fix | ~99.5 |
| (probe) | worktree-repo probe | 0.2 |

Model routed by each sub-goal's `Model:` header (opus for the two widest builds 03/04 + the deep TIER-4 judgment lenses; sonnet for execution-dominant + mechanical).

## Gate-coverage matrix (lane -> gates recorded per sub-goal)

| SG | Lane | Gates recorded (per-gate reasons in each run's ledger) |
|----|------|--------|
| 01 | normal | think·spec·validate·design-record·test-plan·build·review·docs·ship |
| 02 | full | grill·think(ovr)·design·spec·validate·test-plan·build·review(multi-lens SPEC-069)·docs·ship |
| 03 | normal | grill·think·spec·test-plan·build·review·docs·ship |
| 04 | full | grill·think·design·spec·design-critique·validate·design-record·test-plan·build·review(multi-lens)·docs·ship·reflect |
| 05 | normal | grill·think·spec·design-record·test-plan·build·review·docs·ship |
| 06 | normal | spec·design-record(obvious-collapse)·test-plan·build·review·docs·ship |
| fix | full | think·design·spec·validate·design-record(ovr)·test-plan·build·review·docs·ship |

Every merge gated on: PR CI green **and** a local re-run of the ENTIRE CI suite + the new tests against the integrated tree. Master never went red across 7 merges.

## Callable-stack tree

```
conductor (thin, in-harness subagents; shared auth = no claude -p kill/auth class)
├─ probe (worktree-repo origin)               , confirmed isolation cuts from ops-toolkit, not dwarves-kit
├─ WAVE 1  01 · 02 · 03                        , parallel, own dwarves-kit worktrees
├─ WAVE 2  04 · 05                             , parallel
├─ WAVE 3  06                                  , final, held
├─ TIER-4  integ-verify · security · architecture · test-coverage · advisor   , parallel, read-only
└─ FIX     debt-ledger-response-seam           , serial remediation of the TIER-4 HIGH
```

## The TIER-4 finding (why the fix loop existed)

The debt ledger had two writers with incompatible line shapes: SG-02's classifier writes a FAT line (significance/worthiness/verdict), SG-04's live `quiz-gate respond` writes a THIN line (`response=` only). The reader (SG-05 weekend-batch, last-line-wins) read sig/wor/verdict off the last line -> empty on any human-responded item -> `mark-paid` re-emitted through the fat `debt` verb -> validator rejected (exit 64). The **default live path** was broken, masked because the test hand-seeded fat lines. Three lenses converged; the conductor reproduced it live. Fix (#154): `debt-response` forward-carries the classification; `mark-paid` closes via `debt-response engage`; readers walk back for display; `reason=` can no longer smuggle a control key; + the true end-to-end respond->collect->mark-paid regression test. This is exactly the cross-sub-goal seam TIER-4 exists to catch.

## Totals

- **7 PRs** (6 merged, 1 held) · **8 spec numbers** (122-127 + the fix) · **~5,183 net insertions** across 50 files.
- **~2.39M** subagent output tokens across **13 dispatches** (6 builders + 1 fix + 5 TIER-4 lenses + 1 probe).
- **Full CI (24 wired suites) green** in the final assembled state; 4 previously-unwired understanding-axis tests now CI-gated.

## Held for Han (see the chat close + NOTES `## Proposed additions`)

1. **Merge PR #153** (the held final docs PR) when ready , it declares the axis honestly and is green.
2. **Reconcile the 2 dotfiles halves** , applied+functional locally, on branches `feat/ug-01-design-record` (`27a21e1`, subgoal-template Design field) + `feat/ug-05-weekend-batch` (`3b4c468` weekend-debt-paydown skill, `f18d950` portable OPERATE). NOT pushed: local dotfiles `main` diverged from `origin/main` #193 (which restructured the same skills), so a clean cherry-pick conflicts. A source-of-truth reconciliation left for Han.
3. **The headline design decision (NOTES #1):** wire `significance-classify record` at `/kit:ship` , the fat-line writer is currently un-wired, so the "silent wave, but LOGGED" half of the debt budget is never produced live. Deliberately deferred from the fix (a direction decision , fittingly the kind the understanding gate exists to gate). The seam fix already makes the ledger forward-carry so context flows once `record` is wired.
