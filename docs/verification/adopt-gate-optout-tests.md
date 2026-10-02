# Verification: adopt and gate opt-out tests green again

Fixes three failures on master. Two tests, three causes, none environmental (both tests pin the operator layer; reruns with an empty `XDG_CONFIG_HOME` match).

| Failure | Cause | Fix |
|---|---|---|
| `test-adopt.sh` known list incomplete | `agents-known.sha256` lacked the AGENTS.md version from the lanes-as-data change | regenerated with `lib/adopt/known-hashes.sh` |
| `test-gate-opt-out.sh` proof_of_done and lane_gates still blocked | `.kit.toml` is now a hard path and the floor reads `lane_gates` at the merge base; the test committed the opt-out on the feature branch | opt-out lands on main, branch rebased; a new NC pins that a branch-level opt-out still hits the floor |
| `test-gate-opt-out.sh` lint: hooks read config | `harvest_sweep.py` re-implemented the TOML reader; two comments named the file | the sweep calls `kit_config_get_root` through `lib/config/kit-config.sh`; comments reworded |

## Green runs

Command: `bash tests/test-adopt.sh`
Exit: 0
Output (excerpt): `PASS=55 FAIL=0`
Verdict: PASS

Command: `bash tests/test-gate-opt-out.sh`
Exit: 0
Output (excerpt): `PASS no hooks/*.sh names the config file (leaked: none)` then `ALL PASS`
Verdict: PASS

Command: `XDG_CONFIG_HOME=<empty dir> bash tests/test-harvest-sweep.sh` (the sweep resolver changed)
Exit: 0
Output (excerpt): `Passed: 637 / 637`
Verdict: PASS

## Negative control

Command: fixes stashed (`git stash -- lib hooks tests`), both tests rerun, stash popped.
Exit: 1 (adopt), 1 (gate)
Output (excerpt): `NOT ok - known list complete against git log (1 missing...)`, `PASS=54 FAIL=1`; `FAIL proof_of_done=false still blocked`, `FAIL lane_gates=false still blocked`, `FAIL hook reads config`, `FAILS: 3`
Verdict: PASS (red without the fix, green with it)
