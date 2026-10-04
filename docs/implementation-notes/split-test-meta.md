# Implementation note: split test-meta.sh

Delta from `docs/specs/SPEC-389-split-test-meta.md` only; the spec carries the
area table and the design.

## Area choices (the parts the spec left open)

- `contract` holds `AGENTS_MD`/`ASSIGN_MD` users together (AGENTS.md operating
  layer, Freeform front door, Self-intro), so no variable had to move into the
  stub.
- `spec-depth` keeps the SPEC-357 T18 section because it consumes `fhas`,
  `SPEC_CMD_F`, `EXEC_CMD_F`, `WRAP_CMD_F`, `VALIDATE_CMD` defined mid-section
  in the depth-contract block. Keeping them in one suite avoids promoting those
  definitions to the shared stub.
- `docs-registry` is the grab-bag: doc projection pins, generated-file
  freshness (FEATURES.md, verification/implementation-notes logs), the SPEC/ADR
  numbering guard, and Task-type contracts (a classifier contract).

## run-all double-run fix

`tests/test-meta-agent.sh` predates the split and matches `test-meta-*.sh`, so
neither the runner nor run-all can use a bare glob. The runner declares
`# runner-suites: <stems>` and reads its own list; `tests/run-all.sh` expands a
`--changed` pick that names a `# runner:` file into that list (sibling glob as
fallback for runners without one, e.g. test-wrap.sh). The expansion sits in the
`--changed` PICKED block, before the glob loop, because `test-meta-*.sh` sorts
BEFORE `test-meta.sh` in glob order (`-` < `.`): an in-loop expansion would land
after the siblings were already evaluated and skipped. The `test-meta)` timeout
arm became `test-meta*)` so the area suites inherit the 900s ceiling.

## Caller updates

- `tests/test-break-it.sh` `META=` now points at
  `tests/test-meta-review-verifiers.sh`, the file holding `is_on_review_axis()`.
  Its T1-AC3 assert label still reads "extracted from tests/test-meta.sh"; left
  byte-identical per the no-label-change rule (the function now lives in a
  `test-meta-*` file, flag for the lead if the wording should follow).
- `lib/gate/verify-counts.sh` needed no edit: the runner prints the monolith's
  `Passed: N / N` summary line last.
- `docs/FEATURES.md` regenerated (`lib/registry/feature-registry.sh generate`):
  the Tests column resolves feature names inside test files, so the new suite
  filenames appear and `test-meta.sh` disappears. 56 rows touched, column-only.

## Shared-state findings

- Cross-section variables are all loop-locals except `PLUGIN_NAME`,
  `AGENTS_MD`, `ASSIGN_MD`, `fhas`, and the four `*_CMD*` paths, and each
  cluster lives inside one area suite (see above). The stub carries only the
  harness: `KIT_CONFIG_OPERATOR` export, counters, colors, `assert_eq`,
  `assert_true`.
- Temp state (`TMP_HOME`, `INPLACE_HOME`, `MERGE_HOME`) is created and removed
  inside single sections; suites are parallel-safe.

## Flaky / notable

- `test-meta-docs-registry.sh` wall time is ~160s, dominated by the
  feature-registry double-regen pin and the verification-log scans; it is the
  long pole of the runner's parallel schedule (~152s total vs ~5.5 min serial
  baseline on this host).
- No assert was found flaky; nothing needed a DECISIONS.md entry.
