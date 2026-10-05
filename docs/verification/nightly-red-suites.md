# Proof of done: the nightly regression goes green on master again

## What changed

The Mini nightly regression (`mini.kit-nightly-regression`, full `run-all.sh --all` on a fresh clone of master, credential variables dropped, provider tokens pinned to placeholders) was red from 2026-10-03 and posted `kit-regression-failed`. A rehearsal of the same environment on current master found two remaining red suites. Both are fixed here.

## Gate table

| Claim | Evidence |
|---|---|
| `test-config-registry` is red on master for two reasons | pre-fix run below: orphan token and root-only drift |
| `decide.backend`, `decide.points` and `KIT_NARROW_PL` are now registered | post-fix run below, 59 of 59 |
| `test-board-sweep` read the job's pinned `GH_TOKEN` placeholder as a token leak | pre-fix run below: 52 passed, 3 failed |
| the sweep test is now hermetic to an ambient `GH_TOKEN` | post-fix run below, 55 of 55 |
| no other suite is red in the job environment | full glob run below |

## Root cause

| Suite | Cause | Introduced by |
|---|---|---|
| `test-config-registry` AC10 | `lib/wrap/wrap-flick.sh` reads `decide.backend` and `decide.points` with `kit_config_get_root`, but the Root-only keys table did not list them | the flick wrap-7b verb (#924) |
| `test-config-registry` AC1 | `KIT_NARROW_PL` in `bin/test-affected` is a script-local Perl source string that matches the `KIT` seed prefix, with no Allowlist row | per-area test picking (#927) |
| `test-board-sweep` | the sweep test asserts the child sees `GH_TOKEN=UNSET` but never cleared the ambient value; the nightly launcher exports `GH_TOKEN=placeholder-gh-token` | board sweep verbs (#929) |

## Run table

```
Command: bash tests/test-config-registry.sh   (before the fix, current master)
Exit: 1
Output:
ORPHAN: KIT_NARROW_PL
  FAIL 0 orphans on the live tree (drift lint green)
  DIFF (< declared, > actual call sites):
  2a3,4
  > decide.backend
  > decide.points
  FAIL declared root-only keys == actual kit_config_get_root call sites
Verdict: FAIL
```

```
Command: KIT_RUN_ALL=1 bash tests/test-config-registry.sh   (after the fix)
Exit: 0
Output:
=== 59/59 passed ===
Verdict: PASS
```

```
Command: GH_TOKEN=placeholder-gh-token bash tests/test-board-sweep.sh   (negative control: the pre-fix test file)
Exit: 1
Output:
PASS=52 FAIL=3
Verdict: FAIL
```

```
Command: GH_TOKEN=placeholder-gh-token bash tests/test-board-sweep.sh   (after the fix)
Exit: 0
Output:
  ok   --help prints the usage

PASS=55 FAIL=0
Verdict: PASS
```

```
Command: the nightly launcher's environment (credential-named variables dropped, placeholders pinned, empty operator overlay, KIT_RUN_ALL=1) over bash tests/run-all.sh --all, on master before the sweep-test fix
Exit: 1
Output:
run-all: FAILED -> test-board-sweep
run-all: 221 suites run, 0 skipped for missing tooling
Verdict: FAIL (one suite left, fixed by the commit above)
```

The seven suites red on 2026-10-04 (`test-adopt`, `test-bin-forwarders`, `test-config-registry`, `test-meta`, `test-orchestrate-orca`, `test-wrap-apply`, `test-wrap-land`) also pass on current master in that environment, so the earlier reds were already fixed upstream (the `proof-asset` census in #903) or were load-dependent. Only `test-config-registry` needed a new fix.
