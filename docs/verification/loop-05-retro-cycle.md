# Proof-of-done: SPEC-195 `learn propose` (harness-loop SG-05, the keystone)

Rung 3 (over-test): run-table + ONE recorded LIVE run against the real XDG ledgers + three
NCs + COVERAGE-DELTA + a fresh-context recheck-verifier re-execution.

## Run-table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Unit + discipline suite (33 assertions) | `bash tests/test-learn-propose.sh` | PASS 33/33 |
| 2 | Amended reserved-keys lint | `bash tests/test-reserved-config-guard.sh` | PASS 9/9 |
| 3 | Hook behavior suite | `bash tests/test-hooks.sh` | PASS 453/453 |
| 4 | Structural meta suite | `bash tests/test-meta.sh` | PASS 683/683 |
| 5 | LIVE run, real ledgers | `bin/learn propose --days 30` | PASS (16 signals -> 5 hypotheses -> 4 refuted -> 1 staged, exit 0) |
| 6 | Honest-empty NC | empty aggregate | PASS (0 candidates, staging NOT created, exit 0) |
| 7 | Idempotency NC | re-run same window | PASS (run1 stages 1, run2 stages 0, count stays 1) |
| 8 | Adversarial-check NC | planted ungrounded + refuted | PASS (both dropped, no staging file) |
| 9 | Rid fallback NC | broken gate path | PASS (`_rid()` -> `learn-propose-<date>`) |
| 10 | COVERAGE-DELTA | `bash lib/gate/coverage-delta.sh check .` | PASS (source + test move together) |
| 11 | Template size | `wc -m goals/kit-retro.md` | PASS (3870 < 4000) |
| 12 | Fresh recheck-verifier re-executes #5 | `kit:recheck-verifier` | see "Recheck" below |

## 1. LIVE run (real XDG ledgers, real `claude -p` sonnet passes)

Command: `LEARN_PROPOSE_RID=loop-05-liverun bin/learn propose --days 30` with
`DWARVES_KIT_LOG_DIR=$HOME/.local/state/dwarves-kit/logs` (the real machine ledgers).

Console:
```
learn propose: 16 signals over 151 rids -> 5 hypotheses -> 1 candidate staged
(dropped: 0 ungrounded, 4 refuted, 0 duplicate)
[exit 0]
```

The adversarial pass did real work: it REFUTED 4 of the 5 grounded hypotheses (a weakly-grounded
"maybe improve X" is dropped before it can reach staging -- the P0 discipline, live). The ONE
survivor, staged as a byte-format `## [staged]` block (the exact shape `board promote` reads):

```
## [staged] Reduce reflect gate override rate
- Intent: Cut the 28.6% override rate on the reflect gate so retro/reflect actually runs
  instead of being routinely skipped.
- Approach: Sample reflect-gate override reasons from the ledger; determine whether the gate
  is too heavy for its lane or misapplied, then lighten or rescope it.
- Tags: #u-mid #f-mid
- Source: learn propose 2026-07-12 | lens=gate-yield figure="reflect override_pct=28.6"
  rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more
```

Every block cites lens + figure + rids on its `- Source:` line, and the citation is REBUILT
from the deterministic aggregate (the model only chose the signal id `S6`; the figure
`reflect override_pct=28.6` and the rids came from `stats gate-yield`, never from the model).
The rids are the window's 151 covered runs, shown as an 8-id sample + `+143 more`.

`TOKENS` markers landed for every LLM pass (real usage from the `--output-format json`
envelope; `out=` is the real generation cost, e.g.):
```
2026-07-11T22:40:05Z | TOKENS | in=2 out=4170 cache_read=0 cache_create=0   (an interpret pass)
2026-07-11T22:40:17Z | TOKENS | in=2 out=832  cache_read=0 cache_create=0   (an adversarial pass)
2026-07-11T22:40:21Z | TOKENS | in=2 out=13   cache_read=0 cache_create=0   (a REFUTED verdict)
```
(Note: `in=` is under-reported by Claude Code's own usage envelope under heavy system-prompt
caching; `out=` is faithful. The marker emits exactly what the envelope reports.)

## 2. Honest-empty NC

Injected an empty aggregate (`{"signals":[]}`):
```
learn propose: 0 signals over 0 rids -> 0 hypotheses -> 0 candidates staged (...)
learn propose: 0 candidates (empty window)
```
The staging file was NOT created (`[ -f staging.md ]` -> NO), exit 0. An empty window stages
nothing and touches nothing.

## 3. Idempotency NC

Ran the same window twice with a fixed interpreter:
```
run 1: 1 signals -> 1 hypotheses -> 1 candidate staged (...)
run 2: 1 signals -> 1 hypotheses -> 0 candidates staged (dropped: ... 1 duplicate)
staged block count: 1
```
The second run re-derived the same proposal, found it already staged (anchored dedup), and
added nothing. The staging file is stable across re-runs.

## 4. Adversarial-check NC

Planted TWO bad proposals against a one-signal aggregate: one citing a fabricated signal id
(`S99`), one grounded (`S1`) but with the verifier forced to `REFUTED`:
```
learn propose: 1 signals -> 2 hypotheses -> 0 candidates staged (dropped: 1 ungrounded, 1 refuted, 0 duplicate)
learn propose: 0 candidates
```
The ungrounded one was dropped by the deterministic grounding check; the refuted one by the
adversarial pass. Neither reached staging; no staging file was created. This is the SPEC-195
P0 guard (an ungrounded proposal reaching staging is a P0 defect) proven closed on both paths.
The suite also proves the SPEC-144 Run-3 mirror (a suffix-key survives, an exact-key drops)
and the fail-closed path (a garbled verdict drops).

## COVERAGE-DELTA (over-test)

| Surface | Before | After |
|---|---|---|
| `learn propose` behavior | 0 (a REFUSE stub, `exit 1`) | `lib/learn/propose.py` (475 lines): 3-stage pipeline |
| shared staged-block edges | 3 divergent copies (backlog-stage.py, anomalies.py, add-backlog) | one definition: `lib/learn/staging_format.py` (154 lines) |
| test coverage of the above | 0 | `tests/test-learn-propose.sh` (33 assertions) |
| `[features] auto_improvement` | `[design]`, unread | `[impl]`, still guarded no-kit-side-read |

`bash lib/gate/coverage-delta.sh check .` -> `ok: source + test moved together`. The new
behavior surface ships WITH its test surface; prior coverage of every added path = 0.

## Recheck (Rung 3)

A fresh-context `kit:recheck-verifier` was dispatched to RE-EXECUTE the LIVE-run command
(`bin/learn propose --days 30`) against the real ledgers and re-judge the outcome (not a
read-back of this table). Verdict recorded below.

<!-- RECHECK-VERDICT -->
