# Proof of done: lane-edit-vs-mention (SPEC-105 / ID-088)

`lib/lane-classify.sh` escalates a machinery-lib EDIT to `full`, not a mere MENTION, when
`--files` is supplied; text-only behavior is unchanged without it.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | `--files` with no `lib/`/`hooks/` path: a machinery MENTION does NOT escalate | PASS |
| 2 | `--files` with a `lib/`/`hooks/` path: a machinery EDIT DOES escalate to `full` | PASS |
| 3 | No `--files`: current text-only classification is UNCHANGED (regression guard) | PASS |
| 4 | Semantic hard-gates (`auth`) still `full` regardless of `--files` | PASS |
| 5 | `tests/test-lane-classify.sh` green on bash 5.x AND bash 3.2 | PASS |

## Implementation

- `lib/lane-classify.sh`: `--files` on `classify`/`explain`/`check`; `_extract_files` +
  `_files_touch_machinery` helpers; the `kit-machinery` branch of `classify_core`'s hard-gate uses
  the file signal when `--files` is set, else the legacy text match.
- 7 pins added to `tests/test-lane-classify.sh` (incl. the no-`--files` regression guard).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| mention | `classify --files "" "explain mega-merge.sh in the architecture doc"` | not full | `normal` (flags: none) |
| mention (doc edit) | `classify --files "docs/architecture.md" "document how gate-ledger.sh works"` | not full | `normal` |
| edit | `classify --files "lib/mega-merge.sh" "add a guard clause"` | `full` | `full` (flags: kit-machinery) |
| edit (hook) | `classify --files "hooks/ship-gate.sh" "tweak a message"` | `full` | `full` |
| test-only edit | `classify --files "tests/test-x.sh" "extend the lane-telemetry test fixtures"` | not full | `normal` |
| semantic auth | `classify --files "docs/x.md" "add user authentication with jwt sessions"` | `full` | `full` |
| no --files (legacy) | `classify "explain mega-merge.sh in the architecture doc"` | `full` (unchanged) | `full` (flags: kit-machinery) |
| suite | `bash tests/test-lane-classify.sh` (bash 5.x + 3.2) | 23/23 | 23/23 both |

## Run detail (captured 2026-07-02, via `explain`)

```
$ classify --files "" "explain mega-merge.sh in the architecture doc"
normal  (reason: bounded feature/fix (default); flags: none)          # mention suppressed

$ classify --files "lib/mega-merge.sh" "add a guard clause"
full    (reason: hard-gate flag(s): kit-machinery; flags: kit-machinery)   # edit escalates

$ classify "explain mega-merge.sh in the architecture doc"            # NO --files
full    (reason: hard-gate flag(s): kit-machinery; flags: kit-machinery)   # legacy text-only, unchanged
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-lane-classify.sh                 # the edit-vs-mention block + regression guard
/bin/bash tests/test-lane-classify.sh            # bash 3.2 parity (macos CI runner)
```

Negative controls: the no-`--files` regression pin proves text-only behavior is unchanged; the
semantic-`auth`-with-`--files` pin proves the discriminator is scoped to `kit-machinery` only.
