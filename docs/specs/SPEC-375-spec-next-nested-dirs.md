# Spec: spec-next scans nested docs/specs, not just the top level
Generated: 2026-09-30
Status: DRAFT
Lane: full
Depth: standard (root cause is grounded by reading `lib/spec/spec-next.sh` directly and by live experiments run this session -- git pathspec glob semantics, git's own worktree/gitignore boundary, and a real `gh pr list --json files` call -- cited by file:line and by command output below; no outside unknown and no failure mode the author expects to miss alone)
References: `lib/spec/spec-next.sh` functions `_scan_numbers` (:89), `_scan_pr_numbers` (:108), `_numbers` (:160), `next` (:164), `check` (:171), `_prune_reservations` (:195), `_reserve_lock` (:254), `reserve` (:310), `_git_common_dir` (:48); `tests/test-spec-reserve.sh` and `tests/test-spec-next-pr-scan.sh` (the fixture-repo pattern this spec's tests extend); `tests/test-hooks.sh:313-315` (the existing real-repo regression check)

## Amendments

- AMEND-1: 2026-09-30 | round 1 (7 parallel reviewers) came back NEEDS REVISION, 6 CRITICALs | this revision (a) strips every private consumer-repo filename/slug/tool-name from the Problem evidence, keeping only bare SPEC numbers and a generic description; (b) redesigns the local scan around `git ls-files` instead of `find` (measured ~35x faster on a many-worktree repo, and it sidesteps symlink/argv-injection concerns by construction); (c) fixes the double-scan-under-the-lock cost in `reserve`/`check`; (d) replaces the PR-scan's per-head Trees-API call with one `gh pr list --json number,headRefOid,files` call; (e) fixes the false non-goal that claimed `_prune_reservations` was untouched; (f) adds digit-count capping, fail-soft wrapping, and a consistent T1-T15 test-case numbering used identically across Task Breakdown, Acceptance Criteria, and Test plan | why: correctness and performance findings, all reproduced directly against this repo before writing this revision | at review | re-validated: pending round 2

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

## Root cause

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
so both inherit the blind spot.

The identical shape sits in `_scan_pr_numbers` (`:108-133`), used by `_numbers`
for open PRs, at `:130`:

```
130    gh api "repos/$owner_repo/contents/docs/specs?ref=$ref" --jq '.[].name' 2>/dev/null \
131      | grep -oE 'SPEC-[0-9]+' || true
```

The GitHub Contents API call is scoped to exactly one path, `docs/specs`, and is
non-recursive by nature of that endpoint. An open PR that adds a spec under
`tools/<x>/docs/specs/` is invisible to this scan too.

**A second, independent defect found this round: the scan runs TWICE inside the
reservation lock.** `reserve` (`:310-338`) calls `next` (`:320`-ish, inside the
`while` loop), which calls `_numbers` -> `_scan_numbers` once; then, still inside
the same locked critical section, `_prune_reservations` (`:195`, called at the
tail of `reserve`) calls `_scan_numbers` again at its own `realized="$(_scan_numbers)"`
line to compute which reservations are now realized. `check` similarly calls
`_numbers` twice per invocation (`:171-183`, once for the zero-padded form and
once for the bare-int form). Measured on a 28-worktree consumer repo this
round: the (rejected) find-based widening of `_scan_numbers` took ~6s warm,
~28.7s cold, ~39.5s summed across all 28 worktrees (each worktree walk finding
the same ~79 nested `docs/specs` dirs independently). `_reserve_lock`
(`:254-302`) gives up after ~600 tries of 10-90ms backoff, about 30s
(`:296`-ish). A scan this slow, run twice per `reserve` and up to 5 times across
`reserve`'s own retry loop (`:310`), can exceed that budget, and a failed
`reserve` falls back to the racy `next` path in `lib/queue/orchestrate.sh`
(`:1334-1340`), **reopening the exact collision this tool exists to prevent.**
This is why the fix below is not just "widen the scan" but "widen it cheaply and
call it once."

**Reservation atomicity itself is unaffected and does not need a fix.**
`_reserve_lock` (`:254-302`) claims the mkdir-mutex keyed on the repository's
physical git-common-dir (`_git_common_dir`, `:48-55`), with a dead-holder
reclaim, a TTL-based stale-lock reclaim, split signal traps that exit rather
than resume unprotected, and a re-validation of lock ownership after computing
`next()` before appending the claim. This machinery guards WHO gets to claim a
number and HOW an in-flight claim is broadcast to sibling callers; the coverage
gap above is about WHICH numbers count as "seen," and the latency finding above
is about how EXPENSIVE computing that answer is while the lock is held, not
about the locking protocol's correctness. This spec does not touch
`_reserve_lock`, `_reserve_unlock`, the lock's owner-token/TTL logic, or the
reservation ledger's line format.

**Correction to the original draft's non-goal:** the original draft claimed "no
change to `_prune_reservations()`". That was false: `_prune_reservations`
(`:195`) calls `_scan_numbers` internally to compute which reservations are now
realized, so widening `_scan_numbers` changes what `_prune_reservations` treats
as realized too (a nested spec's reservation now gets pruned once the real
nested file lands, which it did not before). This revision fixes that claim and
adds a test for it (T9 below).

## Scope

- `_scan_numbers` (`lib/spec/spec-next.sh:89-101`): widen the per-worktree local
  scan to see every nested `docs/specs` directory, using `git ls-files` (not
  `find`) for both tracked and untracked-but-not-ignored files, unioned with the
  existing top-level `ls` line kept verbatim for symlink parity.
- `_scan_pr_numbers` (`lib/spec/spec-next.sh:108-132`): replace the per-head
  Trees-API call with one `gh pr list --json number,headRefOid,files` call,
  filtered to the same one-level `docs/specs` predicate the local scan uses.
- Scan the local surface exactly ONCE per `reserve`/`check` invocation: thread
  the one `_scan_numbers` result into both the number computation and
  `_prune_reservations`'s realized-check, instead of recomputing it.
- Bound the digit count of every extracted `SPEC-NNN` token to guard the
  `10#$max` arithmetic against a garbage token with an unbounded digit run.
- Fail-soft wrap every new pipeline stage so a scan error under `set -euo
  pipefail` degrades to an empty contribution instead of aborting `reserve`
  after the ledger claim line is already appended.
- New/updated tests: `tests/test-spec-next-nested-dirs.sh` (new, T1-T14),
  `tests/test-spec-next-pr-scan.sh` (stub `gh` extended to answer `pr list
  --json ...,files`; the T4 no-`gh` PATH fence corrected), `tests/test-spec-reserve.sh`
  and `tests/test-hooks.sh:313-315` re-run unchanged as regression (T15).

## Non-goals

- **No renumbering of any existing duplicate spec file**, in the reporting
  consumer repo or in this kit's own `lib/stats`/`lib/sync`/`lib/skill-curator`/
  `lib/cosmetic`/`lib/plugin-check`/`_meta/megagoals/_archive` directories. This
  spec reports the shape; a repo's own maintainers decide whether and how to
  renumber.
- **No configurable glob list.** A fixed `git ls-files` pathspec matching any
  `.../docs/specs/<file>` (one level, via git's own glob magic, verified below)
  covers every convention seen; a repo whose spec directories are named
  something other than `docs/specs` anywhere in the path is out of scope.
- **Widening the scan to count `lib/*`, `_meta/megagoals/_archive/*`, `tools/*`,
  and `experiments/*` nested specs is intentional, not a bug to design around.**
  It can only push `next()` to a higher number than strictly necessary
  (fail-open); it can never mint a number that collides with something real.
  The only two namespaces excluded outright are `tests/fixtures/**` and
  `examples/**` (Scope; neither ever holds a real project spec). No claim in
  this spec says a repo with nested specs sees byte-identical output; that
  claim was false in the original draft and is retracted (see `## After
  state`).
- **No change to `_reservations()`, the reservation ledger file format, or the
  mkdir-mutex/TTL/reclaim logic** (Root cause: this machinery is correct and
  untouched).
- **No change to `next`/`check`/`reserve`'s CLI surface, output format, or exit
  codes.**
- **`gate-ledger.sh validate-round` and `hooks/ship-gate.sh` have the same
  top-level-only blind spot** for locating a spec by `docs/specs/SPEC-*-<rid>.md`,
  meaning a co-located spec (nested under `tools/*/docs/specs/`) cannot use
  `validate-round` today. Out of scope for this spec; noted here as a
  follow-up, not fixed.

## Interface

Both fixes are internal to `lib/spec/spec-next.sh`; no new script, no new flag,
no new environment variable beyond one debug-only knob for test instrumentation
(below). The change is confined to what `_scan_numbers` and `_scan_pr_numbers`
walk and to how many times the local scan runs per invocation, not to any
function's output shape (`_numbers`'s `sort -n | uniq` union is unchanged).

**Local scan** (`_scan_numbers`), per worktree `wt`:

1. Keep, verbatim: `ls "$wt/docs/specs" 2>/dev/null | grep -oE 'SPEC-[0-9]{1,6}' || true`
   (only the digit cap changes). This preserves today's exact behavior for the
   common case, including that `ls` follows a symlinked top-level `docs/specs`
   directory (T11).
2. Add: `git -C "$wt" ls-files --cached --others --exclude-standard -- \
   ':(glob)**/docs/specs/*' ':(exclude,glob)tests/fixtures/**' \
   ':(exclude,glob)examples/**' 2>/dev/null | grep -oE 'SPEC-[0-9]{1,6}' || true`.
   `--cached --others --exclude-standard` in one call returns tracked AND
   untracked-but-not-gitignored files (matching today's "an uncommitted sibling
   spec stub reads as taken" contract, header comment `:22-24`), without a
   second `find`-based pass. Git's own worktree-boundary handling means this
   call, run from `$wt`, never descends into a nested SIBLING worktree
   (verified below: a worktree directory is gitignored and/or recognized as a
   separate git root by git's own file-walk, so no explicit sibling-worktree
   prune is needed).
3. Union both (they already flow into the same `{ ...; } | grep -oE '[0-9]+' |
   sort -n | uniq` this function ends with today).

**Local scan, called once per invocation.** `reserve` computes
`_LOCAL_SCAN="$(_scan_numbers)"` exactly once, immediately after acquiring the
lock, and passes it to both the number computation and to a
`_prune_reservations` that now takes the precomputed text as an argument
instead of recalling `_scan_numbers`. `check` computes `_numbers` once into a
local variable and greps it twice (zero-padded and bare-int forms) instead of
invoking `_numbers` twice. `next`, called standalone (no lock held), keeps
calling `_scan_numbers` directly; the "once per invocation" contract applies
inside `reserve`'s locked critical section, where the cost is multiplied by
lock contention.

**PR scan** (`_scan_pr_numbers`): one call, `gh pr list --state open --json
number,headRefOid,files --limit 100`. This single call returns, per open PR
(including fork PRs, which the Trees/Contents API 404s on), the list of changed
file paths -- no per-head follow-up call, no 3MB/2s-per-head tree fetch. Filter
each PR's `.files[].path` (via `--jq`) to the regex `(^|/)docs/specs/[^/]+$`,
excluding any path already excluded locally (`tests/fixtures/`, `examples/`),
and extract `SPEC-[0-9]{1,6}` from the basename. Every existing fail-soft branch
(`gh` missing, not authenticated, `repo view`/`pr list` failing) is unchanged;
a PR whose `files` array holds nothing matching the predicate contributes
nothing, same as a 404 does today (not every PR touches specs).

## Picture

```
                         spec-next.sh {next|check|reserve}
                                      |
                                      v
                                 _numbers()  <-- unioned ONCE per invocation
                    /                |                  \
                   v                 v                   v
          _scan_numbers      _scan_pr_numbers        _reservations
          (per worktree)     (one gh pr list call)   (ledger; unaffected)
                   |                 |
     TODAY:        |                 |
     ls "$wt/docs/specs"   gh api contents/docs/specs?ref=<head>
     (ONE path, no descent) (ONE path, no descent, one call PER head)
                   |                 |
          BLIND to lib/*/, tools/*/, experiments/*/docs/specs/
                   |                 |
     FIXED:        v                 v
     ls "$wt/docs/specs"      gh pr list --json number,headRefOid,files
       (kept, symlink parity)   (ONE call, every open head, incl. forks)
       UNION
     git -C "$wt" ls-files       | .files[].path
       --cached --others         | filter (^|/)docs/specs/[^/]+$
       --exclude-standard         | exclude tests/fixtures/**, examples/**
       -- **/docs/specs/*
          :(exclude) tests/fixtures/** examples/**
                   \                 /
                    v               v
              every SPEC-NNN under any docs/specs, one level deep, anywhere
              (git's own worktree/gitignore boundary keeps this from ever
               walking into a sibling worktree -- verified, not assumed)
                    |
                    v
        sort -n | uniq  (unchanged; dedupes across all three sources)
                    |
                    v
   reserve(): compute the union ABOVE exactly ONCE under the lock,
   thread it into next()'s max+1 AND into _prune_reservations'
   realized-check -- no second live rescan while the lock is held
```

## Design

### Diagram

See `## Picture`.

### Why `git ls-files`, not `find` (rejected)

The original draft proposed a recursive `find` per worktree. Measured this
round on a 28-worktree consumer repo: 6s warm / 28.7s cold / 39.5s summed
across all worktrees, each walk independently finding the same ~79 nested
`docs/specs` directories. `git ls-files --cached --others --exclude-standard`
against the same repo, all 28 worktrees, took 1.1s and returned the same 131
numbers. `find` also raises three problems `ls-files` sidesteps by
construction: (a) `find`'s `-path`/`-prune` args need a bash array (never
`eval`) to stay injection-safe against a path holding glob metacharacters; (b)
`find -L` (the default on some systems) follows symlinked subdirectories,
which is exactly the ambiguity the "keep or match symlinks" finding raised,
whereas `git ls-files` follows a top-level symlink only through the KEPT
explicit `ls` line and never walks into a deeper symlinked directory, matching
git's own general (and already-documented) symlink handling; (c) `find`
physically walks the filesystem and does not know about git's worktree
boundaries, so pruning sibling worktrees would need to be built by hand from
`git worktree list` output. `git ls-files` needs none of this: verified this
session, `git ls-files -- '.claude/worktrees/**'` from the main checkout
returns zero files, because `.claude/worktrees/` is gitignored (`.gitignore`
line: `/.claude/*` plus a `.claude/worktrees/<name>` allow-then-worktree
arrangement) and/or git treats a nested `.git`-bearing directory as a separate
root it does not walk into for untracked-file discovery. No sibling-worktree
prune code is needed; it falls out of using `git ls-files` at all.

### Why the exclude pathspec is `tests/fixtures/**` and `examples/**` only

This kit's own repo has real nested specs under `lib/{sync,stats,skill-curator,
cosmetic,plugin-check}/docs/specs/` and `_meta/megagoals/_archive/*/docs/specs/`
that hold distinct, real documents (Problem section: `lib/stats/docs/specs/
SPEC-126-ledger-event-schema.md` is a real spec, not a fixture, even though it
happens to share the number 126 with the unrelated top-level `SPEC-126-weekend-
batch.md`). Counting these is correct: they are real specs whose numbers must
be treated as taken, exactly like the consumer-repo evidence in `## Problem`.
`examples/hello-spec/docs/specs/SPEC-001-version-flag.md` and
`tests/fixtures/whole-spec-dispatch/ab-medium/.../docs/specs/*` are, by
contrast, demo/teaching content and test scaffolding respectively -- never a
real project spec, in this repo or any consumer repo that copies this kit's own
`examples/` pattern. These two namespaces are excluded by name; every other
nested tier is counted, and the resulting "next() jumps higher on a repo with
real nested specs" is the intended, fail-open direction (Non-goals).

### Why `gh pr list --json ...,files`, not the Git Trees API

Verified live this session against this repo (`gh pr list --json
number,headRefOid,files --limit 1`, real output, one PR, `files` array of
changed paths with `path`/`additions`/`deletions`/`changeType`). One call
returns every open PR's changed-file list in one round trip; the previous
per-head Trees-API design cost ~3MB/~2s per head and 404s on a fork PR's head
(the fork's tree is not reachable through the base repo's API without adding
the fork as a remote). `gh pr list --files` reads the PR's own file list
regardless of whether the head is a fork, and needs no `--jq`-driven follow-up
call per head. This also designs out the Trees API's `truncated` field
entirely: there is nothing to check, because there is no tree fetch. The
residual risk (`gh`'s own file-list has a practical cap for an enormous PR) is
the same class of best-effort risk the header comment already accepts for
"any bootstrap call fails, the scan falls back... and prints one stderr note"
(`:31-32`); it is not a new failure mode, and it is directly testable with a
stub `gh` returning a capped array (T6).

### Scan-once-per-reserve, and why it also fixes `_prune_reservations`

`reserve` today calls `next` (one `_scan_numbers` call) and then
`_prune_reservations` (a second, independent `_scan_numbers` call), both under
the same lock. With the widened scan measured at up to ~6s warm on a large
repo, two calls inside a ~30s lock budget (`_reserve_lock`'s ~600-try backoff)
materially eats into the budget a concurrent wave needs, and `reserve`'s own
retry loop (`:310`, up to 5 attempts) can multiply that further. The fix
computes the local scan once, threads it into both consumers, and additionally
corrects the false non-goal from the original draft: because
`_prune_reservations` now consumes the SAME scan `reserve` just took (not a
stale or separately-recomputed one), a reservation for a number that was just
realized by this very `reserve` call's own union is pruned in the same pass,
with no second live rescan.

### Boundaries & failure modes

See `## Failure modes`.

## Task Breakdown

Test file first (T1-T14 encode the acceptance contract before any
implementation task claims to satisfy it), then the two scan fixes, then test
infra parity and docs, then full regression.

### Phase 0: Test harness

- [ ] TASK-1: `tests/test-spec-next-nested-dirs.sh` (new), following the
  `mk_repo()` temp-git-repo pattern already used by `tests/test-spec-reserve.sh`
  and `tests/test-spec-next-pr-scan.sh` (no static `tests/fixtures/` tree for
  THIS test file's own fixtures -- a temp repo built with `mktemp -d` + `git
  init`, matching precedent, and never itself placed under `tests/fixtures/`
  so it is not excluded by TASK-2's own pathspec). Implements fixture builders
  (`mk_repo_nested`, a many-worktree variant, a symlinked-`docs/specs` variant)
  and all fourteen local/PR test bodies, T1-T14 (`## Test plan`). Run against
  today's UNFIXED `lib/spec/spec-next.sh`, T1/T2/T3/T5/T8/T9/T10/T12 are
  expected to FAIL (red); T4/T6/T7/T11/T13/T14 already pass or encode the
  negative control the fix must not break.
  Verify: `bash tests/test-spec-next-nested-dirs.sh` runs to completion and its
  per-case PASS/FAIL output matches the red/expected split above.

### Phase 1: Local scan

- [ ] TASK-2: `lib/spec/spec-next.sh` `_scan_numbers` (`:89-101`): keep the
  existing top-level `ls` line (digit cap only), add the `git ls-files
  --cached --others --exclude-standard` line with the include/exclude pathspec
  from `## Interface`.
  Verify: T1, T2, T3, T7, T11, T12 go green in `tests/test-spec-next-nested-dirs.sh`.
- [ ] TASK-3: Single-scan threading inside `reserve` (`:310`) and `check`
  (`:171`): compute the local scan / `_numbers` result once per invocation;
  `_prune_reservations` (`:195`) takes the precomputed text as a parameter
  instead of recalling `_scan_numbers`.
  Verify: T8, T9 go green.
- [ ] TASK-4: Digit-count cap (`SPEC-[0-9]{1,6}` everywhere `SPEC-[0-9]+`
  appears today) and fail-soft wrapping on every new pipeline stage (`2>/dev/null
  ... || true`, matching the script's existing convention) so a scan error
  under `set -euo pipefail` degrades to an empty contribution rather than
  aborting `reserve` after the ledger claim line is appended.
  Verify: T10, T13 go green.

### Phase 2: PR scan

- [ ] TASK-5: `lib/spec/spec-next.sh` `_scan_pr_numbers` (`:108-132`): replace
  the per-head Trees-API call with one `gh pr list --json number,headRefOid,files
  --limit 100` call; filter `.files[].path` to `(^|/)docs/specs/[^/]+$` minus
  the `tests/fixtures/`/`examples/` exclusions; extract `SPEC-[0-9]{1,6}` from
  the basename. Keep every existing fail-soft branch.
  Verify: T5, T6, and the PR half of T12 go green.

### Phase 3: Test infra parity + docs

- [ ] TASK-6: `tests/test-spec-next-pr-scan.sh`: extend the stub `gh` to also
  answer `pr list --json number,headRefOid,files` with a matching JSON `files`
  array (today's stub only answers `contents/docs/specs` and ignores `--jq`,
  `:34-52`); fix T4's fenced PATH so it includes every binary the new call path
  needs (`git` for the local scan's `ls-files`; no `find` is needed anywhere in
  this design, so none is added).
  Verify: `bash tests/test-spec-next-pr-scan.sh` passes with the updated stub.
- [ ] TASK-7: Docs. Update the script's own header comment (`:5-7`, "docs/specs/
  filenames in every worktree" language; `:28-29`, "gh api .../contents/docs/specs?ref=<head>"
  language) to describe the widened scan and the single-call PR source; add a
  `CHANGELOG.md` entry; write `docs/verification/spec-next-nested-dirs.md`
  holding the T1-T15 run transcript once TASK-2 through TASK-6 are green.
  Verify: header comment no longer describes the old single-path scan;
  `docs/verification/spec-next-nested-dirs.md` exists and quotes the test run.

### Phase 4: Regression

- [ ] TASK-8: Full regression: `bash tests/test-meta.sh`, `bash
  tests/test-spec-reserve.sh`, `bash tests/test-spec-next-pr-scan.sh` (updated),
  and `bash tests/test-hooks.sh` (the SPEC-064/ID-052 real-repo check at
  `:313-315`) all green.
  Verify: T15; all four commands exit 0.

## After state

- [ ] `spec-next.sh next` / `check` / `reserve`, run from a repo with specs
  under any nested `docs/specs/` (this kit's own `lib/*` included), treat those
  numbers as taken. (Today: only `<root>/docs/specs/` counts.)
- [ ] An open PR whose head adds a spec under a nested `docs/specs/` is folded
  into `_scan_pr_numbers`'s result via one `gh pr list` call. (Today: only a PR
  touching the top-level `docs/specs/`, fetched per-head, is seen.)
- [ ] `reserve` computes the local scan exactly once per invocation, not twice;
  `_prune_reservations` consumes that same result. (Today: two independent
  `_scan_numbers` calls per successful `reserve`.)
- [ ] A repo whose only nested specs are under `tests/fixtures/` or `examples/`
  sees no material change (both excluded). A repo with real nested specs
  elsewhere (this kit included) sees `next()` return a higher number than
  before; this is the intended, disclosed, fail-open direction, not a claimed
  no-op (the original draft's "byte-identical" claim is retracted).

## Acceptance Criteria (global)

| # | Case | Criterion | Command | Pass |
|---|---|---|---|---|
| AC1 | T1 | Nested-only local spec counts as taken | `bash tests/test-spec-next-nested-dirs.sh T1` | `check` on a number that exists only under a nested `docs/specs/` reports TAKEN |
| AC2 | T2 | `next`/`reserve` skip past a nested-only number | `bash tests/test-spec-next-nested-dirs.sh T2` | both print a number strictly greater than the fixture's nested max |
| AC3 | T3 | Nested-only duplicate (no top-level entry at all) is caught | `bash tests/test-spec-next-nested-dirs.sh T3` | a fixture with the SAME number under two DIFFERENT nested dirs, neither at top level, is reported TAKEN by `check` and skipped by `next` |
| AC4 | T4 | Negative control: unpatched script reproduces the bug on the identical fixture | `bash tests/test-spec-next-nested-dirs.sh T4` | the script body pinned to base commit `d2ec4c40` (or a `$TMPDIR` copy of it if the branch history is later squashed away), invoked against the same fixture, reports the nested-only number as free / mints a colliding number; the patched working tree does not |
| AC5 | T5 | PR-scan sees a nested spec via one call | `bash tests/test-spec-next-nested-dirs.sh T5` | a stub `gh pr list --json number,headRefOid,files` response listing a nested `docs/specs/SPEC-NNN-*.md` path folds into `next`'s result |
| AC6 | T6 | PR-scan per-head fail-soft | `bash tests/test-spec-next-nested-dirs.sh T6` | one PR entry with no matching `files` (or a malformed/oversized array) contributes nothing; a second PR's real match still folds in |
| AC7 | T7 | Namespace excludes hold both ways | `bash tests/test-spec-next-nested-dirs.sh T7` | a fixture spec under `tests/fixtures/**` or `examples/**` is NOT counted; a fixture spec under `lib/x/docs/specs/` or `_meta/megagoals/_archive/x/docs/specs/` IS counted |
| AC8 | T8 | Local scan runs exactly once per `reserve` | `bash tests/test-spec-next-nested-dirs.sh T8` | an instrumented scan-call log shows exactly one local-scan invocation for one successful `reserve` call (not two) |
| AC9 | T9 | Prune uses the same single scan | `bash tests/test-spec-next-nested-dirs.sh T9` | a reservation whose number the just-computed scan already shows as realized is pruned in the same `reserve` call, with the scan-call log from T8 still showing exactly one invocation |
| AC10 | T10 | Oversized number token does not crash | `bash tests/test-spec-next-nested-dirs.sh T10` | a fixture filename with 20+ digits after `SPEC-` is ignored by every consumer (`next`/`check`); no arithmetic error |
| AC11 | T11 | Symlinked top-level `docs/specs` still works | `bash tests/test-spec-next-nested-dirs.sh T11` | a fixture whose top-level `docs/specs` is a symlink to a real directory elsewhere in the repo is still scanned (kept `ls` line, unchanged behavior) |
| AC12 | T12 | Basename-only, one level deep, on both surfaces | `bash tests/test-spec-next-nested-dirs.sh T12` | a fixture with `docs/specs/implementation-notes/SPEC-NNN-*.md` and `docs/specs/data/SPEC-NNN-*.tsv` (two levels deep) is NOT counted by the local scan (git glob magic) or by the PR-scan (explicit regex) |
| AC13 | T13 | Scan failure inside `_prune_reservations` does not orphan a claim | `bash tests/test-spec-next-nested-dirs.sh T13` | a fault-injected scan failure after the ledger claim line is appended still returns the claimed number to the caller and leaves exactly one live reservation line, under `set -euo pipefail` |
| AC14 | T14 | Latency budget on a many-worktree fixture | `bash tests/test-spec-next-nested-dirs.sh T14` | a fixture with several worktrees completes `reserve` well inside `_reserve_lock`'s retry budget; documented as an order-of-magnitude check, not a strict wall-clock assertion (CI-machine variance) |
| AC15 | T15 | No regression | `bash tests/test-meta.sh && bash tests/test-spec-reserve.sh && bash tests/test-spec-next-pr-scan.sh && bash tests/test-hooks.sh` | all exit 0 |

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

Fixture repo (`mk_repo_nested()`, same `mktemp -d` + `git init` shape as
`tests/test-spec-reserve.sh:mk_repo()`), reproducing the shape from `##
Problem` and the self-check evidence, with placeholder numbers (no consumer
repo names or slugs):

```
docs/specs/SPEC-100-top.md
docs/specs/SPEC-141-a.md
tools/toolA/docs/specs/SPEC-141-b.md          # duplicate of 141, ALSO visible at top level (KEEP control)
tools/toolA/docs/specs/SPEC-142-x.md          # nested-only, no top-level entry
tools/toolB/docs/specs/SPEC-145-y.md          # nested-only
tools/toolA/docs/specs/SPEC-143-z1.md         # nested-only duplicate, part A
tools/toolB/docs/specs/SPEC-143-z2.md         # nested-only duplicate, part B (no top-level entry either)
experiments/foo-bar/docs/specs/SPEC-150-x.md  # nested-only, experiments/ tier
lib/x/docs/specs/SPEC-160-lib.md              # counted-nested-tier proof (mirrors this kit's own lib/stats shape)
_meta/megagoals/_archive/y/docs/specs/SPEC-161-arc.md  # counted-nested-tier proof
tests/fixtures/z/docs/specs/SPEC-970-decoy.md # must NOT be counted
examples/hello/docs/specs/SPEC-971-decoy.md   # must NOT be counted
docs/specs/implementation-notes/SPEC-980-deep.md  # two levels deep, must NOT be counted
docs/specs/data/SPEC-981-deep.tsv             # two levels deep, must NOT be counted
docs/specs/SPEC-99999999999999999999-huge.md  # oversized token, must not crash arithmetic
```

| Case | Kind | Covers | Proof |
|---|---|---|---|
| T1: `check 142` against the fixture, patched script | positive | AC1 | exit 1, "TAKEN" |
| T2: `next` against the fixture, patched script | positive | AC2 | prints a number > 161 (the highest counted nested number), not > 145 (the old top-level-blind ceiling) |
| T3: `check 143` against the fixture (nested-only duplicate, no top-level entry) | positive | AC3 | exit 1, "TAKEN"; `next` still returns > 161 |
| T4: `check 142` / `check 145` against the fixture, script pinned to base commit `d2ec4c40` | negative control (must reproduce the reported bug) | AC4 | exit 0, "free" |
| T4b: `next` against the fixture, pinned base commit | negative control | AC4 | mints 143 or 146 (colliding with an already-committed nested spec), not 162 |
| T5: stub `gh pr list --json number,headRefOid,files` listing `tools/toolC/docs/specs/SPEC-170-y.md` in one PR's `files` | positive | AC5 | `next` prints > 170 |
| T6: two stubbed PRs, one with a `files` array holding no `docs/specs` path, one with a real match | negative control (fail-soft per-PR) | AC6 | the non-matching PR contributes nothing (no error, no note); the matching PR's number folds in |
| T7a: `check 970` (tests/fixtures) and `check 971` (examples) | negative control (excluded namespaces) | AC7 | both exit 0, "free" |
| T7b: `check 160` (lib/x) and `check 161` (_meta/megagoals/_archive) | positive (counted namespaces) | AC7 | both exit 1, "TAKEN" |
| T8: scan-call log around one `reserve` call | positive, instrumented | AC8 | the log (an env-gated append-only file, e.g. `SPEC_NEXT_SCAN_LOG=<path>`, written by the local-scan helper on each invocation) has exactly 1 line for this `reserve` call |
| T9: a reservation for 142 exists in the ledger; the fixture's real `SPEC-142` file is added between two `reserve` calls; the second call's scan-log (T8's mechanism) still shows exactly 1 line | positive | AC9 | the stale reservation for 142 is pruned as realized in that same call, and the scan-call log confirms no second scan ran to do it |
| T10: `check` and `next` against the fixture's `SPEC-99999999999999999999-*` file | negative control (overflow guard) | AC10 | no arithmetic error; the oversized token is excluded from the max computation entirely |
| T11: fixture where `docs/specs` (top level) is a symlink to `real-specs/` holding `SPEC-190-x.md` | positive (regression-preserving) | AC11 | `check 190` exits 1, "TAKEN" |
| T12: `check 980` (implementation-notes/, 2 levels) and `check 981` (data/, 2 levels) against the fixture; a stubbed PR whose `files` includes a matching 2-level-deep path | negative control (depth guard, both surfaces) | AC12 | all exit 0 / contribute nothing |
| T13: fault-injected scan failure (a wrapper that exits nonzero) invoked from inside `_prune_reservations`, after the claim line is already appended, against a repo with `set -euo pipefail` active | negative control (fail-soft under `set -e`) | AC13 | `reserve` still prints the claimed number; the ledger has exactly one live line for it; no unhandled script abort |
| T14: a fixture with 5+ worktrees, each holding a handful of nested `docs/specs` dirs | positive (latency budget) | AC14 | `reserve` completes in low single-digit seconds, well under `_reserve_lock`'s ~30s give-up budget |
| T15: `test-meta.sh`, `test-spec-reserve.sh`, `test-spec-next-pr-scan.sh` (updated stub), `test-hooks.sh:313-315` | regression | AC15 | all green; no fixture in those files touches a nested dir or the new PR-scan shape except where TASK-6 updates the stub |

Dry trace for the key negative control (AC4/T4): today's `_scan_numbers` runs
`ls "$wt/docs/specs"` (`:97`), which on the fixture repo returns only
`SPEC-100` and `SPEC-141` (the two files physically inside `docs/specs/`);
`SPEC-142`, `SPEC-143`, `SPEC-145`, `SPEC-150`, `SPEC-160`, and `SPEC-161` never
appear because `ls` does not descend into `tools/`, `experiments/`, `lib/`, or
`_meta/`. `check 142` therefore reports free. After TASK-2, the same fixture's
`git ls-files` pass visits every nested `docs/specs` one level deep (excluding
`tests/fixtures/` and `examples/`), `check 142` finds the file and reports
TAKEN, and `next` returns 162.

## Edge Cases

1. A repo whose only nested `docs/specs` entries are under `tests/fixtures/` or
   `examples/`: no material change (T7a).
2. A number that exists ONLY inside an excluded namespace and ALSO, separately,
   as a real nested spec elsewhere: the real nested copy still makes it TAKEN;
   the excluded copy is simply invisible, same as a number that never existed
   at all inside `tests/fixtures/`.
3. A PR whose `files` array is capped by `gh`'s own practical limit for very
   large PRs: the same accepted best-effort risk the header comment already
   states for any bootstrap-call failure (`:31-32`); fewer numbers seen, never
   more.
4. A repo with no `gh` on PATH, or `gh` unauthenticated: unchanged from today,
   local-only fallback plus one stderr note (covered by `tests/test-spec-next-pr-scan.sh`
   T2-T4, unaffected by this spec).
5. A worktree whose `.git` is a plain file (the normal worktree shape, not a
   directory): `git -C "$wt" ls-files` handles this identically to a primary
   checkout; nothing special needed.
6. A nested `docs/specs` reached only through a symlinked INTERMEDIATE directory
   (not the top-level `docs/specs` itself, e.g. `tools/foo -> elsewhere`): out
   of scope, matching git's own general symlink-walk limits; no repo surveyed
   uses this pattern (Non-goals).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| The local scan runs more than once per lock-held critical section, eating into `_reserve_lock`'s ~30s budget on a large/many-worktree repo, and a failed `reserve` falls back to the racy `next` path in `lib/queue/orchestrate.sh` | T8/T14; a `reserve` failure rate uptick on a large repo | scan-once-per-reserve (TASK-3) plus `git ls-files` instead of `find` (measured ~35x faster) |
| A repo's fixture/example/archive content pollutes the global numbering | T7 | explicit pathspec exclude for `tests/fixtures/**` and `examples/**`; every other nested tier is intentionally counted (fail-open, Non-goals) |
| A garbage `SPEC-`-prefixed token with an unbounded digit run overflows the `10#$max` arithmetic | T10 | `SPEC-[0-9]{1,6}` cap on every extraction |
| A scan stage fails under `set -euo pipefail` inside `_prune_reservations`, after the ledger claim line is already appended, aborting the process before the claimed number is returned | T13 | fail-soft wrapping (`2>/dev/null ... \|\| true`) on every new pipeline stage, matching the script's existing convention; fail OPEN (treat an unreadable path as "not yet realized," never as a reason to drop the claim) |
| `gh pr list --json ...,files` itself caps an enormous PR's file list | none added beyond the existing best-effort contract | accepted; same risk class the header comment already states for any bootstrap-call failure; testable via a stub returning a capped array (T6) |
| A nested `docs/specs` reached only through a symlinked intermediate directory | none (out of scope) | Non-goals / Edge case 6; no repo surveyed needs it |
| `gate-ledger.sh validate-round` / `hooks/ship-gate.sh` locate a spec by a top-level-only `docs/specs/SPEC-*-<rid>.md` path | unaffected by this spec; flagged, not fixed | Non-goals follow-up |

## Migration notes (existing adopted repos)

- A repo whose nested specs are ONLY under `tests/fixtures/` or `examples/`
  sees no change.
- A repo with real nested specs anywhere else (a co-located `tools/*/docs/specs/`
  convention, or, as this kit's own repo shows, a `lib/*/docs/specs/`
  convention) will see `next()` return a higher number after this fix lands,
  because numbers that were silently invisible before now count. This is a
  one-time, disclosed jump, not a bug.
- `reserve` behaves identically from a caller's point of view; only its
  internal scan cost and call count change.

## Out of Scope

- Renumbering or merging any existing duplicate spec file, anywhere.
- A configurable glob/pattern list for a repo naming its nested tier something
  other than `docs/specs`.
- Any change to `_reservations()`, the mkdir-mutex, the TTL/reclaim logic, or
  the reservation ledger file format.
- `gate-ledger.sh validate-round` / `hooks/ship-gate.sh`'s own top-level-only
  spec lookup (Non-goals follow-up).
- The reporting consumer repo itself: this spec fixes the kit's own
  `spec-next.sh`; it does not touch, open a PR against, or renumber anything
  in that repo.

## Touches

Single files: `lib/spec/spec-next.sh`, `tests/test-spec-next-nested-dirs.sh`
(new), `tests/test-spec-next-pr-scan.sh`, `CHANGELOG.md`,
`docs/verification/spec-next-nested-dirs.md` (new).

No shared-file conflict expected with any in-flight sibling spec (checked: no
other `docs/specs/SPEC-*.md` in this repo currently lists `lib/spec/spec-next.sh`
under its own `## Touches`).

## Decision Log

- DEC-1: `git ls-files --cached --others --exclude-standard` with an
  include/exclude pathspec, not `find`, for the local scan (measured ~35x
  faster on a many-worktree repo; sidesteps argv-injection, deep-symlink, and
  sibling-worktree-descent concerns by construction rather than by added
  pruning code).
- DEC-2: `gh pr list --json number,headRefOid,files`, not the Git Trees API,
  for the PR scan (one call, works on fork heads, designs out the untestable
  `truncated`-field question entirely).
- DEC-3: exclude only `tests/fixtures/**` and `examples/**`; every other
  nested tier (including this kit's own `lib/*` and `_meta/megagoals/_archive/*`)
  is intentionally counted, and widening `next()`'s output on such a repo is
  the correct, fail-open direction, not a regression to guard against.
- DEC-4: scan the local surface exactly once per `reserve`/`check` invocation,
  threading the result into `_prune_reservations` instead of letting it
  recompute; corrects the original draft's false claim that
  `_prune_reservations` was untouched.
- DEC-5: cap extracted digits at `SPEC-[0-9]{1,6}` everywhere, closing a
  latent arithmetic-overflow risk unrelated to nesting but found while auditing
  the same extraction regex.
- DEC-6: keep the original top-level `ls "$wt/docs/specs"` line verbatim
  (digit cap only) rather than folding it into the `git ls-files` call, so a
  symlinked top-level `docs/specs` keeps working exactly as it does today.
- DEC-7: recognize (do not renumber) that this kit's own repo already carries
  duplicate numbers between top-level and several `lib/*` subsystems; out of
  scope, reported as grounding evidence only.

## Grounding

- Root-cause line: `lib/spec/spec-next.sh:97` (`ls "$wt/docs/specs" 2>/dev/null
  | grep -oE 'SPEC-[0-9]+' || true`), confirmed by direct read this session.
- Self-referential duplicate evidence (this kit's own repo, run this session):
  `git ls-files -- ':(glob)**/docs/specs/*' | grep -v '^docs/specs/'` returns
  311 nested matches including `lib/stats/docs/specs/SPEC-126-ledger-event-schema.md`,
  `lib/sync/...`, `lib/skill-curator/...`, `lib/cosmetic/...`,
  `lib/plugin-check/...`, `examples/hello-spec/docs/specs/SPEC-001-version-flag.md`,
  and `_meta/megagoals/_archive/token-optim-v2/docs/specs/SPEC-122-static-floor-reduction.md`;
  `ls docs/specs/SPEC-126-*.md docs/specs/SPEC-134-*.md` shows unrelated
  top-level documents (`SPEC-126-weekend-batch.md`, `SPEC-134-security-hardening.md`)
  sharing those numbers with the nested copies.
- Pathspec one-level-deep proof (run this session): `git ls-files -- ':(glob)**/docs/specs/*'`
  returns 311 entries, none of them two levels deep under any `docs/specs/`
  (no `.../docs/specs/implementation-notes/*` or `.../docs/specs/data/*` in the
  result), confirming git's glob magic (`*` does not cross `/`; `**` does)
  already enforces the one-level predicate for the local scan without an extra
  filter.
- Worktree-boundary proof (run this session): `git ls-files -- '.claude/worktrees/**'`
  from the main checkout returns 0 files; `git check-ignore -v
  .claude/worktrees/spec-next-nested-dirs` confirms the path is covered by
  `.gitignore` (`/.claude/*` plus the worktree carve-out). No sibling-worktree
  descent is possible through `git ls-files`.
- `gh pr list --json ...,files` proof (run this session, real output, one
  open PR against this repo): `[{"files":[{"path":"commands/execute.md",...},
  ...,{"path":"docs/specs/SPEC-311-impl-notes-gate.md","additions":162,
  "deletions":0,"changeType":"ADDED"},...],"headRefOid":"7f8a4d6f...",
  "number":756}]` -- confirms the field name, shape, and that a
  `docs/specs/SPEC-NNN-*.md` addition shows up directly in `.files[].path`
  with no follow-up call.
- Measured timings (reported by the review round against a 28-worktree
  consumer repo, generic per the privacy rule): the rejected `find`-based
  local scan took ~6s warm / ~28.7s cold / ~39.5s summed across all 28
  worktrees, each finding the same ~79 nested `docs/specs` dirs independently;
  `git ls-files --cached --others --exclude-standard` across the same 28
  worktrees took ~1.1s and returned the same 131 numbers.
- Existing regression anchors: `tests/test-hooks.sh:313-315` runs `spec-next.sh
  check`/`next` against this kit's own real repo today (the SPEC-064/ID-052
  check); `tests/test-spec-next-pr-scan.sh:34-52` is today's stub `gh`, which
  answers only `contents/docs/specs` and must be extended (TASK-6) to also
  answer `pr list --json number,headRefOid,files`.

## Open questions

(none; every unknown from round 1 was settled by direct reading of
`lib/spec/spec-next.sh` or by a live command run this session, cited above)
