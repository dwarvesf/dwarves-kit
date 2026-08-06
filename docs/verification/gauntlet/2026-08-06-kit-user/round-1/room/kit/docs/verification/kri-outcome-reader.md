# Proof of done: reconcile proof-table-gen's OUTCOME reader to the real 01 marker (SPEC-133)

`lib/gate/proof-table-gen.py` (SPEC-132, sub-goal 05) parsed an **assumed** single-line OUTCOME
shape (`caught=<bool> [dur_ms=<N>]`). `lib/gate/gate-ledger.sh`'s `outcome()`/`outcome_read()`
(SPEC-129, sub-goal 01) merged with a **different, real** shape: a `start`/`end` line pair
per phase, duration in seconds as `dur_s=`. The DURATION column never populated from real
01 data (`dur_ms=` never emitted); the CAUGHT column's match was an unmodeled regex
coincidence, not a designed pairing. This closes the gap: the parser now models the real
`start`/`end` event field, reads `caught=`/`dur_s=` off the `end` line, and falls back to an
`end.at - start.at` epoch delta if `dur_s=` is ever absent.

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Test | Result |
|---|---|---|---|
| 1 | Real-01-format OUTCOME pair (`start`+`end`, `caught=true dur_s=N`) round-trips into the Caught + Duration (s) columns | T2 | PASS |
| 2 | A GATE-covered phase with no OUTCOME lines still renders `n/a`/`n/a` per row (unchanged) | T2 (partial fixture) | PASS |
| 3 | Zero OUTCOME lines anywhere still renders the plain 5-column table (unchanged) | T1/T3 | PASS |
| 4 | `dur_s=` absent on the end line falls back to the `at=` epoch delta | T2C (new) | PASS |
| 5 | `tests/test-proof-table-gen.sh` green after the fixture correction | full suite | PASS (25/25) |
| 6 | Negative control: reverting the parser turns the real-format assertions RED | manual revert run | PASS (5 assertions RED, all in T2/T2C) |
| 7 | No regression in the wider meta-suite | `tests/test-meta.sh` | PASS (667/667) |

## Confirmation run-table

| Run | Command | Exit | Verdict |
|---|---|---|---|
| green | `bash tests/test-proof-table-gen.sh` | 0 | PASS (25/25 assertions) |
| negative control | `lib/gate/proof-table-gen.py` stashed back to the pre-fix parser, re-run | 1 | RED-as-expected (5 assertions failed, all real-01-format: T2 Caught/Duration header, T2 spec row, T2 build row, T2C fallback-duration row, plus the derived acceptance FAIL row printed on stderr/stdout) |
| restore | `git stash pop` then `bash tests/test-proof-table-gen.sh` | 0 | PASS (25/25, back to green) |
| cross-platform | `/bin/bash tests/test-proof-table-gen.sh` (bash 3.2.57, macOS system bash) | 0 | PASS (25/25) |
| no-regression | `bash tests/test-meta.sh` | 0 | PASS (667/667) |
| standalone parser check | `python3 -c "..."` importing `parse_ledger()` directly against a hand-built real-01-format fixture | n/a | `outcomes = {'spec': {'caught': 'true', 'dur_s': '42'}}` (both fields populated) |

## Run detail

### Green (25/25)

```
Command: bash tests/test-proof-table-gen.sh
Exit: 0
Verdict: proof-table-gen green.
Passed: 25 / 25
```
All 25 assertions pass, including the corrected T2 (real 01 start/end pair, both phases
populate Caught + Duration (s)), T2's partial-fixture per-row degrade, the new T2C
(dur_s= absent -> epoch-delta fallback), and the unchanged T1/T3/T4/T5/T7/T8 additive-
tolerance and canonical-file-protection assertions.

### Negative control (revert -> RED -> restore)

To prove the fix is load-bearing (not decorative), the parser fix in
`lib/gate/proof-table-gen.py` was stashed (`git stash push -- lib/gate/proof-table-gen.py`),
restoring the pre-fix regex-only OUTCOME reader, and the suite re-run against the
now-updated (real-01-format) fixtures:

```
Command: bash tests/test-proof-table-gen.sh   (with the pre-fix parser)
Exit: 1
Verdict: 5 assertions failed
```
The failures were exactly the real-01-format assertions:
- T2: "Caught/Duration columns appear when OUTCOME lines exist" (label mismatch:
  pre-fix still emits `Duration (ms)`)
- T2: "spec row populates caught=false dur=12 ..." (dur column stayed `n/a`, since
  pre-fix never reads `dur_s=`)
- T2: "build row populates caught=true dur=43 ..." (same)
- T2: "spec row still populates in the partial fixture" (same)
- T2C: "dur_s= absent -> duration derived from end.at - start.at epoch delta (45)"
  (pre-fix has no fallback path at all)

`git stash pop` restored the fix; re-running returned the suite to 25/25 green (Exit 0).
The fix is load-bearing: without it, a genuinely real-format OUTCOME pair still renders
`n/a` for Duration and carries the stale `(ms)` label.

### Cross-platform

```
Command: /bin/bash tests/test-proof-table-gen.sh
bash version: GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
Exit: 0
Verdict: PASS (25/25)
```
The change is pure Python (portable) plus bash-heredoc test fixtures with no BSD-sensitive
constructs (no `date -d`/`-r`, no `stat -f`, no `sed -i ''`), so no cross-platform risk.

### No-regression (wider meta-suite)

```
Command: bash tests/test-meta.sh
Exit: 0
Verdict: All meta tests passed.
Passed: 667 / 667
```

## Reproduce

```
cd <repo>
bash tests/test-proof-table-gen.sh                 # 25/25 green
/bin/bash tests/test-proof-table-gen.sh            # cross-platform (macOS bash 3.2)
bash tests/test-meta.sh                            # 667/667, no regression

# negative control
git stash push -- lib/gate/proof-table-gen.py
bash tests/test-proof-table-gen.sh                 # 20/25, 5 real-01-format assertions RED
git stash pop
bash tests/test-proof-table-gen.sh                 # 25/25 green again
```
