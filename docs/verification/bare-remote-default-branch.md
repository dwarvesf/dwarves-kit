# Verification: gate-dispatch bare remote HEAD

`tests/test-orchestrate-gate-dispatch.sh` failed 5 assertions on both dev Macs and passed on both CI runners. The fixture created its bare upstream with `git init --bare` and no `-b`, so the remote HEAD followed the machine's `init.defaultBranch`. The seed then pushed `master`. On a machine set to `main`, the remote HEAD named a branch that never existed, `git clone` landed an empty working tree, and every assertion that reads a fixture file failed. CI runners leave the setting unset, git falls back to `master`, and the fixture matched by accident.

The fix pins the fixture's own remote: `git init -q --bare -b master`. `tests/test-premerge.sh:35` already pins its remote the same way.

## Green run

The suite must pass under BOTH git configurations, because the defect is a configuration dependency.

| # | Configuration | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | this Mac, `init.defaultBranch=main` | `bash tests/test-orchestrate-gate-dispatch.sh` | 0 | PASS |
| 2 | CI shape, no global git config | `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash tests/test-orchestrate-gate-dispatch.sh` | 0 | PASS |
| 3 | full glob, this Mac | `bash tests/run-all.sh` | 0 | PASS |

Run 1 and run 2 both ended `ALL PASS`. Run 3 ended `run-all: all 134 suites passed, 1 skipped for missing tooling`.

```
Command: bash tests/test-orchestrate-gate-dispatch.sh
PASS A1: merged-PR box flip accepted; run exits 0 (no false halt)
PASS A1: driver logs what it reconciled
PASS A1: no stale-box guardrail halt
PASS A1: clean checkout was fast-forwarded to origin/master
ALL PASS
Exit: 0
Verdict: PASS
```

## Negative control

Remove `-b master` from the fixture, run the suite, restore the file.

```
Command: sed -i '' 's/git init -q --bare -b master/git init -q --bare/' tests/test-orchestrate-gate-dispatch.sh \
         && bash tests/test-orchestrate-gate-dispatch.sh; git checkout -- tests/test-orchestrate-gate-dispatch.sh
FAIL A1: local checkout not fast-forwarded
FAIL A2: bare remote box wrongly accepted (rc=64)
FAIL A3: dirty tree handling wrong (rc=64)
(warning: remote HEAD refers to nonexistent ref, unable to checkout)
5 FAILED
Exit: 1
Verdict: RED as expected, then restored clean
```

The control bites. Without the pinned HEAD the suite returns to exactly the 5 failures the dev Macs reported.

## Reproduce

```bash
git config --global init.defaultBranch main   # the dev-Mac setting that triggers it
bash tests/test-orchestrate-gate-dispatch.sh  # ALL PASS with the fix, 5 FAILED without
```

## Scope

Five other suites create a bare remote. Only this one was exposed. `test-premerge.sh` and `test-board-publish.sh` already pass an explicit branch. `test-board-writeback.sh` reads the branch name from the fixture's own `symbolic-ref`. `test-board.sh` and `test-hooks.sh` clone their remote while it is still empty, so the clone adopts whatever HEAD names and stays self-consistent. No change was made to any of them.
