# Verification: wrap accepts absorbed content as a merge proof

Spec: `docs/specs/SPEC-331-wrap-absorbed-proof.md`. Change: `lib/wrap/wrap.sh` `_absorbed`, wired into `_merge_proof`, `_apply_branches`, and the `scan` verdict.

| Check | Command | Result |
|---|---|---|
| Suite | `bash tests/test-wrap.sh` | `test-wrap: all 1413 passed` (1403 before, plus 10 new) |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<force _absorbed to return 1>"` | green, RED under mutation, green after restore, `Verdict: PASS` |
| Real flow | new and installed `bin/wrap scan` and `apply` dry run on the real ops-toolkit checkout | below |

## Real flow

The ops-toolkit checkout held 20 `agent-*` worktrees on `worktree-agent-<id>` branches that no proof covered. Their branches were archived to origin as `archive/<branch>-20260927` before the worktrees were removed by hand. For this run, six archives were restored as local branches: four whose merge into `origin/main` changes nothing, two whose files `origin/main` edited after landing them.

New `wrap scan` (this branch):

```
     proof-a0dd8e3cbf62e339b  [ABSORBED: content already on origin/main, safe to -D]
     proof-a4039cfab8f83e3cc  [ABSORBED: content already on origin/main, safe to -D]
     proof-a7c5f5dbec7a6c956  [NOT merged / unknown: LEAVE]
     proof-aa165da2cb97cc523  [ABSORBED: content already on origin/main, safe to -D]
     proof-acf7a10e552031edd  [ABSORBED: content already on origin/main, safe to -D]
     proof-adfa1398d3a81946f  [NOT merged / unknown: LEAVE]
```

Installed `wrap scan` (master, 2.2.0), same checkout, same branches:

```
     proof-a0dd8e3cbf62e339b  [NOT merged / unknown: LEAVE]
     proof-a4039cfab8f83e3cc  [NOT merged / unknown: LEAVE]
     proof-a7c5f5dbec7a6c956  [NOT merged / unknown: LEAVE]
     proof-aa165da2cb97cc523  [NOT merged / unknown: LEAVE]
     proof-acf7a10e552031edd  [NOT merged / unknown: LEAVE]
     proof-adfa1398d3a81946f  [NOT merged / unknown: LEAVE]
```

New `wrap apply` dry run (branch sweep):

```
     [DRY-RUN] delete proof-a0dd8e3cbf62e339b (content already on origin/main)
     [DRY-RUN] delete proof-a4039cfab8f83e3cc (content already on origin/main)
     SKIP proof-a7c5f5dbec7a6c956: no merged PR found for this head
     [DRY-RUN] delete proof-aa165da2cb97cc523 (content already on origin/main)
     [DRY-RUN] delete proof-acf7a10e552031edd (content already on origin/main)
     SKIP proof-adfa1398d3a81946f: no merged PR found for this head
```

The six temporary branches were deleted afterwards; their archives stay on origin.

## Test plan coverage

| Row | Run |
|---|---|
| 1 absorbed branch with a worktree | `test-wrap.sh` absorbed section: scan, dry run, apply removal; real flow above |
| 2 partial landing | `test-wrap.sh` "a partial landing is left", "the partial branch stays" |
| 3 landed then edited | `test-wrap.sh` "a branch main edited since is left"; real flow `a7c5f5`, `adfa13` |
| 4 absorbed branch, no worktree | `test-wrap.sh` "the branch sweep names the proof", "deleted it" |
| 5 without gh | every absorbed case runs with `GH_STUB_UNAUTH=1` |
| 6 existing cases unchanged | suite 1403 to 1413, all green |
| 7 negative control | `negctl.sh` `Verdict: PASS` |
