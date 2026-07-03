# Proof of done: advisory coverage-delta gate (SPEC-130)

Advisory coverage-delta gate `lib/coverage-delta.sh`: flags an under-tested behavioral diff,
quiet on a well-tested one, exempt on docs/test/generated-only, ALWAYS exits 0 (never blocks).

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Test | Result |
|---|---|---|---|
| 1 | under-tested diff -> FLAGGED (names the file) | T1 | PASS |
| 2 | well-tested diff -> NOT flagged (**false-positive NC, load-bearing**) | T2 | PASS |
| 3 | docs/test/generated-only -> exempt | T3, T5, T6 | PASS |
| 4 | ADVISORY: a flagged diff still exits 0 (cannot block) | T4 | PASS |
| 5 | warning names what is under-covered | T1 | PASS |
| 6 | diff-plumbing reuse: staged-only change is seen | T8 | PASS |
| 7 | real-runner hook (non-zero runner still exit 0) | T9 | PASS |
| 8 | ledger record: `\| GATE \| coverage-delta \| ran \|` w/ src=/test= | T10 | PASS |

## Confirmation run-table

| Run | Command | Exit | Verdict |
|---|---|---|---|
| green | `bash tests/test-coverage-delta.sh` | 0 | PASS (17/17 assertions) |
| negative control | test-class detection disabled, re-run | 1 | RED-as-expected (T2 false-positive NC fires) |
| restore | `bash tests/test-coverage-delta.sh` | 0 | PASS (17/17, back to green) |
| no-regression | `bash tests/test-meta.sh` | 0 | PASS (667/667) |
| cross-platform | `/bin/bash tests/test-coverage-delta.sh` (bash 3.2.57) | 0 | PASS (17/17) |
| dogfood | `bash lib/coverage-delta.sh check .` (this branch) | 0 | `ok: source + test moved together (src=203 test=100)` |

## Run detail

### Green (17/17)

```
Command: bash tests/test-coverage-delta.sh
Exit: 0
Verdict: PASS
```
All 17 assertions pass, including T2 (the false-positive negative control: a well-tested diff
does NOT trip) and T4 (a FLAGGED diff still exits 0 , advisory cannot block).

### Negative control (revert -> RED -> restore)

To prove the source-vs-test classification is load-bearing (not decorative), the test-class
detection in `classify_path` was disabled so a test file falls through to `source`. Re-running
the suite turned the false-positive NC RED:

```
Command: bash tests/test-coverage-delta.sh   (with test-class detection disabled)
Exit: 1
Verdict: RED-as-expected
- NEGATIVE CONTROL: T2 (false-positive NC) went RED:
  "FAIL T2 (NC) well-tested diff wrongly FLAGGED: [coverage-delta] WARNING under-tested: 4
   source line(s) changed with no matching test change"
  (T5 test-only-exempt and T7 classification also flipped, confirming the class is load-bearing)
```

Restoring `lib/coverage-delta.sh` returned the suite to 17/17 green (Exit 0). The classification
is load-bearing: without it, a genuinely well-tested diff is wrongly flagged , exactly the
false positive the gate exists to avoid.

## Reproduce

```
cd <repo>
bash tests/test-coverage-delta.sh        # 17/17 green
/bin/bash tests/test-coverage-delta.sh   # cross-platform (macOS bash 3.2)
bash tests/test-meta.sh                  # 667/667, no regression
bash lib/coverage-delta.sh check .       # live: advisory line on this branch, exit 0
```
