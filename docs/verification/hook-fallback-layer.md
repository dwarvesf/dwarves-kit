# Proof of done: hook fallback layer (SPEC-084 / ID-036)

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | section + 3-layer rule + placement test | meta pins "the section exists", "3-layer fallback rule", "hard criterion" |
| AC2 | parity, computed both sides | pin "parity: table rows == hook files (16)"; both counts computed at test time |
| AC3 | 5 hard hooks classed hard | 5 per-hook pins |
| AC4 | C3 reconciliation | pin "bounded guardrail" |
| AC5 | folds dispositioned | pin "folded concerns dispositioned" (ID-012 P2 + ID-027) |
| AC6 | Reviewer 4 autonomy-gate bullet | pin on commands/spec-validate.md |
| AC7 | still-open marker gone | negative pin |
| AC8 | suites + NC | run table |

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| failing-first | `bash tests/test-meta.sh` pre-edit | 13 RED (every SPEC-084 pin) |
| green | all three suites post-edit | meta 493/493, hooks 426/426, e2e 20/20 |
| negative control | statusline table row deleted, meta suite | parity pin RED (expected 16, got 15); restored; green |

Verdict: PASS (claim: the hook layer is declared, classed, and drift-pinned;
metric: meta pins; threshold: 14/14 green with the parity NC flipping RED).

## Reproduce

```
bash tests/test-meta.sh          # === SPEC-084 === section
ls hooks/*.sh | wc -l            # 16, must equal the inventory row count
```
