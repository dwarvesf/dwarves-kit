# Proof of done: `wrap rebase` moves a worktree branch onto origin/<default>, resolving only the safe conflicts

2026-09-27. Spec: `docs/specs/SPEC-329-rebase-resolve.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `bin/wrap`, `tests/test-wrap.sh`, `commands/wrap.md`, `docs/consumer-contract.md`, `docs/CHANGELOG.md`, `docs/implementation-notes/rebase-resolve.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: `bin/wrap rebase <worktree>` rebases the worktree's branch onto `origin/<default>` with rerere and updateRefs pinned off. At each stop it regenerates `docs/FEATURES.md` with the worktree's own generator, keeps both sides of a `docs/CHANGELOG.md` conflict only when both sides purely added lines, and aborts naming any other path (exit 1, HEAD back at the old tip). It scans the exact stage set for conflict markers before `git add`, commits only one regeneration once no rebase is stopped, refuses the main checkout, and never pushes.

## Green run

| Command | Exit | Output |
|---|---|---|
| `bash tests/test-wrap.sh` | 0 | `test-wrap: all 1369 passed` |
| `RUN_ALL_TIMEOUT_SECS=1500 bash tests/run-all.sh --changed` | 0 | `run-all: all 18 suites passed, 0 skipped for missing tooling` |

The first `run-all --changed` at the default 300s ceiling killed four long suites on time (`test-config-registry`, `test-config-seams`, `test-meta`, `test-wrap`) with no assertion failed; the rerun above raised the ceiling only.

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: bash /tmp/rb-mutate.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation is `perl -i -pe 's/if grep -qE (?=\x27\^\(<\{7\})/if false && grep -qE /' lib/wrap/wrap.sh`: the marker scan in `_rb_markers` never reports a hit. Under it the rebase block goes red on four assertions, and the rebased commit carries `+<<<<<<< HEAD` in `docs/FEATURES.md`:

```
  FAIL rebase: leftover markers exit 1
  FAIL rebase: leftover markers named
  FAIL rebase: leftover markers restore the old tip
  FAIL rebase: no marker in any reachable commit
```

The control above ran on `deedde29`, after the review fixes. An earlier control on the first feature commit also passed, but only three assertions went red: `no marker in any reachable commit` piped `git log` into `grep -q`, and pipefail hid the match. The test fix landed as its own commit and the control above ran on it.

## Review mutations

A fresh-context review returned FIX THEN SHIP. The fixes were written tests-first: before the code changed, the new cases failed 9 of 102 in the rebase block. Each pin was then removed on its own, and the rebase block rerun:

| Mutation | Result |
|---|---|
| drop `-c rerere.enabled=false` | red: `a recorded resolution is still refused by name` |
| drop `-c rebase.updateRefs=false` | red: `the stacked branch ref did not move` |
| swap `git add -- <set>` for `git add -u` | green, 102/102: equivalent while the preflight refuses tracked changes (see the implementation notes) |

## Test plan coverage

| SPEC-329 test-plan row | Block in `tests/test-wrap.sh` (rebase section) |
|---|---|
| Nothing to rebase | `nothing to rebase`, 3 assertions |
| Clean rebase | `clean rebase`, 5 assertions |
| Union handled by git | `a union-declared file`, 4 assertions |
| CHANGELOG pure additions | `CHANGELOG: both sides only added bullets`, 6 assertions |
| CHANGELOG reworded | `CHANGELOG: a reworded bullet refuses`, 4 assertions (this case caught a pipefail bug in the pure-addition test) |
| CHANGELOG line both sides added (review HIGH) | `CHANGELOG: both sides added the same line refuses`, 3 assertions |
| Generated stop | `generated FEATURES conflict`, 7 assertions |
| Generator side effect staged | `the generator's side effect`, 3 assertions |
| Empty pick after regen | `a pick left empty`, 3 assertions |
| Final regeneration | `final regeneration`, 3 assertions |
| No final commit when fresh | `clean rebase`, `no regen commit when FEATURES is fresh` |
| Refused conflict | `a hand-written conflict refuses`, 4 assertions |
| Mixed stop | `a mixed stop`, 4 assertions |
| Leftover markers | `leftover markers`, 5 assertions |
| Generator fails | `a failing generator aborts`, 3 assertions |
| No generator | `no generator in the repo`, 2 assertions |
| Union delete conflict | `a delete conflict on a union-declared file`, 2 assertions |
| Stop bound | `the stop bound aborts`, 3 assertions |
| Abort fails | `a failed abort says so`, 2 assertions, `git` shim on PATH |
| No commit while stopped | `generated FEATURES conflict`: no merge commit, one pick and no regen commit |
| Preflight refusals | `preflight refusals`: main checkout, protected name, detached HEAD, dirty tracked file, stale `index.lock`, fetch failure, rebase in progress, HEAD unchanged |
| Usage | `usage`: no argument, two arguments, unknown flag, not a repo, all 64 |
| Help | `help and usage` loop names `rebase`; `bin/wrap header names rebase` |
| rerere pinned off (review) | `a recorded rerere resolution never resolves a stop`, 4 assertions |
| updateRefs pinned off (review) | `a stacked branch ref never moves`, 2 assertions |
| Non-ASCII path (review) | `a non-ASCII path the generator changes`, 3 assertions |
| Final-pass failure prefix (review) | `a failing final regeneration`, 3 assertions; the mid-rebase generator case asserts no `AFTER REBASE` |
| Step 10 wiring (review) | `/kit:wrap step 10 runs the verb`, 3 assertions on `commands/wrap.md` |

## Not proven

- No run against a real kit worktree that fell behind `origin/master`; every case uses scratch repos with a stub generator. The real generator is the same file the verb calls, from the worktree under rebase.
- A delete or rename conflict on `docs/FEATURES.md` itself is not tested; the generator would recreate the file and the stage by name would stage it.
- Rollback: `git revert` of the feature commit. The verb holds no state; a branch it rebased is recoverable from the printed old tip or the reflog.
