# RUN_REPORT: gate-review-absorptions

**Run date:** 2026-07-04 · **Mode:** subagent-delegate (thin conductor) · **Merge:** auto-bottom-up, gated-final
**Outcome:** 6/6 sub-goals BUILT. 4 merged (01, 02, 05, 06). 2 HELD for Han's gated-final review (03 gate + 04 final). Convergence machine-demos GREEN; the one human demo (a real pl-gate review) is the held gate itself.

## Objective vs delivered

| Objective clause | Delivered | State |
|---|---|---|
| Human gates get a surface (plannotator `--gate --json` trial) | `pl-gate` wrapper, verified pinned install (v0.21.4, checksum + SLSA attestation), fail-open NC proven, decision JSON -> gate-ledger line | 03 #698 HELD (live trial = the gate) |
| Reviews get a memory (rejected-findings ledger + `findings=/rejected=` emit) | per-repo `docs/verification/rejected-findings.md` + pre-flag surface-not-suppress + emit grammar parsed by kit_gates | 02 #173 merged |
| Observatory prices lens false-positives (`review-yield`) | `rejected_findings` adapter + `review-yield` FP-rate query, per-run denominator, `approx=true` labeled | 04 #701 HELD (final) |
| Stale-ADR inversion lands | two-sided rule byte-identical in advisor.md / review.md / review-team.md, `stale-adr:` finding-key | 01 #172 merged |
| Gate-deny triage-first contract + measurement principles land | OPERATE.md deny contract + n-rule; counterfactual-same-row + honest-negative in the observatory design trail | 05 #697 merged |
| Advisor P5/P6 become first-class ledger rows | `advisor` rows (`mode=P5|P6 findings=N`) from review-team Step 2b + a mega.md convergence-gate dispatch step | 06 #174 merged |

No gate-REQUIREMENT changed anywhere: every deliverable is a surface, a memory, or an emit. The wrapper is OPTIONAL; the memory is fail-open; the emits are observability.

## Timeline (relative minutes; two parallel per-repo lanes)

```
        0    10    20    30    40    50    60    70   76
        |----|----|----|----|----|----|----|----|---|
kit 01  ⣿⣿⣿⣿⣿⣷                                         #172 ✓ (0->10)
kit 02        ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷                              #173 ✓ (14->38)
kit 06                        ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷           #174 ✓ (40->71)
ops 05  ⣿⣿⣿⣷                                            #697 ✓ (0->6)
ops 03        ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷                          #698 ⏸ (10->42)
ops 04                          ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷           #701 ⏸ (46->75)
demoC                                              ⣿    conv review (75->76)
ghost·· ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  critical path = 01->02->06 (kit) ‖ 05->03->04 (ops)
```

⣿ active worker · ⏸ built-then-held · ghost lane = the dependency-forced critical path (one worker per lane at a time; kit tail 06 and ops tail 04 set the ~76-min wall-clock).

## Worker minutes by model (all sonnet)

| Sub-goal | Model | Wall-min | Tokens | Lane | PR |
|---|---|---|---|---|---|
| 05-ops-contracts | sonnet | 6.1 | 182,550 | tiny | #697 merged |
| 01-stale-adr | sonnet | 9.9 | 202,940 | normal | #172 merged |
| 02-findings-mem | sonnet | 23.5 | 287,307 | full | #173 merged |
| 04-review-yield | sonnet | 28.7 | 381,610 | full | #701 held |
| 06-advisor-vis | sonnet | 31.0 | 385,347 | full | #174 merged |
| 03-pl-gate | sonnet | 32.5 | 322,575 | normal | #698 held |
| demo-C reviewer | sonnet | 0.7 | 58,827 | (convergence) | n/a |
| **Total** | | **~132.4** | **~1,821,156** | | 4 merged · 2 held |

Wall-clock ~76 min against ~132 worker-min = the two lanes overlapped ~1.7x. No worker kills this run (all in-harness subagents; the one stale re-notification was a leftover `find /` sweep, not a worker death).

## Gate coverage matrix

| Sub-goal | lane | gates recorded | overrides (audited) |
|---|---|---|---|
| 01 | normal | spec, build, ship | ship (lead-owned CHANGELOG/VERSION) |
| 02 | full | spec, validate, test-plan, build, review, docs, ship |, |
| 05 | tiny | (docs) | proof (docs-only, no behavioral claim) |
| 06 | full | spec, validate, test-plan, build, review, docs, ship, reflect | design, design-critique (obvious wiring) |
| 03 | normal | spec, build, ship |, |
| 04 | full | think, design, design-critique, spec, validate, design-record, test-plan, build, review, docs, ship, reflect |, |

## Callable-stack tree

```
dwarves-kit  master
  └─ 01 stale-adr-inversion    #172  ✓ merged e54397b  (SPEC-143)
     └─ 02 review-findings-mem #173  ✓ merged 0904e74  (SPEC-144, over-test)
        └─ 06 advisor-visibility #174 ✓ merged b628549  (SPEC-145)
ops-toolkit  main
  └─ 05 ops-contracts-batch    #697  ✓ merged 4400fce
     └─ 03 plannotator-gate-trial #698 ⏸ HELD (gate; live trial = the review)
        └─ 04 review-yield-lens  #701 ⏸ HELD (ops-stack final; tool-local SPEC-137)
```

## Convergence demos (machine-verifiable, GREEN)

- **Demo B, review-yield on real ledgers:** `dwarves-kit/architecture n_rejected=1 raised=4 fp_rate_approx=0.25 approx=True low_n=True`; ops-toolkit honestly zero rows. Emitter (02) -> adapter (04) -> query connects end-to-end on the assembled tree.
- **Demo C, live review dispatch (kit:code-reviewer over a combined fixture), all three in ONE pass on ONE rid:**
  - (A) `stale-adr: ADR-0100:3 claims "at most 3 times", retry.go:3 does MaxAttempts = 5`, fresh, HIGH.
  - (B) `bare-recover:notify.go` -> surfaced "previously rejected 2026-06-20: intentional fail-open", NOT re-raised (pipe-anchored whole-key match).
  - (C) `sql-injection:notify.go` novel on the SAME file as (B) -> fired FRESH (proves the memory mutes only on whole finding-key, never file-alone).
  - SG-02 emit landed live: `... | review | ran | CHANGES_REQUESTED findings=2 suppressed=0 rejected=1 actor=Han Ngo` (exit 0).
- **Demo A, a real pl-gate human review:** PENDING. This IS the held gate on #698; running it is Han's live trial.

## Load-bearing negative controls (all proven by deliberate break, red -> restore -> green)

- **02 novel-finding-still-fires:** file-path-only match wrongly suppressed a novel SQL-injection (RED); whole-key match restores it (GREEN). Also caught+fixed a real substring-collision bug (`except` vs `bare-except`) via pipe-anchoring.
- **03 fail-open:** removing the `jq -e .` guard turned exactly bats test 5 RED; restore -> 11/11 green. Missing binary / non-zero exit / malformed JSON / unrecognized decision / `dismissed` all -> visible warning + manual fallback + NO ledger write.
- **04 honest-zero:** reversing the JOIN + `NULL`->`0.0` fabricated a bogus all-null row from zero data (RED); restore -> `[]` (GREEN), source byte-identical.
- **06 honest-zero + emit-failure-never-blocks:** a rid with no advisor dispatch renders `advisor_rows=0` (never fabricated); a `chmod 555` ledger dir -> warning + exit 0, review unaffected.

## Totals / lessons

- 6 sub-goals, 7 dispatches, all sonnet, ~1.82M worker tokens, ~132 worker-min / ~76 wall-min.
- 4 PRs merged (CI green on every runner that applies), 2 held for the gated-final review.
- SPECs: dwarves-kit 143/144/145 (conductor-reserved up front) + ops tool-local 137 (ledger-observatory namespace).
- Green-field identity plumbing shipped while cheap: `actor=<git user.name>` on every new emit grammar (02, 03, 06) per the advisor-P6 pre-launch decision.
- Honest adaptation, not spec-worship: 03 found plannotator's real decision schema is 3-way (`approved`/`annotated`/`dismissed`), not the sketched 2-way, and mapped `dismissed`->fail-open rather than fabricate a denial. 06's advisor-critique lens caught a real `$RID`-doesn't-survive-to-convergence bug and switched to a static final-sub-goal rid.
- Never-diverge check paid off backwards: 06's mega.md beat was already in the ops `plan-for-mega-goal` skill verbatim (landed same day), so no dotfiles mirror was needed, verified, not assumed.

## What remains (Han's gate)

1. Live pl-gate trial on #698's own held diff (the self-referential trial); record the verdict paragraph + the low-n baseline number in `experiments/plannotator-gate/README.md`.
2. iPhone-over-Tailscale phone checkpoint (honest reachability note).
3. On an ADOPT verdict: merge the ops stack bottom-up (#698 then #701), which also lands this RUN_REPORT, the ROADMAP flips, and the LAB_LOG entry on main. On PARK: close per the README's park reasons; 04 can be retargeted to main and merged independently (no semantic dep on 03).

## Post-close update (2026-07-05)

The gate resolved. Han's verdict: **PARK the plannotator binary, KEEP the `pl-gate` pattern** (wrapper + ledger-emit stay as the validated, swappable surface); mega merge policy left as `gated-final`. The two live pl-gate trials (on the #698 diff, then the README) both returned a non-decision (`dismissed` / killed), so the fail-open path was proven twice with the real binary but no approve/deny UX datapoint was captured; the verdict is argued from mechanics + costs, recorded in `experiments/plannotator-gate/README.md` (e).

Both held PRs then merged (03 #698 -> e79ae40, 04 #701 -> 3b2221e), so **all 6 sub-goals are on `main`**. Stacked-merge conflicts were confined to the append-only index files + the README verdict divergence, resolved keeping both this run's and the parallel `runner-fastpath` session's entries. Worktrees + stale branches cleaned.

**Deferred (one item):** OPERATE co-location of this completed mega folder to `_meta/megagoals/_archive/` is NOT done yet, because the active `runner-fastpath` mega references this folder's path as a live dependency (its SG-05 unparked on 04's merge; its POINTER/HANDOFF/ROADMAP point at `gate-review-absorptions/ROADMAP.md`). Archive-move + ref-fix should run once runner-fastpath settles, to avoid dangling its live paths.
