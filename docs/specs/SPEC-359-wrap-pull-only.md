# SPEC-359: `wrap apply --pull-only`, the pull stage alone

**Status:** VALIDATED (0 criticals, 6 warnings folded)
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

Add `--pull-only` to `wrap.sh apply`. Under it, `_apply_repo` gates the write-capable sweeps
(worktrees, branches, archive, origin branches, stray lines, stray commits) off and runs only
`fetch --prune`, default-branch resolution, and the existing pull section (`_pull_default` when
the checkout is on the default branch, the existing `fetch origin <def>:<def>` fallback
otherwise). It does not touch `_pull_default` itself: the union carry and the
`wrap.pull_past_dirty` stash-and-pop both keep working exactly as SPEC-286 and the union-carry
sibling spec describe, because `--pull-only` changes what `_apply_repo` calls, never what the
pull stage does. A read-only remainder (the tip snapshot, the `gh` auth probe) still runs; see
"What the flag narrows" below for exactly which of those are gated and which are accepted as
harmless leftovers.

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
| tip snapshot (`wrap.sh:1559-1565`, `TIPS_FILE`) | still computed unconditionally, per repo. It exists to compare branch tips right before a delete `_apply_branches`/`_apply_worktrees` would make; under `--pull-only` neither of those runs, so the snapshot is read and thrown away unused. Accepted as a harmless leftover (one `for-each-ref`, no write, removed at the end of the call) rather than threading a second condition through `_apply_repo`'s existing single early-return-free body |
| `_gh_state` (`cmd_apply`, resolved once before the repo loop) | still runs, unchanged. It is a `gh auth status` read shared across every repo in the call regardless of flags; gating it per-flag would mean resolving it twice under some flag combinations for no behavior change, since nothing under `--pull-only` reads its result. Accepted as a harmless leftover |
| `--tips-file` | **rejected**: `--pull-only` combined with `--tips-file` exits 64, for the same reason as `--worktrees`/`--archive-unmerged`/`--own` below, a test seam for tip-comparison logic that never runs under this flag is a silent no-op the operator should not be allowed to pass by accident |
| `_apply_worktrees` (worktree removal, branch delete on merge proof) | does not run |
| `_apply_branches` (local branch delete on merge proof) | does not run |
| `_apply_archive_unmerged` (opt-in origin archive push) | does not run, even if `--archive-unmerged` is also given (rejected, see Flag interaction) |
| `_apply_origin_branches` (origin branch delete on merged PR) | does not run |
| `_carry_stray` (stray-line carry branch + push) | does not run |
| `_carry_stray_commits` (`wrap.sh:1592`, stray-commit carry branch + push, `git reset --keep` back to origin) | does not run, see "Stray commits interaction" below |
| `_pull_default` (union carry, `wrap.pull_past_dirty` stash/pop, `pull --ff-only`) | runs, unchanged |
| off-default-branch fallback (`fetch origin <def>:<def>`) | runs, unchanged |

Nothing above is a new code path inside `_pull_default`; `--pull-only` is purely a gate around
the write-capable calls `_apply_repo` already makes in sequence, plus one new arg-parsing
refusal (`--tips-file`).

### Stray commits interaction

Plain `apply` runs `_carry_stray_commits` before the pull specifically because, per its own
comment at `wrap.sh:1592`, "a default branch ahead of origin can never fast-forward": when the
main checkout is on the default branch and holds commits origin does not, that step pushes them
to a `wrap/stray-commits-*` branch and moves the local default branch back to where it forked
from origin, so the pull that follows can land. `--pull-only` skips that step entirely (see
above). Two different outcomes follow, and they are not the same case:

- **Ahead-only** (the default branch holds a local commit origin lacks, and origin's own tip has
  not moved): origin's tip is still an ancestor of `HEAD`, so `git pull --ff-only` is a true
  no-op here, git reports "Already up to date", exits 0, and `HEAD` does not move. The local
  commit is not lost, but it is not reported or carried anywhere either: `--pull-only` never runs
  `_carry_stray_commits`, so nothing pushes it to a `wrap/stray-commits-*` branch, and a plain
  `apply --apply` (or `apply --pull-only` again) is what eventually surfaces it.
- **Diverged** (origin's tip has also moved, to a commit that is not an ancestor of `HEAD`):
  `git pull --ff-only` refuses. Its own message here is `fatal: Not possible to fast-forward,
  aborting.`, no file or ref names, unlike the dirty-tracked-file refusal above, which names the
  blocking path. `run()` (`wrap.sh:422-437`) prints `FAILED pull --ff-only: exit <rc>` and sets
  `FAILURES=1`, so the call exits 2. Nothing is pushed and nothing local moves.

This is expected under `--pull-only`, not a defect: the flag's whole point is to skip every write
but the pull, and moving stray commits onto a carry branch is itself a write.

**NOTE**: an operator who hits `FAILED pull --ff-only` under `--pull-only` should re-run plain
`apply --apply <repo>`, which carries any stray commits onto a branch and moves the default
branch back so the pull lands. An ahead-only checkout needs no such recovery, it already exited
0 with `HEAD` unchanged; the failure is specific to the diverged case.

### Flag interaction

`--pull-only` refuses to combine with `--worktrees`, `--archive-unmerged`, `--own`, or
`--tips-file` (exit 64, naming the conflicting flag): the first three exist to widen or scope a
sweep `--pull-only` explicitly turns off, and `--tips-file` seeds tip-comparison data that step
never reads under this flag (see "What the flag narrows"); silently ignoring any of the four
would let a typo skip a cleanup the operator meant to run, or waste a seeded test fixture with no
visible effect. `--under` is unaffected: `--pull-only` only changes which steps `_apply_repo`
runs per resolved repo, not how the repo list is built. `--apply` behaves as it does today: omit
it for a dry run (the existing `NOTE`/`WOULD` lines `_pull_default` already prints), pass it to
execute the fetch and the pull.

**Check order.** The conflict check runs right after `cmd_apply`'s flag-parsing loop, immediately
after the existing `want_own` bare-flag check and **before** the `TIPS_OVERRIDE` existence check
at `wrap.sh:1637` (`[ -n "$TIPS_OVERRIDE" ] && [ ! -f "$TIPS_OVERRIDE" ]`). Chosen deliberately:
`--pull-only --tips-file=<path>` should be refused for the conflict, not for whether `<path>`
exists, so the operator reading the error sees the actual reason (the flag combination) rather
than an unrelated file-not-found that would still be wrong advice even with a real path.

### Report shape

`--pull-only` prints the repo header, the fetch line (or its failure), and the `-- pull:`
section exactly as `_apply_repo` prints them today, with one wording change: the fetch-failure
line at `wrap.sh:1548` today reads `(fetch failed; every delete is skipped)`, which is misleading
under `--pull-only` because nothing here ever deletes. Under the flag it reads `(fetch failed;
the pull below will likely fail too)` instead; without the flag the line is unchanged.
`--pull-only` never prints `-- worktrees:`, `-- branches:`, `-- archive unmerged:`,
`-- origin branches:`, `-- stray lines:`, or `-- stray commits:`, not even a `SKIPPED` line for
each, because those sections do not run at all under this flag, and a `SKIPPED` line implies a
step that considered the repo and declined, which is not what happened. The closing
`== APPLY complete. ...` / `== DRY-RUN complete. ...` line is unchanged.

## Picture

```
cmd_apply(args)
      |
      v
parse flags (incl. --pull-only -> global PULL_ONLY=1)
      |
      v
[PULL_ONLY=1 && (--worktrees|--archive-unmerged|--own|--tips-file given)?]
      |                                       |
      no                                     yes --> exit 64, nothing written
      v
gh_state = _gh_state()   -- once, before the repo loop (wrap.sh:1653), unconditional
      |
      v
for each repo: _apply_repo(repo, gh_state)
      |
      v
fetch --prune  (failure message varies under PULL_ONLY, see Report shape)
      |
      v
resolve def (default branch), cur (checked-out branch)
      |
      v
tip snapshot    -- read-only, accepted leftover either way (global PULL_ONLY, not gated)
      |
      v
   [PULL_ONLY?] ----------------- no ----------------+
      |                                               v
     yes                              worktrees -> branches -> archive-unmerged
      |                                -> origin branches -> stray lines
      |                                -> stray commits (cur == def only)
      |                                               |
      +-----------------------------------------------+
      |
      v
  cur == def? --- no --> SKIP pull; fetch origin <def>:<def>
      |
     yes
      v
  _pull_default: union carry -> wrap.pull_past_dirty stash/pop -> git pull --ff-only
```

## Design

obvious: `--pull-only` as a flag on the existing `apply` verb, not a new `wrap pull` verb. See
"Why a flag on `apply`, not a new verb" above, `apply` already owns the repo list, `--under`
expansion, the dry-run/`--apply` split, and the per-repo `_apply_repo` loop the pull stage
already lives inside; a sibling verb would rebuild all of that for zero new behavior.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-A: Write this spec.

### Phase 2: Core (`lib/wrap/wrap.sh`)
- [ ] TASK-B: add a global `PULL_ONLY=0` next to the existing `APPLY=0`/`WORKTREES=0`/
  `ARCHIVE_UNMERGED=0` declarations (`wrap.sh:387-389`), matching their style, not a parameter
  threaded through a call chain. `cmd_apply` arg parsing gains a `--pull-only` case that sets
  `PULL_ONLY=1`. Immediately after the existing `want_own` bare-flag check, and **before** the
  `TIPS_OVERRIDE` existence check at `wrap.sh:1637` (see "Flag interaction" → "Check order" for
  why that order), add: when `PULL_ONLY=1` and any of `WORKTREES=1`, `ARCHIVE_UNMERGED=1`,
  `OWN_N -gt 0`, or `TIPS_OVERRIDE` non-empty, print `wrap.sh apply: --pull-only cannot combine
  with <flag>` naming the specific conflicting flag and exit 64, writing nothing. Acceptance:
  Test plan "Flag conflict" rows.
- [ ] TASK-C: `_apply_repo` gate: read the global `PULL_ONLY` directly inside `_apply_repo`, the
  same way `ARCHIVE_UNMERGED` is already read there (`[ "$ARCHIVE_UNMERGED" = 1 ] && ...`), not
  as a parameter passed in from `cmd_apply`'s call site. Wrap the `_apply_worktrees`,
  `_apply_branches`, `_apply_archive_unmerged`, `_apply_origin_branches`, `_carry_stray`, and
  `_carry_stray_commits` calls (each with its own section-header echo) in
  `if [ "$PULL_ONLY" != 1 ]; then ... fi`, so nothing prints for those sections under the flag.
  Leave the tip snapshot, `_gh_state`, the fetch call, and the pull section itself unconditional,
  per "What the flag narrows". Vary the fetch-failure line per "Report shape" (`PULL_ONLY=1` →
  `(fetch failed; the pull below will likely fail too)`). Acceptance: Test plan "Scope, happy
  path", "Scope", "Off default branch", "Fetch-failure wording" rows.

### Phase 3: Wiring and docs
- [ ] TASK-D: `commands/wrap.md` step 5 gains one bullet: when the operator wants the pull alone
  (a shared checkout, other sessions own the open branches), `bin/wrap apply --pull-only --apply
  <repo>` instead of the full `apply --apply --worktrees` sweep, including the "Stray commits
  interaction" NOTE (a checkout ahead of origin still needs plain `apply` to carry those commits
  before the pull can land). Acceptance: reviewed against this spec's wording; no test asserts
  prose.
- [ ] TASK-E: three usage strings gain `[--pull-only]` in the flag list: `bin/wrap`'s own usage
  header (line 9), `wrap.sh`'s own header comment (line 6, what `_usage()` prints via
  `sed -n '2,31p'`, `wrap.sh:120`), and the inline usage string `cmd_apply` prints on the no-repo
  path (`lib/wrap/wrap.sh` around line 1641, `usage: wrap.sh apply [--apply] [--worktrees]
  ...`). Acceptance: tested through the no-repo path, not a flag conflict, `wrap.sh apply
  --pull-only` with no repo argument and no other flag exits 64 and its usage line contains
  `--pull-only` (Test plan "Usage line" row); the flag-conflict rows exercise the conflict check
  from TASK-B, not this usage string, and stay separate on purpose.
- [ ] TASK-F: `docs/consumer-contract.md` line 78 (the `bin/wrap` row's `apply` description)
  gains the flag and its one-line behavior. Acceptance: reviewed for accuracy against
  TASK-B/TASK-C; no test.
- [ ] TASK-G: `docs/CHANGELOG.md` `[Unreleased]` section gains one bullet in the file's existing
  per-surface style, `Command surface (\`wrap apply\`, additive): ...`, citing SPEC-359.
  Acceptance: reviewed against the file's own convention (surface tag, one-paragraph behavior,
  trailing `(SPEC-359)`).
- [ ] TASK-H: `tests/test-wrap.sh` gains the case block from `## Test plan` below: scope (happy
  path + section-absence), union carry, `pull_past_dirty` on and off, dry run, off-default-branch,
  stray commits ahead-only, stray commits diverged, fetch-failure wording, usage line (no-repo
  path), flag conflicts (all four rejected flags), regression, multi-repo. Acceptance:
  `bash tests/test-wrap.sh` exits 0 with every new `chk`/`chk_has`/`chk_no` passing.
- [ ] TASK-I: `docs/verification/wrap-pull-only.md`, the negative-control record: remove the
  `pull_only` gate around one swept step (for example `_apply_branches`), confirm the "no branch
  delete" assertion from TASK-H goes red, restore, and record the run (green run plus the
  negative control, per this repo's verification-doc shape). Acceptance:
  `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<mutation>'` reports PASS.

### Phase 4: Regression
- [ ] TASK-J: Run the full pre-existing `apply` test block in `tests/test-wrap.sh` (no
  `--pull-only` anywhere in it) and confirm every assertion in it still passes. Acceptance:
  `bash tests/test-wrap.sh` exits 0 and no pre-existing `chk` line in the file changed its
  pass/fail outcome (diff the PASS/FAIL summary against a pre-change run).

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
- No gating of the tip snapshot or `_gh_state`: both are accepted read-only leftovers, per "What
  the flag narrows".

## After state

- `wrap.sh apply --pull-only <repo>` (dry run) and `wrap.sh apply --pull-only --apply <repo>`
  print only the repo header, the fetch line, and the `-- pull:` section; no worktree, branch,
  archive, origin-branch, stray-line, or stray-commit section prints.
- A repo passed through `--pull-only --apply` ends with the same checkout state
  `_pull_default` alone would produce: `wrap.pull_past_dirty` off and a non-union dirty file
  present leaves the checkout behind with `FAILED pull --ff-only`; on, the blocking file is
  stashed and restored exactly as SPEC-286 describes; a union-marked dirty file is carried
  across either way.
- A checkout on the default branch, ahead-only (local commits origin lacks, origin's tip
  unmoved): `_carry_stray_commits` does not run, so nothing pushes the commits anywhere, but
  `git pull --ff-only` is a genuine no-op, "Already up to date", exit 0, `HEAD` unchanged. The
  local commits stay unreported until a plain `apply --apply` run carries them.
- The same checkout, diverged (origin's tip has also moved): `git pull --ff-only` refuses,
  `FAILED pull --ff-only`, exit 2, nothing pushed, nothing local moves. Plain `apply --apply` is
  the recovery, per the Stray commits interaction NOTE.
- No worktree is removed, no local or origin branch is deleted, no stray-line or stray-commit
  carry branch is pushed, under `--pull-only`, whatever those steps would otherwise have done on
  the same repo.
- `wrap.sh apply --pull-only` combined with `--worktrees`, `--archive-unmerged`, `--own`, or
  `--tips-file` exits 64 and writes nothing.
- The fetch-failure line reads `(fetch failed; the pull below will likely fail too)`
  under `--pull-only`, and `(fetch failed; every delete is skipped)` as before without it.
- Every pre-existing `apply` assertion in `tests/test-wrap.sh` (no `--pull-only` involved) stays
  green, unchanged in outcome.
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
| Stray commits, ahead-only | `--pull-only --apply` on a repo whose default branch holds a local commit origin lacks, with origin's own tip unmoved: exit 0, "Already up to date" (no `FAILED` line), `HEAD` unchanged, no `wrap/stray-commits-*` branch created locally or on origin | same |
| Stray commits, diverged | same fixture, but origin's default branch has also moved to a different commit: exit 2, `FAILED pull --ff-only` present in the output, no `wrap/stray-commits-*` branch created locally or on origin, default branch left exactly where it was | same |
| Fetch-failure wording | `--pull-only` on a repo whose fetch fails (origin unreachable): the printed line reads `(fetch failed; the pull below will likely fail too)`, not the plain-`apply` wording, and the run exits 2 with a `FAILED pull` line present | same |
| Usage line | `wrap.sh apply --pull-only` with no repo argument and no other flag: exit 64, the printed `usage: wrap.sh apply ...` line contains `--pull-only` | same |
| Flag conflict | `--pull-only --worktrees`, `--pull-only --archive-unmerged`, `--pull-only --own <path>`, and `--pull-only --tips-file <path>` each exit 64 and change nothing in the repo | same |
| Regression | the existing `apply` assertions already in `tests/test-wrap.sh` (worktree removal, branch delete, the pull, all with no `--pull-only` in the call) stay green, unchanged in outcome | same |
| Multi-repo | `--pull-only --apply` given two repo args: each gets its own header and pull section, in argument order, matching plain `apply`'s existing multi-repo behavior | same |
| Negative control | remove the `pull_only` gate around one swept step (for example `_apply_branches`) while leaving the flag parsing in place: the "no branch delete" assertion above goes red, confirming the test actually exercises the gate; restore | `docs/verification/wrap-pull-only.md` |

## Verification

- `bash tests/test-wrap.sh` exits 0.
- `bash tests/run-all.sh` fails no suite that does not already fail on `master`.
- `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<pull_only gate removed from one step>'` reports PASS.
