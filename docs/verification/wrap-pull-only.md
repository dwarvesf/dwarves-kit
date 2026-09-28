# `wrap apply --pull-only`, the pull stage alone

Spec: `docs/specs/SPEC-359-wrap-pull-only.md`. No board row filed; the operator named the work directly. Deltas from the spec: `docs/implementation-notes/wrap-pull-only.md`.

`bin/wrap apply --apply <repo>` sweeps worktrees, branches, archive-unmerged, origin branches, stray lines, and stray commits in the same call as the pull. An operator who wants only the pull, right after merging one PR while other sessions still own the other open branches in a shared checkout, had no verb for that and hand-rolled `git stash push -- <file> && git pull --ff-only && git stash pop` four times in one session, the exact workaround `commands/wrap.md` already forbids. `--pull-only` runs exactly `fetch --prune`, default-branch resolution, and the existing pull section (union carry, `wrap.pull_past_dirty` stash/pop, unchanged), with every other write-capable step gated off by a global `PULL_ONLY` flag.

## The change

| Piece | Where |
|---|---|
| Global `PULL_ONLY=0`, `--pull-only` case, the four-flag conflict check (before the `--tips-file` existence check) | `lib/wrap/wrap.sh` `cmd_apply` |
| `if [ "$PULL_ONLY" != 1 ]; then ... fi` around `_apply_worktrees`/`_apply_branches`/`_apply_archive_unmerged`/`_apply_origin_branches`/`_carry_stray`/`_carry_stray_commits`; the fetch-failure line varies under the flag | `lib/wrap/wrap.sh` `_apply_repo` |
| Usage strings: the header doc line 6 (plus a new line 7), `_usage()`'s `sed` range widened `2,31p` -> `2,32p`, the inline no-repo usage string | `lib/wrap/wrap.sh` |
| Step 5 bullet: when to reach for `--pull-only`, the ahead-only vs. diverged distinction, the NOTE pointing at plain `apply` | `commands/wrap.md` |
| `bin/wrap` row description | `docs/consumer-contract.md` |
| `[Unreleased]` COMPAT bullet | `docs/CHANGELOG.md` |
| Real-git fixtures for every row below | `tests/test-wrap.sh` |

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 1550 passed`
- Verdict: PASS

| Test plan row (SPEC-359) | Assertion group | Got |
|---|---|---|
| Scope, happy path | `pull-only scope: ...` (exits 0, HEAD moved, `old-branch still exists`, `-- pull:` prints) | PASS |
| Scope | `pull-only scope: no worktrees/branches/archive unmerged/origin branches/stray lines/stray commits section` | PASS |
| Union carry still works | `pull-only union+stash: ...` (union file carried, incoming and local log lines both present, A.md local line survived) | PASS |
| `pull_past_dirty` still works | `pull-only union+stash: ...` (non-union blocker stashed and restored, no stash left) | PASS |
| `pull_past_dirty` off | `pull-only knob off: ...` (exit 2, `FAILED pull --ff-only`, nothing stashed, HEAD unmoved) | PASS |
| Dry run | `pull-only dry run: ...` (`[DRY-RUN] pull --ff-only` prints, HEAD unmoved, no branches section) | PASS |
| Off default branch | `pull-only off-default: ...` (`SKIP pull:`, `fetch origin main:main` fallback ran, no branches/worktrees section) | PASS |
| Stray commits, ahead-only | `pull-only ahead-only: ...` (exit 0, no `FAILED pull`, HEAD unchanged, no `wrap/stray-commits-*` branch locally or on origin) | PASS |
| Stray commits, diverged | `pull-only diverged: ...` (exit 2, `FAILED pull --ff-only` present, HEAD unmoved, no `wrap/stray-commits-*` branch anywhere) | PASS |
| Fetch-failure wording | `pull-only fetch failure: ...` (`(fetch failed; the pull below will likely fail too)` present, `every delete is skipped` absent, exit 2, `FAILED pull` follows) | PASS |
| Usage line | `pull-only usage: ...` (no-repo path, exit 64, usage line names `--pull-only`) | PASS |
| Flag conflict | `pull-only conflict --worktrees/--archive-unmerged/--own/--tips-file: ...` (all four exit 64, `--tips-file` conflict named ahead of the missing-path wording) | PASS |
| Regression | every pre-existing `apply` assertion in the file (no `--pull-only` involved), unchanged in outcome across this same run | PASS |
| Multi-repo | `pull-only multi-repo: ...` (two repos, each with its own header, both pulled) | PASS |

The fixtures reuse the real-git `build_pd_repo`/`advance_pd_repo` helpers already in the suite (bare origin plus a clone, a `merge=union` `_meta/LAB_LOG.md`, a plain `A.md`/`B.md`): the subject is `git pull --ff-only`'s own exit behavior under ahead-only vs. diverged history, which a stubbed git cannot distinguish.

## Negative control

Produced with `lib/gate/negctl.sh` after the change was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/if \[ "$PULL_ONLY" != 1 \]; then/if [ "$PULL_ONLY" != 99 ]; then/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation makes the `PULL_ONLY` gate around `_apply_worktrees`/`_apply_branches`/`_apply_archive_unmerged`/`_apply_origin_branches`/`_carry_stray`/`_carry_stray_commits` always true, so every one of those steps runs whether or not `--pull-only` was given. Re-run by hand (outside `negctl`, output captured this time) to name the exact failures: `1532 passed, 18 FAILED of 1550`.

```
  FAIL pull-only scope: old-branch still exists (branch sweep never ran)
  FAIL pull-only scope: no worktrees section
  FAIL pull-only scope: no branches section
  FAIL pull-only scope: no origin branches section
  FAIL pull-only scope: no stray lines section
  FAIL pull-only scope: no stray commits section
  FAIL pull-only union+stash: no branches section
  FAIL pull-only dry run: no branches section
  FAIL pull-only off-default: no branches section
  FAIL pull-only off-default: no worktrees section
  FAIL pull-only ahead-only: HEAD unchanged
  FAIL pull-only ahead-only: no local stray-commits branch
  FAIL pull-only ahead-only: no origin stray-commits branch
  FAIL pull-only diverged: exits 2
  FAIL pull-only diverged: FAILED pull line present
  FAIL pull-only diverged: HEAD did not move
  FAIL pull-only diverged: no local stray-commits branch
  FAIL pull-only diverged: no origin stray-commits branch
```

The ahead-only and diverged rows go red for a second reason beyond the section-absence checks: with the gate removed, `_carry_stray_commits` runs again, pushes the local commit to a `wrap/stray-commits-*` branch, and moves the default branch back with `git reset --keep`, which changes `HEAD`, the exit code, and the branch set the assertions expect under `--pull-only`. That is the exact behavior difference the flag exists to turn off. The file was restored with `git checkout HEAD -- lib/wrap/wrap.sh` immediately after this run; the tree was confirmed clean before writing this doc.

## Reproduce

```bash
cd ~/.claude/dwarves-kit   # or this worktree's path
bash tests/test-wrap.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" \
  'sed -i '"'"''"'"' '"'"'s/if \[ "$PULL_ONLY" != 1 \]; then/if [ "$PULL_ONLY" != 99 ]; then/'"'"' lib/wrap/wrap.sh'
```

## What this does not cover

A live run against a real shared checkout with another session's dirty file present, as opposed to the synthetic `build_pd_repo` fixtures. The `wrap.pull_past_dirty` mechanics themselves (stash-by-pathspec, pop-by-identity, the union carry) are unchanged from SPEC-286 and carry that spec's own negative controls; this proof only shows `--pull-only` reaches the same `_pull_default` code path, not that path's own correctness a second time.

The `docs/consumer-contract.md` and `docs/CHANGELOG.md` edits are prose; no test asserts their wording, per the spec's Task Breakdown (TASK-F, TASK-G are "reviewed for accuracy," not test-covered).
