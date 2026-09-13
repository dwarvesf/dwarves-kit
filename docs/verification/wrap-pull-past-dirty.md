# wrap apply pulls a checkout past a sibling session's dirty tracked files

Spec: `docs/specs/SPEC-286-wrap-pull-past-dirty.md`. Board row: ID-874. Deltas from the spec: `docs/implementation-notes/wrap-pull-past-dirty.md`.

`bin/wrap apply --apply <repo>` used to print `FAILED pull --ff-only` whenever git refused the pull because of dirty tracked files, and the operator did the recovery by hand: a named stash of only the files git names, the pull, a pop by ref, a union resolve on the append-only log. Twice in one day on the kit clone. Behind `wrap.pull_past_dirty` (root-only, default `false`) `apply` now does that sequence itself and leaves every other stash, dirty file, and untracked file alone.

## The change

| Piece | Where |
|---|---|
| Knob `wrap.pull_past_dirty`, default `false`, root-only | `kit.toml` `[wrap]`, `lib/config/module-registry.md` |
| Stash by pathspec under a unique name, pull, pop by ref, union resolve, `POP CONFLICT` report | `lib/wrap/wrap.sh` `_pull_past_dirty_on` and the `cmd_apply` pull path |
| Step 5 names the knob and the `POP CONFLICT` line | `commands/wrap.md` |
| Real-git fixtures for the four validation steps | `tests/test-wrap.sh` |
| Review fix: the run's own stash is resolved by its subject, never by reading `refs/stash` after the push | `lib/wrap/wrap.sh` `_stash_blocked`, fixture `after-push stash` in `tests/test-wrap.sh` |

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 489 passed` (482 on master at the review branch point; the PR's cases cover knob off, knob on with a sibling stash present, a non-union pop conflict, and a mid-pull sibling stash staged by a post-merge hook; the review added the seven `after-push stash` assertions)
- Verdict: PASS

| Validation step (SPEC-286) | Fixture | Expected | Got |
|---|---|---|---|
| 1 knob off | dirty `A.md` `B.md`, untracked `C.md`, stash `sibling` | `FAILED`, tree and stash list unchanged | PASS |
| 2 knob on | same | pulled, `A.md` keeps the local edit, `B.md` still dirty, `C.md` present, stash list is exactly `sibling` | PASS |
| 3 knob on, non-union conflict | incoming commit conflicts with the local edit on a non-union file | `POP CONFLICT`, non-zero exit, named stash kept, `sibling` untouched | PASS |
| 4 sibling stash pushed mid-pull | post-merge hook pushes a stash between pull and pop | the pop still resolves by ref, never by position | PASS |
| 5 sibling stash pushed right after ours (review) | a git shim pushes a sibling stash the instant the run's own `stash push` returns, before the run reads which entry is its own | the run's own entry is popped and dropped, the sibling's survives, the local edit is back | PASS |

The fixtures are real git repositories with a real remote, not stubs: the subject is stash and pop behaviour, which a stubbed git cannot exercise.

Against the merged PR code, fixture 5 fails three assertions (`486 passed, 3 FAILED of 489`): the local edit is gone from the worktree, the sibling's entry was popped, and the surviving stash is the run's own. That is the defect the review fixed.

## Negative control

Produced with `lib/gate/negctl.sh` after the change was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/pull_past_dirty/pull_past_dirtX/g' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation renames the config key the guard reads, so the knob reads false whatever the operator set and every knob-on case goes red. Restoring the file goes green again.

That control proves the knob wiring, not the pop. The spec's test plan names a second mutation: make the pop take the first entry instead of the one whose commit matches. The review ran it, plus a third for the review's own fix. Both produced with `lib/gate/negctl.sh` after the fix was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/if \[ "\$h" = "\$sha" \]; then ref="\$gd"; break; fi/ref="\$gd"; break/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Under this mutation `_unstash` pops the top of the stack. Five assertions go red (`484 passed, 5 FAILED of 489`): `mid-pull stash: A.md kept the local edit`, `mid-pull stash: and it is the sibling's, not ours`, and the three `after-push stash` assertions below. The mid-pull fixture therefore exercises pop-by-ref, which the first control never showed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/case "\$s" in \*": \$\{name\}"\) printf/case "\$s" in *) printf/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Under this mutation `_stash_blocked` records the top entry whatever its subject, which is the merged PR's behaviour. Three assertions go red (`486 passed, 3 FAILED of 489`): `after-push stash: A.md kept the local edit`, `after-push stash: the sibling's entry was not popped`, `after-push stash: and it is the sibling's, not ours`.

## Test plan coverage

Rows are the ordinals of the `## Test plan` matrix in SPEC-286. Every run is an assertion group in `bash tests/test-wrap.sh` unless a control is named.

| Row | Run / skip reason |
|---|---|
| 1 | `knob off: ...` (exit 2, `FAILED pull --ff-only`, HEAD unmoved, A.md and B.md byte-identical, untracked file present, sibling stash the only stash) |
| 2 | `knob on: apply exits 0`, `HEAD moved to the incoming commit`, `the incoming line landed in A.md`, `the local line survived in A.md`, `A.md is still uncommitted`, `A.md is not staged` |
| 3 | `knob on: exactly the one blocking file was stashed` |
| 4 | `knob on: B.md kept its local edit`, `B.md is still dirty` |
| 5 | `knob on: the untracked file is untouched` |
| 6 | `knob on: the sibling stash is the only stash left`, `the surviving stash is the sibling's`; plus the review's `after-push stash: ...` group for a sibling entry pushed after the run's own |
| 7 | `mid-pull stash: ...` (post-merge hook pushes a sibling stash between the stash and the pop); red under the bare-pop control above |
| 8 | `pop conflict: ...` (exit 2, `PULLED, POP CONFLICT: A.md, stash wrap-pull-past-dirty-`, markers in the file, both stashes listed, pull landed) |
| 9 | `union pop: ...` (two files stashed, no `POP CONFLICT`, both log lines present, no stash left) |
| 10 | `untracked block: ...` (exit 2, pull failed, stash came back, HEAD unmoved, untracked content kept) |
| 11 | `dirty index: ...` (index reason prints, nothing stashed, path still staged) |
| 12 | `dry run: ...` (nothing stashed, no stash created, file byte-identical, `--apply would stash` announced) |
| 13 | `rename: ...` (stashed, pull landed, local edit followed the rename onto Z.md, A.md gone) |
| 14 | `deleted: ...` (nothing stashed, pull landed, file rewritten, no unmerged path) |
| 15 | `diverged: ...` (exit 2, nothing stashed, no stash created, HEAD unmoved) |
| 16 | `odd name: ...` (one file stashed, local edit back, the decoy untouched) |
| 17 | `wrap.pull_past_dirty ships as false`, `honours the operator kit.toml`, `ignores a project .kit.toml` |
| 18 | the bare-pop negative control above (spec-named mutation, `484 passed, 5 FAILED`) |

## Reproduce

```bash
cd ~/.claude/dwarves-kit
bash tests/test-wrap.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh >/dev/null 2>&1" "perl -pi -e 's/pull_past_dirty/pull_past_dirtX/g' lib/wrap/wrap.sh"
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh >/dev/null 2>&1" "bash /path/to/mutation.sh"
bash lib/gate/proof-gate.sh coverage docs/specs/SPEC-286-wrap-pull-past-dirty.md docs/verification/wrap-pull-past-dirty.md
```

For the two pop controls, put the `perl -pi -e ...` line quoted in its control block above into `mutation.sh` as written; the dollar signs and brackets do not survive a double-quoted negctl argument.

## What this does not cover

A sibling push between the run's `git stash list` and its `git stash pop`. The pop names a positional `stash@{N}` resolved a moment earlier, and git has no drop-by-commit, so that window can shrink but not close. The implementation notes carry it as an open question.

A dirty tracked file the incoming commits delete. The knob stashes it, the pull lands, and the pop is a modify/delete conflict every time, which leaves a `DU` entry in the shared index. Reproduced by hand during the review; the implementation notes carry it as an open question.

A live run against the kit primary checkout while a sibling session holds it. The clone that motivated this row was diverged by a sibling's local commits at proof time, which is the `FAILED` path with or without the knob, so the first live use waits for a checkout that is only dirty, not diverged.
