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

Operator decision (2026-09-28): replace name-based exclusion entirely with a **one-level
scan**. `cmd_list` lists only `*.md` files sitting DIRECTLY inside `_meta/handoffs/` and
`.claude/handoffs/`:

```sh
find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null
```

A file living in ANY subdirectory of either scan root, whatever that subdirectory is named,
counts as consumed/archived; no exclusion list of names is maintained anywhere. This also
eliminates the ancestor-path bug class as a structural side effect: `-maxdepth 1` never walks
below the immediate children of `$d`, and (unlike `-not -path`) never tests a substring of the
full printed path against anything, so a `done`, `_archive`, `archive`, or `.claude` segment
sitting ABOVE `$d` in the checkout path is never examined at all.

Update the two header-doc passages near the top of the file to describe the one-level rule
(not a list of excluded names), and reconcile the DEAD-verdict advice line to say a DEAD
handoff is deleted OR moved into any subdirectory, either marks it consumed.

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
   -type d -prune -o -type f -name '*.md' -print` (a name denylist pruned by exact directory
   name).** This was the FIRST fix picked for this spec, and it does correctly fix both the
   two named shapes and the ancestor bug (`-name` tests only a visited node's own basename,
   never a substring of the full path). Rejected on operator review: a name denylist breaks
   the next time a repo picks a fifth archive-folder convention (`superseded/`, `resolved/`,
   `old/`, anything not on the list), silently reporting those files as still-open again, the
   exact failure mode this spec exists to close. A subdirectory convention needs no list at
   all: any file not sitting directly in the scan root is, by construction, not a live
   top-level handoff. Verified before choosing approach 4: no repo under the operator workspace root
   keeps a live (unconsumed) handoff in a subdirectory of either scan root, so "any subdir
   means consumed" costs nothing today and is immune to every future naming choice.
4. **One-level scan: `find "$d" -maxdepth 1 -type f -name '*.md'`.** Chosen. No exclusion list
   to maintain, ever: depth alone decides open vs. consumed. Also fixes the ancestor bug as a
   structural side effect (see `## Solution` above), and is the simplest of the four -- one
   flag, no `-prune` branch, no name enumeration.

## Design
obvious: replace one `find` filter shape with a strict one-level (`-maxdepth 1`) scan plus a
header-doc update. No new component, no data-model change, no external integration.

## Contract

1. The `find` call in `cmd_list` becomes:
   ```sh
   find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null
   ```
   replacing the two `-not -path` clauses (and, in this worktree's history, the `-prune`/
   `-name` denylist that briefly replaced them) entirely.
2. `lib/session/handoffs.sh`'s two existing header-doc passages get updated to describe the
   one-level rule, not a list of excluded names:
   - Lines ~5-6 (currently naming a `done/`/`_archive/`/`archive/`/nested-`.claude/`
     convention) become: a file sitting directly in a scan root is open; a file moved into ANY
     subdirectory, whatever it is named, counts as consumed. No enumeration of names.
   - Lines ~20-21 (currently "skipping anything under a done/, _archive/, archive/, or nested
     .claude/ subdirectory") become: scans each root ONE LEVEL DEEP (no recursion); a file in
     any subdirectory is treated as consumed.
   - The DEAD-verdict advice line ("delete it") becomes "delete it or move it into any
     subdirectory, either marks it consumed".
3. A file sitting in any subdirectory of either scan root, whatever that subdirectory's name,
   is skipped: it never enters `files[]`, never gets an age/excerpt/liveness row, and never
   affects the "no handoffs" empty-result message. This holds regardless of the subdirectory's
   name, one level deep or many levels deep.
4. The fix's protection for a scan root checked out under a `done`, `_archive`, `archive`, or
   `.claude` ANCESTOR (a path segment above `$d`, not a descendant of it) is structural:
   `-maxdepth 1` never descends below `$d`'s immediate children and performs no substring match
   against the full path at all, so an ancestor segment above `$d` is never examined. This
   covers both scan roots checked out under a path like `<repo>/.claude/worktrees/<name>/`.
5. A legitimate handoff file whose OWN NAME merely contains the substring `archive` or
   `.claude` (e.g. `_meta/handoffs/archived-notes.md`, `_meta/handoffs/.clauded.md`) is
   unaffected as long as it sits directly in the scan root: `-maxdepth 1` only tests depth, and
   `-name '*.md'` only tests the `.md` suffix, neither inspects the file's own basename for a
   forbidden substring.
6. A handoff is one top-level `.md` file. A multi-file handoff bundle needs a top-level index
   `.md` that a reader (and this lister) can find directly in the scan root; any supporting
   file the bundle puts in a subdirectory is invisible to `cmd_list`, since subdirectories
   count as consumed by design. (The `handoff` skill that WRITES bundles is updated separately,
   outside this spec's touches.)

## Out of scope

- Renaming or migrating any repo's existing archived-subdirectory content.
- Any change to `_meta/handoffs` or `.claude/handoffs` as the two scan roots.
- Any change to `handoff_liveness`, board loading, or the age/excerpt columns.
- Maintaining or extending a name denylist anywhere in this file (rejected by design; see
  approach 3 above).

## Test plan

Each case builds its OWN fresh `mktemp -d` fixture repo, never the shared `$REPO` the
pre-existing suite already uses: `$REPO` backs exact-count assertions in the pre-existing
tests (`[1]` "2 lines + count", `[4]` "2 open handoffs", `[6]` the `--days` count), and adding
files to it would change those counts. New fixtures below use their own repo variables so
every count asserted is local to that fixture, never a shared or moving number.

| # | Case | Fixture | Expected |
|---|---|---|---|
| 1 | Pre-existing golden-path cases `[1]`-`[15]` (including the `done/` decoy under `$REPO`) | `$REPO` and its siblings, unchanged | still pass unmodified: a `done/` subdirectory is excluded because it is a subdirectory (depth-based), not because its name is on a list |
| 2 | An arbitrarily named subdirectory neither `done`/`_archive`/`archive`/`.claude`, e.g. `$ARCREPO/_meta/handoffs/old/x.md` | new `ARCREPO="$(mktemp -d)"` | excluded, not listed (proves the design is NOT a name denylist) |
| 3 | Repo itself checked out under a `done/` ancestor: `DREPO="$(mktemp -d)/done/repo"`, with live `$DREPO/_meta/handoffs/live.md` and live `$DREPO/.claude/handoffs/live.md` (both directly in the scan root, no subdirectory) | `$DREPO` | both listed, exact count 2 (the decisive NC1 case: the pre-SPEC-333 filter's `-not -path '*/done/*'` matches this ancestor segment and wipes both scan roots, since the printed path is `.../done/repo/_meta/handoffs/live.md`) |
| 4 | `archive/`, `_archive/`, and a nested `.claude/session-state/` under both scan roots (the shapes the original bug report named) | same `$ARCREPO` as case 2 | excluded, not listed |
| 5 | Live files sitting directly in `$ARCREPO/.claude/handoffs/live.md` and `$ARCREPO/_meta/handoffs/live.md` | same `$ARCREPO` | both listed, exact count 2 |
| 6 | Repo itself checked out under a `.claude/` ancestor: `CREPO="$(mktemp -d)/.claude/worktrees/x/repo"`, with live `$CREPO/_meta/handoffs/live.md` and live `$CREPO/.claude/handoffs/live.md` (both directly in the scan root, no subdirectory) | `$CREPO` | both listed, exact count 2 (proves the `.claude/` ancestor fix) |
| 7 | Only subdirectory-nested files exist (no top-level `.md` in either scan root) | fresh `$(mktemp -d)` | "no handoffs" message |

## After state

- [ ] `bash lib/session/handoffs.sh list --repo <repo>` on a repo with any archived-style
  subdirectory under either scan root, named anything at all, no longer reports its files as
  open, and still lists every live handoff sitting directly in either scan root, including
  when the repo itself is checked out under a `.claude/` OR `done/` ancestor path.
- [ ] `bash lib/session/tests/test-handoffs.sh` passes, covering the cases above.

## Acceptance Criteria (global)

- [ ] Every Contract item above holds under `bash lib/session/tests/test-handoffs.sh`.
- [ ] The suite asserts, from its own fixtures: a file in an arbitrarily-named subdirectory
  (not on any list) is excluded, proving the design has no denylist to bypass; every named
  shape from the original bug report (`archive/`, `_archive/`, nested `.claude/`) is also
  excluded; every live top-level file under both `.claude/handoffs` and `_meta/handoffs`,
  including the ancestor-path variant, is present with an exact expected file count.
- [ ] The fix must not merely reduce false positives while also dropping true positives: a
  test run where live counts silently went to zero would be a regression, not a pass.

## Verification
`bash lib/session/tests/test-handoffs.sh`

## Negative control
Two reversions, each run against the full fixture set, each required to turn the suite RED,
then reverted back to confirm GREEN:

1. **Revert to the pre-SPEC-333 `-not -path` filter** (`git show 194c89f0:lib/session/handoffs.sh`,
   the two-clause `done/`/`_archive/`-only filter that predates this spec entirely). Must go
   RED on the arbitrarily-named-subdirectory case (`old/x.md`), on the `archive/`/nested
   `.claude/` cases, AND specifically on the `done/`-ancestor case (test plan row 3): the old
   filter's `-not -path '*/done/*'` matches the ancestor segment in `$DREPO`'s own path and
   wipes both scan roots there, live files included, not just the four named shapes.
2. **Apply the rejected name-denylist approach** (approach 3 above; the `-prune`/`-name`
   filter this worktree's history briefly shipped as commit `359d8836`). Must go RED
   specifically on the arbitrarily-named-subdirectory case (`old/x.md`): `old` is not one of
   the four denylisted names, so a denylist-based fix reports that file as open, which is
   exactly the future-proofing gap this spec's operator decision exists to close.

## Touches
- lib/session/handoffs.sh
- lib/session/tests/test-handoffs.sh
- commands/start.md

## Decision Log
- DEC-A: Prune on exact directory NAME (`-name ... -prune`), not a `-not -path`
  substring/glob match against the full path. Rationale (superseded by DEC-B below): `-not
  -path` matches the full path `find` prints, which includes everything above the start point
  too, so a scan root whose own ancestor path contains an excluded segment name loses every
  descendant, live files included. Originally implemented as commit `359d8836`.
- DEC-B (operator override, 2026-09-28): Replace the name-denylist design (DEC-A) with a
  one-level (`-maxdepth 1`) scan. A denylist breaks the next time a repo archives into a new
  folder name; a subdirectory convention needs no list, and structurally also carries forward
  DEC-A's ancestor-path fix (a one-level scan never tests a substring of the full path either).
  Verified before this change: no repo under the operator workspace root keeps a live handoff in a
  subdirectory of either scan root. Consequence: a handoff is one top-level `.md` file; a
  multi-file bundle needs a top-level index `.md`, since a subdirectory counts as consumed
  regardless of its contents (Contract item 6). The `handoff` skill that writes bundles is
  updated separately, outside this spec's touches.

## Open questions
(none)
