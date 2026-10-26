# gauntlet

Read-only statistics for the gauntlet run records. The convergence loop itself is the `kit:gauntlet` skill. This module only projects the record corpus under `docs/verification/gauntlet/` into one convergence table.

**Entry points**
- `lib/gauntlet/stats.sh`: scan the record directories, parse the verdict markers, row-verdict tables, and probe transcripts, and print the table. Run it from the kit root.
- `lib/gauntlet/stats.sh --write [--force]`: also write a dated snapshot next to the records. It refuses a same-day overwrite without `--force`, and never writes inside a record directory.

A malformed verdict marker is a loud error, not a skipped row.

**Tests**: `bash tests/test-gauntlet-proof-audit.sh` pins and runs `stats.sh`. Related: `tests/test-gauntlet-remote-key.sh`.

**Spec and docs**: `docs/patterns/gauntlet.md`, `commands/gauntlet.md`, `docs/specs/SPEC-240-gauntlet-stats.md`.
