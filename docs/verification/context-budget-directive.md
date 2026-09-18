# Proof of done: context-budget turns directive one band past the budget

## What changed

`hooks/context-budget.sh` spoke with one tone at every band: an advisory that asked the model to recommend a handoff at the next boundary. Measured over 14 days on one operator machine, that advisory fired 227 times across 89 sessions and changed nothing. 72 lead sessions ran past 400 turns, 25 past 800, peak context 996k on the 1M-window model, 9 compactions in total.

The hook now keeps the band-0 advisory and, from band 1 (`KIT_CTX_WARN + KIT_CTX_STEP`) upward, speaks as a directive: finish the step in flight, write the handoff, stop opening sub-tasks or dispatching subagents, tell the operator in one line to `/clear`. Band math, state file, and the fail-open contract are unchanged. `tests/test-context-budget.sh` gains case 7: both tones, plus the silent and directive outcomes under an env-set 450k threshold.

## Gate table

| Claim | Evidence |
|---|---|
| band 0 still carries the advisory text | case 7.1, run table below |
| band 1 carries the directive text | case 7.2, run table below |
| an env-set 450k threshold stays silent at 250k | case 7.3, run table below |
| an env-set 450k threshold is a directive at 560k | case 7.4, run table below |
| the 13 ported cases still hold | run table below |
| the new cases are load-bearing | negative control below |
| tree-wide lints still hold | run table below |

## Run table

```
Command: bash tests/test-context-budget.sh
Exit: 0
Results: 17 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
run-all: all 8 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

```
Command: git show HEAD~1:hooks/context-budget.sh >| hooks/context-budget.sh; bash tests/test-context-budget.sh
Exit: 1
  FAIL 7.2 310k, band 1, directive                        missing CONTEXT CEILING
  FAIL 7.4 560k with WARN=450000, band 1                  missing CONTEXT CEILING
Verdict: RED (expected)
```

```
Command: git checkout hooks/context-budget.sh; bash tests/test-context-budget.sh
Exit: 0
Results: 17 passed, 0 failed
Verdict: PASS (restored)
```

## Reproduce

From a clean checkout of this branch: `bash tests/test-context-budget.sh`. Hermetic HOME, no network, jq only.
