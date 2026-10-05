# Proof of done: the mega gate applies the ship-gate's diff and spec rules

## What changed

`lib/goal/mega-merge.sh gate` ran only the ledger check. `hooks/ship-gate.sh` also blocks a large normal-lane spec with no validate record and a hard-path diff whose full-lane gates have not run. Both rules now live in `lib/gate/ship-rules.sh`; the hook and the mega gate call it. A green mega gate means the push passes both rules.

## Gate table

| Claim | Evidence |
|---|---|
| a large normal spec without validate blocks in both gates, same message | case a, run 1 |
| a validate override clears both | case b, run 1 |
| a hard-path diff under a normal ledger blocks in both, same message | case c, run 1 |
| every full phase recorded clears both | case d, run 1 |
| a small spec with no hard path passes both (no regression) | case e, run 1 |
| a hard-path diff with no spec blocks in both | case f, run 1 |
| hook messages and exit codes match master | run 2 |
| the existing gate suites hold | runs 3 to 9 |
| the helper call is load-bearing | negative control |

## Run table

Run 1: the five requested cases plus a no-spec floor case.

```
Command: bash tests/test-mega-gate-parity.sh
Exit: 0
ok - a large normal spec without validate: ship gate exit 2, mega gate exit 1, same message
ok - b large spec with a validate override: ship gate exit 0, mega gate exit 0
ok - c hard path under a normal ledger: ship gate exit 2, mega gate exit 1, same message
ok - d hard path with every full phase recorded: ship gate exit 0, mega gate exit 0
ok - e small spec, no hard path: ship gate exit 0, mega gate exit 0
ok - f hard path, no spec, no ledger: ship gate exit 2, mega gate exit 1, same message
PASS=6 FAIL=0
Verdict: PASS
```

Run 2: hook stderr and exit code, master's copy (git archive of the base commit) against this branch, on the same fixture repos, kit path normalised.

```
Command: scratch script running hooks/ship-gate.sh from both kit copies on the case a, b, c, d and no-spec fixtures
Exit: 0
SAME large-spec block master-rc=2 mine-rc=2 bytes=819
SAME large-spec override master-rc=0 mine-rc=0 bytes=159
SAME floor block master-rc=2 mine-rc=2 bytes=989
SAME floor pass master-rc=0 mine-rc=0 bytes=0
SAME floor no-spec block master-rc=2 mine-rc=2 bytes=1422
Verdict: PASS (byte-identical)
```

Runs 3 to 9: existing suites, one at a time.

```
Command: bash tests/test-mega-merge.sh
Exit: 0
=== 30/30 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-ship-gate-coverage-map.sh
Exit: 0
PASS=10 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-ship-gate-fail-closed.sh
Exit: 0
PASS=11 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-ship-gate-impl-notes.sh
Exit: 0
PASS=19 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-ship-gate-profiles.sh
Exit: 0
ALL PASS (3 profiles x allow+block)
Verdict: PASS
```

```
Command: bash tests/test-hooks.sh
Exit: 0
Passed: 826 / 826
Verdict: PASS
```

The first test-hooks run failed one case (6c: the hook run with a plugin root that has no lib/ must still reach the BACKLOG advisory). The hook exited early when the helper was missing from the plugin root. It now falls back to its own checkout's helper; the rerun above is green.

## Negative control

Committed first (0f62c72a). A saved copy of `lib/goal/mega-merge.sh` was kept outside the tree; the `_ship_rules_gate` call in `gate` was replaced with `return 0`.

```
Command: bash tests/test-mega-gate-parity.sh   (helper call dropped)
Exit: 1
NOT ok - a ... got ship 2, mega 0
NOT ok - c ... got ship 2, mega 0
NOT ok - f ... got ship 2, mega 0
PASS=3 FAIL=3
Verdict: RED, as required: the mega gate passes while the ship gate blocks
```

Restored with `command cp -f`; `git status` clean and the same command exits 0 again.

```
Command: bash tests/test-mega-gate-parity.sh   (restored)
Exit: 0
PASS=6 FAIL=0
Verdict: PASS
```

## Project lane config (case g)

`gate` now runs the lane ledger check through `ship_rules_ledger_check`, which sets `KIT_PROJECT_ROOT` to the repo, as the hook does. Before, the check read `$PWD/.kit.toml`, so a mega gate run from a subdirectory ignored a project lane override. Case g commits a clean `.kit.toml` that makes `docs` required for the normal lane and runs the mega gate from `sub/`.

```
Command: bash tests/test-mega-gate-parity.sh
Exit: 0
ok - g project lane override: ship gate exit 2, mega gate exit 1, both name docs
PASS=7 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-mega-merge.sh; bash tests/test-ship-gate-fail-closed.sh; bash tests/test-ship-gate-impl-notes.sh; bash tests/test-ship-gate-coverage-map.sh; bash tests/test-ship-gate-profiles.sh; bash tests/test-hooks.sh
Exit: 0 for each (30/30, 11/11, 19/19, 10/10, all pass, 826/826)
Verdict: PASS
```

Negative control (committed first, 7ba3552e): in `mega-merge.sh` the `ship_rules_ledger_check` call was replaced with the bare `bash "$GATE_LEDGER" check`.

```
Command: bash tests/test-mega-gate-parity.sh   (KIT_PROJECT_ROOT dropped from the mega gate)
Exit: 1
NOT ok - g want ship 2 / mega 1 / MISSING-GATE: docs; got ship 2, mega 0
PASS=6 FAIL=1
Verdict: RED, as required
```

Restored with `command cp -f`; the same command exits 0 again (PASS=7).
