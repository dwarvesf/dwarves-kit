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
