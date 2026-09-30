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
pull stage does. The design critique (below) also gates the two read-only reads nothing under
the flag consumes, the tip snapshot and the `gh` auth probe; see "What the flag narrows".

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
| tip snapshot (`wrap.sh:1559-1565`, `TIPS_FILE`) | skipped. It exists to compare branch tips right before a delete `_apply_branches`/`_apply_worktrees` would make; under `--pull-only` neither runs. The validated spec accepted it as a leftover; the design critique gated it (no `mktemp`, no `for-each-ref`) |
| `_gh_state` (`cmd_apply`, resolved once before the repo loop) | skipped. Every reader of its result is a sweep `--pull-only` turns off, so the call makes no `gh auth status` round-trip. Gated by the design critique, as above |
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
  commit is not lost and not carried anywhere: `--pull-only` never runs `_carry_stray_commits`,
  so nothing pushes it to a `wrap/stray-commits-*` branch. It is reported, though: the pull
  section prints `NOTE: <def> is N commits ahead of origin/<def>; --pull-only never carries them,
  plain apply --apply does` (see Report shape), so the commits never go silent.
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

One line is added inside `-- pull:` (added by the retroactive `/kit:think` pass, see
`docs/briefs/DECISION-BRIEF-wrap-pull-only.md`): when the checkout is on the default branch, the
fetch succeeded, and `git rev-list --count origin/<def>..HEAD` is N > 0, it prints
`NOTE: <def> is N commits ahead of origin/<def>; --pull-only never carries them, plain apply
--apply does` before the pull runs. It is read-only and changes no exit code. It prints in both
the ahead-only and the diverged case, and never without `--pull-only` (plain `apply` reports the
same commits in its `-- stray commits:` section).

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
gh_state = _gh_state()   -- once, before the repo loop, skipped under PULL_ONLY
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
tip snapshot    -- read-only, skipped under PULL_ONLY
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
- [x] TASK-B: add a global `PULL_ONLY=0` next to the existing `APPLY=0`/`WORKTREES=0`/
  `ARCHIVE_UNMERGED=0` declarations (`wrap.sh:387-389`), matching their style, not a parameter
  threaded through a call chain. `cmd_apply` arg parsing gains a `--pull-only` case that sets
  `PULL_ONLY=1`. Immediately after the existing `want_own` bare-flag check, and **before** the
  `TIPS_OVERRIDE` existence check at `wrap.sh:1637` (see "Flag interaction" → "Check order" for
  why that order), add: when `PULL_ONLY=1` and any of `WORKTREES=1`, `ARCHIVE_UNMERGED=1`,
  `OWN_N -gt 0`, or `TIPS_OVERRIDE` non-empty, print `wrap.sh apply: --pull-only cannot combine
  with <flag>` naming the specific conflicting flag and exit 64, writing nothing. Acceptance:
  Test plan "Flag conflict" rows.
- [x] TASK-C: `_apply_repo` gate: read the global `PULL_ONLY` directly inside `_apply_repo`, the
  same way `ARCHIVE_UNMERGED` is already read there (`[ "$ARCHIVE_UNMERGED" = 1 ] && ...`), not
  as a parameter passed in from `cmd_apply`'s call site. Wrap the `_apply_worktrees`,
  `_apply_branches`, `_apply_archive_unmerged`, `_apply_origin_branches`, `_carry_stray`, and
  `_carry_stray_commits` calls (each with its own section-header echo) in
  `if [ "$PULL_ONLY" != 1 ]; then ... fi`, so nothing prints for those sections under the flag.
  Leave the fetch call and the pull section itself unconditional; skip the tip snapshot and
  `_gh_state` (design critique), per "What the flag narrows". Vary the fetch-failure line per "Report shape" (`PULL_ONLY=1` →
  `(fetch failed; the pull below will likely fail too)`). Acceptance: Test plan "Scope, happy
  path", "Scope", "Off default branch", "Fetch-failure wording" rows.

### Phase 3: Wiring and docs
- [x] TASK-D: `commands/wrap.md` step 5 gains one bullet: when the operator wants the pull alone
  (a shared checkout, other sessions own the open branches), `bin/wrap apply --pull-only --apply
  <repo>` instead of the full `apply --apply --worktrees` sweep, including the "Stray commits
  interaction" NOTE (a checkout ahead of origin still needs plain `apply` to carry those commits
  before the pull can land). Acceptance: reviewed against this spec's wording; no test asserts
  prose.
- [x] TASK-E: three usage strings gain `[--pull-only]` in the flag list: `bin/wrap`'s own usage
  header (line 9), `wrap.sh`'s own header comment (line 6, what `_usage()` prints via
  `sed -n '2,31p'`, `wrap.sh:120`), and the inline usage string `cmd_apply` prints on the no-repo
  path (`lib/wrap/wrap.sh` around line 1641, `usage: wrap.sh apply [--apply] [--worktrees]
  ...`). Acceptance: tested through the no-repo path, not a flag conflict, `wrap.sh apply
  --pull-only` with no repo argument and no other flag exits 64 and its usage line contains
  `--pull-only` (Test plan "Usage line" row); the flag-conflict rows exercise the conflict check
  from TASK-B, not this usage string, and stay separate on purpose.
- [x] TASK-F: `docs/consumer-contract.md` line 78 (the `bin/wrap` row's `apply` description)
  gains the flag and its one-line behavior. Acceptance: reviewed for accuracy against
  TASK-B/TASK-C; no test.
- [x] TASK-G: `docs/CHANGELOG.md` `[Unreleased]` section gains one bullet in the file's existing
  per-surface style, `Command surface (\`wrap apply\`, additive): ...`, citing SPEC-359.
  Acceptance: reviewed against the file's own convention (surface tag, one-paragraph behavior,
  trailing `(SPEC-359)`).
- [x] TASK-H: `tests/test-wrap.sh` gains the case block from `## Test plan` below: scope (happy
  path + section-absence), union carry, `pull_past_dirty` on and off, dry run, off-default-branch,
  stray commits ahead-only, stray commits diverged, fetch-failure wording, usage line (no-repo
  path), flag conflicts (all four rejected flags), regression, multi-repo. Acceptance:
  `bash tests/test-wrap.sh` exits 0 with every new `chk`/`chk_has`/`chk_no` passing.
- [x] TASK-I: `docs/verification/wrap-pull-only.md`, the negative-control record: remove the
  `pull_only` gate around one swept step (for example `_apply_branches`), confirm the "no branch
  delete" assertion from TASK-H goes red, restore, and record the run (green run plus the
  negative control, per this repo's verification-doc shape). Acceptance:
  `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<mutation>'` reports PASS.

### Phase 4: Regression
- [x] TASK-J: Run the full pre-existing `apply` test block in `tests/test-wrap.sh` (no
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

## After state

Each bullet is an acceptance criterion; the `AC-n` ids key the Test plan below.

- AC-1: `wrap.sh apply --pull-only <repo>` (dry run) and `wrap.sh apply --pull-only --apply <repo>`
  print only the repo header, the fetch line, and the `-- pull:` section; no worktree, branch,
  archive, origin-branch, stray-line, or stray-commit section prints.
- AC-2: A repo passed through `--pull-only --apply` ends with the same checkout state
  `_pull_default` alone would produce: `wrap.pull_past_dirty` off and a non-union dirty file
  present leaves the checkout behind with `FAILED pull --ff-only`; on, the blocking file is
  stashed and restored exactly as SPEC-286 describes; a union-marked dirty file is carried
  across either way.
- AC-3: A checkout on the default branch, ahead-only (local commits origin lacks, origin's tip
  unmoved): `_carry_stray_commits` does not run, so nothing pushes the commits anywhere, but
  `git pull --ff-only` is a genuine no-op, "Already up to date", exit 0, `HEAD` unchanged. The
  pull section's `NOTE: <def> is N commits ahead of origin/<def>` line names the commits; a plain
  `apply --apply` run carries them.
- AC-4: The same checkout, diverged (origin's tip has also moved): `git pull --ff-only` refuses,
  `FAILED pull --ff-only`, exit 2, nothing pushed, nothing local moves. Plain `apply --apply` is
  the recovery, per the Stray commits interaction NOTE.
- AC-5: No worktree is removed, no local or origin branch is deleted, no stray-line or stray-commit
  carry branch is pushed, under `--pull-only`, whatever those steps would otherwise have done on
  the same repo.
- AC-6: Under `--pull-only --apply`, a pull skipped because `index.lock` stays held, or a repo whose
  default branch does not resolve, exits 2: the pull is the whole job, so a skipped pull is a
  failed call. Plain `apply` keeps exit 0 in both cases. In a dry run the unresolved default
  branch still exits 2 (the real run cannot pull either); a held lock does not, since it is
  transient and the dry run writes nothing.
- AC-7: `wrap.sh apply --pull-only` combined with `--worktrees`, `--archive-unmerged`, `--own`, or
  `--tips-file` exits 64 and writes nothing.
- AC-8: The fetch-failure line reads `(fetch failed; the pull below will likely fail too)`
  under `--pull-only`, and `(fetch failed; every delete is skipped)` as before without it.
- AC-9: Every pre-existing `apply` assertion in `tests/test-wrap.sh` (no `--pull-only` involved) stays
  green, unchanged in outcome.
- AC-10: `bash tests/test-wrap.sh` is green.

## Test plan
Date: 2026-09-30. Revised after /kit:test-plan-review-team rounds 1 and 2. Retroactive: the matrix was re-derived after the build, from the After state above plus the brief's survival scenarios. Every proof below is an assertion group that runs in `tests/test-wrap.sh`.
Source: this spec's ## After state (AC-1..AC-10) and `docs/briefs/DECISION-BRIEF-wrap-pull-only.md` ## Survival scenarios (S1..S5)

`tests/test-wrap.sh` has no group filter. Every Proof below runs the full suite and names the assertion prefix it prints, not a runnable filter.

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | `--pull-only --apply` on a repo with a merged local branch and an incoming commit | happy-path | AC-1, AC-5 | exit 0, HEAD at origin's tip, the merged branch survives, `-- pull:` prints | `bash tests/test-wrap.sh`; assertions `pull-only scope: *` |
| 2 | Same run: no sweep section prints | happy-path | AC-1 | none of `-- worktrees:`, `-- branches:`, `-- archive unmerged:`, `-- origin branches:`, `-- stray lines:`, `-- stray commits:`; no ahead NOTE (not ahead) | `bash tests/test-wrap.sh`; assertions `pull-only scope: no ... section`, `pull-only scope: no ahead NOTE` |
| 3 | Dirty `merge=union` file plus a non-union blocker, `wrap.pull_past_dirty` on | happy-path | AC-2 | union lines carried, blocker stashed and restored, no stash left, exit 0; the stray log line is not carried to an origin `wrap/stray-*` branch | `bash tests/test-wrap.sh`; assertions `pull-only union+stash: *` |
| 4 | Non-union blocker, knob off | failure-injection | AC-2 | exit 2, `FAILED pull --ff-only`, nothing stashed, HEAD unmoved; a dirty union file's local line survives the failed pull | `bash tests/test-wrap.sh`; assertions `pull-only knob off: *` |
| 5 | Dry run (no `--apply`) | boundary/edge | AC-1 | `[DRY-RUN] pull --ff-only`, HEAD unmoved, no sweep section | `bash tests/test-wrap.sh`; assertions `pull-only dry run: *` |
| 6 | Checkout on a feature branch (S5) | boundary/edge | AC-1 | `SKIP pull:` and the `fetch origin main:main` fallback, no sweep section | `bash tests/test-wrap.sh`; assertions `pull-only off-default: *` |
| 7 | Default branch ahead, origin unmoved (S1) | boundary/edge | AC-3, AC-5 | exit 0, no `FAILED`, HEAD unchanged, ahead NOTE prints, no `wrap/stray-commits-*` branch locally or on origin | `bash tests/test-wrap.sh`; assertions `pull-only ahead-only: *` |
| 8 | Default branch ahead, origin also moved | failure-injection | AC-4, AC-5 | exit 2, `FAILED pull --ff-only`, ahead NOTE prints, HEAD unmoved, no carry branch anywhere | `bash tests/test-wrap.sh`; assertions `pull-only diverged: *` |
| 9 | Origin unreachable (S3) | failure-injection | AC-8 | `(fetch failed; the pull below will likely fail too)`, not `(fetch failed; every delete is skipped)`, exit 2, `FAILED pull`. Plain `apply` keeps the old wording (pre-existing fetch-failure assertions) | `bash tests/test-wrap.sh`; assertions `pull-only fetch failure: *` |
| 10 | A stale `index.lock` held through the pull, mtime fixed at 2000-01-01 so it is stale on any clock | failure-injection | AC-6 | `--pull-only --apply` prints `SKIP pull --ff-only (checkout on main): index.lock held by another writer` and exits 2; plain `apply --apply` on the same locked repo exits 0 | `bash tests/test-wrap.sh`; assertions `pull-only stale lock: *`, `plain apply stale lock: *` |
| 11 | A repo with no origin, so no default branch resolves | failure-injection | AC-6 | `--pull-only` exits 2 naming the skip; plain `apply` on the same repo still exits 0 | `bash tests/test-wrap.sh`; assertions `pull-only no default branch: *`, `plain apply no default branch: *` |
| 12 | Each of `--worktrees`, `--archive-unmerged`, `--own <path>`, `--own=<path>`, `--tips-file` with `--pull-only` (S2) | security/abuse | AC-7 | each call passes `--apply`; exit 64 naming the flag; `--tips-file` refused for the conflict before the missing-path check; HEAD unmoved though origin moved | `bash tests/test-wrap.sh`; assertions `pull-only conflict: *`, `pull-only conflicts: no refused call pulled` |
| 13 | `apply --pull-only` with no repo | boundary/edge | AC-7 (TASK-E) | exit 64, usage line names `--pull-only` | `bash tests/test-wrap.sh`; assertions `pull-only usage: *` |
| 14 | Two repo args | boundary/edge | AC-1 | each repo gets its own header and pulls | `bash tests/test-wrap.sh`; assertions `pull-only multi-repo: *` |
| 15 | Every pre-existing `apply` group, no `--pull-only` | regression | AC-9, AC-10 | unchanged outcome | `bash tests/test-wrap.sh`, exit 0 (full suite) |
| 16 | A live run against a real remote: `git clone` the dwarves-kit origin into a scratch dir, reset the clone's main back one commit, then `bin/wrap apply --pull-only --apply <clone>` | integration (live remote) | AC-1, AC-5 | exit 0, HEAD back at origin/main, only the header, fetch, and `-- pull:` sections print | the recorded run in `docs/verification/wrap-pull-only.md`, "Live run" |
| N1 | Negative control: sweep gate. In `lib/wrap/wrap.sh`, change `if [ "$PULL_ONLY" != 1 ]; then` to `!= 99` | regression (negative control) | AC-1, AC-5 | RED: `pull-only scope:` section-absence and branch-survival, the union+stash stray-branch assertion, the ahead-only and diverged carry-branch assertions | `bash lib/gate/negctl.sh "$PWD" 'bash tests/test-wrap.sh' 'python3 <mut.py> N#'`, mutation script and output recorded in `docs/verification/wrap-pull-only.md` |
| N2 | Negative control: ahead NOTE gate. Change the first `= 1` in `if [ "$PULL_ONLY" = 1 ] && [ "$fetch_ok" = 1 ]; then` to `= 99` | regression (negative control) | AC-3, AC-4 | RED: the ahead-only and diverged NOTE assertions | `bash lib/gate/negctl.sh "$PWD" 'bash tests/test-wrap.sh' 'python3 <mut.py> N#'`, mutation script and output recorded in `docs/verification/wrap-pull-only.md` |
| N3 | Negative control: skipped-pull exit in `run()`. Change the first `= 1` in `[ "$PULL_ONLY" = 1 ] && [ "$APPLY" = 1 ] && FAILURES=1` to `= 99` | regression (negative control) | AC-6 | RED: `pull-only stale lock: exits 2` | `bash lib/gate/negctl.sh "$PWD" 'bash tests/test-wrap.sh' 'python3 <mut.py> N#'`, mutation script and output recorded in `docs/verification/wrap-pull-only.md` |
| N4 | Negative control: unresolved default branch exit. Change `[ "$PULL_ONLY" = 1 ] && FAILURES=1` to `= 99` | regression (negative control) | AC-6 | RED: `pull-only no default branch: exits 2` | `bash lib/gate/negctl.sh "$PWD" 'bash tests/test-wrap.sh' 'python3 <mut.py> N#'`, mutation script and output recorded in `docs/verification/wrap-pull-only.md` |
| N5 | Negative control: conflict refusals. On every line containing `cannot combine with`, change `if [` to `if false && [`, so no refusal fires | regression (negative control) | AC-7 | RED: the `pull-only conflict` exit and names-the-flag assertions, the `--tips-file` not-the-missing-path assertion, and `pull-only conflicts: no refused call pulled` | `bash lib/gate/negctl.sh "$PWD" 'bash tests/test-wrap.sh' 'python3 <mut.py> N#'`, mutation script and output recorded in `docs/verification/wrap-pull-only.md` |
| N6 | Negative control: fetch wording. Replace the string `(fetch failed; the pull below will likely fail too)` with `(fetch failed; every delete is skipped)` | regression (negative control) | AC-8 | RED: `pull-only fetch failure:` wording assertions | `bash lib/gate/negctl.sh "$PWD" 'bash tests/test-wrap.sh' 'python3 <mut.py> N#'`, mutation script and output recorded in `docs/verification/wrap-pull-only.md` |

The tip-snapshot skip and the `_gh_state` skip under `--pull-only` are performance-only. Neither changes any observable output or exit code, so neither has an oracle and neither carries a negative control.

### Coverage notes
- Categories skipped: none. Security/abuse is thin by nature: the flag reads no untrusted input beyond argv, so the abuse surface is flag combinations (row 12).
- Uncovered scenario S4 (design critique Medium finding 6, concurrency): two sessions run `--pull-only --apply` on one checkout under `wrap.pull_past_dirty`. The race lives in `_pull_default`'s stash/pop (SPEC-286), unchanged here. A deterministic two-process fixture would test that spec, not this one. Named as a gap, not a guarantee.
- AC-5's worktree half has no fixture of its own: worktree removal needs `--worktrees`, which `--pull-only` refuses (row 12), so a worktree could never be removed under the flag. The stray-line and stray-commit halves are rows 3, 7 and 8.
- Accepted LOW: the ahead count is only ever 1 in fixtures.
- Uncovered (design critique Low finding 3): `--pull-only` with `--under <root>`. Repo-list building does not read `PULL_ONLY`.
- Uncovered (design critique Low finding 4): NOTE ordering when the ahead NOTE and `_pull_default`'s own dirty-file NOTE both print. Named as a gap, not a guarantee.
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list. A missing acceptance criterion or an unenumerated category is a gap, surfaced here, not a guarantee.
- Rejected round-1 findings, with reasons: exact-string assertions stay exact (the report wording is the contract, as everywhere in this suite); the `1 commits` pluralization stays (it matches the file's existing `${ahead} stray commits` style); no gh precondition is added (`_gh_state` never runs under `--pull-only`); fixture-name registry and helper `set -e` are suite-wide conventions, out of scope for this spec; a single-case runner is a suite-wide change, out of scope for this spec.

## Verification

- `bash tests/test-wrap.sh` exits 0.
- `bash tests/run-all.sh` fails no suite that does not already fail on `master`.
- `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<pull_only gate removed from one step>'` reports PASS.

## Design critique
Date: 2026-09-30
Design source: SPEC-359 ## Decision (the spec carries no `## Solution` heading; its Decision section is the solution) plus the `## Solution` of `docs/briefs/DECISION-BRIEF-wrap-pull-only.md`
Lenses run: simplicity, performance, boundaries/composability, data-model & correctness, operability/failure-modes; missing: none
Run retroactively on a built change. Every finding marked FIXED became a code or spec change on this branch, re-verified by `tests/test-wrap.sh`.

### Critical findings
None.

### High findings
1. Under `--pull-only --apply`, a persistent `index.lock` makes `run()` print `SKIP pull --ff-only: index.lock held by another writer` and return 0, so the one step the flag exists for is skipped with exit 0. -- found by: correctness -- fix: FIXED, `run()` sets `FAILURES=1` on that SKIP when `PULL_ONLY=1` and `APPLY=1`; the call exits 2.
2. `commands/wrap.md` said ahead-only commits "stay unreported", false once the ahead NOTE landed. -- found by: operability -- fix: FIXED in the docs gate (manual, CHANGELOG, consumer-contract).

### Medium findings
1. The tip snapshot (`mktemp` + `for-each-ref`) runs per repo under `--pull-only`, where nothing reads it. -- found by: simplicity, performance -- fix: FIXED, skipped when `PULL_ONLY=1`; the "accepted leftover" row in "What the flag narrows" is superseded.
2. `_gh_state` (`gh auth status`) runs once per call under `--pull-only`, where nothing reads it. -- found by: performance -- fix: FIXED, skipped when `PULL_ONLY=1`.
3. `bin/wrap`'s usage header lacked `[--pull-only]` (TASK-E named it). -- found by: boundaries -- fix: FIXED.
4. An unresolved default branch prints `SKIP` and exits 0, so the pull never ran and a script sees success. -- found by: operability -- fix: FIXED under `--pull-only` only (`FAILURES=1`, exit 2); plain `apply` keeps its behavior.
5. A diverged pull failure printed no recovery at the failure site. -- found by: operability -- fix: FIXED by the ahead NOTE, which prints before the pull and names plain `apply --apply`.
6. Two concurrent `--pull-only --apply` runs under `wrap.pull_past_dirty` on one checkout can race on the shared working tree. -- found by: correctness -- fix: not changed; the stash/pop mechanics are `_pull_default`'s, owned by SPEC-286, and a Non-goal here. `--pull-only` adds no new race beyond plain `apply`.

### Low findings
1. The ahead NOTE adds a fifth `rev-list --count origin/<def>..HEAD` copy in `wrap.sh`. -- found by: boundaries, performance -- fix: none; a shared helper earns its place at a sixth caller.
2. The fetch-failure wording branches on `PULL_ONLY` inline. -- found by: simplicity, boundaries -- fix: none; matches the file's style.
3. No test combines `--pull-only` with `--under`. -- found by: boundaries -- fix: none; repo-list building is independent of `PULL_ONLY`.
4. The ahead NOTE and `_pull_default`'s own dirty-file NOTE can both print; their order is unasserted. -- found by: correctness -- fix: none.

### Scores
- Simplicity: 8/10
- Performance: 7/10
- Boundaries/composability: 8/10
- Data-model & correctness: 7/10
- Operability/failure-modes: 7/10

### Verdict: REVISE

## Test plan critique
Date: 2026-09-30
Spec: SPEC-359
Lenses run: coverage completeness, oracle & falsifiability, feasibility & reproducibility, test-ladder & boundary depth, determinism & maintainability; missing: none. Tiering & floor: N/A, not an AI-in-the-loop plan.
Rounds: `[[QL-VERDICT round=1 clean=false findings=17]]` (five parallel lenses, deduplicated) · `[[QL-VERDICT round=2 clean=false findings=8]]` (one distinct reviewer, all five lenses; max severity fell CRITICAL to HIGH) · `[[QL-VERDICT round=3 clean=true findings=0]]` (one distinct reviewer). Round 1 was revised by a distinct reviser subagent; round 2's fixes were single-line scale and hand-applied by the lead, then confirmed by the round-3 reviewer.

### Critical findings
1. One negative control covered only the sweep gate; the NOTE, the skipped-pull exits, the conflict refusals and the fetch wording were green-only. -- found by: oracle -- fix: N1 to N6, one mutation per gate, recorded in `docs/verification/wrap-pull-only.md` -- resolved in round 2

### High findings
1. Proofs named assertion groups the suite cannot run alone. -- found by: feasibility -- fix: every proof now runs the full suite and names the assertion prefix -- resolved in round 2
2. No live run on real state. -- found by: ladder -- fix: row 16, a pull-only run on a fresh clone of the real origin -- resolved in round 2
3. N-row mutation arguments were labels, not commands; N5 left the refusal message printing. -- found by: feasibility, oracle -- fix: `mut.py N#` with exact-once match guards; N5 disables each whole refusal -- resolved in round 3
4. The stale-lock fixture used a 2026 mtime. -- found by: determinism, feasibility -- fix: `touch -t 200001010000` -- resolved in round 2

### Medium findings
1. `--own=<path>` form never combined with `--pull-only`. -- found by: ladder -- resolved in round 2
2. Conflict calls lacked `--apply`, so "no refused call pulled" could not go red. -- found by: oracle -- resolved in round 3
3. Row 9 Expected named the wrong string. -- found by: coverage -- resolved in round 3
4. AC-2 knob-off lacked a union file; AC-5 had no stray-line fixture. -- found by: coverage -- resolved in round 3 (the worktree half is unreachable under the flag, named in the coverage notes)
5. Accepted gaps lived only in the design critique. -- found by: coverage -- resolved in round 2

### Low findings
1. Ahead count is only ever 1. -- found by: ladder -- accepted
2. Exact-string assertions, `1 commits` pluralization, gh precondition, fixture registry, single-case runner. -- found by: determinism, feasibility -- rejected with reasons in the coverage notes

### Scores (final round)
- Coverage completeness: 8/10
- Oracle & falsifiability: 9/10
- Feasibility & reproducibility: 9/10
- Test-ladder & boundary depth: 8/10
- Determinism & maintainability: 9/10
- Tiering & floor: N/A, not an AI-in-the-loop plan

### Verdict: SOLID

## Review
Date: 2026-09-30
Files reviewed: 11 (`git diff ad1fc35f 96b4e37b`)
Reviewers: security (opus), architecture (sonnet), test-coverage (sonnet), kit:advisor critique (sonnet). No domain lens: `role-classify` returned `generic`. Coverage-delta: `ok: source + test moved together`.

### Security
Verdict SECURE, 9/10. Every delete, archive and push call sits inside the `PULL_ONLY` sweep gate. The conflict check runs after the whole argv loop, so flag order, repeats and `--own=` cannot slip past it. One LOW, advisory: `--tips-file=` with an empty value passes the conflict check, but the snapshot is skipped under the flag, so the call does nothing extra (`lib/wrap/wrap.sh:1653`).

### Architecture
7/10. The sweep gate is one seam; the other `PULL_ONLY` checks each carry a distinct behavior at a pre-existing decision point. MEDIUM `stale-adr: commands/wrap.md:133` said ahead-only commits "stay unreported", contradicting AC-3 and `wrap.sh` NOTE: FIXED in this round. LOW `stale-adr`: CHANGELOG and consumer-contract omit AC-6's exit 2: fixed by the docs gate.

### Test coverage
9/10. Every observable `PULL_ONLY` branch has an assertion and a named negative control (N1 to N6). LOW, not worth: the snapshot and `gh` skips have no oracle (performance-only).

### Advisor (critique mode)
1 finding: Test plan row 16 pointed at a "Live run" record that did not exist, and the verification doc still listed a live run under "does not cover". FIXED: the live run ran on a fresh clone of the real origin and is recorded.

### Suppressed
- Security, confidence 50: the global `FAILURES` baseline in `_pull_default` (`before="$FAILURES"`) hides a later repo's failed pull once an earlier repo failed in the same multi-repo call, so its stash pops and union carry-back run as if the pull landed. Pre-existing, predates this spec; `--pull-only`'s lock-skip is one more trigger. Route manual, reported as a follow-up, not fixed here.

### Previously rejected
None (`docs/verification/rejected-findings.md` has no matching finding-key).

### Scores
- Security: 9/10
- Architecture: 7/10
- Test coverage: 9/10
- Combined: 8.3/10

### Verdict: FIX THEN SHIP, fixes applied
Both MEDIUM-or-higher findings (the stale manual sentence, the missing live-run record) are fixed on this branch. Re-review round 2 over the fix diff: see the ledger `review` record.

### TODOs
- Follow-up (manual, pre-existing): make `_pull_default` compare against a per-repo failure baseline rather than the global `FAILURES`.
