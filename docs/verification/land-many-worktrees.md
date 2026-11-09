# Verification -- land-many-worktrees

`wrap land` takes several worktrees and lands them one at a time in argument order, stopping at the first failure, ending on a summary table. One worktree behaves as before.

## Rebase decision

`land` does not rebase. Its only contact with `origin/<default>` is the merge-in cycle, which runs after the push and the checks wait, and only when the PR already reads CONFLICTING. For a never-pushed branch behind a just-landed sibling, that costs a pushed head and a CI wait per worktree. So the many-worktree path adds one step: before every land after the first, `cmd_rebase` runs on a branch that is not on origin (`git ls-remote --exit-code --heads origin <branch>` exits 2). A branch already on origin is skipped and keeps the merge-in cycle, because its history is published. The first worktree is not rebased.

`--verify` is forwarded unchanged to each land, so it keeps its single-land meaning: it runs only inside the CONFLICTING merge-in cycle. A rebase that moved HEAD is therefore not re-tested by `land`.

## Green run

```
Command: LAND_CACHE=0 LAND_ONLY=many bash tests/test-wrap-land.sh
Exit: 0
Output:
  test-wrap-land: LAND_ONLY='many' selected 1 of 18 sections
  test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
  test-wrap-land: all 31 passed
Verdict: PASS
```

The CLI table, which lists the verbs and flags:

```
Command: bash tests/test-wrap-cli.sh
Exit: 0
Output:
  test-wrap-cli: all 22 passed
Verdict: PASS
```

The repo-wide quick check, run once (the diff-scoped suites plus the always-on lints; the other land sections were credited from the section cache, keyed on the identical tree):

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
  test-wrap-cli                                  ok (2s)
  test-wrap-land                                 ok (0s)
  test-wrap-rebase                               ok (19s)
  test-wrap-ship                                 ok (25s)
  run-all: all 44 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

The new section covers: two worktrees land in order with the second rebased first (and `--verify true` accepted); the second refuses (dirty worktree, exit 1), the run stops, the third is listed `not run` and never started; one worktree prints no header and no table; `--title`, `--body-file` and `--draft` with two worktrees exit 64 naming the flag, and a bad path exits 64 before any merge; a branch already on origin is not rebased.

## Negative control

Committed first, then four mutations of `lib/wrap/wrap-land.sh` through `lib/gate/negctl.sh` against `LAND_CACHE=0 LAND_ONLY=many bash tests/test-wrap-land.sh`. Each went RED and was restored (green after restore).

```
Command: bash lib/gate/negctl.sh "$PWD" "LAND_CACHE=0 LAND_ONLY=many bash tests/test-wrap-land.sh" "<mutation>"
Exit: 1 (under mutation, RED expected)
Output:
  restore the file to before the change:            13 passed, 18 FAILED of 31
  skip the rebase (cmd_rebase becomes return 0):    27 passed, 4 FAILED of 31
  keep going after a failed land (no break):        26 passed, 5 FAILED of 31
  never take the many path (threshold 99):          13 passed, 18 FAILED of 31
Verdict: PASS
```

## Not proven

- Real GitHub: `gh` is stubbed, so the wait for CI between lands is not exercised; the sequencing is proven by the ordered merge calls.
- `--verify` is only proven to be accepted with many worktrees; it fires only in the CONFLICTING cycle, which the many-worktree section does not drive.
- A rebase that stops on a conflict inside the many path is the `rebase` verb's own refusal; the run stops on it with the rebase exit code, but no case here forces one.
