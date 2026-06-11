# Proof of done: operator doc sync (SPEC-085 / ID-070)

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | hooks block: summary == files == rows; ship-gate + codebase-index present | parity pins x2 + content pin |
| AC2 | commands block: summary == files == rows; adopt + test-plan-review-team present | parity pins x2 + content pin |
| AC3 | six stale descriptions refreshed | context-readiness board pin; review-team/verify rows in diff |
| AC4 | pins computed both sides | pin source: `ls hooks/*.sh \| wc -l` vs grep'd summary number |
| AC5 | suites + NC | run table |

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| failing-first | `bash tests/test-meta.sh` pre-edit | 7 RED (every SPEC-085 pin) |
| green | all three suites post-edit | meta 500/500, hooks 426/426, e2e 20/20 |
| negative control | ship-gate row deleted from README, meta suite | 2 RED (row parity 16 vs 15, ship-gate content pin); restored; green |

Verdict: PASS (claim: the three operator docs match shipped reality and the
README tables are drift-pinned; metric: meta pins; threshold: 7/7 green with
the NC flipping 2 RED).

## Reproduce

```
bash tests/test-meta.sh                 # === SPEC-085 === section
ls hooks/*.sh | wc -l                   # must equal README hooks summary + rows
ls commands/*.md | wc -l                # must equal README commands summary + rows
```
