# Spec: spec-next scans nested docs/specs, not just the top level
Generated: 2026-09-30
Status: DRAFT
Lane: full
Depth: standard (root cause is grounded by reading `lib/spec/spec-next.sh` directly, cited by file:line below; no outside unknown and no failure mode the author expects to miss alone)
References: `lib/spec/spec-next.sh:89-101` (`_scan_numbers`, the local scan this spec fixes); `lib/spec/spec-next.sh:104-132` (`_scan_pr_numbers`, the open-PR scan with the same blind spot); `tests/test-spec-reserve.sh` and `tests/test-spec-next-pr-scan.sh` (the fixture-repo pattern this spec's tests extend)

## Problem

`ops-toolkit` (a separate, unrelated repo) keeps specs co-located per its own
`CLAUDE.md`: a central `docs/specs/`, plus `tools/<name>/docs/specs/` and
`experiments/<slug>/docs/specs/` per tool/experiment. On 2026-09-29,
`bash ~/.claude/dwarves-kit/lib/spec/spec-next.sh reserve` handed out SPEC-142,
which `tools/circle/docs/specs/SPEC-142-circle-phases.md` already held, and
`spec-next.sh check 144` / `check 145` both reported free while
`tools/vps-mon/docs/specs/SPEC-144-never-pinged-lifecycle.md` and
`tools/vps-mon/docs/specs/SPEC-145-catalog-gap-close.md` were already committed.

Evidence gathered directly from the ops-toolkit checkout (this session, read-only):

| Number | Nested files that exist | Top-level `docs/specs/` entry |
|---|---|---|
| SPEC-141 | `docs/specs/SPEC-141-tenant-health-socket-census.md`, `tools/circle/docs/specs/SPEC-141-circle.md`, `tools/mac-mini-substrate/docs/specs/SPEC-141-mini-run-gh-token.md` | present (x3 total, the collision the user already knew about) |
| SPEC-142 | `tools/circle/docs/specs/SPEC-142-circle-phases.md` | **none** -- the exact case `reserve` missed |
| SPEC-143 | `tools/circle/docs/specs/SPEC-143-circle-bonding.md`, `tools/vps-mon/docs/specs/SPEC-143-cf-auth-account-id.md` | none (x2 collision) |
| SPEC-144 | `tools/vps-mon/docs/specs/SPEC-144-never-pinged-lifecycle.md` | **none** -- the exact case `check` missed |
| SPEC-145 | `tools/vps-mon/docs/specs/SPEC-145-catalog-gap-close.md` | **none** -- the exact case `check` missed |
| SPEC-134 (found this session, not previously reported) | `docs/specs/SPEC-134-eb-post-stream.md`, `tools/agentic-inbox/docs/specs/SPEC-134-email-ingest-lanes.md`, `tools/vps-mon/docs/specs/SPEC-134-catalog-stages.md`, `tools/social-desk/docs/specs/SPEC-134-social-desk.md` | present, but 3 of the 4 collide unseen (x4 total) |

Every collision that has NO top-level entry (142, 143, 144, 145) sits directly in a
nested `tools/*/docs/specs/` directory that the scan never visits.

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

`ls "$wt/docs/specs"` is a flat, non-recursive listing of exactly ONE directory per
worktree: `<worktree-root>/docs/specs`. It correctly loops over every worktree (line
94-98 handles the concurrency case SPEC-064/128 fixed), but within each worktree it
never descends into `tools/*/docs/specs/`, `experiments/*/docs/specs/`, or any other
convention a consumer repo layers on top of the kit's own single-`docs/specs/`
assumption. `next()` (`:135-140`) and `check()` (`:142-153`) both call `_numbers()`
(`:102`), which folds in `_scan_numbers` verbatim, so both inherit the blind spot.

Confirmed, not just theorized: every collision in the table above that has no
top-level `docs/specs/` entry (142, 143, 144, 145) exists ONLY under a nested
`tools/*/docs/specs/` path, which is exactly the set `ls "$wt/docs/specs"` cannot see.

A second, same-shaped instance sits in `_scan_pr_numbers` (`:104-132`), used by
`_numbers()` for open PRs:

```
130    gh api "repos/$owner_repo/contents/docs/specs?ref=$ref" --jq '.[].name' 2>/dev/null \
131      | grep -oE 'SPEC-[0-9]+' || true
```

The GitHub Contents API call is also scoped to exactly one path, `docs/specs`, and is
non-recursive by nature of that endpoint. An open PR that adds a spec under
`tools/<x>/docs/specs/` is invisible to this scan too. This is the same root cause
(a hardcoded single top-level path) manifesting in the second scan surface `_numbers()`
unions.

**Reservation atomicity is unaffected and does not need a fix.** `reserve()`
(`:230-259`) claims a number under a portable mkdir-mutex (`_reserve_lock`,
`:186-227`) keyed on the repository's physical git-common-dir (`:38-46`), so every
worktree of one repo shares one lock and one ledger. The lock has a dead-holder
reclaim (owner-pid `kill -0` check), a TTL-based stale-lock reclaim, split signal
traps that exit rather than resume unprotected, and a re-validation of lock ownership
after computing `next()` before appending the claim (closing the window where a
stale reclaim could hand the lock to another process mid-scan). This machinery
guards WHO gets to claim a number and HOW an in-flight claim is broadcast to sibling
callers; it says nothing about WHICH numbers `next()` computes as taken. The bug in
this spec is a coverage gap in `_scan_numbers`/`_scan_pr_numbers` (what counts as
"seen"), fully orthogonal to the locking correctness `reserve()` already has. This
spec does not touch `_reserve_lock`, `_reserve_unlock`, `_prune_reservations`, or the
reservation ledger format.

## Scope

- `_scan_numbers` (`lib/spec/spec-next.sh:89-101`): widen the per-worktree scan from
  one hardcoded path to every directory anywhere under that worktree whose path ends
  in `docs/specs`, pruned so it never walks `.git`, `node_modules`, or a nested
  sibling worktree's own subtree (a worktree already gets its own loop iteration;
  walking into it again from a parent worktree is redundant and, for a large
  `node_modules`-bearing nested worktree, slow).
- `_scan_pr_numbers` (`lib/spec/spec-next.sh:104-132`): widen the open-PR scan from
  one Contents-API call on `docs/specs` to a recursive listing of the PR head's tree,
  filtered to paths whose directory segment is `docs/specs`, keeping the existing
  fail-soft contract (any missing tool, failed auth, or failed bootstrap call still
  degrades to one stderr note and an empty result).
- New tests proving both surfaces see a nested spec, including the exact duplicate
  shape from the Problem table, plus a negative control showing the bug reproduces
  without the fix.

## Non-goals

- **No renumbering of existing duplicates.** SPEC-141 (x3), SPEC-143 (x2), and
  SPEC-134 (x4, newly found this session) stay as they are; this spec reports them,
  it does not touch ops-toolkit or rename any file. ops-toolkit's own maintainers
  decide whether and how to renumber.
- **No configurable glob list.** A fixed recursive `find` for any directory path
  ending in `docs/specs` already covers every convention seen (a bare top-level
  `docs/specs/`, per-tool `tools/<x>/docs/specs/`, per-experiment
  `experiments/<slug>/docs/specs/`, and any future sibling that follows the same
  `.../docs/specs` shape). A consumer repo whose spec directories are named
  something else entirely (not `docs/specs` anywhere in the path) is out of scope;
  no repo surveyed uses a different name.
- **No change to the reservation ledger, the mkdir-mutex, or the TTL/reclaim logic**
  (see Root cause: this machinery is correct and untouched).
- **No change to `_reservations()` or `_prune_reservations()`.** They read the
  ledger, not the filesystem; the fix here does not affect them.
- **No change to `next`/`check`'s CLI surface, output format, or exit codes.** A
  repo with zero nested spec dirs (today's common case) sees byte-identical output,
  because the recursive find still visits `<root>/docs/specs` as one of its matches.

## Interface

Both fixes are internal to `lib/spec/spec-next.sh`; no new script, no new flag, no
new environment variable. The change is confined to what `_scan_numbers` and
`_scan_pr_numbers` walk, not their output shape (both still emit one `SPEC-NNN` token
per line, unioned and deduped by the existing `sort -n | uniq` in `_numbers()`).

`_scan_numbers`, per worktree `wt`, replaces the single `ls` with a recursive find
that:

1. Prunes `$wt/.git`, any `node_modules` directory, and every OTHER worktree's root
   directory reachable under `$wt` (built from the same `git worktree list
   --porcelain` output already parsed at `:94`, excluding `$wt` itself) before
   descending further.
2. Matches every remaining directory whose path ends in `docs/specs` (covers
   `$wt/docs/specs`, `$wt/tools/*/docs/specs`, `$wt/experiments/*/docs/specs`, and
   any other depth).
3. Lists each match's immediate files (still non-recursive INSIDE a matched
   `docs/specs` dir -- nothing in this repo or ops-toolkit nests a `docs/specs`
   inside another `docs/specs`) and greps `SPEC-[0-9]+`, exactly as `:97` does today.

`_scan_pr_numbers` replaces the single Contents-API call with one Git Trees API call
per PR head (`gh api "repos/$owner_repo/git/trees/$ref?recursive=1"`, one call
instead of the risk of one call per nested directory), filters `.tree[].path` to
entries whose path contains a `docs/specs/` segment, and greps `SPEC-[0-9]+` from the
basenames. The existing fail-soft branches (`gh` missing, not authenticated, `gh repo
view`/`gh pr list` failing) are unchanged; a tree-fetch failure for one PR head is
skipped the same way a 404 on `contents/docs/specs` is skipped today (not every PR
touches specs).

## Picture

```
                         spec-next.sh {next|check|reserve}
                                      |
                                      v
                                 _numbers()
                    /                |                  \
                   v                 v                   v
          _scan_numbers      _scan_pr_numbers        _reservations
          (per worktree)     (per open PR head)      (ledger; unaffected)
                   |                 |
     TODAY:        |                 |
     ls "$wt/docs/specs"   gh api contents/docs/specs?ref=<head>
     (ONE path, no descent) (ONE path, no descent)
                   |                 |
          BLIND to tools/*/docs/specs/ and experiments/*/docs/specs/
                   |                 |
     FIXED:        v                 v
     find "$wt" -prune {.git,        gh api git/trees/<head>?recursive=1
       node_modules, sibling         | filter path ~ */docs/specs/*
       worktree roots}
       -path '*/docs/specs' -type d
       -> ls each match
                   \                 /
                    v               v
              every SPEC-NNN under any docs/specs, anywhere in the tree
                    |
                    v
        sort -n | uniq  (unchanged; dedupes across all three sources)
```

## Design

The fix is additive at the exact seam that was already correct in shape: both
`_scan_numbers` and `_scan_pr_numbers` already union "every worktree" /
"every open PR", they just each stop one level too early inside a single worktree
or a single PR tree. Nothing about the union/dedupe logic in `_numbers()` (`:102`)
changes; only what each source contributes gets wider.

**Why `find`, not a glob list (rejected).** A hand-maintained list of glob patterns
(`docs/specs`, `tools/*/docs/specs`, `experiments/*/docs/specs`, ...) would need a
new entry every time a repo invents a new tier (a `packages/*/docs/specs/`
convention, say), and ops-toolkit already has three tiers today, all matching the
same shape: a directory literally named `specs` whose parent is literally named
`docs`. A single `-path '*/docs/specs' -type d` predicate covers all three today and
any future sibling that keeps the same naming, with no maintenance.

**Why prune sibling worktrees (not just `.git`/`node_modules`).** This kit's own
worktree convention (`docs/ref/worktrees.md`, referenced from the global CLAUDE.md)
places worktrees at `<repo>/.claude/worktrees/<name>`, INSIDE the main checkout's
directory tree (this very spec is being written from
`.claude/worktrees/spec-next-nested-dirs`, nested under the main dwarves-kit
checkout). Without pruning, a recursive find from the main worktree's root would
also walk every sibling worktree's full tree (including that worktree's own
`node_modules` if any), duplicating work the per-worktree loop (`:96-98`) already
does for that same sibling on its own iteration. `sort -n | uniq` would still dedupe
the result correctly, so this is a performance/hygiene prune, not a correctness one;
it is included because the task explicitly calls for it and because an unbounded
recursive find across N worktrees' full trees (each potentially holding its own
`node_modules`) is the kind of thing that turns a fast collision check into a slow
one on a repo with several active worktrees.

**Why the Git Trees API for `_scan_pr_numbers` (not one Contents-API call per
nested dir).** The Contents API lists one directory per call; finding every nested
`docs/specs/` under a PR head would need either (a) a full recursive walk issuing
one Contents-API call per directory level (many round trips, and the walk itself
needs to discover subdirectories to descend into, which the Contents API cannot do
in one shot), or (b) one Git Trees API call with `recursive=1`, which returns the
PR head's entire path list in one response. (b) is one HTTP call, matching the
existing "no clone, no fetch" design constraint stated in the script's own header
comment (`:28-29`), and is a strict widening of the existing single call, not a new
class of dependency.

## Task Breakdown

### Phase 1: Local scan

- [ ] TASK-1: `lib/spec/spec-next.sh` `_scan_numbers` (`:89-101`): replace the
  per-worktree `ls "$wt/docs/specs"` with a recursive `find "$wt" ...` that prunes
  `.git`, `node_modules`, and every other worktree root parsed from the same `git
  worktree list --porcelain` output, matches any directory path ending in
  `docs/specs`, and lists each match's immediate files through the same `grep -oE
  'SPEC-[0-9]+'`.
  Verify: `bash tests/test-spec-next-nested-dirs.sh scan` passes (T1-T4 below).
- [ ] TASK-2: `lib/spec/spec-next.sh` `_scan_pr_numbers` (`:104-132`): replace the
  single `gh api .../contents/docs/specs?ref=$ref` call with `gh api
  .../git/trees/$ref?recursive=1`, filter `.tree[].path` to entries containing a
  `docs/specs/` segment via `--jq`, and grep `SPEC-[0-9]+` from the result; keep
  every existing fail-soft branch (`gh` missing, not authed, `repo view`/`pr list`
  failing) unchanged.
  Verify: `bash tests/test-spec-next-nested-dirs.sh pr-scan` passes (T5-T6 below).

### Phase 2: Tests + regression

- [ ] TASK-3: `tests/test-spec-next-nested-dirs.sh`, new file, following the
  `mk_repo()`-style fixture pattern already used by `tests/test-spec-reserve.sh` and
  `tests/test-spec-next-pr-scan.sh` (a temp git repo built with `mktemp -d` + `git
  init`, no static `tests/fixtures/` tree). Covers the fixture repo and negative
  control described in `## Test plan` below.
  Verify: `bash tests/test-spec-next-nested-dirs.sh` exits 0.
- [ ] TASK-4: full regression. `bash tests/test-meta.sh`, `bash
  tests/test-spec-reserve.sh`, and `bash tests/test-spec-next-pr-scan.sh` still pass
  unchanged (a repo with zero nested spec dirs, which is every existing fixture in
  those two files, must see byte-identical output after TASK-1/TASK-2).
  Verify: all three commands exit 0.

## After state

- [ ] `spec-next.sh next` / `check` / `reserve`, run from a repo with specs under
  `tools/*/docs/specs/` or `experiments/*/docs/specs/`, treat those numbers as taken.
  (Today: only `<root>/docs/specs/` counts.)
- [ ] An open PR whose head adds a spec under a nested `docs/specs/` is folded into
  `_scan_pr_numbers`'s result. (Today: only a PR touching the top-level `docs/specs/`
  is seen.)
- [ ] A repo with no nested spec directories (every repo this kit ships tests
  against today) sees no change in output.

## Acceptance Criteria (global)

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | Nested local spec counts as taken | `bash tests/test-spec-next-nested-dirs.sh nested-check` | `check` on a number that exists only under `tools/x/docs/specs/` reports TAKEN |
| AC2 | `next`/`reserve` skip past a nested-only number | `bash tests/test-spec-next-nested-dirs.sh nested-next` | `next` and `reserve` both print a number strictly greater than every nested SPEC number in the fixture, not just the top-level max |
| AC3 | Duplicate shape from the Problem table reproduces and is caught | `bash tests/test-spec-next-nested-dirs.sh dup-shape` | a fixture with the SAME number under both `docs/specs/` and `tools/x/docs/specs/` (the SPEC-141/143/134 shape) is reported TAKEN by `check`, and is skipped by `next` |
| AC4 | Negative control: unpatched script reproduces the bug on the identical fixture | `bash tests/test-spec-next-nested-dirs.sh negative-control` | the pre-fix script body (captured from the parent commit before TASK-1, invoked against the same fixture) reports the nested-only number as free / mints a colliding number; the patched script does not |
| AC5 | PR-scan sees a nested spec | `bash tests/test-spec-next-nested-dirs.sh pr-scan` | a stub `gh` whose `git/trees` response lists a `tools/x/docs/specs/SPEC-NNN-*.md` path is folded into `next`'s result, matching the T1-style stub-`gh` pattern in `tests/test-spec-next-pr-scan.sh` |
| AC6 | Pruning holds | `bash tests/test-spec-next-nested-dirs.sh prune` | a fixture with a `node_modules/docs/specs/SPEC-999-x.md` decoy and a sibling worktree under `.claude/worktrees/` are NOT counted (the decoy proves prune-by-name; the sibling worktree proves no double-descent, checked via a bounded `find` call count, not a wall-clock timing assertion) |
| AC7 | No regression on zero-nested repos | `bash tests/test-meta.sh && bash tests/test-spec-reserve.sh && bash tests/test-spec-next-pr-scan.sh` | all exit 0, unchanged from before this spec |

## Verification

```bash
bash tests/test-spec-next-nested-dirs.sh
bash tests/test-spec-reserve.sh
bash tests/test-spec-next-pr-scan.sh
bash tests/test-meta.sh
```

## Test plan

Date: 2026-09-30

Fixture repo (`mk_repo_nested()`, same `mktemp -d` + `git init` shape as
`tests/test-spec-reserve.sh:mk_repo()`), reproducing the ops-toolkit shape:

```
docs/specs/SPEC-100-top.md
docs/specs/SPEC-141-a.md
tools/circle/docs/specs/SPEC-141-b.md            # duplicate of 141, both visible today
tools/circle/docs/specs/SPEC-142-circle-phases.md  # nested-only, no top-level entry
tools/vps-mon/docs/specs/SPEC-145-catalog-gap-close.md  # nested-only
experiments/foo-bar/docs/specs/SPEC-150-x.md     # nested-only, experiments/ tier
node_modules/docs/specs/SPEC-999-decoy.md        # must NOT be counted
```

| Case | Kind | Covers | Proof |
|---|---|---|---|
| `check 142` against the fixture, patched script | positive | AC1 | exit 1, "TAKEN" |
| `next` against the fixture, patched script | positive | AC2 | prints a number > 150 (the highest nested number), not > 141 (the top-level-only max) |
| `check 141` against the fixture (duplicate already visible today) | KEEP control | AC3 | exit 1, unchanged from pre-fix behavior (this case never needed the fix) |
| `check 142` / `check 145` against the fixture, PRE-fix script body | negative control (must reproduce the reported bug) | AC4 | exit 0, "free" -- proves the bug exists before the fix, on the same fixture the positive case uses |
| `next` against the fixture, PRE-fix script body | negative control | AC4 | mints 143 or 146 (colliding with an already-committed nested spec), not 151 |
| `check 999` against the fixture, patched script | negative control (decoy must not count) | AC6 | exit 0, "free" -- `node_modules/docs/specs/SPEC-999-decoy.md` is pruned |
| A second fixture nested under `.claude/worktrees/sibling/` with its own `docs/specs/SPEC-200-x.md`, scanned from the PARENT worktree | positive + prune check | AC6 | SPEC-200 is still seen overall (because the per-worktree loop visits the sibling directly, `:96-98` unchanged), and a `find`-call-count assertion shows the parent worktree's recursive find did not descend into the sibling's subtree a second time |
| Stub `gh` (extending `tests/test-spec-next-pr-scan.sh:mk_stub_gh`) whose `git/trees?recursive=1` response lists `tools/x/docs/specs/SPEC-160-y.md` | positive | AC5 | `next` prints > 160 |
| Stub `gh` whose `git/trees` call fails (404 or malformed) for one PR head, another PR head's call succeeds | negative control (fail-soft per-head) | AC5 | the failing head is skipped silently (no stderr note per the existing "not every PR touches specs" contract), the succeeding head's numbers still fold in |
| `gh` absent from PATH entirely | KEEP control | AC7 | unchanged from `tests/test-spec-next-pr-scan.sh` T4: local-only fallback, one stderr note |
| Full existing suites (`test-spec-reserve.sh`, `test-spec-next-pr-scan.sh`, `test-meta.sh`) | regression | AC7 | all green, no fixture in those files touches a nested dir, so their expected outputs are unchanged |

Dry trace for the key negative control (AC4): today's `_scan_numbers` runs `ls
"$wt/docs/specs"` (`:97`), which on the fixture repo returns only `SPEC-100` and
`SPEC-141` (the two files physically inside `docs/specs/`); `SPEC-142`, `SPEC-145`,
and `SPEC-150` never appear in its output because `ls` does not descend into
`tools/circle/`, `tools/vps-mon/`, or `experiments/foo-bar/`. `check 142` therefore
finds no match and reports free. After TASK-1, the same fixture's recursive find
visits all four `docs/specs` directories, `check 142` finds the file and reports
TAKEN, and `next` returns 151.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `find` walks an enormous `node_modules` or `vendor` tree looking for a `docs/specs` name that will never appear there, slowing `next`/`check`/`reserve` | a slow local run on a real repo; the `node_modules` prune in TASK-1 is the fix, not a fallback | prune is a hard predicate (`-prune`), not a soft filter, so a big pruned tree costs one `stat`, not a full walk |
| A repo names its nested spec tier something other than `docs/specs` (e.g. `spec/` singular) | such a repo's specs stay invisible to this scan, same as today | out of scope (see Non-goals); no repo surveyed uses a different name, and this spec does not invent a mapping for one that might |
| Git Trees API response for a very large repo is paginated or truncated (`git/trees` has a size cap around 100k entries) | `gh api` would return a `truncated: true` field or a short list; not directly tested here (no ops-toolkit-sized PR head fixture exists in this kit's test suite) | fails soft the same way an empty/failed call does today: fewer numbers seen than exist is the SAME class of risk `_scan_pr_numbers` already accepts (a PR with no `docs/specs/` 404s silently); flagged here, not fixed, since the existing design already treats this scan as best-effort, never authoritative (the reservation ledger is the authoritative concurrency guard, per Root cause) |
| A sibling worktree lives OUTSIDE the convention path (`<repo>/.claude/worktrees/<name>`), so the prune-by-worktree-list still finds it (worktree paths come from `git worktree list`, not a hardcoded `.claude/worktrees` string) | none needed; the prune list is built from `git worktree list --porcelain` output, which is authoritative regardless of where a worktree physically lives | no mitigation needed, this is already handled by construction |
| A duplicate spec number that exists in BOTH `docs/specs/` and a nested dir, where the two names disagree (e.g. `SPEC-142-a.md` and `SPEC-142-b.md`) | `_scan_numbers` still emits `SPEC-142` twice, deduped by the existing `sort -n \| uniq`; the tool reports the NUMBER as taken, never picks a "correct" file | unchanged from today's behavior for the already-visible SPEC-141/SPEC-134 duplicates; this spec reports the shape, it does not adjudicate which file is canonical (Non-goals) |

## Out of Scope

- Renumbering or merging any existing duplicate spec file (SPEC-141, SPEC-143,
  SPEC-134, or any future one this scan newly surfaces).
- A configurable glob/pattern list for repos naming their nested tier something
  other than `docs/specs`.
- Any change to `_reservations()`, `_prune_reservations()`, the mkdir-mutex, or the
  reservation ledger file format.
- Pagination/truncation handling for a Git Trees API response beyond the existing
  fail-soft contract.
- ops-toolkit itself: this spec fixes the kit's own `spec-next.sh`; it does not
  touch, open a PR against, or renumber anything in ops-toolkit.

## Touches

Single files: `lib/spec/spec-next.sh`, `tests/test-spec-next-nested-dirs.sh` (new).

No shared-file conflict expected with any in-flight sibling spec (checked: no other
`docs/specs/SPEC-*.md` in this repo currently lists `lib/spec/spec-next.sh` under its
own `## Touches`).

## Decision Log

- DEC-1: Recursive `find` matching any `*/docs/specs` directory path, not a
  maintained glob list (Non-goals: simplicity, and it already covers every
  convention tier ops-toolkit uses today).
- DEC-2: Prune sibling worktree roots during the recursive find, even though
  `sort -n | uniq` would make the result correct without it, because the task
  explicitly calls for it and an unpruned walk is a real slowdown risk on a repo
  with several active worktrees.
- DEC-3: Fix `_scan_pr_numbers` in the same spec as `_scan_numbers`, since both are
  the identical root-cause shape (one hardcoded top-level path) feeding the same
  `_numbers()` union, rather than splitting into a second spec.
- DEC-4: The negative control runs the PRE-fix script body against the SAME fixture
  used for the positive case, rather than a separate "old behavior" fixture, so the
  before/after comparison is exact.

## Open questions

(none; root cause is grounded by direct file:line reading, reservation atomicity is
confirmed unaffected, and scope/non-goals were set by the operator's own task
framing)
