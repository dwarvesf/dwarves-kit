# telemetry

Where the kit writes its run data and how it reads it back. One resolver fixes the durable log root, so a plugin reinstall cannot wipe the corpus that feeds retros.

**Entry points**
- `lib/telemetry/kit-log-dir.sh`: source it for `kit_resolve_log_dir`, `kit_legacy_log_dir` and `kit_note_unmigrated`. It only resolves a path and never copies.
- `lib/telemetry/hook-log-dir.sh`: source it for `kit_hook_log_dir`, the `hooks/` subdir under the resolved root.
- `lib/telemetry/kit-migrate.sh`: run once by `install.sh` and `lib/adopt.sh`. It moves the legacy run corpus and hook logs into the durable root, without clobbering or deleting.
- `lib/telemetry/lane-telemetry.sh report|misfires|render|trace <rid>`: aggregate the run ledgers into per-lane totals, lane misfires, a routing diagram, or one run's story. It is advisory.
- `lib/telemetry/egress-fail.sh record <source> <reason>` and `summary [days]`: log a failed model call to `egress-failures.log` and print a one-line summary. Source it for `egress_fail`.

**Tests**: `lib/telemetry/tests/smoke.sh` covers the log-root resolver (`bash lib/telemetry/tests/smoke.sh`). The root suites are `tests/test-lane-telemetry.sh`, `tests/test-hook-log-dir.sh`, `tests/test-ledger-durability.sh` and `tests/test-egress-visible.sh`. Run one with `bash tests/run-all.sh --only lane-telemetry`.

**Spec and docs**: `docs/specs/SPEC-061-lane-telemetry.md`, `docs/specs/SPEC-062-telemetry-closure.md`, and `lib/telemetry/docs/proof-of-done.md`.
