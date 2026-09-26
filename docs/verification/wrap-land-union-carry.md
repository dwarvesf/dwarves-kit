# Proof of done: `wrap land` carries a dirty union file across its fast-forward

`land`'s post-merge fast-forward now calls `_land_ff_pull` instead of a bare `git pull --ff-only`. `_land_ff_pull` reuses `_union_marked` and `_union_carry_back` (the same building blocks `apply`'s pull already carries a dirty `merge=union` file with): a dirty union-marked file is saved aside, the pull runs, and the local lines are merged back into the pulled file. A staged change or a dirty non-union file is untouched, exactly as before this change; `wrap.pull_past_dirty` is not read here (SPEC-321, design record: union-carry only).

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | a dirty `merge=union` file no longer blocks the fast-forward | new land test case, `build_land unionlog --union-log`: exit 0, no `PULL BLOCKED` |
| AC2 | the save and carry-back are reported | `chk_has "saved 1 union-marked file(s) aside so the pull can fast-forward"`, `chk_has "carried 1 local line(s) back into _meta/LAB_LOG.md"` |
| AC3 | the existing `pulled <repo>: ...` line stays byte-identical | `chk_has "the fast-forward is still reported as pulled" "$out" "pulled ${LREPO_UP}"` |
| AC4 | both sides of the union file survive: the incoming line and the sibling's local, uncommitted line | `chk` on `grep -qxF 'remote entry'` and `grep -qxF 'local entry'`; `git -C "$LREPO_U" diff --name-only` still names the file |
| AC5 | a dirty NON-union file is unaffected (regression check) | the pre-existing `build_land blocked --modify-base` case still passes unmodified: exit 2, `PULL BLOCKED: pull --ff-only refused in ...`, `nothing was stashed or reset` |
| AC6 | the worktree/branch tidy still runs regardless | both new and existing land cases: worktree removed, local branch deleted |
| AC7 | no regression to the rest of `wrap` | full `test-wrap.sh` green |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 1175 passed
```

New assertions (land block, SPEC-321):
```
--- a dirty merge=union file in the main checkout is carried across the fast-forward (SPEC-321)
PASS a union-carried pull exits 0
PASS the carry reports the save
PASS the carry reports the carry-back
PASS the fast-forward is still reported as pulled
PASS no PULL BLOCKED on a union-only dirty file
PASS the main checkout fast-forwarded to the landed tip
PASS the incoming log line landed
PASS the sibling's local log line survived
PASS the local log line is still uncommitted
PASS the pr-file.txt content also landed
PASS the worktree was removed
PASS the branch was deleted
```

Pre-existing non-union case, unchanged and still green:
```
--- PULL BLOCKED: a dirty tracked file in the main checkout never stops the tidy
PASS a blocked pull exits 2
PASS the blocked pull says PULL BLOCKED
PASS the blocked pull says nothing was stashed or reset
PASS the blocked pull left the main checkout where it was
PASS the blocked pull left the sibling's dirty file alone
PASS the merge still landed
PASS the worktree was still removed
PASS the removal is still reported
PASS the branch was still deleted
```

## Negative control

`bash lib/gate/negctl.sh <worktree root> "bash tests/test-wrap.sh" "<mutate reverting _land_ff_pull to the bare pull>"`:

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak "2164s/_land_ff_pull \"\$repo\"/git -C \"\$repo\" pull --ff-only/" lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Under the mutation, `test-wrap: 1167 passed, 8 FAILED of 1175`; the 8 failures are all inside the new land case:
```
FAIL a union-carried pull exits 0
FAIL the carry reports the save
FAIL the carry reports the carry-back
FAIL the fast-forward is still reported as pulled
FAIL no PULL BLOCKED on a union-only dirty file
FAIL the main checkout fast-forwarded to the landed tip
FAIL the incoming log line landed
FAIL the pr-file.txt content also landed
```
(The other 4 assertions in that same case -- the local line surviving, the local line staying uncommitted, the worktree removed, the branch deleted -- hold either way, since a blocked pull also leaves the union file's local line untouched and the tidy still runs; they are not the ones the fix changes.) `git checkout HEAD -- lib/wrap/wrap.sh` returns the suite to `test-wrap: all 1175 passed`, exit 0, tree clean.

## Not proven

- No live GitHub run: `gh` is stubbed in every land test, unchanged from the existing `wrap-land.md` proof; this change touches only the post-merge fast-forward, after `gh`'s part is already done.
- A dirty index (staged change) alongside a dirty union file is not covered by a new test case; the guard mirrors `_pull_default`'s existing staged-index behavior, which the `apply` union-carry tests already exercise (case 5, `docs/verification/` for `apply`).
- A union file that fails `git merge-file --union` (the `FAILED carry` path) is exercised for `apply` (`_union_carry_back`'s own logic, unchanged), not re-tested for `land`; `_land_ff_pull` calls the exact same function.

## Reproduce

```
bash tests/test-wrap.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" \
  'sed -i.bak "2164s/_land_ff_pull \"\$repo\"/git -C \"\$repo\" pull --ff-only/" lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak'
```
