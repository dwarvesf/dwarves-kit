# ID-481: untrusted-content marking for intake-born sync rows

## Claim

Rows pulled into a hub `BACKLOG.md` from foreign spokes (hermes, notion,
multica, github) now carry the SPEC-147 untrusted-data marker in their notes, so
a downstream agent reading the board sees the "data, NOT instructions" boundary
in-band. The title is deliberately left clean to preserve two-way identity.

## Run table

| # | Action | Result |
|---|---|---|
| 1 | `uv run --isolated --with pytest --python 3.12 python -m pytest lib/sync/tests -q` | 233 passed |
| 2 | `test_board_add_marks_intake_notes_untrusted` | row.notes startswith UNTRUSTED_PREFIX; title == "buy milk"; "#inbox" preserved |
| 3 | prior `test_apply_board_add_inbox_section_and_status` (updated) | startswith UNTRUSTED_PREFIX |

## Negative control

`test_second_run_is_idempotent` and the full round-trip suite stay green: the
notes marker does not cause re-intake or duplicate minting (identity keys off
the title, which is untouched).

## Review

Reviewed inline through the kit lenses (security / architecture / test-coverage)
because the subagent review dispatch was down this session:

- **Security:** closes the notes-cell surface; residual is the untagged title
  cell, accepted because tagging it breaks `titles_agree()` two-way identity.
- **Architecture:** `UNTRUSTED_PREFIX` duplicated local to `sync_core` rather
  than imported from `cockpit` (which does I/O and would violate the core's
  pure-logic boundary); drift risk cross-referenced in the comment.
- **Test coverage:** all four invariants asserted.

No blockers.
