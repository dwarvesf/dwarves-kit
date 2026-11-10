# Implementation notes -- queue-board-flip

Delta from the brief. Short decisions, each with the reason.

- Board path is `<repo>/_meta/BACKLOG.md`. The queue sees only slug, repo and pointer, so it cannot learn a custom `--board` path from the watcher. Both slug producers use the repo root, so the default holds.
- The row id comes from the slug (`<repo>__<ID>`). A hand-authored slug has no such suffix and flips nothing, silently. A board-shaped slug whose board or row is missing logs `BOARD FLIP FAILED` on stderr.
- The flip dirties the board in the checkout. That would have skipped the next row as `dirty tree`, gated it for writing the protected `_meta/BACKLOG.md`, and credited a dirty tree as progress. Each flip records the board's content hash in `<run-dir>/board-flips.tsv`; `_status_porcelain` hides the board line only while its content equals that hash. A run that edits the board changes the hash, so its write still gates. Persisted to a file so the next watcher tick benefits too.
- The reaper also flips the row when it writes `done` or `gated`. Without that, the dead-beat path leaves the same stale `queued` row this change fixes.
- The reaper needs the repo and the before-run snapshot, which only the conductor has. The conductor now writes `<slug>.launch` (repo, HEAD, branch tips, window-open time) before the window opens; `_beat_clear` removes it with the beat. No record (a run from before this change) keeps today's `gated`.
- The reaper always checks protected paths before `done`. The conductor checks only for an untrusted-path run, but the reaper cannot tell which kind died. Fail closed: a trusted run with a protected-path delta is gated.
- A REASON beside `EXIT_SIGNAL: true` stays `gated` in the reaper, matching the conductor. A dead beat without `EXIT_SIGNAL` stays `stalled` even with a delta.
- Row note: `queue <slug>: <verdict> (<reason>)`, with `|`, `[`, `]` stripped and capped at 160 chars, because the gated reason is pane text and the note lands in a markdown table cell.

Open question: the flip leaves an uncommitted board edit on the default branch of the main checkout. `kit_warn_default_branch` prints its usual warning. Someone still has to commit that edit.
