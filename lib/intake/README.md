# intake

The scripted dedup gate for knowledge intake. It answers "have we already decided this?" in one run. Before it, several intake skills carried drifting prose copies of the same checklist, and a decided item came back in through another source.

**Entry points**
- `lib/intake/intake.sh gate <url | "subject">`: read every configured store and print one JSON object with the subject, each hit, and each skipped source. Exit 0 on any hit, 1 on none.
- `bin/intake` forwards to `lib/intake/intake.sh`.

Hit kinds are `url`, `board`, `verdict`, `owned`, `note`, and `pr`. A board hit also carries `row_kind` (`eval`, `skim`, or `other`), because a skim row must not close an eval. Each store is read through an operator config key. An empty key, a missing command, or a missing path is skipped and reported, and never fails the gate.

**Tests**: `bash tests/test-intake.sh`. The deferred-link sweep hook has its own suites: `tests/test-intake-sweep.sh` and `tests/test-intake-sweep-parity.sh`.

**Spec and docs**: `docs/implementation-notes/intake-gate.md`, `docs/verification/intake-gate.md`.
