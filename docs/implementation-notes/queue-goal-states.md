# Delta: queue and goal state simplification

Decisions that are not in the worker brief.

## Queue terminal set

- `_verdict_is_terminal` in `lib/queue/queue.sh` is the one definition: `done` or `gated`. `error`, `stalled` and `skipped` stay retryable.
- `_journal_last_verdict` moved from `watch-board.sh` to `queue.sh` (the watcher sources it). `queue run` now reads the slug's LAST verdict, like the watcher, instead of "any done row or any gated no-delta row".
- Tradeoff: a `gated` row followed by a later non-terminal row (a human re-ran it by hand) is retryable again. The old any-row rule would have skipped it forever.
- Skip message changed from "already done or gated no-delta" to "already done or gated". The `already done` substring that tests grep is kept.

## Goal registry

- Removed the `status` subcommand and its usage text. `claim` no longer writes `status=`.
- `list` keeps its STATUS column so printed output is unchanged: it shows the record's own `status=` if an old record has one, else `running` (every record is live until `release`).
- Also fixed the subcommand list in `lib/goal/README.md`. It sits outside the named slice but documents the same removed verb.

## Goal drafts

- Chose derive-from-location. `/kit:assign` stops writing `status: drafted`; `archive` stops rewriting it; `list` prints `(drafted)` for every top-level draft, which is exactly what it printed before for every draft `/kit:assign` wrote.
- Old drafts with the line still list and archive without error. Their archived copy keeps whatever the line said (no rewrite); the `done/` directory is the truth.
- `list` still excludes `done/`, as before, so it never needed a "shipped" label.

## Open

- `commands/start.md` (outside the slice) still describes the draft list as `slug -> target_spec (status)`; the printed shape is unchanged, so it stays accurate.
