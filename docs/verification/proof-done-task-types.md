# Proof of done: SPEC-044 (proof-of-done task-type contracts)

Class: behavioral. Verified 2026-06-08. Three parts: a green real run, a negative
control, and reproducibility.

## GREEN (real run)

Command: `bash tests/test-meta.sh`
Exit: 0
VERDICT: PASS
Output excerpt:

```
=== Task-type contracts (SPEC-044) ===
  PASS lib/classify/task-type-classify.sh exists and is executable
  PASS classify -> eval
  PASS classify -> research
  PASS classify -> doc
  PASS classify -> migration
  PASS classify -> data-tool
  PASS classify default (neg control) -> spec-feature
  PASS task-type-classify types lists 6
  PASS registry has a row for 'eval' ... 'spec-feature'
  PASS proof-gate contract names the data-tool type
  PASS proof-gate contract names the recorded-run artifact + owning skill
  PASS proof-gate contract upgrades a migration to stateful (class wins on rigor)
=== Results ===
Passed: 389 / 389
All meta tests passed.
```

Primary flow (the feature itself), captured:

Command: `bash lib/classify/task-type-classify.sh classify "build a CLI to pull Growatt solar data from the API"`
Output: `data-tool`

Command: `bash lib/gate/proof-gate.sh contract "build a CLI to pull Growatt solar data from the API"`
Output:

```
type=data-tool class=behavioral
proof: recorded live run of the real commands (e.g. prove.py to docs/proof-of-done.md)
owner: ops-tool-shape Done gate
rigor: behavioral: run the REAL primary flow end-to-end ... include a negative control (revert -> RED -> restore).
```

Command: `bash lib/gate/proof-gate.sh contract "migrate the database schema to add a column"`
Output: `type=migration class=stateful` (the class still wins on rigor: a migration upgrades to stateful even though it is a distinct type).

## NEGATIVE CONTROL (revert -> RED -> restore)

Command: `mv lib/classify/task-type-classify.sh /tmp/ttc.bak && bash tests/test-meta.sh; mv /tmp/ttc.bak lib/classify/task-type-classify.sh`
Exit while reverted: 1

```
Passed: 379 / 389
Failed: 10
  FAIL lib/classify/task-type-classify.sh exists and is executable
  FAIL classify -> eval (expected 'eval', got '')
  ... every SPEC-044 pin failed (classify -> '', types -> 0, contract pins)
```

Restored: `bash tests/test-meta.sh` -> Exit 0, Passed 389/389. This proves the pins
measure the implementation, not a trivially-green check.

## Reproducible

Re-run `bash tests/test-meta.sh` (Exit 0). Re-run the `classify` / `contract` commands
above for identical output. Re-run the negative-control sequence to reproduce the RED.
