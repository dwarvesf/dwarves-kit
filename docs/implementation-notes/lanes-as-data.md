# Implementation notes: lanes as data (SPEC-368)

Decisions, deviations, and open questions that differ from the spec.

| # | Note |
|---|---|
| 1 | Premise check at build start: the cited lines in `gate-ledger.sh`, `kit-config.sh`, `gate-policy.sh`, `kit.toml` match the spec. |
| 2 | The ledger for rid `lanes-as-data` already held the spec-phase records; the builder appended a START line and a `build ran` line at the start, then an OUTCOME start bracket. The final `build ran` follows at the end. |
| 3 | A new file, `lib/gate/lane-data.sh`, holds the lane reader. The spec names `gate-ledger.sh` as the reader, but `lane-classify.sh` also needs the default lane and `extra_hard_paths`, and two copies of the committed-and-clean rule would drift. `lib/gate/**` is inside the Touches. |
| 4 | The reader reads each layer's file directly (`_kit_toml_get`) instead of `kit_config_get_root`, because the winning layer must supply both `phases` and `light` together. The last-dot fix in `kit-config.sh` is still shipped and covered by its selftest. |
| 5 | `tests/test-hooks.sh` and `tests/test-ledger-durability.sh` are not in the Touches list. Both pinned the old behavior (normal lists validate as lite, a normal ship needs only spec/build/ship, `check normal` with heavy text logs a downgrade). The pins now assert the new behavior; no assertion was weakened. |
| 6 | `parity` (byte-identical against the baseline) holds only at the refactor commit. The default test run uses `parity-after-flip`, which allows only normal `validate` and `review` lines to differ. |
| 7 | A backfill phrase plus a hard-gate subject used to return `full`. It now returns the default lane with the suggestion, since words never pick `full`. |
| 8 | `KIT_LANES_ONLY` was renamed `LANES_KIT_ONLY` so the env-var drift lint (seed prefix `KIT`) does not flag an internal variable. |
| 9 | Tasks 4 and 5 (classifier default and `floor` verb) landed in one commit; the code paths share `_path_kind` and split cleanly only by hunk. |
| 10 | Stale "take the heavier one" text remains in `docs/workflow-map.md`, `docs/guides/lanes.md`, and `examples/hello-spec/WORKFLOW.md`. They are outside the Touches list and outside AC21's four files. |
| 11 | `tests/test-config-registry.sh` AC1 (0 orphans) fails on master too: `HARVEST_STATE_DIR`, `HARVEST_SWEEP_CHILD`, `KIT_WRAP_CI_GRACE_SECS` are unregistered. Not caused by this change. |
