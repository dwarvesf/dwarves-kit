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

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 460 passed` (398 on master at the branch point; the new cases cover knob off, knob on with a sibling stash present, a non-union pop conflict, and a mid-pull sibling stash staged by a post-merge hook)
- Verdict: PASS

| Validation step (SPEC-286) | Fixture | Expected | Got |
|---|---|---|---|
| 1 knob off | dirty `A.md` `B.md`, untracked `C.md`, stash `sibling` | `FAILED`, tree and stash list unchanged | PASS |
| 2 knob on | same | pulled, `A.md` keeps the local edit, `B.md` still dirty, `C.md` present, stash list is exactly `sibling` | PASS |
| 3 knob on, non-union conflict | incoming commit conflicts with the local edit on a non-union file | `POP CONFLICT`, non-zero exit, named stash kept, `sibling` untouched | PASS |
| 4 sibling stash pushed mid-pull | post-merge hook pushes a stash between pull and pop | the pop still resolves by ref, never by position | PASS |

The fixtures are real git repositories with a real remote, not stubs: the subject is stash and pop behaviour, which a stubbed git cannot exercise.

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

## Reproduce

```bash
cd ~/.claude/dwarves-kit
bash tests/test-wrap.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh >/dev/null 2>&1" "perl -pi -e 's/pull_past_dirty/pull_past_dirtX/g' lib/wrap/wrap.sh"
```

## What this does not cover

A live run against the kit primary checkout while a sibling session holds it. The clone that motivated this row was diverged by a sibling's local commits at proof time, which is the `FAILED` path with or without the knob, so the first live use waits for a checkout that is only dirty, not diverged.
