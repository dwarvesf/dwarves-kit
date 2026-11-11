# Verification -- proof-contract-visual-master-table

The nightly regression run of 2026-11-11 (master at f50c321) failed two suites. `test-proof-contract-visual` is a real defect in the test; `test-flick` is not a code regression.

## Causes

| Suite | Cause | Added by | Reproduced |
|-------|-------|----------|------------|
| test-proof-contract-visual | case 22 copies only `origin/master:lib/gate/proof-gate.sh` into a temp tree. Since #1140 that file sources `proof-classes.sh` (and reads `proof-classes.tsv`) from its own directory, so master's gate cannot start and both byte-identity checks fail (2 of 5) | #1140 | yes, on the nightly commit |
| test-flick | not fixed here, see below | none | no code change; one symptom-identical failure, then green |

The suite passed in #1140's own PR because `origin/master` then still had the old gate with no class table; the test is red only once the table is on master itself.

## Fix

`tests/test-proof-contract-visual.sh` case 22 now also extracts master's `proof-classes.sh` and `proof-classes.tsv` into the temp tree. No change to `proof-gate.sh`.

## Green run

```
Command: bash tests/test-proof-contract-visual.sh
Exit: 0
Output:
  PASS project visual=false: contract output identical to master
  PASS no .kit.toml at all: contract output identical to master
  PASS verify.md gates the capture step on proof.visual and points at bin/proof-asset put
  ALL PASS (5/5)
Verdict: PASS
```

## Negative control (the fix stashed, then restored)

```
Command: git stash; bash tests/test-proof-contract-visual.sh; git stash pop
Exit: 1
Output:
  .../master/lib/gate/proof-gate.sh: line 55: .../master/lib/gate/proof-classes.sh: No such file or directory
  FAIL project visual=false: output drifted from master
  FAIL no .kit.toml at all: output drifted from master
  2/5 FAILED
Verdict: PASS (the unfixed test fails exactly as in the nightly log; the fixed test passes)
```

## test-flick: not a cause found in code

`tests/test-flick.sh`, `tests/lib/flick-stub.py`, and `bin/flick` were untouched between the last green nightly (62b3d914) and f50c321; the range only adds `tests/lib/host-slots.sh` (#1137) and `tests/lib/wrap-stub.sh` (#1139). The nightly failure is the stub never publishing its port within the 5 s wait in `start_stub` (`stub listens on a port` is the first failure; every later json is empty or `bad_input`).

```
Command: bash tests/test-flick.sh   (three runs, default PATH)            -> flick: 346 passed, 0 failed (x3)
Command: PATH=<nightly PATH> bash tests/test-flick.sh                     -> flick: 346 passed, 0 failed
Command: six runs at once under the nightly PATH                          -> 111 passed, 236 failed (x6, first try, stub not up)
Command: the same six runs, repeated twice                                -> 345 or 346 passed, 0 or 1 failed
```

The nightly PATH resolves `python3` to Homebrew's 3.15.2, which also failed to publish a port inside a 3 s probe on its first launch here, then started in 0.14 s on every later run. The likely cause is a slow cold start of that interpreter under load, with a fixed 5 s wait. The same parallel load also flaked `the descendant was killed with its group` in 4 of 6 runs, so the suite is load-sensitive. Not fixed: the evidence does not pin the cold-start cause, and a longer wait would only hide the next one.
