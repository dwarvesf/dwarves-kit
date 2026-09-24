# Verification -- wrap-stray-commit-carry

`wrap apply` now carries stray commits off a shared default branch (SPEC-312).
With the main checkout on the default branch and ahead of origin, `--apply`
pushes the commits to `wrap/stray-commits-<stamp>`, prints the PR command, and
moves the branch back with `reset --keep` to where it left origin. The pull
then fast-forwards.

## Green run

| Check | Command | Exit | Result |
|---|---|---|---|
| Wrap suite | `bash tests/test-wrap.sh` | 0 | `test-wrap: all 1029 passed` (1018 on the first cut, before the review fixes) |
| Structure | `bash tests/test-meta.sh` | 0 | `Passed: 854 / 854` (docs/FEATURES.md regenerated) |
| Config registry | `bash tests/test-config-registry.sh` | 0 | `56/56 passed` |
| Config seams, stamp, guard | `test-config.sh`, `test-config-seams.sh`, `test-config-stamp.sh`, `test-reserved-config-guard.sh` | 0 each | selftest PASS, 56/56, 17/17, 9/9 |

```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS -- all 1029 passed, including the stray-commits block: dry run
  names the commit and the move and writes nothing; --apply pushes the branch
  at the commit, keeps a local branch, moves main to the fork point, and the
  pull lands on origin/main with the dirty union line kept; origin unmoved
  prints the exact "moved main back to origin/main" line; a dirty non-union
  file keeps main ahead and still pushes; the rerun reuses the branch,
  recreates the local branch, reprints the PR command, and ignores a
  foo/wrap/stray-commits-x ref; a dirty union file the commits change and a
  staged union file each block the move; a squash-merged carry is found by
  patch id and nothing is pushed; knob false writes nothing; a refused push
  is FAILED, exit 2, and the pull still runs.
```

## Real primary flow

The incident replayed on scratch copies of the real ops-toolkit history (its
own `.gitattributes`, the real `_meta/LAB_LOG.md`). A bare copy stands in for
origin. One clone commits on `main` without pushing. Origin gains a log line
from a "merged PR". A second session's uncommitted log line sits in the shared
checkout.

```
Command: bash <scratchpad>/replay.sh
Exit: 0
before: ## main...origin/main [ahead 1, behind 1]
plain pull --ff-only: fatal: Not possible to fast-forward, aborting.
OLD wrap (origin/master) apply --apply: [APPLY] pull --ff-only ... hint: Diverging branches can't be fast-forwarded
NEW wrap dry run:
  WOULD carry 1 stray commits on main onto a branch:
    b050071e6 docs(replay): a commit made on the shared main
  WOULD move main back to origin/main
NEW wrap apply --apply:
  carried 1 stray commits on main to origin/wrap/stray-commits-20260924-1415
  open its PR with: gh pr create --head wrap/stray-commits-20260924-1415
  moved main back to b8900db5d, where it left origin/main; the 1 commits live on wrap/stray-commits-20260924-1415
  saved 1 union-marked file(s) aside so the pull can fast-forward
  Fast-forward
  carried 1 local line(s) back into _meta/LAB_LOG.md
  HEAD: 5280cedec chore: merged PR moves the log
rc=0
after: ## main...origin/main
HEAD == origin main: yes
uncommitted log line kept: 1; merged-PR log line present: 1
Verdict: PASS
```

The first cut reset straight to `origin/main`, as the brief named. The fixture
with a moved origin and a dirty union log showed `reset --keep` refusing there,
so the target became the fork point.

A dry run of the new code on the real ops-toolkit main checkout printed
`-- stray commits:` / `none` (no real repo was ahead at the time).

## Negative control

`lib/gate/negctl.sh` ran once per mutation, each in its own clone of the
committed branch (`ea89539`), each with `bash tests/test-wrap.sh` as the test.

| Mutation | Under mutation | Verdict |
|---|---|---|
| step not wired into apply | Exit 1 (RED) | PASS |
| reset to origin/<def>, not the fork point | Exit 1 (RED) | PASS |
| block ignored, move always runs | Exit 1 (RED) | PASS |
| knob false no longer returns | Exit 1 (RED) | PASS |
| refused push not FAILED | Exit 1 (RED) | PASS |
| origin carry branch never reused | Exit 1 (RED) | PASS |
| `refs/heads/wrap/` prefix filter dropped | Exit 1 (RED) | PASS |
| squash-landed detection inverted | Exit 1 (RED) | PASS |
| dirty-union overlap never detected | Exit 1 (RED) | PASS |
| staged union file counted as clean | Exit 1 (RED) | PASS |
| local branch not recreated on reuse | Exit 1 (RED) | PASS |

```
Command: lib/gate/negctl.sh <clone> "bash tests/test-wrap.sh" "<mutation>"  (x11)
Exit: 0 under every restore; 1 under every mutation
Verdict: PASS
```

Two first-pass controls were bad runs, not test gaps. The prefix mutation
matched an unrelated `*) continue ;; esac` at wrap.sh:454; re-anchored, it went
RED. The overlap control failed "green after restore" with eleven suites
running in parallel; alone it passed all three steps.

## Review

One correctness lens (Opus) on the first commit. Every finding but one was
applied in `ea89539`; see SPEC-312 "Review".

## Not proven

- No `--apply` against a real GitHub origin; pushes go to local bare repos.
  Branch protection is modelled with a refusing `pre-receive` hook.
- The `ORIG_HEAD` race restore has no test: the window is between two git
  calls and no fixture holds it open.
- A `master` or `develop` default branch is not exercised in the new block.
  The step reads the detected name and hardcodes none.
- A carry PR merged by rebase (not squash) is not detected as landed when it
  holds more than one commit; the step then pushes a duplicate branch.
