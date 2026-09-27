# Verification: wrap accepts absorbed content as a merge proof

Spec: `docs/specs/SPEC-331-wrap-absorbed-proof.md`. Change: `lib/wrap/wrap.sh` `_absorbed`, wired into `_merge_proof`, `_apply_branches`, and the `scan` verdict.

| Check | Command | Result |
|---|---|---|
| Suite | `bash tests/test-wrap.sh` | `test-wrap: all 1420 passed` (1403 before, plus 17 new) |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<force _absorbed to return 1>"` | green, RED under mutation, green after restore, `Verdict: PASS` |
| Real flow | new and installed `bin/wrap scan` and `apply` dry run on the real ops-toolkit checkout | below |

## Real flow

The ops-toolkit checkout held 20 `agent-*` worktrees on `worktree-agent-<id>` branches that no proof covered. Their branches were archived to origin as `archive/<branch>-20260927` before the worktrees were removed by hand. For this run, six archives were restored as local branches. A trial merge called four of them absorbed; the tree-identity proof (revision 2) calls two absorbed, because `origin/main` later edited files the other two touched.

New `wrap scan` (this branch, revision 2):

```
     proof-a0dd8e3cbf62e339b  [ABSORBED: content already on origin/main, safe to -D]
     proof-a4039cfab8f83e3cc  [NOT merged / unknown: LEAVE]
     proof-a7c5f5dbec7a6c956  [NOT merged / unknown: LEAVE]
     proof-aa165da2cb97cc523  [NOT merged / unknown: LEAVE]
     proof-acf7a10e552031edd  [ABSORBED: content already on origin/main, safe to -D]
     proof-adfa1398d3a81946f  [NOT merged / unknown: LEAVE]
```

Installed `wrap scan` (master, 2.2.0), same checkout, same branches: all six `[NOT merged / unknown: LEAVE]`.

New `wrap apply` dry run (branch sweep):

```
     [DRY-RUN] delete proof-a0dd8e3cbf62e339b (content already on origin/main)
     SKIP proof-a4039cfab8f83e3cc: no merged PR found for this head
     SKIP proof-a7c5f5dbec7a6c956: no merged PR found for this head
     SKIP proof-aa165da2cb97cc523: no merged PR found for this head
     [DRY-RUN] delete proof-acf7a10e552031edd (content already on origin/main)
     SKIP proof-adfa1398d3a81946f: no merged PR found for this head
```

The six temporary branches were deleted afterwards; their archives stay on origin.

## Revision 1 regression check

Revision 1 proved absorption with `git merge-tree --write-tree`. Validation and review each reproduced data loss through `.gitattributes` merge drivers. The revision 2 attack cases run against revision 1's `lib/wrap/wrap.sh` (`git show e6fcb91a:lib/wrap/wrap.sh`) go red, and green against revision 2:

```
  FAIL absorbed: driver stays LEAVE
  FAIL absorbed: uniondel stays LEAVE
  FAIL absorbed: lateredit stays LEAVE
  FAIL absorbed: the driver branch survives apply
  FAIL absorbed: the uniondel branch survives apply
  FAIL absorbed: the lateredit branch survives apply
test-wrap: 1414 passed, 6 FAILED of 1420
```

## Test plan coverage

| Row | Run |
|---|---|
| 1 absorbed branch with a worktree | `test-wrap.sh` absorbed section: scan, dry run, apply removal; real flow above |
| 2 partial landing | "a partial landing is left", "the partial branch stays" |
| 3 landed then edited, same lines | "a branch main edited since is left"; real flow `a7c5f5`, `adfa13` |
| 4 absorbed branch, no worktree | "the branch sweep names the proof", "the branch sweep deleted it" |
| 5 without gh | every absorbed case runs with `GH_STUB_UNAUTH=1` |
| 6 keep-ours driver | "driver stays LEAVE", "the driver branch survives apply" |
| 7 union line deletion | "uniondel stays LEAVE", "the uniondel branch survives apply" |
| 8 landed then edited, another hunk | "lateredit stays LEAVE", "the lateredit branch survives apply"; real flow `a4039c`, `aa165d` |
| 9 shadowing tag | "a tag named like the branch does not prove it" |
| 10 existing cases unchanged | suite 1403 to 1420, all green |
| 11 negative control | `negctl.sh` `Verdict: PASS` (below) |
