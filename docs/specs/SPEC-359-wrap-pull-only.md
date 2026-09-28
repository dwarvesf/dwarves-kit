# SPEC-359: `wrap apply --pull-only`, the pull stage alone

**Status:** DRAFT
Lane: full
**Source:** operator paraphrase, this session. No board row filed; the operator named the work directly.

## Problem

`wrap apply` is the only verb that fast-forwards a shared main checkout past two obstacles: a
sibling session's dirty `merge=union` file (LAB_LOG, BACKLOG), carried across the pull and
restored, and, with `wrap.pull_past_dirty` on, a sibling's dirty non-union tracked file, stashed
by pathspec and popped back by identity. Both live inside `_pull_default` in `lib/wrap/wrap.sh`.

`apply --apply` also sweeps worktrees, deletes local and origin branches, opens stray-line and
stray-commit carry branches, and (opt-in) archives unmerged branches, all in the same call. An
operator who wants only the pull, for example right after merging one PR while other sessions
still own the other open branches in a shared checkout, has no verb that runs the pull stage
alone. `commands/wrap.md` forbids the workaround directly: "Never force-push and never rewrite
history"; a bare `git stash push -- <file> && git pull --ff-only && git stash pop` is the same
three commands SPEC-286's Decision section names as "what a script must not guess at" (a bare
stash takes every dirty and untracked file this session does not own; a bare pop takes whatever
sits on top of the stack, which on a shared checkout is another session's stash). This session
hand-rolled that workaround four times.

## Decision

Add `--pull-only` to `wrap.sh apply`. Under it, `_apply_repo` runs exactly: `fetch --prune`,
resolve the default branch, and the existing pull section (`_pull_default` when the checkout is
on the default branch, the existing `fetch origin <def>:<def>` fallback otherwise). Every other
step in `_apply_repo`, `_apply_worktrees`, `_apply_branches`, `_apply_archive_unmerged`,
`_apply_origin_branches`, `_carry_stray`, `_carry_stray_commits`, does not run and prints
nothing. `_pull_default` itself is untouched: the union carry and the `wrap.pull_past_dirty`
stash-and-pop both keep working exactly as SPEC-286 and the union-carry sibling spec describe,
because `--pull-only` changes what `_apply_repo` calls, never what the pull stage does.

### Why a flag on `apply`, not a new verb

`apply` already owns the repo list, `--under` expansion, the dry-run/`--apply` split, the
`--tips-file` test seam, and the per-repo `_apply_repo` loop. The pull stage's own gating
(`wrap.pull_past_dirty`, the union carry, the default-branch check) lives entirely inside that
loop already. A new `wrap pull <repo>` verb would duplicate all of that arg parsing and gain
nothing a flag does not; the ladder rung that fits is reuse, not a sibling surface. `--pull-only`
reads the same way the existing `--worktrees` and `--archive-unmerged` flags do: it narrows what
one call of `apply` touches, on the same repo list, under the same `--apply`/dry-run split.

### What the flag narrows, and what it leaves alone

| Step in `_apply_repo` | Under `--pull-only` |
|---|---|
| `fetch --prune` | runs, unchanged |
| default branch resolution | runs, unchanged |
| `_apply_worktrees` (worktree removal, branch delete on merge proof) | does not run |
| `_apply_branches` (local branch delete on merge proof) | does not run |
| `_apply_archive_unmerged` (opt-in origin archive push) | does not run, even if `--archive-unmerged` is also given (rejected, see below) |
| `_apply_origin_branches` (origin branch delete on merged PR) | does not run |
| `_carry_stray` (stray-line carry branch + push) | does not run |
| `_carry_stray_commits` (stray-commit carry branch + push, `default` reset) | does not run |
| `_pull_default` (union carry, `wrap.pull_past_dirty` stash/pop, `pull --ff-only`) | runs, unchanged |
| off-default-branch fallback (`fetch origin <def>:<def>`) | runs, unchanged |

Nothing above is a new code path inside `_pull_default`; `--pull-only` is purely a gate around
the calls `_apply_repo` already makes in sequence.

### Flag interaction

`--pull-only` refuses to combine with `--worktrees`, `--archive-unmerged`, or `--own` (exit 64,
naming the conflicting flag): each of those exists to widen or scope a sweep `--pull-only`
explicitly turns off, and silently ignoring them would let a typo skip a worktree cleanup the
operator meant to run. `--under` and `--tips-file` are unaffected: `--pull-only` only changes
which steps `_apply_repo` runs per resolved repo, not how the repo list is built or how branch
tips are read. `--apply` behaves as it does today: omit it for a dry run (the existing `NOTE`/
`WOULD` lines `_pull_default` already prints), pass it to execute the fetch and the pull.

### Report shape

`--pull-only` prints the repo header, the fetch line (or its failure), and the `-- pull:`
section exactly as `_apply_repo` prints them today. It never prints `-- worktrees:`,
`-- branches:`, `-- archive unmerged:`, `-- origin branches:`, `-- stray lines:`, or
`-- stray commits:`, not even a `SKIPPED` line for each, because those sections do not run at
all under this flag, and a `SKIPPED` line implies a step that considered the repo and declined,
which is not what happened. The closing `== APPLY complete. ...` / `== DRY-RUN complete. ...`
line is unchanged.

## Wiring (one edit per surface)

| Surface | Edit |
|---|---|
| `lib/wrap/wrap.sh` | `cmd_apply` arg parsing: `--pull-only` flag plus the three-flag conflict check; `_apply_repo` gains a `pull_only` parameter and wraps the worktree/branch/archive/origin/stray-line/stray-commit calls in `if [ "$pull_only" != 1 ]; then ... fi`; the header comment's verb-line and write-set enumeration gain the flag |
| `commands/wrap.md` | step 5 gains one bullet: when the operator asks for the pull alone (a shared checkout, other sessions own the open branches), `bin/wrap apply --pull-only --apply <repo>` instead of the full `apply --apply --worktrees` |
| `tests/test-wrap.sh` | the flag's own case block (see Test plan) |

## Non-goals

- No new verb (`wrap pull`). `apply --pull-only` is the whole surface.
- No change to `_pull_default`, the union carry, or the `wrap.pull_past_dirty` stash/pop. This
  spec gates which callers reach them, not their own logic.
- No change to `--worktrees`, `--archive-unmerged`, `--own`, or the origin-branch sweep's own
  behavior when `--pull-only` is absent.
- No new knob. `--pull-only` is a per-call flag, not a `kit.toml` default: the operator who wants
  only the pull says so on the command, the same way `--worktrees` and `--archive-unmerged`
  already work.
- No change to `cmd_scan`, `cmd_merge`, `cmd_land`, or any other `wrap.sh` verb.
- No retry, no forced pull, no reset beyond what `_pull_default` already does.

## After state

- `wrap.sh apply --pull-only <repo>` (dry run) and `wrap.sh apply --pull-only --apply <repo>`
  print only the repo header, the fetch line, and the `-- pull:` section; no worktree, branch,
  archive, origin-branch, stray-line, or stray-commit section prints.
- A repo passed through `--pull-only --apply` ends with the same checkout state
  `_pull_default` alone would produce: `wrap.pull_past_dirty` off and a non-union dirty file
  present leaves the checkout behind with `FAILED pull --ff-only`; on, the blocking file is
  stashed and restored exactly as SPEC-286 describes; a union-marked dirty file is carried
  across either way.
- No worktree is removed, no local or origin branch is deleted, no stray-line or stray-commit
  carry branch is pushed, under `--pull-only`, whatever those steps would otherwise have done on
  the same repo.
- `wrap.sh apply --pull-only` combined with `--worktrees`, `--archive-unmerged`, or `--own`
  exits 64 and writes nothing.
- A plain `wrap.sh apply --apply <repo>` (no `--pull-only`) is byte-identical to its output
  before this change.
- `bash tests/test-wrap.sh` is green.

## Test plan

| Category | Case | Where |
|---|---|---|
| Scope, happy path | `--pull-only --apply` on a repo with a mergeable branch, a removable worktree, and a clean pull: the pull lands, HEAD moves to the incoming commit, and the branch and the worktree both still exist afterward | `tests/test-wrap.sh` |
| Scope | same run: no `-- worktrees:`, `-- branches:`, `-- archive unmerged:`, `-- origin branches:`, `-- stray lines:`, or `-- stray commits:` line appears anywhere in the output | same |
| Union carry still works | `--pull-only --apply` on a repo with a dirty `merge=union` file blocking the ff: the file is saved aside, the pull lands, the local line is carried back, matching plain `apply --apply` on the same fixture | same |
| `pull_past_dirty` still works | `--pull-only --apply` with the knob on and one non-union dirty tracked file blocking the ff: the file is stashed under the run-named stash, the pull lands, the stash pops back, matching plain `apply --apply` under the same knob | same |
| `pull_past_dirty` off | `--pull-only --apply` with the knob off and a blocking dirty file: exit 2, `FAILED pull --ff-only`, nothing stashed, matching plain `apply --apply` | same |
| Dry run | `--pull-only` with no `--apply`: prints the pull section's `NOTE`/`WOULD` lines, executes nothing, HEAD unmoved | same |
| Off default branch | `--pull-only --apply` on a repo whose checkout is on a non-default branch: prints `SKIP pull:` and runs the `fetch origin <def>:<def>` fallback, same as plain `apply` | same |
| Flag conflict | `--pull-only --worktrees`, `--pull-only --archive-unmerged`, and `--pull-only --own <path>` each exit 64 and change nothing in the repo | same |
| Regression | plain `apply --apply <repo>` with no `--pull-only`, on a fixture exercising a worktree removal, a branch delete, and the pull together: output is byte-identical to the pre-change baseline | same |
| Multi-repo | `--pull-only --apply` given two repo args: each gets its own header and pull section, in argument order, matching plain `apply`'s existing multi-repo behavior | same |
| Negative control | remove the `pull_only` gate around one swept step (for example `_apply_branches`) while leaving the flag parsing in place: the "no branch delete" assertion above goes red, confirming the test actually exercises the gate; restore | `docs/verification/wrap-pull-only.md` |

## Verification

- `bash tests/test-wrap.sh` exits 0.
- `bash tests/run-all.sh` fails no suite that does not already fail on `master`.
- `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<pull_only gate removed from one step>'` reports PASS.
