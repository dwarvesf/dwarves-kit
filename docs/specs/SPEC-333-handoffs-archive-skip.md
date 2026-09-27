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

Measured on ops-toolkit: 11 of 16 "open handoffs" lines were actually under
`.claude/handoffs/archive/...` or `.claude/handoffs/.claude/session-state/...`, both already
consumed, not open work.

## Solution

Add two more `-not -path` clauses to the same `find` call: one for any `archive/` path
segment, one for any nested `.claude/` path segment under the scan roots. Update the header
comment above the filter to name all four exclusions. No change to `done/` or `_archive/`
handling, no change to the two scan roots (`_meta/handoffs`, `.claude/handoffs`), no change
to `handoff_liveness` or any other function.

### Approaches considered
1. **Rename/move the offending directories instead of changing the filter.** Rejected: this
   is a per-repo data fix, not a fix to the lister; a future repo can reintroduce either shape
   and the bug returns.
2. **Exclude by matching the literal `archive` or `.claude` component (`-not -path
   '*/archive/*'`, `-not -path '*/.claude/*'`), same style as the existing two clauses.**
   Chosen: minimal diff, same idiom the file already uses, no new dependency.

## Design
obvious: two more `-not -path` clauses appended to an existing `find`, plus a comment update.
No new component, no data-model change, no external integration.

## Contract

1. The `find` call in `cmd_list` gains two more `-not -path` clauses:
   `-not -path '*/archive/*'` and `-not -path '*/.claude/*'`, alongside the existing
   `-not -path '*/done/*' -not -path '*/_archive/*'`.
2. The comment immediately above the `find` call names all four exclusions (`done/`,
   `_archive/`, `archive/`, nested `.claude/`) instead of the current two.
3. A file that matches an excluded path is skipped identically to how `done/`/`_archive/`
   are skipped today: it never enters `files[]`, never gets an age/excerpt/liveness row, and
   never affects the "no handoffs" empty-result message.
4. A legitimate handoff whose path merely contains the substring `archive` or `.claude` as
   part of a longer segment name (e.g. `_meta/handoffs/archived-notes.md`,
   `_meta/handoffs/.clauded.md`) is unaffected: `-not -path '*/archive/*'` matches only a path
   SEGMENT exactly `archive` (bounded by `/` on both sides), not a substring inside a longer
   segment name, matching how the existing `*/done/*` clause already behaves.

## Out of scope

- Renaming or migrating any repo's existing `archive/` or `.claude/session-state/` content.
- Any change to `_meta/handoffs` or `.claude/handoffs` as the two scan roots.
- Any change to `handoff_liveness`, board loading, or the age/excerpt columns.

## Test plan

| # | Case | Expected |
|---|---|---|
| 1 | A handoff under `.claude/handoffs/archive/old.md` | excluded, not listed |
| 2 | A handoff under `_meta/handoffs/archive/old.md` | excluded, not listed |
| 3 | A stray nested `.claude/handoffs/.claude/session-state/foo.md` | excluded, not listed |
| 4 | A live handoff directly under `.claude/handoffs/live.md` | listed, unaffected |
| 5 | A live handoff directly under `_meta/handoffs/live.md` | listed, unaffected |
| 6 | Existing `done/` and `_archive/` fixtures (pre-existing test cases) | still excluded, unchanged |
| 7 | Only excluded files exist (all skipped) | "no handoffs" message, same as the pre-existing empty case |

## Tasks

- [ ] TASK-A: Add the two `-not -path` clauses to the `find` call in `cmd_list`
  (`lib/session/handoffs.sh`, around line 168) and update the comment above it to name all
  four exclusions.
- [ ] TASK-B: Extend `lib/session/tests/test-handoffs.sh` with one fixture per new case
  (1 to 3 above; 4 to 7 are already covered or trivially derived from the existing fixtures),
  asserting the archived/nested paths never appear in `cmd_list` output and the existing
  `done/`/`_archive/` and live-file assertions still pass.

## After state

- [ ] `bash lib/session/handoffs.sh list --repo <repo>` on a repo with `archive/` or nested
  `.claude/` handoff paths no longer reports them as open.
- [ ] `bash lib/session/tests/test-handoffs.sh` passes, covering all seven cases above.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] `bash lib/session/tests/test-handoffs.sh` covers the new archive/nested-`.claude/`
  cases and the pre-existing `done/`/`_archive/` cases, all green.
- [ ] Re-running the ops-toolkit measurement (`bash lib/session/handoffs.sh list --repo
  <ops-toolkit path>`) drops the 11 archived/nested lines from its output.

## Verification
`bash lib/session/tests/test-handoffs.sh`

## Negative control
Revert only the `find` clause change (keep the test file), re-run
`bash lib/session/tests/test-handoffs.sh`: the new archive/nested-`.claude/` cases must go
RED. Restore the clause, confirm GREEN again.

## Touches
- lib/session/handoffs.sh
- lib/session/tests/test-handoffs.sh

## Decision Log
- DEC-A: Match on the exact path segment (`*/archive/*`, `*/.claude/*`) rather than a
  substring match, so a legitimately named file containing "archive" or ".claude" in a longer
  segment name is not accidentally excluded. Same idiom as the existing `*/done/*` clause.

## Open questions
(none)
