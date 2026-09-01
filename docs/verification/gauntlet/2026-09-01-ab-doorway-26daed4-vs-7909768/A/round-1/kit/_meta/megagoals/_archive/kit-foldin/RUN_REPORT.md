# RUN_REPORT , kit-foldin

**Terminus:** non-deployable (cross-repo code-move + refactor + one new subagent). Build + merge IS the terminus.
**Outcome:** 6/6 dwarves-kit sub-goals merged to master; SG-07 ops-toolkit retire-sweep OPEN as the HELD final PR #720 for Han. Convergence gate clean.
**Run mode:** subagent-delegate, thin conductor, hand-made cross-repo worktrees.
**Date:** 2026-07-05.

## PR ledger

| SG | Title | Repo | PR | Merge SHA | Model | Status |
|----|-------|------|----|-----------|-------|--------|
| 01 | lib-regroup | dwarves-kit | #187 | `d319f1c` | opus | merged |
| 02 | hooks-batch | dwarves-kit | #186 | `29e3127` | sonnet | merged |
| 03 | session-tools | dwarves-kit | #188 | `0601249` | sonnet | merged |
| 04 | skill-curator | dwarves-kit | #185 | `eb41df9` | sonnet | merged |
| 05 | plugin-check | dwarves-kit | #183 | `44232b7` | sonnet | merged |
| 06 | claim-verifier | dwarves-kit | #184 | `3a00c80` | opus | merged |
| 07 | retire-sweep | ops-toolkit | #720 | `62183c2` | sonnet | **HELD for Han** |
| , | gate-fix: doc leaks | dwarves-kit | #189 | `b7e44b1` | opus (conductor) | merged (convergence-caught) |

## Timeline (minutes from Wave-1 dispatch; ⣿ active, ⣀ idle, ▸ merge point)

```
        0        10        20        30        40        50        60        70        80
        |----+----|----+----|----+----|----+----|----+----|----+----|----+----|----+----|
W1 05   ⣿⣿⣿⣿⣿▸                                                          merged #183 (10.4m)
W1 06   ⣿⣿⣿⣿⣿⣷      ▸held············▸                                  merged #184 (11.5m)
W1 04   ⣿⣿⣿⣿⣿⣿⣿⣿⣿▸                                                     merged #185 (16.9m)
W1 02   ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷▸ (re-CI vs base)  ▸                             merged #186 (23.2m)
W1 01   ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿▸ BASE                                        merged #187 (28.8m)
W2 03            ghost▸┈┈┈┈┈┈┈┈┈⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿▸                            merged #188 (20.7m)
FI 07                              ghost▸┈┈┈┈┈┈┈⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿▸ HELD #720   (21.5m)
CV gate                                                    ⣿⣿⣿⣿⣿⣿ install+40/40+grep+advisor
        |----+----|----+----|----+----|----+----|----+----|----+----|----+----|----+----|
```

Ghost lane (`┈`) = wavefront projection: 03 could not start until 01's `lib/session/` landed on master; 07 could not start until all of 01-06 merged. The dependency wavefront, not worker speed, set the critical path (01 → 03 → 07 → gate). Wave-1 leaves (05/06/04/02) merged as they greened; the base (01) merged last of Wave 1, which is why 03's ghost extends to ~29m.

## Worker minutes by model

| Model | Sub-goals | Wall-clock min | Subagent tokens |
|-------|-----------|----------------|-----------------|
| opus | 01, 06 (+ advisor P6) | 40.3 (+ advisor) | 427,075 (+ advisor) |
| sonnet | 02, 03, 04, 05, 07 | 92.7 | 1,234,238 |
| **total (7 builders)** | | **133.0** worker-min | **1,661,313** |

Wall-clock end-to-end ≈ 85 min (vs 133 worker-min summed , parallelism bought ~36% off a serial run; the dependency chain 01→03→07 is the irreducible floor).

## Gate-coverage matrix (per sub-goal, recorded via `lib/gate-ledger.sh`)

| SG | spec | design | build | review | recheck | ship/proof | named NCs | Rung |
|----|------|--------|-------|--------|---------|-----------|-----------|------|
| 01 | , | bearing | ✓ | ✓ | , | proof✓ | engine-run ×2 + backstop RED→GREEN | 2 |
| 02 | skip(obvious) | , | ✓ | ✓ | ✓ | proof✓ | empty/malformed/missing-ledger ×4 | 3 |
| 03 | ✓ | bearing | ✓ | ✓ | ✓ | proof✓ | honest-zero/malformed/missing-dir | 3 |
| 04 | override(obvious) | , | ✓ | ✓ | , | proof✓ | unset-ledger clean-error | 2 |
| 05 | , | , | ✓ | ✓ | , | proof✓ | stale-plugin | 2 |
| 06 | ✓ | bearing | ✓ | ✓ | ✓ | proof✓ | agent-effectiveness + smoke | 3 |
| 07 | , | , | ✓ | ✓ | , | proof✓ (fresh-proof+rollback, no override) | git-revert dry-run | 2 |

Convergence lenses: integration-install (4 hooks + skills) ✓ · system-verify (kit 40/40 + all tool suites) ✓ · both-repo dangling-ref grep ✓ · advisor P5/P6 (in-harness) ✓ → **2 tenant-path leaks CAUGHT + fixed + merged (kit PR #189, `b7e44b1`)** + 5 P6 follow-ups filed. The gate did its job: the advisor's dash-slug + prose-form leaks had evaded every sub-goal's `workspace/<owner>` grep.

## Callable-stack tree (what now lives where in the kit)

```
dwarves-kit/
  lib/                          SG-01: 32 flat → subsystems + 33 root + 21 cross-sub shims (transitive closure)
    board/ queue/ gate/ classify/ spec/ goal/ telemetry/ session/
    session/parse_transcript.py SG-03: shared JSONL parser (iter_entries/load; raw dict, no Turn wrapper)
  hooks/                        SG-02: backlog-stage · citation-guard · context-hints · harvest
    (wired in BOTH root settings.json + hooks.json; install.sh skill-copy → skills/* glob)
  agents/claim-verifier.md      SG-06: in-harness N=3 majority-refute skeptic panel (was verify-claim CLI)
  skills/skill-review/          SG-04: promoted from nested tools/ to loader-mandated top-level
  tools/
    session-observe/ (3 bins)   SG-03  ┐
    session-recall/  (python)   SG-03  ├─ import lib/session/parse_transcript in-process
    session-intel/   (+deploy)  SG-03  ┘
    skill-curator/              SG-04: was cc-self-improve; CC_SI_MEMORY_LEDGER opt-in
    plugin-check/               SG-05: was cc-plugin-check
ops-toolkit/ (HELD PR #720)     SG-07: 14 dirs → MOVED.md tombstones; cc-money-gate + 2 deploy/ sets preserved
```

## Totals + lessons

- **7 sub-goals, 8 PRs** (6 merged kit + 1 convergence gate-fix + 1 held ops). Zero red-CI merges; every kit PR re-verified against the integrated tree (update-branch → fresh CI) before its bottom-up merge.
- **Bearing calls that mattered:** SG-01 strategy (b) needed a per-subsystem TRANSITIVE closure the design note didn't spell out (a callee reached via a shim runs with `$DIR`=that subdir, so ITS downstream calls need shims there too); a naive per-pair shim set would have false-greened. SG-03 chose a raw-dict parser over a `Turn` wrapper (only the parse loop was duplicated, not role/ts/text extraction). SG-06's fan-out is single-dispatch-N-in-context (harness disallows subagent recursion), cross-tier not cross-vendor (one subagent = one model).
- **Contract tensions resolved in-flight:** SG-04's "whole deploy/ stays ops" vs "11 tests green" (generic install scripts moved, personal plist stayed); SG-07's override path blocked by a newer guard (`cc-hyg-04`) → fresh-proof + dry-run rollback instead.
- **Open follow-ups (NOTES ## Proposed additions):** host-local `redeploy.sh` full reconciliation (4 more tombstoned tools still listed); session-observe bin-naming debt (cc- prefixes kept per contract); ledger-observatory pre-existing personal-path strings.
- **Deferred (not built):** cc-worktree-provision, review-findings-memory. **Stayed ops:** cc-money-gate, prose-rag.

**STOP:** the held final PR #720 is the terminal condition. Do not merge , Han's single click. Post-merge close-out: co-locate `_meta/megagoals/kit-foldin/` → `_meta/megagoals/_archive/`.
