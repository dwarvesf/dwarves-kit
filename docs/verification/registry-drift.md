# Proof of done: registry-drift

`tests/test-config-registry.sh` was red on master (57/59) with two drift failures:

- AC1 orphan `KIT_NARROW_PL`: a Perl program held in a shell variable in `bin/test-affected` (added by #927). The drift lint reads any `KIT_*` name as an env var. It is not one, so the variable is renamed `NARROW_PL`.
- AC10: `decide.backend` and `decide.points` are read with `kit_config_get_root` (`lib/wrap/wrap-flick.sh`, `lib/wrap/report-lint.sh`) but were missing from the Root-only keys table in `lib/config/module-registry.md`. Both rows added; the Doc column already called them root-only.

## Recorded run

Command: `bash tests/test-config-registry.sh`
Exit: 0
Verdict: PASS, 59/59.

Command: `bash tests/test-test-affected.sh; bash tests/test-test-affected-replay.sh`
Exit: 0
Verdict: PASS, the rename changes no selection.

Command: `bash lib/registry/feature-registry.sh check`
Exit: 0
Verdict: PASS, FEATURES.md fresh.

## Recorded run (negative control)

Command: pre-fix `lib/config/module-registry.md` restored from git into the tree, then `bash tests/test-config-registry.sh`
Exit: 1
Verdict: NEGATIVE CONTROL red as expected, 58/59 (AC10 fails on the two decide keys).

Command: `command cp -f <saved fixed copy> lib/config/module-registry.md; bash tests/test-config-registry.sh`
Exit: 0
Verdict: PASS, 59/59, tree clean.
