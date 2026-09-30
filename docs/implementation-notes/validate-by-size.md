# Implementation notes: validate by size

Delta from `docs/specs/SPEC-379-validate-by-size.md` only: decisions the spec did not make, deviations, and tradeoffs.

## Before the edits

- Helper lives in `lib/spec/spec-depth.sh` as a `size` verb, not in `spec.sh`, because `spec.sh` forwards and "adds NO new logic", and `spec-depth.sh` already owns the header reader and the Depth parse. `spec.sh depth size <spec>` works through the existing forward.
- Task count: checkbox lines `- [ ] TASK-...` or `- [x] TASK-...` outside fenced blocks, the convention in `commands/spec.md` and `spec-task-done.sh`. The spec table's `| T1 |` rows use a different shape; the verb counts both so a kit spec with a task table also counts.
- A spec with zero countable tasks reads LARGE. A malformed task list must not silently skip the round.
- Lane read from the header with the same regex `hooks/ship-gate.sh` uses (first word of the `Lane:` value).
