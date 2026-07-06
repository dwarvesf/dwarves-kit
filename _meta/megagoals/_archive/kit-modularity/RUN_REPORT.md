# RUN REPORT, kit-modularity (ID-277)

**Destination reached:** dwarves-kit is now a MIDDLE-LEVEL composable toolkit. lib-vs-tools split retired into per-subsystem modules; observability split into an append-only ledger (SoT) + a stateless `stats` projection; standalone `<subsystem> <verb>` commands; layered a-la-carte install; every module documented + wired; operate-contract + the 3 scaffolders reconciled.

**Terminus:** non-deployable (build + merge). Reached. 7 of 8 sub-goals merged; SG-07 BUILT + HELD for Han (edits his authoring skills). Convergence gate PASSED.

**Run date:** 2026-07-05 · Conductor: subagent-delegate (thin) · Base: b7e44b1 → master 175557c

---

## Timeline (wavefront; each ▓ ≈ 5 worker-min; ░ = wall-clock ghost where a wave ran parallel)

```
WAVE 1  01-module-collapse   OPUS   ▓▓▓▓▓▓▓▓▓▓  51m   #190 cb64f15
WAVE 2  02-stats-plane       OPUS   ▓▓▓▓▓▓▓▓▓▓▓ 55m   #191 053c381
WAVE 3  03-subsystem-cmds    sonnet ▓▓▓▓▓▓      29m   #192 b2e8717
WAVE 4  04-install-wire      sonnet ▓▓▓▓▓▓░     31m ┐ #193 bc5bf56
        08-mega-status       sonnet ▓▓▓▓▓▓▓     36m ┘ #194 5e7ca71   (parallel)
WAVE 5  05-operate-contract  sonnet ▓▓▓         13m ┐ #196 0460c36
        06-docs              sonnet ▓▓░         11m ┘ #195 c6e1ad6   (parallel)
WAVE 6  07-reconcile [HELD]  sonnet ▓▓          11m   #197 + dotfiles #207  (NOT merged)
GATE    fix docs-wiring      conductor ▓        —     #198 175557c
        advisor P5+P6        OPUS   ▓            6m    (machine-verified, 20 suites)
```

Wall-clock < sum-of-worker-minutes: waves 4 and 5 ran two workers in parallel (hand-made worktrees, no `.git/index.lock` collision). Linear spine 01→02→03 was mandatory (02 renames what 03 wraps; 04 wires what 03 exposes).

## Worker minutes by model

| Model | Sub-goals | Worker-min |
|---|---|---|
| Opus | 01, 02, advisor-gate | ~112 |
| Sonnet | 03, 04, 05, 06, 07, 08 | ~131 |
| **Total** | 8 sub-goals + gate | **~243 worker-min** |

Tokens (subagent): ~2.13M across 9 dispatched workers (01: 280k, 02: 363k, 03: 226k, 04: 306k, 05: 147k, 06: 202k, 07: 184k, 08: 347k, advisor: 78k).

## Gate-coverage matrix

| Sub-goal | build | review (gate-ledger) | named NCs | proof-of-done | CI green | merged |
|---|---|---|---|---|---|---|
| 01 module-collapse | ✓ | ✓ | 0-symlink · suite-identical 56/2→56/2 · orchestrate+mega-merge e2e · CI-path audit | ✓ | ✓ | #190 |
| 02 stats-plane | ✓ | ✓ | no-persist snapshot + fresh-recheck HOLDS · unset-DIR · honest-zero · tools/-empty | ✓ | ✓ | #191 |
| 03 subsystem-cmds | ✓ | ✓ | delete-dispatcher · 14/14 call-sites resolve | ✓ | ✓ | #192 |
| 04 install-wire | ✓ | ✓ | spine-only · un-opted-hook-absent · 21/21 + neg-control · anti-registry lint | ✓ | ✓ | #193 |
| 05 operate-contract | ✓ | ✓ | grep-audit 0 stale (both files) | ✓ | ✓ | #196 |
| 06 docs | ✓ | ✓ | 35-row F-bar audit 0 gaps · delete-a-doc NC | ✓ | ✓ | #195 |
| 08 mega-status | ✓ | ✓ | CLAIM-UNVERIFIED · STALLED · MERGED-UNCHECKED · WIP-nuance · 16/16 | ✓ | ✓ | #194 |
| 07 reconcile | ✓ | ✓ | mirror byte-identical (shasum a42939f + neg-control) · grep-audit 0 stale ×3 | ✓ | ✓ | **HELD #197/#207** |

**Convergence gate (composed, on merged master 175557c):**

| Check | Result |
|---|---|
| Full kit suite | 59 pass / 3 fail, the 3 are pre-existing LOCAL-env-only (board stale-installed-path, classify-md-inert /tmp-copy, ship-gate-profiles needs-installed-hook); all green in CI |
| Spine-only temp-HOME install | ✓ exactly 6 spine hooks wired, 0 optional-module hooks |
| Per-module doc + firing point | ✓ SG-06 35-row audit, 0 unjustified gaps |
| 3-scaffolder mirror check | ✓ triage-ladder fence byte-identical (shasum unchanged + negative control) |
| Advisor P5 (seam critique) | ✓ all 7 invariants HOLD (machine-verified); 1 MINOR comment-only, non-blocking |
| Advisor P6 (over-suggest) | ✓ 5 follow-ups → Proposed additions (CI test-coverage gaps + 2 lints) |
| Recheck | ✓ advisor independently ran 20 suites (fresh-context re-audit of the PASS) |

## Callable-stack (what the mega left on master)

```
dwarves-kit/
├─ lib/                         (kept name; LIB_ROOT anchor, 0 symlink aliases)
│  ├─ ledger/    ← append substrate (SoT): ledger_append/read/root, KIT_LEDGER_DIR
│  ├─ stats/     ← renamed from ledger-observatory; pure :memory: projection, persists nothing
│  ├─ board/  gate/  classify/  spec/  goal/  session/{observe,recall,intel}
│  │            └─ standalone <subsystem> <verb> entries (board/orchestrate shape)
│  ├─ skill-curator/  plugin-check/   ← bare orphan module dirs
│  ├─ mega.sh                          ← bare orphan: `mega status <slug>` drift reconciler
│  └─ adopt/explain/pitch/precedent    ← bare orphan scripts
├─ install.sh   ← layered: 6-hook spine unconditional + `--with <modules>` opt-in
│               └─ writes kit.toml [modules] into the CONSUMER (never a runtime registry)
├─ tools/       ← GONE (split retired)
├─ AGENTS.md + WORKFLOW.md   ← refreshed to the modular surface
├─ README.md + docs/PHILOSOPHY.md  ← toolbox-not-appliance + 35-row F-bar audit
└─ commands/mega.md + skills plan-for-goal / plan-for-mega-goal  ← reconciled [HELD]
```

## What the run caught that per-sub-goal review structurally could not

- **SG-02 TOKENS-marker regression** (test-docs-wiring AC7): the ledger-substrate extraction dropped the inline `\n`, staling a fixed-string assertion, AND that test was absent from CI, so every per-PR CI missed it. The full-suite-on-merged-master gate caught it; fixed + wired into CI (#198).
- **A stale HANDOFF claim** ("SG-02 not started / empty worktree"): a mid-flight snapshot, disproven by git (7 commits at merge). Motivated SG-08's in-flight-vs-STALLED nuance.
- **1 MINOR comment-only stale `tools/` path** (advisor P5): non-blocking, routed to a follow-up.

## Totals

- **8 sub-goals** (7 merged + 1 held), **9 merged PRs** (#190-196, #198) + **2 held** (#197 dwarves-kit, #207 dotfiles).
- **~243 worker-min**, **~2.13M** subagent tokens, **1 conductor fix** (#198).
- **0 blocking findings** at the gate. Verdict: SOUND TO CLOSE.

## Follow-ups (Proposed additions → one substantive backlog row, NOT executed at close)

Wire the load-bearing tests absent from CI (`test-mega-reconcile`, `test-install-compat`, `test-install-contract`, ship-gate suites, 18/63 currently in CI) + a no-stale-path lint (would fold the conform.sh:3 comment) + a substrate-append lint (document which side-logs are deliberately outside the run-line stream).

## Held-final pause

SG-07's two PRs edit Han's authoring skills (`plan-for-goal`, `plan-for-mega-goal`) + `/kit:mega`. Both are green, CLEAN, and HELD. **Han merges them** (dwarves-kit #197, then dotfiles #207) to complete the reconciliation; the SG-07 ROADMAP box flips on merge.
