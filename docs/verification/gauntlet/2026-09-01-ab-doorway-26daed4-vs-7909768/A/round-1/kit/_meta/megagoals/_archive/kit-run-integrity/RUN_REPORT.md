# RUN_REPORT , kit-run-integrity

**Objective:** make dwarves-kit's autonomous run layer MEASURABLE + COLLISION-SAFE + HONESTLY-PROVEN.
**Run date:** 2026-07-04 · **Conductor:** SUBAGENT-DELEGATE (thin conductor, in-harness worktree/clone workers) · **Work repo:** `dwarvesf/dwarves-kit` · **Base:** `13c95c2` → **Head:** `a9a2e55` (+ 06 held).
**Terminus reached:** 8 PRs (7 merged, 06 HELD for Han), TIER-4 clean.

## Timeline (▓ merged · ▒ held · ✗→✓ CI-fix resume · ★ conductor recovery)

```
     phase / PR                         model     ┊ build → ci → merge
──────────────────────────────────────────────────┊────────────────────────────
W1  02 spec-race        #155 SPEC-128   OPUS   ▓▓▓▓▓✗✓▓  merge f07fb6b   [race-enabler]
      └ CI-fix: BSD stat -f → GNU stat -c (fail-open mutex, Linux-only)
────────────────────────────────────────────────── (02 merged unblocks the parallel wave)
W2  05 proof-table      #157 SPEC-132   sonnet  ▓▓▓▓▓▓   merge 83ace8d   ┐
    03 coverage-delta   #156 SPEC-130   OPUS    ▓▓▓▓✗✓▓  merge f240c95   │ 4 parallel
    04 mutation-smoke   #159 SPEC-131   OPUS    ▓▓▓▓▓▓   merge 3371680   │ (own clones,
    01 gate-outcome     #158 SPEC-129   OPUS    ▓▓▓★▓▓   merge 76ce29a   ┘  pinned SPECs)
      └ 01: missing proof-of-done (subagent push bypassed ship-gate) → resume
      └ 01: proof push-delay → conductor re-fetch recovered ★
      └ 03: test.yml union conflict → merge-master-in resolve
      └ 01: gate-ledger OUTCOME+MUTATION verb union conflict → resolve
────────────────────────────────────────────────── TIER-4
T4  133 reconcile 05↔01 #160 SPEC-133   sonnet  ▓▓▓▓▓▓   merge c8f56cc   [no-orphan fix]
    integration+no-orphan          (verify) OPUS  ▓▓      CLEAN, 0 blocking
    advisor both modes             (verify) advis ▓▓      → NOTES (advisory→block = Han)
    security review                (verify) sec   ▓▓      HIGH+MED found
    134 security-harden   #161 SPEC-134  OPUS    ▓▓▓▓✗✓▓  merge a9a2e55   [remediation]
      └ 134 CI-fix: negctl used `git show origin/master` → shallow checkout@v4 (no master ref)
────────────────────────────────────────────────── W3
W3  06 docs-wiring       #162 SPEC-135  sonnet  ▓▓▓▓▓▒   HELD for Han     [final, gated]

wavefront-projection ghost lane (if the wave had NOT been serialized by the test.yml/gate-ledger
seams): W2's four would have merged in ~1 CI-cycle instead of 4 sequential conflict-resolves;
the seams (shared test.yml + gate-ledger.sh) forced a serial merge tail. Fix landed anyway.
```

## Worker minutes by model (approx, wall-clock per dispatch)

| Model | Dispatches | Build min | Notes |
|---|---:|---:|---|
| opus | 02, 01, 03, 04, 134, +2 CI-fixes, +2 verify (int/sec) | ~167 | all design-bearing + security + the two portability CI-fixes |
| sonnet | 05, 133, 06 | ~43 | execution-dominant (generator, reconcile, docs) |
| advisor (kit) | 1 | ~4 | both modes |
| **total worker** | **13 dispatches** | **~214 (much overlapped)** | session elapsed ~3h08m (W2 ran 4 concurrent) |

Model routing held to the rule (planning/design/security → opus; execution → sonnet), per `research/2026-07-03-megagoal-execution-hygiene.md` §4.

## Gate-coverage matrix (per merged sub-goal)

| Surface | SPEC | spec+validate | build | test-plan/over-test | review | proof-of-done | CI (ubu+mac) |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|
| 02 spec-race | 128 | ✓ (Design) | ✓ | ✓ 35/35 (20-parallel-distinct + negctl) | ✓ | ✓ kri-02 | ✓ |
| 01 gate-outcome | 129 | ✓ (Design) | ✓ | ✓ 22/22 (additive-equiv + real negctl) | ✓ | ✓ kri-01 | ✓ |
| 03 coverage-delta | 130 | ✓ (Design) | ✓ | ✓ 17/17 (false-positive NC) | ✓ | ✓ kri-03 | ✓ |
| 04 mutation-smoke | 131 | ✓ (Design) | ✓ | ✓ 32/32 (false-positive NC + clean-tree) | ✓ | ✓ mutation-smoke/ | ✓ |
| 05 proof-table | 132 | ✓ | ✓ | ✓ 25/25 (additive-tolerance both ways) | ✓ | ✓ kri-05 | ✓ |
| 133 reconcile | 133 | ✓ | ✓ | ✓ (real-01-format + negctl) | ✓ | ✓ kri-outcome-reader | ✓ |
| 134 security | 134 | ✓ (Design) | ✓ | ✓ 22/22 (3 per-guard negctls) | ✓ | ✓ kri-security-hardening | ✓ |
| 06 docs-wiring | 135 | ✓ | ✓ | ✓ 31/31 (no-orphan + executed negctl) | ✓ doc-verifier 22/22 | ✓ kri-06 | (held) |

## Callable-stack (the wired triad , honest enforcement labels from TIER-4)

```
COLLISION-SAFE   orchestrate.sh wavefront ──► spec-next.sh reserve (mkdir-mutex + ledger)   [HOOK-ENFORCED]
MEASURABLE       hooks/ship-gate.sh ────────► gate-ledger.sh outcome  (caught= + dur_s)     [HOOK-ENFORCED, ship-only]
HONESTLY-PROVEN  commands/review-team.md ───► coverage-delta.sh  (diff-line HEURISTIC)      [PROSE-INVOKED, advisory]
                 commands/verify.md 6b ─────► mutation-smoke.sh  (bite check, MAX=5)        [PROSE-INVOKED, advisory]
                 operator / skill ──────────► proof-table-gen.sh → docs/runs/<rid>.md       [OPERATOR-INVOCABLE]
                                                 ├─ reads OUTCOME marker  (SPEC-133 reconcile)
                                                 └─ rid sanitized + realpath-confined  (SPEC-134 security)
```

No-orphan verdict (TIER-4 integration + 06's `test-kri-wiring.sh`): **CLEAN, zero blocking.** 03/04 are honestly labeled prose-invoked-optional (skippable, invisible to ledger status surfaces today) rather than certified as hard-wired.

## Totals

- **8 PRs** (7 merged: #155 #157 #156 #159 #158 #160 #161; 1 HELD: #162), **8 SPECs** (128-135), all on `dwarvesf/dwarves-kit`.
- **~2.85M subagent tokens** across 13 dispatches (10 build + 3 verify).
- **CI: green on ubuntu-latest + macos-latest** for every merged PR (2 portability failures caught + fixed pre-merge).
- **2 security findings** (1 HIGH path-traversal, 1 MEDIUM) found by the TIER-4 security gate and remediated before the final PR.
- **06 HELD** = the intended gated-final terminus (Han's click).

## Non-obvious lessons (the ones worth keeping)

1. **`isolation:"worktree"` targets the conductor's session repo, not a cross-repo build target.** This run's cwd was ops-toolkit but the build repo was dwarves-kit; harness worktree-isolation gave ops-toolkit worktrees. Parallel isolation came from per-worker `git clone` instead (a normal git op, no worktree-rule conflict), with pinned SPEC numbers as the collision belt.
2. **The ubuntu-vs-macOS CI matrix earned its cost twice.** (a) 02's mutex used BSD `stat -f` (garbage on GNU, exit 0, defeated the `||` fallback) → fail-open lock, macOS-green/Linux-red. (b) 134's negctl reverted via `git show origin/master:` which is empty under `actions/checkout@v4` shallow (`fetch-depth:1`, no master ref) → the negative control couldn't fire. Both invisible to a single-platform run.
3. **The proof-gate caught a real gap live:** 01 shipped without a `docs/verification/` proof (its subagent push bypassed the ship-gate; the conductor's push enforced it). The honesty layer working as designed , the whole point of the mega-goal.
4. **Parallel-build seams are real:** 05 built against an ASSUMED 01 marker shape (single-line) while 01 shipped a two-line `dur_s` shape → a 4th reconciliation PR (133). The mega-goal's own "05 has a soft data dependency on 01, builds in parallel" is exactly what let it happen; additive-tolerance kept it non-blocking, TIER-4 no-orphan forced the fix.
5. **Dev residue in shared durable state:** 02's test runs left 64 phantom SPEC reservations in `~/.local/state/dwarves-kit/` inflating `next` to 193; truncated + re-reserved clean (128-135 contiguous).
6. **Scaffold was authored in-run:** the pointer assumed a pre-existing scaffold that did not exist; the conductor built it from the binding sources (benchmark §2/§5 + effectiveness-audit "gate ledger = ceremony as built" + ledger-observatory "reuse the additive marker") rather than stopping.

## Open items for Han (from NOTES `## Proposed additions (TIER-4)`)

- **Merge #162** (the held docs PR) at your discretion , CI is green, doc-verifier 22/22.
- **Advisory→BLOCK promotion** for 03/04: advisor recommends NOT yet (land per-gate `caught=` telemetry + measure a false-positive rate first; the localterm datum is an override analogy, not direct evidence). Your call.
- Follow-ups: per-gate OUTCOME emit (beyond ship-only), auto-fire proof-table-gen at ship, a graduated nag-counter → BACKLOG rows.
