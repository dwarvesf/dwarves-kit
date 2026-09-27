# SPEC-333: handoffs.sh skips archive/ and nested .claude/

**Status:** DRAFT
Lane: tiny
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
against `$d` itself, not just descendants. `$d` is one of the two scan roots
(`_meta/handoffs`, `.claude/handoffs`). When a repo is checked out under a path that already
contains a `done`, `_archive`, or (after this fix) `archive`/`.claude` segment, such as the
estate's own worktree convention `<repo>/.claude/worktrees/<name>/`, every file under `$d`
matches `*/.claude/*` and the whole scan root goes empty, live handoffs included.

## Solution

Replace the `-not -path` substring clauses with a `-prune` walk keyed on the exact directory
NAME at each level below the start point, not a path substring match anywhere in the full
path. Update the header comment above the filter to name all four exclusions and the
start-point fix. No change to the two scan roots (`_meta/handoffs`, `.claude/handoffs`), no
change to `handoff_liveness` or any other function.

### Approaches considered
1. **Rename/move the offending directories instead of changing the filter.** Rejected: this
   is a per-repo data fix, not a fix to the lister; a future repo can reintroduce either shape
   and the bug returns.
2. **Add two more `-not -path '*/archive/*'` / `-not -path '*/.claude/*'` clauses, same style
   as the existing two.** Rejected: `-not -path 'GLOB'` matches against the full path
   `find` prints, including `$d` itself. With `$d` = `<repo>/.claude/handoffs`, the glob
   `*/.claude/*` matches every file under that whole scan root, not just a nested `.claude/`
   subdirectory, so all live `.claude/handoffs` entries would vanish (verified: 14 of 14 lost
   on ops-toolkit before this fix). The same class of bug already existed for `done/`/
   `_archive/`: a repo checked out under a path containing either segment (for example this
   very worktree, under `.claude/worktrees/handoffs-archive-skip/`) would lose every handoff
   under `_meta/handoffs` too, live ones included.
3. **`-mindepth 1 \( -name done -o -name _archive -o -name archive -o -name .claude \)
   -type d -prune -o -type f -name '*.md' -print`.** Chosen: `-name` matches only the
   directory's own basename at that path component, never a substring of the full path, and
   `-mindepth 1` means the start point `$d` itself is never tested against `-name`, so a scan
   root that happens to sit under a `.claude`, `archive`, `done`, or `_archive` ancestor is
   unaffected, only a directory named exactly one of those four found AT OR BELOW `$d`
   (depth >= 1) gets pruned. This also fixes the pre-existing ancestor bug for `done/` and
   `_archive/` as a side effect, not just the two new exclusions.

## Design
obvious: replace one `find` filter shape with a `-prune`-based walk plus a comment update.
No new component, no data-model change, no external integration.

## Contract

1. The `find` call in `cmd_list` becomes:
   ```sh
   find "$d" -mindepth 1 \( -name done -o -name _archive -o -name archive -o -name .claude \) \
     -type d -prune -o -type f -name '*.md' -print 2>/dev/null
   ```
   replacing the two `-not -path` clauses entirely (not appended alongside them).
2. The comment immediately above the `find` call names all four exclusions (`done/`,
   `_archive/`, `archive/`, nested `.claude/`) and states that pruning is keyed on the
   directory's own name at or below the start point, not a substring anywhere in the path, so
   the scan root's own ancestors never trigger it.
3. A file under a pruned directory is skipped identically to how `done/`/`_archive/` are
   skipped today: it never enters `files[]`, never gets an age/excerpt/liveness row, and
   never affects the "no handoffs" empty-result message.
4. A scan root (`$d`) whose own path contains a `done`, `_archive`, `archive`, or `.claude`
   segment ABOVE the start point (an ancestor, not a descendant) is unaffected: `-mindepth 1`
   means `$d` itself is never tested by `-name`, so descendants are still walked and listed
   normally. This covers both scan roots (`_meta/handoffs`, `.claude/handoffs`) checked out
   under a path like `<repo>/.claude/worktrees/<name>/`.
5. A legitimate handoff whose path merely contains the substring `archive` or `.claude` as
   part of a longer segment name (e.g. `_meta/handoffs/archived-notes.md`,
   `_meta/handoffs/.clauded.md`) is unaffected: `-name` matches the whole basename exactly,
   never a substring inside a longer name.

## Out of scope

- Renaming or migrating any repo's existing `archive/` or `.claude/session-state/` content.
- Any change to `_meta/handoffs` or `.claude/handoffs` as the two scan roots.
- Any change to `handoff_liveness`, board loading, or the age/excerpt columns.

## Test plan

Fixture repo root is `$REPO`, matching the existing `test-handoffs.sh` mktemp-based style.

| # | Case | Expected |
|---|---|---|
| 1 | `$REPO/.claude/handoffs/archive/old.md` | excluded, not listed |
| 2 | `$REPO/_meta/handoffs/archive/old.md` | excluded, not listed |
| 3 | `$REPO/.claude/handoffs/.claude/session-state/foo.md` | excluded, not listed |
| 4 | `$REPO/_meta/handoffs/_archive/old.md` (new `_archive` fixture; the pre-existing suite only covers `done/`) | excluded, not listed |
| 5 | Live `$REPO/.claude/handoffs/live.md` | listed |
| 6 | Live `$REPO/_meta/handoffs/live.md` | listed |
| 7 | Pre-existing `done/` fixture (`_meta/handoffs/done/decoy.md`) | excluded, unchanged |
| 8 | `$REPO` itself checked out under a parent path containing `.claude`, e.g. `<tmp>/.claude/worktrees/x/$REPO`; live files under both `_meta/handoffs/live.md` and `.claude/handoffs/live.md` | both listed (proves the start-point/ancestor fix) |
| 9 | Only excluded files exist across cases 1 to 4 (no live file) | "no handoffs" message |

Case 8 is the regression case for approach 2's bug: a naive `-not -path '*/.claude/*'` or
`-not -path '*/archive/*'` clause fails it because the ancestor path itself matches the glob.

## After state

- [ ] `bash lib/session/handoffs.sh list --repo <repo>` on a repo with `archive/` or nested
  `.claude/` handoff paths no longer reports them as open, and still lists every live handoff
  under both scan roots, including when the repo itself is checked out under a `.claude/`
  ancestor path.
- [ ] `bash lib/session/tests/test-handoffs.sh` passes, covering all nine cases above.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] `bash lib/session/tests/test-handoffs.sh` asserts, from its own fixtures: every
  archived/nested path (cases 1 to 4) is absent from `cmd_list` output, AND every live path
  under `.claude/handoffs` and `_meta/handoffs` (cases 5, 6, and case 8's ancestor-path
  variant) is present, with an exact expected file count per fixture, not an external
  moving number.
- [ ] The fix must not merely reduce false positives while also dropping true positives: a
  test run where live counts silently went to zero would be a regression, not a pass, per
  case 8.

## Verification
`bash lib/session/tests/test-handoffs.sh`

## Negative control
Two reversions, each run against the full case 1 to 9 fixture set, each required to turn the
suite RED, then reverted back to confirm GREEN:

1. Revert the `find` clause back to the two `-not -path` clauses from before this spec (no
   `-prune`, no `-mindepth 1`). Cases 1 to 3 must fail (archived/nested paths reappear as
   listed).
2. Apply approach 2 from `## Solution` (`-not -path '*/archive/*' -not -path
   '*/.claude/*'` appended to the original two clauses, no `-prune`/`-mindepth`) instead of
   the chosen fix. Case 8 must fail: the live file under `.claude/handoffs/live.md` when the
   repo sits under a `.claude/` ancestor must disappear from the listing, proving the test
   suite catches the exact bug the validator flagged, not just the two new exclusions.

## Touches
- lib/session/handoffs.sh
- lib/session/tests/test-handoffs.sh

## Decision Log
- DEC-A: Prune on exact directory NAME at or below the start point (`-mindepth 1` +
  `-name ... -prune`), not a `-not -path` substring/glob match against the full path.
  Rationale: `-not -path` matches the full path `find` prints, including the start point
  itself, so a scan root whose own ancestor path contains an excluded segment name loses
  every descendant, live files included (verified for both the two new exclusions and,
  retroactively, the two original ones). `-prune` with `-mindepth 1` scopes the match to
  descendants only.

## Open questions
(none)
