# Proof of done: wrap adopt adopts a repo and lands the adoption in one call

## What changed

`bin/wrap adopt [--apply] [--body-file F] <repo>...` composes `adopt.sh` with `wrap start` and `wrap land`. It dry-runs by default. With `--apply`, each repo gets a `chore/kit-adopt` worktree, an adoption commit, a logged proof override, and one landed PR. Repos run in argument order, a failure never stops the next one, an interrupt stops the batch with `not run` rows, and an `ADOPT SUMMARY` table closes the run. Contract: `docs/specs/SPEC-387-adopt-land.md`. Builder deltas: `docs/implementation-notes/adopt-land.md`.

## Gate table

| Claim | Evidence |
|---|---|
| every spec case (1-39, 34a, 34b) passes | suite run below |
| no regression in the suites the diff touches | `run-all.sh --changed` below |
| the gitignore preflight is load-bearing | negative control below |
| the dry run writes nothing in a real repo | live dry run below |
| the code matches the spec rules | review lens: no CRITICAL or WARNING findings |

## Run table

```
Command: bash tests/test-wrap-adopt.sh
Exit: 0
Output:
  PASS 39: unparseable JSON is unreadable
  PASS 39: still no resume:
test-wrap-adopt: all 207 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
run-all: --changed against 7b2ca7aa: 25 changed files -> 31 suites (26 named, the rest always-on)
run-all: 30 suites, 4 at a time, 1 serial
test-bin-forwarders                            ok (4s)
test-config-registry                           ok (42s)
test-no-personal-paths                         ok (5s)
test-wrap-adopt                                ok (67s)
run-all: all 30 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

The interrupt cases launch the verb through a perl exec that resets SIGINT to default, because `run-all.sh` starts each suite as a background job and SIGINT arrives ignored. Without it, 34a-INT and 34b-INT went red under `run-all.sh` only.

## Test plan coverage

Every row runs in `tests/test-wrap-adopt.sh` (run table above), and each assertion is labelled with its row number.

| Row | Run / skip reason |
|---|---|
| 1 | test-wrap-adopt.sh case 1 |
| 2 | test-wrap-adopt.sh case 2 |
| 3 | test-wrap-adopt.sh case 3 |
| 4 | test-wrap-adopt.sh case 4 |
| 5 | test-wrap-adopt.sh case 5 |
| 6 | test-wrap-adopt.sh case 6 |
| 7 | test-wrap-adopt.sh case 7 |
| 8 | test-wrap-adopt.sh case 8 |
| 9 | test-wrap-adopt.sh case 9 |
| 10 | test-wrap-adopt.sh case 10 |
| 11 | test-wrap-adopt.sh case 11 |
| 12 | test-wrap-adopt.sh case 12 |
| 13 | test-wrap-adopt.sh case 13 |
| 14 | test-wrap-adopt.sh case 14 |
| 15 | test-wrap-adopt.sh case 15 |
| 16 | test-wrap-adopt.sh case 16 |
| 17 | test-wrap-adopt.sh case 17 |
| 18 | test-wrap-adopt.sh case 18 |
| 19 | test-wrap-adopt.sh case 19 |
| 20 | test-wrap-adopt.sh case 20 |
| 21 | test-wrap-adopt.sh case 21 |
| 22 | test-wrap-adopt.sh case 22a and its variants |
| 23 | test-wrap-adopt.sh case 23 |
| 24 | test-wrap-adopt.sh case 24 |
| 25 | test-wrap-adopt.sh case 25a and its variants |
| 26 | test-wrap-adopt.sh case 26 |
| 27 | test-wrap-adopt.sh case 27 |
| 28 | test-wrap-adopt.sh case 28 |
| 29 | test-wrap-adopt.sh case 29 |
| 30 | test-wrap-adopt.sh case 30 |
| 31 | test-wrap-adopt.sh case 31 |
| 32 | test-wrap-adopt.sh case 32a and its variants |
| 33 | test-wrap-adopt.sh case 33 |
| 34a, 34b | test-wrap-adopt.sh cases 34a and 34b, INT and TERM each, also green under `run-all.sh` |
| 35 | test-wrap-adopt.sh case 35 |
| 36 | test-wrap-adopt.sh case 36 |
| 37 | test-wrap-adopt.sh case 37 |
| 38 | test-wrap-adopt.sh case 38 |
| 39 | test-wrap-adopt.sh case 39 |

## Negative control

```
Command: bash lib/gate/negctl.sh . "bash tests/test-wrap-adopt.sh" "<line 326: the check-ignore hit no longer adds a refusal>"
Exit: 0 (green before mutation)
Changed: lib/wrap/wrap-adopt.sh
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-adopt: 202 passed, 5 FAILED of 207
Restore: git checkout HEAD -- lib/wrap/wrap-adopt.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Live dry run (two local repos, read-only)

```
Command: bin/wrap adopt <workspace>/ops-toolkit <workspace>/til
Exit: 1
Output:
== <workspace>/ops-toolkit
    adopt: single-source mode on (adopt.single_source knob)
  result: - refused: adopt --dry-run: adopt: --single-source refuses: <workspace>/ops-toolkit/CLAUDE.md and <workspace>/ops-toolkit/AGENTS.md both exist and differ; merge them by hand
== <workspace>/til
    adopt: --dry-run for <workspace>/til (changes above)
  result: - refused: .claude/settings.json is gitignored
ADOPT SUMMARY
  ops-toolkit  -  refused: adopt --dry-run: ...
  til          -  refused: .claude/settings.json is gitignored
Verdict: PASS
```

Exit 1 is correct: neither row is `would adopt`. Afterwards `til` showed a clean `git status`, one worktree, and no `chore/kit-adopt` branch. The `til` refusal is the gitignore preflight the negative control mutates, firing on a real repo. `--apply` was not run live: it opens and merges a PR, and it is operator-only.

## Rollback

The verb: revert its squash commit on master. Nothing else depends on it, and `adopt.sh`, `wrap start` and `wrap land` are unchanged.

One adoption `--apply` landed: it is one squash commit on the target repo's default branch, subject `ADOPT_COMMIT_SUBJECT`. Revert that commit with `git revert <sha>` through a normal PR. A failed run leaves its `chore/kit-adopt` worktree and branch for `resume: wrap land <wt>`; to abandon it instead, remove that worktree and branch by hand.
