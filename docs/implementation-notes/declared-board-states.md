# declared-board-states: implementation notes

Spec: `docs/specs/SPEC-417-declared-board-states.md`. Brief: `docs/briefs/DECISION-BRIEF-declared-state-machines.md`. This file is the delta only.

## Decisions not in the spec

- `next` is advisory, never a guard. Legality stays class-based: any declared state from a non-terminal state; a move out of `terminal` prints a notice. Enforcing `next` would have refused sync, reconcile and writeback jumps that exist today.
- `parked` gets the class `hold`. Sync's sets treated it as neither active nor terminal; `hold` names that third kind explicitly. No reader's behavior changed: `hold` feeds no existing set.
- The reopen notice goes to stderr so stdout (`ID -> state`) stays byte-identical for callers that parse it.
- `board-health` imports `sync_core` through `sys.path` (parent dir) rather than reading the TSV itself, so Python has one loader.

## Left as is, with the reason

- `board.sh` priority/quadrant awk (in-flight = active minus `queued`) and `work.sh` jq (`claimed..shipped`): derived subsets, not the vocabulary. `board.sh` output is a pinned byte-identical render. Not worth: a later pass can feed them from `states --class`.
- `backlog.sh dedupe` priority `shipped dropped parked`: a tie-break policy, not the vocabulary.
- `board-mirror.sh _target_native` and `board-writeback.sh _reverse_native`: state MAPS to Hermes, not copies. They change only when the Hermes side changes.
- `sources/*` `COMPLETE_KWS` (`shipped done resolved`): the archive vocabulary, wider than the board's on purpose.

## Open questions for the operator

- Should the copy detector also cover `commands/` and `skills/` prose? Today it scans `lib/`, `hooks/`, `bin/` code only, because prose legitimately lists states.
