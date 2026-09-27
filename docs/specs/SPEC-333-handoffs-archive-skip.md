# SPEC-333: handoffs.sh skips archive/ and nested .claude/

**Status:** VALIDATED
Lane: normal
Type: spec-feature / behavioral

## Problem

`lib/session/handoffs.sh cmd_list` builds its file list with a `find` filter (around line
168) that excludes only `*/done/*` and `*/_archive/*`:

```sh
find "$d" -type f -name '*.md' \
  -not -path '*/done/*' -not -path '*/_archive/*' 2>/dev/null
```

Two archived shapes slip past this filter and get reported as open handoffs:

1. A repo that archives under `archive/` (no leading underscore) instead of `_archive/`.
2. A stray nested `.claude/session-state/` directory living under `.claude/handoffs/`
   itself, which the `.claude/handoffs` scan root walks into.

Measured on ops-toolkit: several "open handoffs" lines were actually under
`.claude/handoffs/archive/...` or `.claude/handoffs/.claude/session-state/...`, both already
consumed, not open work. The count is a moving target as the repo's own handoffs churn, so
this spec does not pin an exact ops-toolkit figure; the fixture counts in `## Test plan` are
the ones the test asserts against.

`-not -path` also has a pre-existing bug this spec's fix corrects as a side effect: it matches
against the FULL path `find` prints for a given file, which includes `$d` itself (one of the
two scan roots, `_meta/handoffs` or `.claude/handoffs`) and everything above it up to the
filesystem root. When a repo is checked out under a path that already contains a `done`,
`_archive`, or (after a naive fix) `archive`/`.claude` segment, such as the estate's own
worktree convention `<repo>/.claude/worktrees/<name>/`, that segment shows up inside the full
path of every file under `$d`, so a plain glob match wipes the whole scan root, live handoffs
included.

## Solution

Replace the `-not -path` substring clauses with a `-prune` walk keyed on the exact directory
NAME of each node `find` visits at or below the start point, not a substring match anywhere in
the full path string. Update the two header-doc passages near the top of the file to name all
four exclusions. No change to the two scan roots (`_meta/handoffs`, `.claude/handoffs`), no
change to `handoff_liveness` or any other function.

### Approaches considered
1. **Rename/move the offending directories instead of changing the filter.** Rejected: this
   is a per-repo data fix, not a fix to the lister; a future repo can reintroduce either shape
   and the bug returns.
2. **Add two more `-not -path '*/archive/*'` / `-not -path '*/.claude/*'` clauses, same style
   as the existing two.** Rejected: `-not -path 'GLOB'` matches against the full path
   `find` prints, including everything in `$d` itself and above it. With `$d` =
   `<repo>/.claude/handoffs`, the glob `*/.claude/*` matches every file under that whole scan
   root, not just a nested `.claude/` subdirectory, so all live `.claude/handoffs` entries
   would vanish (verified: 14 of 14 lost on ops-toolkit before this fix). The same class of bug
   already existed for `done/`/`_archive/`: a repo checked out under a path containing either
   segment (for example this very worktree, under `.claude/worktrees/handoffs-archive-skip/`)
   would lose every handoff under `_meta/handoffs` too, live ones included, because that
   ancestor segment is part of the full path string every match is tested against.
3. **`-mindepth 1 \( -name done -o -name _archive -o -name archive -o -name .claude \)
   -type d -prune -o -type f -name '*.md' -print`.** Chosen: `-name` tests only the basename
   of the specific node `find` is currently visiting, never a substring of the full path, and
   `find` starting at `$d` never re-examines `$d`'s own ancestor path components as separate
   nodes at all (walking begins AT `$d`, not above it) , so a `.claude`, `archive`, `done`, or
   `_archive` segment sitting ABOVE `$d` in the checkout path is structurally outside what
   `-name` ever sees, independent of any flag. `-mindepth 1` adds one narrow extra guard on top
   of that: it stops `$d` itself (depth 0) from being tested by `-name`, for the edge case
   where a scan root's own basename happens to equal one of the four excluded names. Only a
   directory named exactly one of the four, found AT OR BELOW `$d` (depth >= 1), gets pruned.
   This also fixes the pre-existing ancestor bug for `done/` and `_archive/` as a side effect,
   not just the two new exclusions.

## Design
obvious: replace one `find` filter shape with a `-prune`-based walk plus a header-doc update.
No new component, no data-model change, no external integration.

## Contract

1. The `find` call in `cmd_list` becomes:
   ```sh
   find "$d" -mindepth 1 \( -name done -o -name _archive -o -name archive -o -name .claude \) \
     -type d -prune -o -type f -name '*.md' -print 2>/dev/null
   ```
   replacing the two `-not -path` clauses entirely (not appended alongside them).
2. `lib/session/handoffs.sh`'s two existing header-doc passages get updated to name all four
   exclusions, not just `done/`/`_archive/`:
   - Lines ~5-6 (currently "there is no archive/ship flow here, only a `done/` or `_archive/`
     convention a repo may use to mark one consumed") gain `archive/` and a nested `.claude/`
     as convention variants a repo may use.
   - Lines ~20-21 (currently "skipping anything under a done/ or _archive/ subdirectory") list
     all four: `done/`, `_archive/`, `archive/`, or a nested `.claude/`.
3. A file under a pruned directory is skipped identically to how `done/`/`_archive/` are
   skipped today: it never enters `files[]`, never gets an age/excerpt/liveness row, and
   never affects the "no handoffs" empty-result message.
4. The fix's protection for a scan root checked out under a `done`, `_archive`, `archive`, or
   `.claude` ANCESTOR (a path segment above `$d`, not a descendant of it) comes from `-name`
   matching only a visited node's own basename, never a substring of the full path; `find`
   never visits `$d`'s own ancestor components as nodes in the first place. `-mindepth 1` is a
   separate, narrower guard: it only stops `$d` itself (depth 0) from being tested by `-name`,
   for the degenerate case where a scan root's own basename equals one of the four excluded
   names (not the case for `_meta/handoffs` or `.claude/handoffs` today, both end in
   `handoffs`). This covers both scan roots checked out under a path like
   `<repo>/.claude/worktrees/<name>/`.
5. A legitimate handoff whose path merely contains the substring `archive` or `.claude` as
   part of a longer segment name (e.g. `_meta/handoffs/archived-notes.md`,
   `_meta/handoffs/.clauded.md`) is unaffected: `-name` matches the whole basename exactly,
   never a substring inside a longer name.

## Out of scope

- Renaming or migrating any repo's existing `archive/` or `.claude/session-state/` content.
- Any change to `_meta/handoffs` or `.claude/handoffs` as the two scan roots.
- Any change to `handoff_liveness`, board loading, or the age/excerpt columns.

## Test plan

Each case builds its OWN fresh `mktemp -d` fixture repo, never the shared `$REPO` the
pre-existing suite already uses: `$REPO` backs exact-count assertions in the pre-existing
tests (`[1]` "2 lines + count", `[4]` "2 open handoffs", `[6]` the `--days` count), and adding
files to it would change those counts. New fixtures below use their own repo variables so
every count asserted is local to that fixture, never a shared or moving number.

| # | Case | Fixture | Expected |
|---|---|---|---|
| 1 | `$ARCREPO/.claude/handoffs/archive/old.md` | `ARCREPO="$(mktemp -d)"` | excluded, not listed |
| 2 | `$ARCREPO/_meta/handoffs/archive/old.md` | same `$ARCREPO` | excluded, not listed |
| 3 | `$ARCREPO/.claude/handoffs/.claude/session-state/foo.md` | same `$ARCREPO` | excluded, not listed |
| 4 | `$ARCREPO/_meta/handoffs/_archive/old.md` (new `_archive` fixture; the pre-existing suite only covers `done/`) | same `$ARCREPO` | excluded, not listed |
| 5 | Live `$ARCREPO/.claude/handoffs/live.md` | same `$ARCREPO` | listed |
| 6 | Live `$ARCREPO/_meta/handoffs/live.md` | same `$ARCREPO` | listed |
| 7 | `$ARCREPO` count after cases 1 to 6 | same `$ARCREPO` | exactly 2 open handoffs (the two live files; cases 1 to 4 excluded) |
| 8 | Repo itself checked out under a `.claude/` ancestor: `CREPO="$(mktemp -d)/.claude/worktrees/x/repo"`, with live `$CREPO/_meta/handoffs/live.md` and live `$CREPO/.claude/handoffs/live.md` | `$CREPO` | both listed (proves the ancestor fix; see `## Negative control` for which half is decisive) |
| 9 | Only excluded files exist (a fixture repo with cases 1 to 4's paths and no live file) | fresh `$(mktemp -d)` | "no handoffs" message |

## After state

- [ ] `bash lib/session/handoffs.sh list --repo <repo>` on a repo with `archive/` or nested
  `.claude/` handoff paths no longer reports them as open, and still lists every live handoff
  under both scan roots, including when the repo itself is checked out under a `.claude/`
  ancestor path.
- [ ] `bash lib/session/tests/test-handoffs.sh` passes, covering all nine cases above.

## Acceptance Criteria (global)

- [ ] Every Contract item above holds under `bash lib/session/tests/test-handoffs.sh`.
- [ ] The suite asserts, from its own fixtures: every archived/nested path (cases 1 to 4) is
  absent from `cmd_list` output, AND every live path under `.claude/handoffs` and
  `_meta/handoffs` (cases 5, 6, and case 8's ancestor-path variant) is present, with an exact
  expected file count per fixture (case 7), not an external moving number.
- [ ] The fix must not merely reduce false positives while also dropping true positives: a
  test run where live counts silently went to zero would be a regression, not a pass, per
  case 8.

## Verification
`bash lib/session/tests/test-handoffs.sh`

## Negative control
Two reversions, each run against the full case 1 to 9 fixture set, each required to turn the
suite RED, then reverted back to confirm GREEN:

1. Revert the `find` clause back to the two `-not -path` clauses from before this spec (no
   `-prune`, no `-mindepth 1`). Cases 1 to 4 must fail (archived/nested paths reappear as
   listed).
2. Apply approach 2 from `## Solution` (`-not -path '*/archive/*' -not -path
   '*/.claude/*'` appended to the original two clauses, no `-prune`/`-mindepth`) instead of
   the chosen fix. The decisive assertion is case 8's `_meta/handoffs/live.md` entry going
   missing: `_meta/handoffs` is not itself named `.claude`, so its live file disappearing can
   only be explained by the ANCESTOR segment (`.claude/worktrees/x/repo` above `$CREPO`)
   leaking into the path match, which is the exact ancestor bug this spec fixes. (Case 8's
   `.claude/handoffs/live.md` half is expected to fail too under approach 2, but that failure
   is already explained by the scan root's own name and proves nothing new beyond what
   `## Solution` approach 2 already states.)

## Touches
- lib/session/handoffs.sh
- lib/session/tests/test-handoffs.sh

## Decision Log
- DEC-A: Prune on exact directory NAME (`-name ... -prune`), not a `-not -path`
  substring/glob match against the full path. Rationale: `-not -path` matches the full path
  `find` prints, which includes everything above the start point too, so a scan root whose own
  ancestor path contains an excluded segment name loses every descendant, live files included
  (verified for both the two new exclusions and, retroactively, the two original ones).
  `-name`-based pruning tests only each visited node's own basename, so an ancestor segment
  above the start point is never examined at all; `-mindepth 1` is kept as an additional,
  narrower guard against the start point's own basename matching, not the mechanism that makes
  ancestors safe.

## Open questions
(none)
