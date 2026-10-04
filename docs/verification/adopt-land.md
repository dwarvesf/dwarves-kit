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
