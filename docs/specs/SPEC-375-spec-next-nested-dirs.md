# Spec: spec-next scans nested docs/specs, not just the top level
Generated: 2026-09-30
Status: DRAFT
Lane: full
Depth: standard (root cause and every design point are grounded by reading `lib/spec/spec-next.sh` directly and by live experiments run this session: bash `-x` traces of the real empty-repo abort, isolated exit-code probes of `set -euo pipefail` semantics, a real `gh pr list --json` call, and timed `git ls-files` variants; no outside unknown and no failure mode the author expects to miss alone)
References: `lib/spec/spec-next.sh` functions `_scan_numbers` (:89), `_scan_pr_numbers` (:108), `_numbers` (:160), `next` (:164), `check` (:171), `_prune_reservations` (:195), `_reserve_lock` (:254), `reserve` (:310), `_git_common_dir` (:48); `lib/telemetry/kit-log-dir.sh:56` (the default machine-wide, cross-repo ledger location); `tests/test-spec-reserve.sh` and `tests/test-spec-next-pr-scan.sh` (the fixture-repo pattern this spec's tests extend); `tests/test-hooks.sh:313-315` (the existing real-repo regression check)

## Amendments

- AMEND-1: 2026-09-30 | round 1 (7 reviewers) NEEDS REVISION | stripped private consumer-repo names/slugs, redesigned local scan around `git ls-files` over `find`, fixed the double-scan-under-the-lock cost, replaced the PR-scan's per-head Trees-API call with `gh pr list --json files`, corrected the false non-goal about `_prune_reservations` | at review | re-validated: superseded by AMEND-2
- AMEND-2: 2026-09-30 | round 2 (7 reviewers, 12 CRITICALs, 6 unique) NEEDS REVISION; lead closed the round and decided the design points below, applied without reopening | (1) moves BOTH scans outside the reservation lock entirely -- only a ledger read, a max+1, and the append happen while the lock is held, because the reviewed round measured the AMEND-1 local-scan shape (`--cached --others --exclude-standard -- '**/docs/specs/*'`) at 17.7-33.2s across a 29-worktree consumer repo (a leading `**` pathspec forces `--others` to walk the whole tree; `--cached` alone was 0.8-1.1s), and the reservation lock is MACHINE-WIDE by default (`lib/telemetry/kit-log-dir.sh:56`), so a slow scan blocks every repo's reserve, not just this one's; (2) local scan becomes `git ls-files --cached` (fast, index-only) plus a targeted, non-`**` check of literal nested `docs/specs` directories derived from the cached result, for untracked files, disclosing the gap this gives up (an untracked-only nested dir is invisible until first commit); (3) the digit guard becomes extract-then-DROP (`grep -E '^SPEC-[0-9]{1,6}$'`), not a bounded extraction regex, because a bounded regex would silently truncate an oversized token to its first 6 digits rather than rejecting it, and bash's `$((10#$n+1))` overflow is a SILENT WRAP (exit 0), never an error; (4) fixes a live bug reproduced directly against today's unfixed script: `reserve` on a repo with zero SPEC numbers anywhere aborts under `set -euo pipefail` after appending its ledger claim (inside `_prune_reservations`'s `realized="$(_scan_numbers)"`), orphaning that claim and repeating on every retry; (5) replaces the PR scan's per-head Trees-API call with one `gh pr list --json number,headRefOid,files,changedFiles,isCrossRepository` call, skips fork PRs outright (a public-repo poisoning vector), and paginates via `gh api .../pulls/<n>/files --paginate` when `gh`'s own `files` cap (exactly 100; the reviewed repo has PRs with 135, 588, and 667 changed files) truncates the list; (6) both scans emit raw paths and are filtered by ONE shared shell predicate, so the stub test exercises the same regex both surfaces run and the two cannot drift; also folds in a `check` argument-validation fix (bash arithmetic can execute an injected `$(...)` inside `$((...))`) | why: measured evidence plus a live reproduction, all gathered this session | at review | re-validated: pending round 3

## Problem

A private consumer monorepo (unrelated to this kit) keeps specs co-located: a
central `docs/specs/`, plus one `docs/specs/` per tool under `tools/<tool>/` and
per experiment under `experiments/<slug>/`, per that repo's own conventions. On
2026-09-29, `bash lib/spec/spec-next.sh reserve` (run from that repo) minted a
number that a nested tool's `docs/specs/` already held with no top-level entry at
all, and `spec-next.sh check` reported two more nested-only numbers as free while
committed files already existed there. That repo had already accumulated
duplicate numbers before this incident, purely from the same blind spot: one
number exists in 3 places (a top-level file plus 2 nested copies), another in 2
places (both nested, no top-level entry at all).

This session verified the identical shape inside **this kit's own repository**,
with no consumer repo needed as evidence:

```
$ git ls-files -- ':(glob)**/docs/specs/*' | grep -v '^docs/specs/' | head
_meta/megagoals/_archive/token-optim-v2/docs/specs/SPEC-122-static-floor-reduction.md
examples/hello-spec/docs/specs/SPEC-001-version-flag.md
lib/cosmetic/docs/specs/SPEC-201-cosmetic-hooks.md
lib/plugin-check/docs/specs/SPEC-105-cc-plugin-check.md
lib/stats/docs/specs/SPEC-126-ledger-event-schema.md
...
$ ls docs/specs/SPEC-126-*.md docs/specs/SPEC-134-*.md
docs/specs/SPEC-126-weekend-batch.md
docs/specs/SPEC-134-security-hardening.md
```

`lib/stats/docs/specs/SPEC-126-ledger-event-schema.md` and the top-level
`docs/specs/SPEC-126-weekend-batch.md` are two unrelated documents sharing one
number; the same is true for SPEC-134 and several others in `lib/stats/`,
`lib/sync/`, `lib/skill-curator/`, `lib/cosmetic/`, and `lib/plugin-check/`.
Today's `_scan_numbers` (`lib/spec/spec-next.sh:97`) never sees the nested copy,
so `check`/`next`/`reserve` on any of those numbers today would silently treat
them as free.

**A second, independent live bug found and reproduced this session, on an
otherwise ordinary (non-nested) repo:** `reserve`, run against a brand-new repo
that has zero SPEC numbers anywhere, aborts under `set -euo pipefail` AFTER
appending its ledger claim, and repeats on every retry:

```
$ bash lib/spec/spec-next.sh reserve   # against a fresh, empty repo
reserve exit=1                          # prints NOTHING to stdout
$ bash lib/spec/spec-next.sh reserve   # run again, same repo
reserve exit=1
$ cat "$RES_FILE"
2026-09-30T09:31:43Z | RESERVE | num=001 repo=/tmp/kit-empty-repo...
2026-09-30T09:31:43Z | RESERVE | num=002 repo=/tmp/kit-empty-repo...
```

Every real caller gets a hard failure and no number, while the ledger silently
piles up orphaned claims. See `## Root cause` for the mechanism.

## Root cause

### Nested-directory blindness

`lib/spec/spec-next.sh:89-101`, function `_scan_numbers`:

```
93    local wts wt
94    wts="$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')" || wts=""
95    [ -n "$wts" ] || wts="$ROOT"
96    while IFS= read -r wt; do
97      ls "$wt/docs/specs" 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true
98    done <<< "$wts"
```

`ls "$wt/docs/specs"` is a flat, non-recursive listing of exactly ONE directory
per worktree. It correctly loops over every worktree (`:94-98`, the concurrency
case SPEC-064/128 already fixed), but within each worktree it never descends
into `tools/*/docs/specs/`, `experiments/*/docs/specs/`, or (as the self-check
above shows) this kit's own `lib/*/docs/specs/`. `next` (`:164`) and `check`
(`:171`) both call `_numbers` (`:160`), which folds in `_scan_numbers` verbatim,
so both inherit the blind spot. The identical shape sits in `_scan_pr_numbers`
(`:108-133`) at `:130`, scoped to the same single `docs/specs` path via the
GitHub Contents API, non-recursive by nature of that endpoint.

### The reservation lock is machine-wide, and a slow scan holds it

`_reserve_lock` (`:254-302`) is keyed on `RES_LOCK="$RES_FILE.lock"`, and
`RES_FILE` resolves through `kit_resolve_log_dir` (`lib/telemetry/kit-log-dir.sh`).
That resolver's default (`:56`, `ledger.location` unset or `"shared"`) is
`${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs` -- **one path shared by
every repo on the machine**, not per-repo. `reserve` (`:310`) calls `next`
(computing `_numbers` -> `_scan_numbers`, one full scan) while holding this
SAME machine-wide lock, and `_prune_reservations` (`:195`, called at the tail of
`reserve`, still inside the lock) calls `_scan_numbers` a SECOND time via its
own `realized="$(_scan_numbers)"` line. Measured this round against a
29-worktree consumer repo: widening `_scan_numbers` to `git ls-files --cached
--others --exclude-standard -- ':(glob)**/docs/specs/*'` took 17.7-33.2s,
because a leading `**` pathspec cannot prune the untracked-file walk, so
`--others` still walks the entire tree; `--cached` alone (index-only, no
filesystem walk) took 0.8-1.1s on the same repo. Two calls of the slow variant,
inside a lock every OTHER repo's `reserve` on the same machine also has to wait
for, is the real cost this spec must remove -- not `reserve`'s own 5-attempt
retry loop (`:310`), which only re-fires on a rare lost-lock race and does not
multiply ordinary contention the way the shared-lock scope does. (The original
draft named the retry loop as the multiplier; that was wrong and is corrected
here.)

### The live empty-repo abort

Reproduced directly (see `## Problem`) with `bash -x`: on a repo with zero
SPEC numbers anywhere, `_scan_numbers`'s own trailing stage
(`| grep -oE '[0-9]+' | sort -n | uniq`, `:100-101`ish) finds no match, and
`grep` with no match exits 1. Under `set -o pipefail` (`:33`), this makes
`_scan_numbers`'s own reported exit status 1 even though it printed nothing
(no real error, just "found nothing"). Traced live: `next`, called as a bare
top-level command, absorbs this fine (`max="$(_numbers | tail -1)"` is a plain
variable assignment via command substitution, and empirically this specific
call site does not abort the script even when the substituted pipeline reports
non-zero -- confirmed with `bash -x`, `next` prints `001` cleanly). But inside
`reserve`, AFTER the ledger claim line is appended, `_prune_reservations`'s own
`realized="$(_scan_numbers)"` line (`:195`ish) is where the trace stops dead:
no further line of that function executes, and the whole `reserve` invocation
exits 1 with nothing on stdout. The claimed number is never returned to the
caller, yet the ledger keeps the line -- reproduced twice, minting and
orphaning `001` then `002`. `_scan_numbers` needs to return 0 unconditionally
on empty output (wrap its own trailing `grep -oE '[0-9]+'` with `|| true`, the
same convention every other line in this file already uses); this closes the
gap regardless of the precise reason one call site tolerates the non-zero exit
and another does not.

### `check` accepts an unvalidated argument into an arithmetic context

`check()` (`:171-183`ish) does `n="$(printf '%03d' "$((10#$n))")"` before any
validation of `$1`. Bash arithmetic expansion `$((...))` expands a nested
`$(...)` command substitution BEFORE evaluating the expression, so a caller
that can influence the argument (a CI wrapper, a wrapper script eval'ing
tool output) can smuggle a command: `check '$(rm -rf ~)'` executes
`rm -rf ~` as part of evaluating `$((10#$(rm -rf ~)))`, before `check` ever
gets to compare a number. This is unrelated to the nesting bug but sits in the
same function this spec is already touching, and the fix is one line.

### Reservation atomicity itself is unaffected

`_reserve_lock`'s mkdir-mutex, its dead-holder and TTL reclaim, its split
signal traps, and its post-scan ownership re-validation (`:254-302`) are
correct and untouched by this spec. Moving the scan outside the lock (below)
does not change who wins a race for a given number: two concurrent `reserve`
callers still serialize on the SAME lock and read the SAME ledger fresh, under
the lock, for the max+1 computation's ledger half. Reservers coordinate through
the ledger, not through scan freshness; a scan taken before the lock can only
be STALE in the direction of under-pruning an already-realized reservation
(harmless: the TTL and the next `reserve` call clean it up) or under-counting a
number some OTHER process just committed a fraction of a second ago (a
pre-existing race this tool has never closed for non-`reserve` writers, and
does not claim to).

## Scope

- `_scan_numbers` (`:89-101`): widen the local scan to see every nested
  `docs/specs` directory, using `git ls-files --cached` for tracked files (fast,
  index-only) plus a targeted, literal-directory check for untracked files
  (no leading-`**` walk), unioned with the existing top-level `ls` line kept for
  symlink parity, all filtered by ONE shared shell predicate also used by the
  PR scan.
- Move both `_scan_numbers` and `_scan_pr_numbers` OUTSIDE `_reserve_lock`'s
  critical section entirely; inside the lock, only a ledger read, a max+1 over
  (pre-lock scans, ledger), and the append remain.
- `_scan_pr_numbers` (`:108-132`): replace the per-head Trees-API call with one
  `gh pr list --json number,headRefOid,files,changedFiles,isCrossRepository`
  call; skip cross-repository (fork) PRs; paginate via
  `gh api .../pulls/<n>/files --paginate` when `changedFiles` exceeds the
  returned `files` array's length.
- Fix `_scan_numbers`'s empty-output exit code so `reserve` on a fresh repo
  succeeds instead of aborting after the claim.
- Digit guard: extract with the existing unbounded `SPEC-[0-9]+`, then DROP any
  token whose digit run exceeds 6 characters (`grep -E '^SPEC-[0-9]{1,6}$'`
  applied to the extracted token, not a bounded extraction regex).
- `check`: validate its argument is all-digits before any arithmetic context
  touches it.
- New/updated tests: `tests/test-spec-next-nested-dirs.sh` (new, T1-T16),
  `tests/test-spec-next-pr-scan.sh` (stub `gh` extended; the T4 no-`gh` PATH
  fence corrected), `tests/test-spec-reserve.sh` and `tests/test-hooks.sh:313-315`
  re-run unchanged as regression.

## Non-goals

- **No renumbering of any existing duplicate spec file**, anywhere, in the
  reporting consumer repo or in this kit's own `lib/*`/`_meta/megagoals/_archive`
  directories. This spec reports the shape; a repo's own maintainers decide.
- **No configurable glob list.** One shared shell predicate
  (`(^|/)docs/specs/[^/]+$`, minus the fixtures/examples excludes) covers every
  convention seen, on both surfaces, by construction.
- **Widening the scan to count `lib/*`, `_meta/megagoals/_archive/*`, `tools/*`,
  and `experiments/*` nested specs is intentional, not a bug to design around.**
  It can only push `next()` to a higher number than strictly necessary
  (fail-open); it can never mint a number that collides with something real.
  Only `tests/fixtures/**` and `examples/**` are excluded outright. No claim in
  this spec says a repo with nested specs sees byte-identical output.
- **No change to `_reservations()`, the reservation ledger file format, the
  mkdir-mutex, or the TTL/reclaim logic.**
- **No change to `next`/`check`/`reserve`'s CLI surface, output format, or exit
  codes**, beyond `check` now refusing a non-numeric argument with usage +
  exit 64 (it already refuses a missing argument the same way) and `reserve`
  now succeeding on an empty repo where it previously aborted.
- **No change to the machine-wide default ledger location** (`ledger.location`
  in `lib/telemetry/kit-log-dir.sh`). Making the ledger per-repo by default
  would be an architecture change with its own tradeoffs (a machine-wide ledger
  is also what lets two DIFFERENT repos that happen to share a folder-name
  collision key stay correctly separated by physical path, per `_git_common_dir`);
  out of scope here. This spec responds to the shared lock's cost by moving
  work OUT of the critical section, not by changing its scope.
- **No ADR.** Nothing here is an irreversible architecture decision: every
  change is a local, reversible fix inside one script (scan placement, scan
  command, a digit guard, an input check). See `## Design`.
- **`gate-ledger.sh validate-round` and `hooks/ship-gate.sh` have the same
  top-level-only blind spot** for locating a spec by `docs/specs/SPEC-*-<rid>.md`.
  Out of scope for this spec; noted here as a follow-up, not fixed.

## Interface

No new script, no new flag. One new debug-only environment variable
(`SPEC_NEXT_LOCK_LOG`, test instrumentation only, see TASK-5) and one internal
predicate shared by both scan sources.

### Shared predicate (both surfaces, one definition)

```
DOCS_SPECS_RE='(^|/)docs/specs/[^/]+$'
EXCLUDE_RE='(^|/)(tests/fixtures|examples)/'
```

Applied identically to raw path lists from BOTH sources: a path matches if it
matches `DOCS_SPECS_RE` and does NOT match `EXCLUDE_RE`. Neither the local
scan's git-glob narrowing nor the PR scan's `--jq` filtering is the authority
on depth or exclusion; both narrow for performance only, and the FINAL word on
whether a path counts is this one shared `grep -E` applied to raw paths on
both sides, so the stub `gh` in `tests/test-spec-next-pr-scan.sh` exercises the
exact same predicate the local-scan tests do, and the two surfaces cannot
silently diverge.

### Local scan (`_scan_numbers`), per worktree `wt`, OUTSIDE the lock

1. Keep, verbatim except the digit guard: `ls "$wt/docs/specs" 2>/dev/null | grep -oE 'SPEC-[0-9]+' || true`
   piped through the shared digit-drop (`## Scope`). Preserves today's exact
   top-level behavior, including a symlinked `docs/specs` (T11).
2. Tracked, nested, fast: `git -C "$wt" ls-files --cached 2>/dev/null` (no
   pathspec restriction needed -- measured fast regardless, `## Grounding`),
   piped through the shared predicate, then the digit-drop.
3. Untracked, nested, targeted (no `**` walk): derive the distinct nested
   `docs/specs` DIRECTORY paths from step 2's raw (pre-predicate) tracked
   output (strip each matched path's basename, sort -u), then ONE batched call
   `git -C "$wt" ls-files --others --exclude-standard -- "<dir1>/*" "<dir2>/*" ...`
   (every discovered directory's literal pathspec in one invocation, not one
   `git` call per directory -- measured far cheaper than either the `**` walk
   or N separate subprocess calls, `## Grounding`), piped through the shared
   predicate and the digit-drop. **Disclosed gap:** a nested `docs/specs`
   directory that has ZERO tracked files yet (every file in it is untracked)
   never appears in step 2's output, so step 3 never derives it as a directory
   to check -- an untracked-only nested `docs/specs` is invisible until its
   first file is committed. The kept top-level `ls` (step 1) does not have this
   gap, because it lists the top-level directory directly regardless of git
   state, matching today's behavior exactly.
4. Union steps 1-3 (already flowing into the same `sort -n | uniq` this
   function ends with today).

### PR scan (`_scan_pr_numbers`), OUTSIDE the lock

One call: `gh pr list --state open --json number,headRefOid,files,changedFiles,isCrossRepository --limit 100`.
For each PR:

- Skip it entirely if `isCrossRepository` is true (a fork PR). This is a
  public repo; any external contributor could otherwise poison `next` by
  opening a fork PR that adds a fake nested spec at a huge number. Fork PRs
  are simply never a source of "numbers to avoid" here (Non-goals: this is a
  disclosed narrowing, not a bug -- Failure modes).
- If `changedFiles` > the returned `files` array's length (gh's own file-list
  response caps at 100 entries; the reviewed repo has PRs with 135, 588, and
  667 changed files, all beyond that cap), fetch the full list instead:
  `gh api "repos/$owner_repo/pulls/$number/files" --paginate --jq '.[].path'`.
  If that call also fails, print one stderr note (matching the existing
  fail-soft convention) and use whatever the capped `files` array already
  gave.
- Emit every RAW path from whichever list was used (no `--jq` regex filtering
  at the `gh` boundary) and apply the SAME shared predicate + digit-drop the
  local scan uses.

Every existing fail-soft branch (`gh` missing, not authenticated, `repo view`/
`pr list` failing) is unchanged.

### `reserve`, restructured: scan before, ledger-only inside the lock

```
reserve():
  _LOCAL_SCAN="$(_scan_numbers)"        # OUTSIDE the lock, once
  _PR_SCAN="$(_scan_pr_numbers)"        # OUTSIDE the lock, once
  attempt loop (unchanged, up to 5):
    _reserve_lock
    ledger="$(_reservations)"           # fresh, INSIDE the lock (cheap: one file read)
    n = max(_LOCAL_SCAN, _PR_SCAN, ledger) + 1      # inlined max+1; reserve no longer
                                                      # calls the `next` function, since
                                                      # next's job (scan + max+1) is exactly
                                                      # what reserve now does manually with
                                                      # its pre-lock scans -- "pass the scan
                                                      # result in" needs no parameter-threading
                                                      # machinery inside _numbers/next at all
    re-validate lock ownership (unchanged)
    append claim line
    _prune_reservations "$_LOCAL_SCAN"  # takes the SAME pre-lock scan text as a parameter,
                                          # never recomputes; a stale value only under-prunes
                                          # (Root cause), which the next `reserve` call's own
                                          # fresh pre-lock scan corrects
    _reserve_unlock
    print n
```

`next` and `check`, called standalone (no lock involved), are unchanged in
contract: each still computes its own scan fresh, once per invocation (`check`
computes `_numbers` once into a variable and greps it twice -- zero-padded and
bare-int forms -- instead of invoking `_numbers` twice, closing the same
double-scan waste `reserve` had, even though `check` never touched a lock).

### `check` argument validation

Before any arithmetic: `case "$n" in ''|*[!0-9]*) echo "usage: check <NNN>" >&2; return 64;; esac`,
placed ahead of today's existing `[ -n "$n" ] || { ...; return 64; }` guard
(which only catches the EMPTY case, not a non-numeric one).

## Picture

```
                         spec-next.sh {next|check|reserve}
                                      |
                          reserve():  |  next()/check(): scan fresh, standalone,
              scan BOTH sources ONCE,  |  unchanged contract, no lock involved
              BEFORE the lock          v
                    |            _numbers()  (next/check path only)
                    v                 |
     _scan_numbers          _scan_pr_numbers
     (per worktree,         (ONE gh pr list call,
      outside any lock)      outside any lock)
          |                       |
   ls top-level (kept)      skip isCrossRepository (fork) PRs
   UNION                    paginate when changedFiles > len(files)
   git ls-files --cached          |
   UNION                          v
   git ls-files --others   raw .files[].path, RAW, unfiltered at the gh boundary
   --exclude-standard             |
   -- <dir1>/* <dir2>/* ...       |
   (dirs derived from cached;      |
    ONE batched call, no **)       |
          |                       |
          v                       v
     RAW paths -----------> ONE SHARED shell predicate
                              (^|/)docs/specs/[^/]+$  minus
                              (^|/)(tests/fixtures|examples)/
                                      |
                                      v
                         extract SPEC-[0-9]+, then DROP any
                         token > 6 digits (grep -E '^SPEC-[0-9]{1,6}$')
                                      |
                                      v
        sort -n | uniq  (unioned with the ledger read fresh under the lock,
                          for reserve; or with _reservations(), for next/check)

INSIDE THE LOCK (reserve only): a ledger read, max+1 over (the two PRE-LOCK
scan results above, the ledger), the append, and _prune_reservations fed the
SAME pre-lock _scan_numbers text (never `_numbers`, never a fresh rescan) --
nothing here re-touches the filesystem or GitHub.
```

## Design

### Diagram

See `## Picture`.

### Why the scan moves outside the lock

The reservation lock is machine-wide by default (Root cause). Any repo's slow
`reserve` blocks every OTHER repo's `reserve` on the same machine, which is a
far bigger cost than one repo's own contention. Moving both scans outside the
lock means the lock is only ever held for a ledger read, an in-memory max+1,
and an append -- all fast regardless of repo size -- so one repo's expensive
scan no longer taxes the shared resource at all. This is safe because
`reserve`-vs-`reserve` collisions are prevented by the ledger read happening
FRESH, under the lock, every time (Root cause: "reservers coordinate through
the ledger"); the scan's only job is to avoid colliding with something already
real, and a pre-lock scan can only be stale in the safe direction (under-count,
never over-count a number that isn't really there).

### Why `git ls-files --cached` plus a targeted directory check, not a `**` walk

Measured this round: `--cached --others --exclude-standard -- ':(glob)**/docs/specs/*'`
took 17.7-33.2s across a 29-worktree repo, because a leading `**` forces
`--others` (untracked discovery) to walk the ENTIRE working tree -- git cannot
prune a subtree early against a pattern that could match anywhere. `--cached`
alone (index-only, no filesystem walk at all) was 0.8-1.1s on the same repo,
regardless of the pathspec's shape, because the index lookup doesn't touch the
filesystem tree the same way. Splitting the untracked check into ONE batched
call over the SPECIFIC, ALREADY-KNOWN nested directories (derived from the fast
cached pass, not discovered by a blind walk) keeps the untracked side targeted
instead of exhaustive. Measured this session, this kit's own single-worktree
repo (proxy; the private multi-worktree repo is out of scope to reach from
here): `--cached` alone, 0.018s; the rejected `--cached --others
--exclude-standard -- '**/docs/specs/*'` shape, 0.216s; ONE batched
`git ls-files --others --exclude-standard -- <dir>/* <dir>/* ...` call over
this repo's 9 discovered nested directories, 0.116s -- about half the cost of
the `**`-walk shape on the SAME repo, because a literal-prefix pathspec lets
git prune early instead of walking the whole tree. `## Grounding` has the full
numbers and the honest scope of what was and wasn't directly measured here.

### Why one batched call, not one `git ls-files` per directory

A naive per-directory loop (one subprocess per nested `docs/specs` dir) pays
process-spawn overhead per directory; on a repo with many nested dirs across
many worktrees this adds up. `git ls-files` accepts multiple pathspecs in one
invocation, so all discovered directories' literal `<dir>/*` patterns are
passed in ONE call per worktree.

### Why `gh pr list --json ...,changedFiles,isCrossRepository`, not the Trees API

One call returns every open PR's changed-file list, `changedFiles` count, and
fork status, verified live this session against this repo (real `files` array
shape). Skipping `isCrossRepository` PRs closes a real poisoning vector this
round surfaced: this is a PUBLIC repo, so a fork PR is not a "sibling wave
member" the way a same-repo branch is -- it is exactly the kind of input an
untrusted party controls, and folding its claimed spec numbers into `next`'s
output would let anyone push `next` arbitrarily high with a throwaway fork PR.
Paginating past `gh`'s 100-file cap via the plain REST endpoint is a single,
well-known fallback (`--paginate` on `gh api`), needed for real: the reviewed
repo has PRs with 135, 588, and 667 changed files, all past the cap, so
skipping this step would silently under-scan exactly the PRs most likely to
also be the ones adding a batch of new specs.

### Why one shared predicate over raw paths, not two "equivalent" filters

Round 2 relied on git's own glob-pathspec depth semantics for the local scan
and a separately-written regex for the PR scan; two independently-maintained
mechanisms for the same rule can drift without either surface's own tests
catching it. This revision emits raw paths from both sources and runs them
through the identical `grep -E` predicate, so `tests/test-spec-next-pr-scan.sh`'s
stub `gh` and the local-scan fixtures exercise the SAME code path for "does
this count," not two.

### Why extract-then-drop, not a bounded extraction regex

A bounded extraction regex (`SPEC-[0-9]{1,6}`) applied directly to the raw
text would still MATCH the first 6 digits of a longer digit run (silently
truncating `SPEC-1234567` into the wrong number `123456`) rather than
rejecting it outright. Extracting with the existing unbounded `SPEC-[0-9]+`
first, then dropping (not truncating) any token whose full digit run exceeds 6
characters via `grep -E '^SPEC-[0-9]{1,6}$'` on the WHOLE extracted token,
rejects the oversized token entirely. Separately, `next`/`reserve` do not
error on an overflow-adjacent max; bash's `$((10#$max + 1))` wraps SILENTLY
(exit 0, a nonsensical large or negative-looking number, not an error) --
verified this session (`$((10#999999999999999999999 + 1))` returns a wrapped
value with rc 0). The digit-drop is the actual guard; there is no arithmetic
error to "catch."

### ADR link(s)

None. See `## Non-goals`: nothing here is an irreversible decision.

### Boundaries & failure modes

See `## Failure modes`.

## Task Breakdown

Fixtures and test bodies first (T1-T16 encode the acceptance contract before
any implementation task claims to satisfy it); TASK-1 is split by concern so
each implementation task's Verify line names a coherent, already-written slice.

### Phase 0: Test harness (split)

- [ ] TASK-1a: `tests/test-spec-next-nested-dirs.sh` (new; `mktemp -d` + `git init`
  fixtures, matching `tests/test-spec-reserve.sh`'s pattern, never placed under
  `tests/fixtures/` itself). Local-scan fixtures and bodies: `mk_repo_nested()`
  (shared fixture for T1, T2, T3, T7a, T7b, T11, T12, T16 -- no oversized token,
  no pre-seeded reservations), a dedicated overflow fixture for T10, a
  symlink-variant fixture for T11. Run against today's UNFIXED script:
  T1/T2/T3/T7b are expected RED (today's code sees no nested dir at all); T7a,
  T11, T12 are expected GREEN already (today's code also never sees a
  fixtures/examples nested dir, and never recurses two levels deep, for the
  SAME reason it misses the real nested dirs -- these are regression guards,
  not fix targets); T10 and T16 are expected RED (today has no digit guard and
  no argument validation at all).
  Verify: `bash tests/test-spec-next-nested-dirs.sh local` runs to completion
  and its per-case output matches this red/green split.
- [ ] TASK-1b: same file, PR-scan bodies: extend `tests/test-spec-next-pr-scan.sh`'s
  stub `gh` to answer `pr list --json number,headRefOid,files,changedFiles,isCrossRepository`
  and `api .../pulls/<n>/files --paginate`; write T5, T6 against it. Expected
  RED on today's unfixed script (today calls a different API shape entirely).
  Fix T4's fenced PATH (needs `git`; no `find` anywhere in this design).
  Verify: `bash tests/test-spec-next-pr-scan.sh` (updated) and
  `bash tests/test-spec-next-nested-dirs.sh pr` both run to completion.
- [ ] TASK-1c: same file, lock/timing/empty-repo bodies: T8 (lock-hold-time
  instrumentation), T9 (its own fresh `mk_repo_nested()` instance, sequenced),
  T13 (its own fresh empty-repo fixture), T14 (many-worktree fixture, reused
  from T8). Expected RED on today's unfixed script for T13 (reproduced live,
  `## Problem`); T8/T9/T14 are new assertions with no meaningful "before" state
  since the lock-outside-scan design does not exist yet.
  Verify: `bash tests/test-spec-next-nested-dirs.sh lock` runs to completion.

### Phase 1: Local scan + empty-repo fix

- [ ] TASK-2: `_scan_numbers` (`:89-101`): implement the 4-step union from
  `## Interface` (kept top-level `ls`, cached nested, batched untracked-nested,
  union), all through the shared predicate + digit-drop. Fix the trailing
  `grep -oE '[0-9]+' | sort -n | uniq` stage so empty output always returns 0
  (wrap the grep with `|| true`, matching every other line's convention).
  Verify: T1, T2, T3, T7a, T7b, T10, T11, T12, T13 go green.

### Phase 2: Lock restructuring

- [ ] TASK-3: `reserve` (`:310`): move `_scan_numbers`/`_scan_pr_numbers` calls
  before `_reserve_lock`; inline the max+1 computation (no longer calling
  `next`); pass the pre-lock local-scan text into `_prune_reservations` as a
  parameter instead of letting it recompute. `check` (`:171`): compute
  `_numbers` once into a variable, grep it twice.
  Verify: T8, T9 go green; T15's `test-spec-reserve.sh` regression stays green.

### Phase 3: PR scan

- [ ] TASK-4: `_scan_pr_numbers` (`:108-132`): implement `## Interface`'s PR
  scan (one `gh pr list` call, skip forks, paginate past the 100-file cap,
  raw paths through the shared predicate).
  Verify: T5, T6 go green.

### Phase 4: Instrumentation + input validation

- [ ] TASK-5: `SPEC_NEXT_LOCK_LOG` (debug-only env var): when set,
  `_reserve_lock` appends a timestamp on acquire and `_reserve_unlock` appends
  one on release, to that path. This is the only way T8 can assert lock-hold
  duration without a flaky wall-clock guess.
  Verify: T8, T14 go green.
- [ ] TASK-6: `check` argument validation (`## Interface`).
  Verify: T16 goes green.

### Phase 5: Test infra parity + docs

- [ ] TASK-7: Full regression: `bash tests/test-meta.sh`, `bash
  tests/test-spec-reserve.sh`, `bash tests/test-spec-next-pr-scan.sh` (updated),
  `bash tests/test-hooks.sh` (`:313-315`), and `bash
  tests/test-spec-next-nested-dirs.sh` (all of T1-T16) all green.
  Verify: T15; all five commands exit 0.
- [ ] TASK-8: Docs. Update the script's header comment (`:5-7`, `:28-29`) to
  describe the widened scan, the lock-outside placement, and the single-call
  PR source; add a `CHANGELOG.md` entry; write
  `docs/verification/spec-next-nested-dirs.md` holding the T1-T16 run
  transcript once TASK-2 through TASK-7 are green.
  Verify: header comment no longer describes the old single-path, in-lock
  scan; `docs/verification/spec-next-nested-dirs.md` exists and quotes the run.

## After state

- [ ] `spec-next.sh next` / `check` / `reserve`, run from a repo with specs
  under any nested `docs/specs/` (this kit's own `lib/*` included), treat those
  numbers as taken.
- [ ] An open PR whose head adds a spec under a nested `docs/specs/` is folded
  into `_scan_pr_numbers`'s result via one `gh pr list` call; a fork PR never
  is.
- [ ] `reserve` holds the machine-wide lock only for a ledger read, a max+1,
  and an append -- both scans run before the lock, once each.
- [ ] `reserve` on a repo with zero SPEC numbers anywhere succeeds, printing
  `001`, instead of aborting after orphaning a claim.
- [ ] `check` on a non-numeric argument refuses with usage + exit 64, never
  reaching an arithmetic context.
- [ ] A repo whose only nested specs are under `tests/fixtures/` or `examples/`
  sees no material change. A repo with real nested specs elsewhere (this kit
  included) sees `next()` return a higher number than before; disclosed, not a
  claimed no-op.

## Acceptance Criteria (global)

| # | Case | Criterion | Command | Pass |
|---|---|---|---|---|
| AC1 | T1 | Nested-only local spec counts as taken | `... T1` | `check` on a nested-only number reports TAKEN |
| AC2 | T2 | `next`/`reserve` skip past a nested-only number | `... T2` | both print a number strictly greater than the fixture's nested max |
| AC3 | T3 | Nested-only duplicate (no top-level entry at all) is caught | `... T3` | `check` reports TAKEN on both nested copies |
| AC4 | T4 | Negative control: unpatched script reproduces the reported bug | `... T4` | pinned to `d2ec4c40` (or a `$TMPDIR` copy of it), the unfixed body reports the nested-only number free / mints a colliding number; the patched tree does not |
| AC5 | T5 | PR-scan sees a nested spec via one call | `... T5` | a stub `gh pr list` response listing a nested `docs/specs/SPEC-NNN-*.md` path folds into `next`'s result |
| AC6 | T6 | PR-scan: fork skip + pagination fallback | `... T6` | a fork PR (`isCrossRepository: true`) contributes nothing even if its `files` lists a spec; a PR with `changedFiles` > `len(files)` triggers the paginated fetch and its full list folds in |
| AC7 | T7 | Namespace excludes hold both ways | `... T7a` and `... T7b` | `tests/fixtures/**`/`examples/**` NOT counted (T7a); `lib/x/docs/specs/` and `_meta/megagoals/_archive/x/docs/specs/` ARE counted (T7b) |
| AC8 | T8 | Lock is held only for the cheap part | `... T8` | via `SPEC_NEXT_LOCK_LOG`, the acquire-to-release delta is short and does not scale with the many-worktree fixture's scan time |
| AC9 | T9 | A stale pre-lock scan only under-prunes | `... T9` | a reservation whose number becomes realized AFTER this call's pre-lock scan is NOT pruned this round, but IS pruned on the next `reserve` call, whose fresh pre-lock scan sees it |
| AC10 | T10 | Oversized number token is dropped, not truncated or wrapped | `... T10` | a 20+-digit token is excluded entirely from every consumer; no silently-truncated or wrapped value ever appears in output |
| AC11 | T11 | Symlinked top-level `docs/specs` still works | `... T11` | unchanged from today |
| AC12 | T12 | Basename-only, one level deep, on both surfaces | `... T12` | a 2-levels-deep path is NOT counted by either surface |
| AC13 | T13 | `reserve` on an empty repo succeeds | `... T13` | prints `001`, exit 0, exactly one ledger line |
| AC14 | T14 | Many-worktree fixture completes in reasonable wall-clock time, and the lock-held slice (T8's log) stays small regardless | `... T14` | documented as an order-of-magnitude check, not a strict cross-machine assertion |
| AC15 | T15 | No regression | `test-meta.sh && test-spec-reserve.sh && test-spec-next-pr-scan.sh && test-hooks.sh` | all exit 0 |
| AC16 | T16 | `check` rejects a non-numeric / injection-shaped argument | `... T16` | `check '$(id)'` (and plain garbage) exits 64 with usage, no command ever runs |

## Verification

```bash
bash tests/test-spec-next-nested-dirs.sh
bash tests/test-spec-reserve.sh
bash tests/test-spec-next-pr-scan.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
```

## Test plan

Date: 2026-09-30

Shared fixture, `mk_repo_nested()` (its own fresh repo instance per test case
that uses it; no shared mutable state between cases), placeholder numbers only:

```
docs/specs/SPEC-100-top.md
docs/specs/SPEC-141-a.md
tools/toolA/docs/specs/SPEC-141-b.md          # duplicate of 141, ALSO visible at top level
tools/toolA/docs/specs/SPEC-142-x.md          # nested-only, no top-level entry
tools/toolB/docs/specs/SPEC-143-z1.md         # nested-only duplicate, part A
tools/toolA/docs/specs/SPEC-143-z2.md         # nested-only duplicate, part B
tools/toolB/docs/specs/SPEC-145-y.md          # nested-only
experiments/foo-bar/docs/specs/SPEC-150-x.md  # nested-only, experiments/ tier
lib/x/docs/specs/SPEC-160-lib.md              # counted-nested-tier proof
_meta/megagoals/_archive/y/docs/specs/SPEC-161-arc.md  # counted-nested-tier proof
tests/fixtures/z/docs/specs/SPEC-970-decoy.md # must NOT be counted
examples/hello/docs/specs/SPEC-971-decoy.md   # must NOT be counted
docs/specs/implementation-notes/SPEC-980-deep.md  # two levels deep, must NOT be counted
docs/specs/data/SPEC-981-deep.tsv             # two levels deep, must NOT be counted
```

Dedicated fixtures (own repo instances, not part of the shared list above):

- T10: one file, `docs/specs/SPEC-99999999999999999999-huge.md`, alone.
- T9: `mk_repo_nested()` fresh, plus a controlled two-step sequence (see below).
- T13: a bare `git init` repo with zero SPEC numbers anywhere, no fixture files.
- T11: `mk_repo_nested()` fresh, with its top-level `docs/specs` replaced by a
  symlink to a real `real-specs/` directory holding `SPEC-190-x.md`.
- T8/T14: `mk_repo_nested()`'s directory shape replicated across 5+ worktrees.

| Case | Kind | Covers | Proof |
|---|---|---|---|
| T1: `check 142` against the fixture, patched script | positive | AC1 | exit 1, "TAKEN" |
| T2: `next` against the fixture, patched script | positive | AC2 | prints > 161 (the counted nested max) |
| T3: `check 143` against the fixture | positive | AC3 | exit 1, "TAKEN"; `next` still returns > 161 |
| T4: `check 142`/`145`, script pinned to `d2ec4c40` | negative control | AC4 | exit 0, "free"; `next` mints `142` exactly (top-level max is 141, +1), colliding with `tools/toolA/docs/specs/SPEC-142-x.md` |
| T5: stub `gh pr list` with one PR's `files` listing `tools/toolC/docs/specs/SPEC-170-y.md`, `isCrossRepository: false` | positive | AC5 | `next` prints > 170 |
| T6a: same, but `isCrossRepository: true` | negative control (fork skip) | AC6 | contributes nothing; `next` unaffected |
| T6b: a PR with `changedFiles: 300`, `files` array capped at 100 (none matching), stub `gh api .../files --paginate` returns a matching nested path beyond the cap | positive (pagination fallback) | AC6 | the paginated path folds in |
| T6c: the paginated fetch itself fails (stub exits nonzero) | negative control (fail-soft) | AC6 | one stderr note, no abort, other PRs still processed |
| T7a: `check 970` (tests/fixtures) and `check 971` (examples) | negative control | AC7 | both exit 0, "free" |
| T7b: `check 160` (lib/x) and `check 161` (_archive) | positive | AC7 | both exit 1, "TAKEN" |
| T8: `SPEC_NEXT_LOCK_LOG` around one `reserve` call against the 5+-worktree fixture | positive, instrumented | AC8 | the acquire->release delta in the log is on the order of milliseconds, not scaling with the (multi-second) total `reserve` wall-clock time |
| T9: reservation for 142 exists; fixture's real `SPEC-142` file (from a SECOND, independent `mk_repo_nested()`-derived commit) lands after this call's pre-lock scan is taken (sequenced via a controlled two-step harness call); a SECOND `reserve` call follows | positive | AC9 | first call's `_prune_reservations` does NOT drop the 142 reservation (its pre-lock scan predates the file); the second call's fresh pre-lock scan sees the file and its `_prune_reservations` DOES drop it |
| T10: `check`/`next` against the dedicated overflow fixture | negative control | AC10 | the 20+-digit token is excluded entirely; no wrapped or truncated value appears anywhere in output |
| T11: `check 190` against the symlink fixture | positive (regression-preserving) | AC11 | exit 1, "TAKEN" |
| T12: `check 980`/`981` against the fixture; a stubbed PR whose `files` includes a matching 2-level-deep path | negative control | AC12 | all exit 0 / contribute nothing, on both surfaces |
| T13: `reserve` against the dedicated empty-repo fixture | positive (fixes the reproduced live bug) | AC13 | prints `001`, exit 0, exactly one ledger line; a second `reserve` call prints `002` |
| T14: `reserve` against the 5+-worktree fixture, total wall-clock time, cross-checked against T8's lock-log | positive | AC14 | completes in low single-digit seconds; T8's lock-held slice stays a small fraction of that total |
| T15: `test-meta.sh`, `test-spec-reserve.sh`, `test-spec-next-pr-scan.sh` (updated), `test-hooks.sh:313-315` | regression | AC15 | all green |
| T16: `check '$(id)'`, `check 'abc'`, `check ''` | negative control (injection + validation) | AC16 | all exit 64 with usage; no side effect from the injected command (verified by absence of its effect, e.g. a sentinel file the injected command would have created) |

Dry trace for the key negative control (T4/AC4): today's `_scan_numbers` runs
`ls "$wt/docs/specs"` (`:97`), which on the fixture returns only `SPEC-100` and
`SPEC-141` (the two files physically inside `docs/specs/`); every nested number
(142, 143, 145, 150, 160, 161) never appears. `next` on the unfixed script
therefore computes max=141, prints `142` -- which IS
`tools/toolA/docs/specs/SPEC-142-x.md`'s own number, an exact, reproduced
collision, not a hypothetical one. After TASK-2, the same fixture's widened
scan sees all of {100, 141, 142, 143, 145, 150, 160, 161} (970/971/980/981
excluded by the shared predicate), and `next` returns `162`.

## Edge Cases

1. A repo whose only nested `docs/specs` entries are under `tests/fixtures/` or
   `examples/`: no material change (T7a).
2. A brand-new nested `docs/specs` dir with only untracked files (no commit
   yet): invisible until the first commit (disclosed gap, `## Interface` step
   3); the TOP-LEVEL `docs/specs` does not have this gap (step 1 uses `ls`,
   not git state).
3. A PR whose `files` count is capped AND whose paginated fallback also fails
   (rate limit, network): falls back to the capped list plus one stderr note,
   same best-effort risk class the header comment already accepts for any
   bootstrap-call failure.
4. A fork PR that legitimately wants to reserve a number: out of scope by
   design (`## Design`, poisoning-vector rationale); such a contributor's
   number gets reconciled the normal way once their PR is based on a
   same-repo branch or merges.
5. `gh` absent from PATH, or unauthenticated: unchanged, local-only fallback
   plus one stderr note.
6. A worktree whose `.git` is a plain file (the normal worktree shape): `git
   -C "$wt" ls-files` handles this identically to a primary checkout.
7. A nested `docs/specs` reached only through a symlinked INTERMEDIATE
   directory (not the top-level `docs/specs` itself): out of scope, matching
   git's own general symlink-walk limits; no repo surveyed uses this.
8. Two concurrent `reserve` calls on the SAME repo, one with a slow pre-lock
   scan (many worktrees) and one fast: the fast one may acquire the lock
   first even if it started second, since neither is holding the lock during
   its scan; both still get distinct numbers because the ledger read under
   the lock is always fresh at the moment each one actually holds it.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| The reservation lock is machine-wide; a slow scan inside it blocks every repo's `reserve` | T8/T14; the 17.7-33.2s measurement in `## Grounding` | scan moved entirely outside the lock (`## Design`) |
| `reserve` aborts on an empty repo after appending its ledger claim, orphaning it on every retry | T13; reproduced live this session | `_scan_numbers`'s trailing grep wrapped with `\|\| true`, matching the file's existing convention |
| `check` evaluates an unvalidated argument in an arithmetic context, allowing command-substitution injection | T16 | all-digits validation before any `$((...))` touches `$n` |
| A garbage `SPEC-`-prefixed token with an unbounded digit run either gets silently TRUNCATED (a bounded extraction regex) or WRAPS bash arithmetic silently (no digit guard at all, exit 0, wrong huge/negative-looking value) | T10 | extract unbounded, then drop (not truncate) any token over 6 digits |
| A fork PR poisons `next`'s output on this public repo by claiming a huge fake nested spec number | T6a | `isCrossRepository` PRs are skipped outright |
| `gh`'s own PR-files response caps at 100, silently under-scanning exactly the PRs most likely to add many specs at once | T6b/T6c | paginate via `gh api .../pulls/<n>/files --paginate` when `changedFiles` exceeds the capped list; fail soft with one stderr note if that also fails |
| A repo's fixture/example content pollutes the global numbering | T7a | explicit exclude in the ONE shared predicate; every other nested tier is intentionally counted (fail-open) |
| A scan stage fails under `set -euo pipefail` after the ledger claim is appended | now structurally reduced: `_prune_reservations` no longer calls `_scan_numbers` itself (it takes the pre-lock text as a parameter), so a scan failure, if any, would already have surfaced BEFORE the lock was even acquired, never after the claim is written | fail-soft wrapping on every new pipeline stage regardless (belt-and-suspenders) |
| A nested `docs/specs` reached only through a symlinked intermediate directory | none (out of scope) | Edge case 7 |
| An untracked-only nested `docs/specs` (zero commits yet) is invisible | disclosed, not detected by any test beyond documenting the gap | Edge case 2; resolves itself on first commit |
| `gate-ledger.sh validate-round` / `hooks/ship-gate.sh` locate a spec by a top-level-only path | unaffected by this spec | Non-goals follow-up |

## Migration notes (existing adopted repos)

- A repo whose nested specs are ONLY under `tests/fixtures/` or `examples/`
  sees no change.
- A repo with real nested specs anywhere else will see `next()` return a
  higher number after this fix lands, because numbers that were silently
  invisible before now count. One-time, disclosed jump, not a bug.
- The PR scan now sees only files an open PR actually CHANGED, not the head
  branch's whole tree (the rejected Trees-API design would have seen every
  file at that ref, whether the PR touched it or not). This is deliberate,
  not a narrowing to work around: a spec that already exists on the head
  branch but is untouched by the PR's own diff is already visible via the
  LOCAL scan of the branch it will merge into once merged; the PR scan's job
  is only to catch a NEW spec the PR itself is proposing before it lands.
- Both the local and PR excludes (`tests/fixtures/`, `examples/`) are
  root-anchored (matched via `(^|/)`, meaning the path SEGMENT, not merely a
  substring) and fail OPEN: if the exclude match ever fails to apply for some
  reason, the affected path is counted (safe, over-counting direction), never
  silently dropped (which would risk a collision).
- A fork PR's own proposed spec number is never counted; such a contributor's
  number reconciles normally once integrated onto a same-repo branch.
- `reserve` holds the machine-wide lock for materially less time than before;
  no caller-visible contract change beyond the empty-repo fix and `check`'s
  new argument validation.

## Out of Scope

- Renumbering or merging any existing duplicate spec file, anywhere.
- A configurable glob/pattern list; one shared predicate covers every
  convention seen.
- Any change to `_reservations()`, the mkdir-mutex, the TTL/reclaim logic, the
  reservation ledger file format, or the default machine-wide ledger location.
- `gate-ledger.sh validate-round` / `hooks/ship-gate.sh`'s own top-level-only
  spec lookup (Non-goals follow-up).
- The reporting consumer repo itself: this spec fixes the kit's own
  `spec-next.sh`; it does not touch, open a PR against, or renumber anything
  in that repo.
- A fork PR's own reservation needs (Edge case 4).

## Touches

Single files: `lib/spec/spec-next.sh`, `tests/test-spec-next-nested-dirs.sh`
(new), `tests/test-spec-next-pr-scan.sh`, `CHANGELOG.md`,
`docs/verification/spec-next-nested-dirs.md` (new).

No shared-file conflict expected with any in-flight sibling spec (checked: no
other `docs/specs/SPEC-*.md` in this repo currently lists `lib/spec/spec-next.sh`
under its own `## Touches`).

## Decision Log

- DEC-1: move both scans entirely outside `_reserve_lock`; only a ledger read,
  a max+1, and the append happen under the lock (lead decision, round 2:
  the lock is machine-wide, so minimizing hold time matters more than scan
  freshness; a stale pre-lock scan can only under-prune, which self-corrects
  on the next call).
- DEC-2: local scan = `git ls-files --cached` (fast, unrestricted pathspec)
  plus ONE batched `git ls-files --others --exclude-standard` call over
  literal directories derived from the cached pass, never a leading-`**`
  walk (lead decision, round 2: `--others` with `**` cannot prune and was
  measured at 17.7-33.2s across 29 worktrees; `--cached` alone was 0.8-1.1s).
- DEC-3: digit guard is extract-unbounded-then-drop-over-6-digits, not a
  bounded extraction regex (lead decision, round 2: a bounded regex would
  truncate rather than reject; bash arithmetic overflow is a silent wrap,
  never an error, so there is nothing for a bounded regex to "catch" at the
  arithmetic step).
- DEC-4: fix `_scan_numbers`'s empty-output exit code so `reserve` succeeds on
  a repo with zero SPEC numbers, closing a live bug reproduced this session
  (lead decision, round 2).
- DEC-5: PR scan = one `gh pr list --json ...,changedFiles,isCrossRepository`
  call; skip fork PRs outright; paginate past the 100-file cap via `gh api
  .../pulls/<n>/files --paginate` (lead decision, round 2: this is a public
  repo, so a fork PR is an untrusted input, not a sibling wave member; the
  reviewed repo has real PRs past the 100-file cap).
- DEC-6: one shared shell predicate over raw paths on both surfaces, not two
  independently-written filters (lead decision, round 2: prevents the two
  surfaces from silently drifting apart).
- DEC-7: `check` validates its argument is all-digits before any arithmetic
  context, closing a real command-substitution-injection path found while
  auditing the function this spec was already touching.
- DEC-8: `git ls-files --cached`, not `find`, remains the base for the local
  scan (carried over from round 1: sidesteps argv-injection, deep-symlink, and
  sibling-worktree-descent concerns by construction).
- DEC-9: exclude only `tests/fixtures/**` and `examples/**`; every other
  nested tier (including this kit's own `lib/*` and `_meta/megagoals/_archive/*`)
  is intentionally counted, fail-open (carried over from round 1).
- DEC-10: no ADR; nothing here is an irreversible architecture decision.

## Grounding

- Root-cause line: `lib/spec/spec-next.sh:97`, confirmed by direct read.
- Self-referential duplicate evidence (this kit's own repo, this session):
  `git ls-files -- ':(glob)**/docs/specs/*' | grep -v '^docs/specs/'` returns
  311 nested matches across `lib/{sync,stats,skill-curator,cosmetic,
  plugin-check}`, `examples/hello-spec`, and
  `_meta/megagoals/_archive/token-optim-v2`; `ls docs/specs/SPEC-126-*.md
  docs/specs/SPEC-134-*.md` shows unrelated top-level documents sharing those
  numbers with the nested copies.
- Machine-wide lock evidence: `lib/telemetry/kit-log-dir.sh:56`, `shared|"")
  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs"` -- the
  default resolves to one path under the user's home directory, shared by
  every repo, not scoped per-repo.
- Empty-repo abort, reproduced this session with `bash -x`: `reserve` against
  a fresh `git init` repo with zero SPEC numbers exits 1 with empty stdout;
  the trace shows execution stopping immediately after `_prune_reservations`'s
  `realized="$(_scan_numbers)"` line, with the ledger already holding
  `num=001` from that same call; a second call reproduces identically,
  minting and orphaning `002`.
- Bash arithmetic overflow, verified this session: `bash -c 'v=999999999999999999999; printf "%03d\n" "$((10#$v + 1))"; echo "rc=$?"'`
  prints a wrapped, nonsensical value with `rc=0` -- no error, confirming the
  digit guard (not an arithmetic try/catch) is the only real defense.
- `gh pr list --json ...,files` shape, verified live this session (real
  output, one open PR against this repo): a `files` array with `path`/
  `additions`/`deletions`/`changeType` per entry, `headRefOid`, and `number`
  fields, confirming the call shape DEC-5 relies on.
- Local-scan timing, measured this session (this kit's own single-worktree
  repo, 9 discovered nested `docs/specs` directories -- a proxy; the private
  multi-worktree repo the round's 17.7-33.2s / 0.8-1.1s figures came from is
  out of scope to reach from this worktree): `git ls-files --cached --
  ':(glob)**/docs/specs/*'` = 0.018s; `git ls-files --cached --others
  --exclude-standard -- ':(glob)**/docs/specs/*'` (the rejected shape) =
  0.216s; ONE batched `git ls-files --others --exclude-standard --
  <dir1>/* ... <dir9>/*` call over the 9 discovered directories = 0.116s,
  roughly half the rejected shape's cost on this repo, corroborating the
  SHAPE of the fix (a literal-prefix batched call beats a leading-`**` walk)
  without claiming to reproduce the other repo's exact multi-worktree number.
- Existing regression anchors: `tests/test-hooks.sh:313-315` runs `spec-next.sh
  check`/`next` against this kit's own real repo today; `tests/test-spec-next-pr-scan.sh:34-52`
  is today's stub `gh`, answering only `contents/docs/specs`, to be extended
  (TASK-1b) for the new `pr list --json ...,changedFiles,isCrossRepository`
  and `pulls/<n>/files --paginate` shapes.

## Open questions

(none; every unknown from rounds 1 and 2 was settled by direct reading of
`lib/spec/spec-next.sh`, `lib/telemetry/kit-log-dir.sh`, or a live command run
this session, cited above)
