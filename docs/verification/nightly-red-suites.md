# Proof of done: board-sweep test is hermetic to an ambient GH_TOKEN

## What changed

The Mini nightly regression (`mini.kit-nightly-regression`: full `run-all.sh --all` on a fresh clone of master, credential-named variables dropped, provider tokens pinned to placeholders) has been red since 2026-10-03 and posts `kit-regression-failed`. A rehearsal of that environment on master found `test-config-registry` red (already fixed upstream by #932) and `test-board-sweep` red. `run_sweep` in `tests/test-board-sweep.sh` now drops the ambient git credential variables before it runs the sweep.

## Gate table

| Claim | Evidence |
|---|---|
| `test-board-sweep` read the job's pinned `GH_TOKEN` placeholder as a token leaked to a sync | negative control below: 52 passed, 3 failed |
| the test is now hermetic to an ambient `GH_TOKEN` | post-fix run below: 55 of 55 |
| the sweep's own token cases still pass (the in-test `BOARD_SWEEP_TOKEN=` prefixes survive `env -u`) | post-fix run below |
| the rest of the glob is green in the job environment | full glob run below |

## Root cause

| Suite | Cause | Introduced by |
|---|---|---|
| `test-board-sweep` | asserts a child sees `GH_TOKEN=UNSET` but never cleared the ambient value; the nightly launcher exports `GH_TOKEN=placeholder-gh-token` | board sweep verbs (#929) |
| `test-config-registry` | `decide.backend` and `decide.points` missing from the Root-only keys table, and a `KIT*` Perl variable with no allowlist row | per-area test picking (#927), the flick verb (#924); fixed by #932 |

## Run table

```
Command: GH_TOKEN=placeholder-gh-token bash tests/test-board-sweep.sh   (negative control: the pre-fix test file)
Exit: 1
Output:
  ok   --help prints the usage

PASS=52 FAIL=3
Result: RED as expected
```

```
Command: the nightly launcher's environment (credential-named variables dropped, placeholders pinned, empty operator overlay, KIT_RUN_ALL=1) over bash tests/run-all.sh --all, on master with the config-registry fix and before this change
Exit: 1
Output:
run-all: FAILED -> test-board-sweep
run-all: 221 suites run, 0 skipped for missing tooling
Result: RED before this change, one suite left (the one fixed here)
```
```
Command: GH_TOKEN=placeholder-gh-token bash tests/test-board-sweep.sh   (after the fix)
Exit: 0
Output:
  ok   --help prints the usage

PASS=55 FAIL=0
Verdict: PASS
```

The seven suites red on 2026-10-04 (`test-adopt`, `test-bin-forwarders`, `test-config-registry`, `test-meta`, `test-orchestrate-orca`, `test-wrap-apply`, `test-wrap-land`) pass on current master in that environment. The `proof-asset` census drift behind `test-bin-forwarders` and `test-meta` was fixed in #903.
