# Proof of done: `wrap merge` recovers a stacked child and labels a zero-check head

2026-10-25. Lane: normal (the classifier suggests full, kit-machinery; the operator assigns full). Files: `lib/wrap/wrap-merge.sh`, `lib/wrap/wrap-ci.sh`, `lib/wrap/wrap.sh`, `tests/test-wrap-merge-stacked.sh`, `tests/test-wrap-ci.sh`, `bin/test-affected.timeouts`, `commands/wrap.md`, `docs/wrap.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md`.

Two gaps from one real session:

1. A child PR stacked on a parent that squash-merged stayed CONFLICTING after the retarget, and `wrap merge --apply --pr` refused it ("conflict beyond the union-marked files", "does not contain origin/main; not the carried-base case"). `--pr N --rebase-stacked` now runs the hand fix: `git rebase --onto origin/<default> <parent's last pushed head>`, optional `--verify`, then one `--force-with-lease` push of the PR's own branch, then the usual gate and merge.
2. On a repo where CI runs only when the `ci` label is added, a new head with no check runs read an empty rollup on a non-CLEAN state and `wrap merge` refused it as pending. `--pr N` now runs the same `_ci_label_sync` and `_ci_checks_wait` that `land` uses when the head reports no checks and the repo carries an exact `ci` label.

Decision on the flag: `--rebase-stacked` is opt-in. The existing design says the opposite of allowing it: `commands/wrap.md` lists "Never force-pushes" and "Never rewrites history", `lib/wrap/wrap-common.sh` explains why the conflict recovery is a merge ("a rebase would rewrite pushed history and force the push"), and `docs/wrap.md` says `wrap rebase` never pushes. A force-push to an own PR head is therefore not an allowed default, so the operator names it. Those docs now name the one exception.

Decision on the ci label: the label step runs under `--pr` without `--with-ci`, only when the head has zero check runs and the exact `ci` label exists. The `--with-ci` gate stays as it was for every other case (label every merge, wait, refuse an empty rollup), and a PR armed here skips the gate's second sync.

## Guards

| Guard | Refuses when | Case |
|---|---|---|
| Opt-in | `--rebase-stacked` absent: the same conflict is never rewritten | `no flag` |
| Scope | no `--pr`, or `--repo` (no checkout) | `flag shape` |
| Rebase conflict | `git rebase` stops: files named, rebase aborted, branch back at the PR head, nothing pushed | `conflict`, `conflict, held` |
| Head | origin's branch is not the head the gates read | `stale head` |
| PR kind | fork PR, armed auto-merge, unreadable PR | `fork PR`, `auto-merge armed` |
| Dependents | an open PR still targets the branch | `dependents` |
| Parent | none found: not the stacked case, falls through; several: the chain tip wins | `no parent`, `happy` |
| Verify | `--verify` red: rebase undone, nothing pushed | `verify red` |
| Lease | another writer pushed between the rebase and the push: push refused, their commit survives | `lease` |
| Push scope | exactly one leased push, to the PR branch, never main, never a plain force or `+` refspec | `happy` (git trace) |
| ci label | a label that will not set exits 2 and merges nothing | `zero-check noset` |
| ci label | no exact `ci` label, or a head that reports checks: no label call | `zero-check no-label repo`, `zero-check with checks` |

## Green run

```
Command: bash tests/test-wrap-merge-stacked.sh
Exit: 0
Output: test-wrap-merge-stacked: all 63 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-ci.sh
Exit: 0
Output: test-wrap-ci: all 152 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge.sh
Exit: 0
Output: test-wrap-merge: all 410 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output: run-all: --changed against c34a8647: 10 changed files -> 44 suites (38 named, the rest always-on)
        test-wrap-ci                                   ok (32s)
        test-wrap-merge-stacked                        ok (11s)
        test-wrap-merge                                ok (81s)
        run-all: all 44 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

`test-wrap-ci` grew from 127 to 152 assertions (25 new, the zero-check section), `test-wrap-merge-stacked` is new (63), and `test-wrap-merge` is unchanged at 410, so no existing assertion moved.

## Negative control

Run at `3229ccd1`, tree clean, with `lib/gate/negctl.sh --parallel`. Each control applies one exact-string mutation from `docs/verification/wrap-merge-stacked-ci/negctl-mutations.py` (it fails if the string is not found exactly once) to a throwaway copy, and the suite must go green, then red, then green after the restore. The first run of NC1 stayed green: git dropped the replayed parent commits as empty because the squash carried the same lines. The fixture was changed in `3229ccd1` so the parent's second commit edits its first commit's line, and NC1 then went red.

| Control | Mutation | Suite | Red run | Red cases | Verdict |
|---|---|---|---|---|---|
| NC1 | `rebase --onto origin/<def> <parent>` becomes a plain `rebase origin/<def>` | `test-wrap-merge-stacked` | 47 passed, 16 FAILED of 63 | `happy:` and `held:` (the rebase conflicts on the parent's commits) | PASS |
| NC2 | the leased push becomes `--force` | `test-wrap-merge-stacked` | 57 passed, 6 FAILED of 63 | `happy: the lease names the head`, `happy: no plain --force`, `lease:` (3) | PASS |
| NC3 | the conflict branch no longer aborts the rebase | `test-wrap-merge-stacked` | 56 passed, 7 FAILED of 63 | `conflict:` and `conflict, held:` (checkout left mid-rebase) | PASS |
| NC4 | the stacked recovery ignores the missing `--rebase-stacked` | `test-wrap-merge-stacked` | 62 passed, 1 FAILED of 63 | `no flag: no rebase is announced` | PASS |
| NC5 | the dependents guard never fires | `test-wrap-merge-stacked` | 58 passed, 5 FAILED of 63 | `dependents: refused by name`, then the fork and auto-merge cases that ride the rewritten branch | PASS |
| NC6 | the fork and auto-merge guard is `true` | `test-wrap-merge-stacked` | 60 passed, 3 FAILED of 63 | `fork PR: refused by name`, `auto-merge armed: refused by name` | PASS |
| NC7 | the first merged parent wins, not the chain tip | `test-wrap-merge-stacked` | 62 passed, 1 FAILED of 63 | `happy: names the parent it cut at` | PASS |
| NC8 | the zero-check label sync is never called | `test-wrap-ci` | 140 passed, 12 FAILED of 152 | `zero-check --pr:`, `re-add:`, `noset:`, `--with-ci:` | PASS |
| NC9 | a PR armed by the zero-check step does not skip the gate's second sync | `test-wrap-ci` | 150 passed, 2 FAILED of 152 | `zero-check --with-ci: the labels were probed once`, `the label was added once` | PASS |

```
Command: bash lib/gate/negctl.sh --parallel 4 "$PWD" "bash tests/test-wrap-merge-stacked.sh" "python3 docs/verification/wrap-merge-stacked-ci/negctl-mutations.py NC1" ... "... NC7"
Exit: 0
Output:
  NC1 test-wrap-merge-stacked: 47 passed, 16 FAILED of 63
  NC2 test-wrap-merge-stacked: 57 passed, 6 FAILED of 63
  NC3 test-wrap-merge-stacked: 56 passed, 7 FAILED of 63
  NC4 test-wrap-merge-stacked: 62 passed, 1 FAILED of 63
  NC5 test-wrap-merge-stacked: 58 passed, 5 FAILED of 63
  NC6 test-wrap-merge-stacked: 60 passed, 3 FAILED of 63
  NC7 test-wrap-merge-stacked: 62 passed, 1 FAILED of 63
Verdict: PASS (7 of 7 controls; each also green again after the restore)
```

```
Command: bash lib/gate/negctl.sh --parallel 2 "$PWD" "bash tests/test-wrap-ci.sh" "python3 docs/verification/wrap-merge-stacked-ci/negctl-mutations.py NC8" "... NC9"
Exit: 0
Output:
  NC8 test-wrap-ci: 140 passed, 12 FAILED of 152
  NC9 test-wrap-ci: 150 passed, 2 FAILED of 152
Verdict: PASS (2 of 2 controls; each also green again after the restore)
```

Every control restored `lib/wrap/wrap-merge.sh` to HEAD; `git status` was clean after both runs.

## Not proven

- A real GitHub squash merge and a real protected branch. The stub models `gh`; a protected PR branch refuses the push on GitHub's side and the code then reports `PUSH REFUSED` and restores the checkout, but only the lease path is exercised here.
- The INT/TERM/HUP trap inside `_stacked_rebase`. It follows the shape of the resync trap and has no signal case.
- The zero-check label step in `--repo <owner>/<name>` mode. The code path is the same `gh`-only one, but no case runs it.
- A repo with an unused `ci` label and no CI: the empty-rollup wait runs to `KIT_WRAP_CI_GRACE_SECS` (90s) before the gate reads the head.
