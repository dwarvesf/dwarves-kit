# spec-shipped-writer: delta from the brief

- `set` takes the state in any case and upper-cases it; only canonical states from `states.tsv` pass. Aliases (BUILT, SUPERSEDED, SHIPPED-PENDING) and unknown words exit 64.
- A header whose current state already equals the target, aliases included (`BUILT` and target VALIDATED), is a no-op. The file is untouched and decoration stays.
- A bold-wrapped header (`**Status: VALIDATED**`) keeps its closing stars. A `**Status:** X` label stays as is.
- CRLF line endings survive. Mode survives (`cp -p` onto the temp file, then `mv`). A file with no final newline gains one.
- The reopen notice reads `spec-status: <file> reopens from terminal '<from>' to '<to>'` on stderr, and the write still happens.
- /kit:ship Step 6 owns the flip, so Step 7b (goal draft archive) now sees a SHIPPED spec. Exit 1 from `set` is a warning there, never a stop.
- WORKFLOW.md has no hand-edit instruction for SHIPPED (its table already says ship ends with the spec SHIPPED), so it is unchanged. The edits went to spine.md and the MANUAL `/kit:ship` Writes line.
- The 164 stored VALIDATED specs are not rewritten. Backfill is a separate decision.
