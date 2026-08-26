# ID-482: autonomous backlog-row reader, verdict

## Claim
Does any skill / agent / loop autonomously read backlog rows (the
kanban-worker / synthesizer / orchestrator concern)?

## Verdict: CONFIRMED, and it is governed

No file is literally named `kanban-worker`, `synthesizer`, or `orchestrator`
(the 2026-08-21 `find skills agents` premise re-confirmed empty). But a
functional equivalent exists and runs autonomously:

`lib/queue/watch-board.sh` (SPEC-217 "self-grill-watcher", the orchestration-loop
pilot). It scans `<repo>/_meta/BACKLOG.md` for `queued` rows the operator marked
`#auto` and feeds them to the shipped queue launcher in the TSV contract.

## Why the intake is safe, not a bare read

A watcher-planned row is NOT operator-authored: it came from a free-text Notes
cell. `watch-board.sh` therefore applies the hardened pass on its OWN plan,
before any window can open:

| Control | Where |
|---|---|
| `#auto` marker, word-bounded (`#automation` does not match) | `_has_auto` |
| Allow-list: `#queue{repo=,pointer=}` token with charset / self-consistency / containment / existence checks | `parse-board.sh queue-rows` |
| **Symlink-aware** containment on the watcher's own plan (lexical parse-board misses a symlink planted inside an allow-listed dir) | `_pointer_allowlist_reason` |
| `--sanitize-prompt` (SPEC-223): the pointer body is untrusted text, sanitized before it feeds the typed `/goal` line | queue.sh sanitize |
| Re-pick gate: in-flight claim, quarantine, stall backoff, breaker cooldown | `_guard_skip_reason` |
| Dry-run default; `--apply` required to open any window; never a daemon | watch-board.sh |

## Relation to intake marking (ID-481)

The other intake path (backlog_sync) now tags foreign-spoke rows as untrusted at
ingestion (this same build, ID-481 / #427). Rows reaching the hub that a
`#auto` watcher later picks up therefore carry the untrusted marker AND run
through the sanitizer, defense-in-depth on the same free-text-NOTES surface.

## No new action

The autonomous reader exists by design, is `--apply`-gated and sanitized, and
never writes back to the board. Nothing to fix; recorded so the premise is
closed rather than re-derived.
