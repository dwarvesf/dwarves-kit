# Proof of done: batch-1 doc sweep and the no-op migrate calls

Acceptance: (1) the docs the batch-1 workers named say what the code does now (install-time migration, adopt seeding both gates, per-session slop marker, the egress log, the lane-lower line); (2) `docs/SYSTEM-DESIGN.md` is rev C and `docs/design/kit-uml.html` is rebuilt from it; (3) the seven load-time `kit_migrate_log_dir || true` calls are gone and every suite stays green.

## What changed

| Area | Change |
|---|---|
| Docs | MANUAL, architecture, consumer-contract, cosmetic README and SPEC-201, module-registry |
| System design | rev C: decided items, risks closed or accepted, drift row 15 FIXED, answered review questions replaced |
| Code | seven no-op `kit_migrate_log_dir || true` load calls removed; the shim stays for outside callers |
| Test | `lib/telemetry/tests/smoke.sh` migrated through `kit_migrate` (it was red on master after #1000) |

## Green run

| Suite | Command | Result |
|---|---|---|
| hard-claim registry | `bash tests/test-meta-hard-claims.sh` | 25/25 |
| docs and feature registry | `bash tests/test-meta-docs-registry.sh` | 120/120 |
| ledger durability | `bash tests/test-ledger-durability.sh` | 48/48 |
| hook log dir | `bash tests/test-hook-log-dir.sh` | 24/24 |
| telemetry smoke | `bash lib/telemetry/tests/smoke.sh` | 17/17 |
| board work view | `bash tests/test-board-work.sh` | 114/114 |
| changed-suite run | `bash tests/run-all.sh --changed` | 97 of 98 ok |

```
Command: bash lib/telemetry/tests/smoke.sh
Exit: 0
Output:
  ok: 6a POSITIVE CONTROL: a real legacy dir IS migrated (so 6b's refusal is falsifiable)
  ok: 6b the symlink target's contents are NOT copied into the corpus
  ok: 6c the refusal is announced on stderr
  ok: 6d the sentinel is dropped, so a hostile link is not re-scanned every command
  smoke: all 17 passed
Verdict: PASS
```

## Negative control

The smoke suite is the control. On master (branch changes stashed) it prints `smoke: 14 passed, 3 FAILED` (6a, 6c, 6d), because `kit_migrate_log_dir` no longer copies. With the suite pointed at `kit_migrate` it prints `smoke: all 17 passed`. The no-op call removal has no behavior to invert: the shim only printed the stderr note, and `ledger_root` and `kit_hook_log_dir` still print it (`tests/test-ledger-durability.sh` and `tests/test-hook-log-dir.sh` pin that).

One suite is red on master and is not touched by this branch: `tests/test-outcome-emit-sweep.sh` reports `ORPHAN: debug.md (debug)`; it fails the same way on master.

## Rollback

`git revert` the commit. No stored state, no migration, no config key changes.
