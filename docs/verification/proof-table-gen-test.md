# Verification: proof-table-gen test hermetic against the operator overlay

`tests/test-proof-table-gen.sh` T6 failed in the nightly run and passed on the operator machine. Not a regression from #883 to #888. The expected Covered/Uncovered gate sets depend on the lane data, and lane data layers the operator `kit.toml` over the kit root.

| Environment | Operator overlay | Required gates for `normal` | Uncovered for the fixture |
|---|---|---|---|
| Operator machine | `review` light on `normal` | spec, build, ship | `ship` |
| Nightly clone | none | spec, build, review, ship | `review, ship` |

Fix: the test pins `KIT_CONFIG_OPERATOR` to a dir with no `kit.toml`, and T6 now asserts the exact default set `Uncovered: review, ship` (stricter than the old `ship` substring).

## Green runs

Command: `bash tests/test-proof-table-gen.sh`
Exit: 0
Output (excerpt): `Passed: 25 / 25`
Verdict: PASS

Command: `KIT_CONFIG_OPERATOR=$(mktemp) bash tests/test-proof-table-gen.sh`
Exit: 0
Output (excerpt): `Passed: 25 / 25`
Verdict: PASS

Command: `git clone --depth 1 file://<worktree> <scratch>`, then `KIT_CONFIG_OPERATOR=$(mktemp) bash tests/test-proof-table-gen.sh` in the clone
Exit: 0
Output (excerpt): `Passed: 25 / 25`
Verdict: PASS

## Negative control

Command: test file restored to the pre-fix version (`git checkout HEAD~1 -- tests/test-proof-table-gen.sh`), then `KIT_CONFIG_OPERATOR=$(mktemp) bash tests/test-proof-table-gen.sh`, then restored.
Exit: 1
Output (excerpt): `Passed: 24 / 25` and `FAIL T6: coverage-delta names ship as uncovered (required, only skipped)`
Verdict: FAIL as expected, the unpinned test breaks without the overlay
