# Implementation notes: validate by size

Delta from `docs/specs/SPEC-379-validate-by-size.md` only: decisions the spec did not make, deviations, and tradeoffs.

## Before the edits

- Helper lives in `lib/spec/spec-depth.sh` as a `size` verb, not in `spec.sh`, because `spec.sh` forwards and "adds NO new logic", and `spec-depth.sh` already owns the header reader and the Depth parse. `spec.sh depth size <spec>` works through the existing forward.
- Task count: checkbox lines `- [ ] TASK-...` or `- [x] TASK-...` outside fenced blocks, the convention in `commands/spec.md` and `spec-task-done.sh`. The spec table's `| T1 |` rows use a different shape; the verb counts both so a kit spec with a task table also counts.
- A spec with zero countable tasks reads LARGE. A malformed task list must not silently skip the round.
- Lane read from the header with the same regex `hooks/ship-gate.sh` uses (first word of the `Lane:` value).

## Decisions

- `size` prints `small|large tasks=N lane=L depth=D` and exits 0 for small, 1 for large, so the lead reads N for the override text and scripts can branch on the exit code.
- A large normal-lane spec that skips the round is now caught by nothing mechanical, because S3 drops `validate` from the normal-lane gate. The spec's Boundaries name this accepted cost.
- `design-record` needed an override too, because the full lane requires it and no Reviewer 6 ran. The spec's `## Design` section says `obvious`.
- Two `tests/test-hooks.sh` pins asserted that the normal lane requires `validate`. They now assert `lite` and absence from `required`. `NORMAL_GATES` in `test-lanes-data.sh` still records `validate`; extra records are harmless there.
- `docs/verification/lanes-as-data/baseline.txt` is untouched: `parity-after-flip` already tolerates changed normal-lane validate lines.
- `lib/gate/README.md` still says the lane gate parses the WORKFLOW matrix at runtime. That text predates the `kit.toml` lane data. Not touched here.
- Pre-existing failures on a clean origin/master export, unchanged here: `test-gate-opt-out`, `test-install-contract`, `test-research-arch-contract`.

## Review fixes

- The earlier note that a large normal-lane spec is caught by nothing mechanical is superseded: `hooks/ship-gate.sh` now blocks it. The hook reads the size verb's exit code and engages only on exit 1. A missing `spec.sh` or exit 2 (unreadable spec) fails open, matching the hook's other helper failures. The block message names the rule and prints the same `gate-ledger.sh override` hint as the lane-gate block.
- The hook reads the last `validate` GATE line by field (same awk as `commands/execute.md`), so a newer `skipped` from a failed validation still blocks.
- The counter now also counts the kit's own `T1` / `T2a` labels, which the review did not list. Reason: 28 of the 40 zero-task specs in `SPEC-3*` use them, so without them the size rule still read nearly every spec large. Counting more only pushes a spec toward large, the safe side. A spec that lists the same task as both a heading and a checkbox double counts for the same reason.
- An odd fence-line count means an unclosed fence; the counter then ignores fence state entirely. The cost is that a real fenced example in such a file is counted. Accepted, same safe side.
- A numbered test-plan table (`| 1 | case |`) is not counted as tasks: those rows are cases, not tasks.
- `hooks/codex-hooks.json` pins were stale for all five hooks before this change. Repinned with `lib/codex/repin.sh`.
- `tests/test-codex-hooks.sh` "complete feature push is allowed" is the test that shipped a normal-lane spec with no validate line. It now uses a one-task spec and a ledger with a `review` line.
