# RUN_REPORT , harness-ops

**Destination reached:** the dwarves-kit harness is config-driven (one `kit.toml` + per-project `.kit.toml` behind one resolver driving ledger/mega/manifest, stable `bin/` consumer entrypoints, reserved keys honestly inert, a one-page consumer contract) AND tidy (proof/verification split-brain folded, briefs + generated run-tables relocated, the 3 giant root files slimmed to thin stubs, README map refreshed).

**Run mode:** subagent-delegate, thin conductor. **Repo:** dwarves-kit (kit-adopted), default branch `master`. **Cross-repo:** /goal session rooted in ops-toolkit; work in dwarves-kit via hand-cut worktrees at `dwarves-kit/.claude/worktrees/ho-*` (native isolation cuts from the wrong repo).
**Date:** 2026-07-06. **Outcome:** 13/13 built; 12 merged; **PR #222 (13, the final PR) green + HELD for operator click** per gated-final policy.

---

## Timeline (waves; parallel within a wave)

```
        0        ~20m       ~45m       ~70m      ~100m     ~125m
        |---------|----------|----------|---------|---------|----------
WAVE 1  ⣿⣿⣿⣿⣿⣿ 02·03·04·09·10·11  (6 parallel, sonnet)
 11 fix    ⣿⣿⣿  SPEC-135 assert-134 repoint (CI-only integrity check the build missed)
WAVE 2       ⣿⣿⣿⣿⣿ 05(OPUS)·08        (2 parallel, after 04 merged)
WAVE 3           ⣿⣿⣿⣿⣿⣿ 06·12         (2 parallel, after 05 merged; disjoint adopt.sh)
 07                ⣿⣿ (after 06)
GATE 09              ✋──────────► approved by Han ──► merged
WAVE 4 (13)              ⣿⣿⣿⣿ (final, after 09) ──► HELD for click
        wavefront ghost: ideal fully-parallel ≈ 1 build + 1 gate; actual ≈ 4 waves (dep-forced)
```

Dependency-forced serialization (not conductor stalls): 04→05→06→07 (install/adopt chain); 12 after 05 (adopt.sh:72-83 overlap); 13 after 09 (README map must reflect the proof fold). 09 held on the one human gate.

## Merge order (bottom-up, one at a time, CI-green-on-open-PR gated)

`#211(02) → #213(10) → #215(03) → #216(04) → #212(11) → #217(08) → #218(05) → #219(06) → #220(07) → #221(12) → #214(09) → [#222(13) HELD]`

Every merge was followed by a targeted integrated-seam recheck. The full local suite is unusable (test-pane-viewer spawns tmux; test-e2e / test-orchestrate-wavefront / test-ship-gate-profiles / test-classify-md-inert are agent/env flakes that hang or fail locally but pass in CI), so integration was verified via a 15-16 test non-spawning subset + the per-PR CI as the authoritative gate.

## Worker wall-clock by model

Durations are worker-session wall-clock from the task-notification usage blocks; they INCLUDE each worker's own idle CI-watch time (several workers self-watched their PR's CI), so they overstate pure build time.

| Model | Sub-goals | Σ wall-clock (approx) | Σ subagent tokens (approx) |
|---|---|---|---|
| opus | 05 | ~16 min | ~217k |
| sonnet | 02·03·04·06·07·08·09·10·11(+fix)·12·13 | ~137 min | ~2,120k |
| **total** | **13 workers (01 pre-built)** | **~153 min worker-time** (heavily overlapped; conductor wall-clock ~2h) | **~2,335k** |

Per-sub-goal (min / ktok): 02 6.0/152 · 03 13.2/196 · 04 16.0/226 · 05 15.9/217 · 06 12.8/229 · 07 3.3/137 · 08 4.6/139 · 09 11.7/247 · 10 6.0/156 · 11 12.6/167 · 12 29.5/308 · 13 20.9/161.

## Gate-coverage matrix (lane + phases recorded via gate-ledger)

| SG | Lane | SPEC | Gates recorded (ran) | Proof (co-located) |
|---|---|---|---|---|
| 02 | normal | , | build, ship | verification/wire-ledger.md |
| 03 | normal | , | build, docs, ship | verification/ho-03-wire-mega/proof-of-done.md |
| 04 | full | 183 | design·spec·design-record·test-plan·build·review·docs·ship | verification/manifest-reconcile/proof-of-done.md (37/37 +NC) |
| 05 | full | 184 | think·design·design-critique·spec·validate·design-record·test-plan·build·review·docs·ship | verification/SPEC-184-stable-interface/proof-of-done.md |
| 06 | full | 192 | grill·think·design·design-record·test-plan·spec·build·docs·ship | verification/project-override/proof-of-done.md |
| 07 | full | , | think·design·validate·design-record·build·review·docs·ship·reflect | verification/consumer-contract-doc/proof-of-done.md |
| 08 | normal | 188 | spec·test-plan·build·docs·ship | verification/reserved-keys-guard/proof-of-done.md |
| 09 | normal (GATE) | , | build, ship | PR #214 body (8-slug decision table) + proof tests 8/8 |
| 10 | normal | , | think·build·review·docs·ship | verification/briefs-out/proof-of-done.md |
| 11 | normal | , | start·plan·build·verify·ship (+fix) | verification/goal-11-runs-to-generated/run-table.txt |
| 12 | full | 185 | per-phase full lane | verification/... (3 per-file commits; install-copy test) |
| 13 | normal | , | per-phase | verification/harness-ops-13-doc-tidy/proof-of-done.md |

## Callable-stack tree (what drove what)

```
conductor (thin, ops-toolkit-rooted)
├─ wave 1  → 6× Agent(general-purpose) in dwarves-kit worktrees ─ build+proof+PR
│   └─ 11 CI-fix → SendMessage(resume 11 worker) ─ SPEC-135 assert repoint
├─ wave 2  → 2× Agent (05 opus, 08 sonnet)
├─ wave 3  → 2× Agent (06, 12 sonnet)
├─ 07      → 1× Agent
├─ 09 gate → AskUserQuestion(Han) → merge
├─ 13      → 1× Agent → SendMessage(finalize: worker had left README/proof uncommitted)
└─ per merge: gh pr checks --watch (bg) + targeted seam-test subset
```

## Defects the harness caught (not silently passed)

1. **11 (#212) SPEC-135 assert-134**: root-slim-style repoint changed a live confinement string; a CI-only integrity assertion (`test-kri-wiring.sh:92`) the worker didn't run locally caught it. Fixed by repointing the assertion; re-verified green.
2. **04 (#216) git-stash-blind-pop**: worker's errant `git stash pop` pulled a maintainer's unrelated WIP into its tree; caught by a diff audit, reverted, PR diff confirmed clean (no marketplace.json/BACKLOG contamination).
3. **13 (#222) checkpoint-discipline gap**: worker committed only the 2 renames, left the README refresh + proof-of-done uncommitted, then deferred to CI. Caught by a conductor diff audit before the hold; sent back to commit+push; final PR now complete.
4. **03↔11 docs/runs orphan**: 03 wrote a generated table into docs/runs/ that 11's relocation (predating it) missed; logged as a merge-time seam and folded into 13's relocation (never lost).

## Totals

- **13/13 sub-goals delivered.** 12 merged to master; PR #222 held for the operator's final click.
- **12 PRs** opened (211-222). 11 merged bottom-up, all CI-green-on-open-PR. 1 human gate (09) + 1 final hold (13).
- **SPECs written:** 183 (04), 184 (05), 185 (12), 188 (08), 192 (06). Obvious-lane sub-goals recorded gates without a SPEC per the kit's "spec only when it hits a gate" rule.
- **Faster next time:** the two avoidable re-loops were (a) workers ending on intent at a self-CI-watch instead of committing+finishing, and (b) a worker running a CI-only integrity test only in CI. Injecting "commit ALL Done= artifacts before you watch CI" and "run test-kri-wiring locally when you touch a jailed path" into worker prompts removes both. The full-local-suite dead-end (tmux/agent-spawning tests) is intrinsic , keep using the targeted seam subset + CI as authoritative.
