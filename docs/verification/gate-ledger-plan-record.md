# Proof of done: `gate-ledger.sh plan-record`

Branch `feat/gate-ledger-plan-record`, spec `docs/specs/SPEC-287-gate-ledger-plan-record.md`,
board row ID-877. Behavioral surface: a new `plan-record` verb in `lib/gate/gate-ledger.sh` that
disposes every phase of a lane's plan in one call and refuses without writing anything when the
disposition set is incomplete or invalid. Covered by `tests/test-gate-ledger-plan-record.sh`.

## Runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-gate-ledger-plan-record.sh` | 0 | PASS (`=== 35/35 passed ===`) |
| 2 | `bash tests/test-gate-ledger-history.sh` | 0 | PASS (`=== 9/9 passed, 0 failed ===`), the ledger's other readers unchanged |
| 3 | `bash tests/test-gate-ledger-report.sh` | 0 | PASS (`=== 8/8 passed, 0 failed ===`) |
| 4 | `bash tests/test-meta.sh` | 0 | `Passed: 851 / 852`, `Failed: 1`. The one failure is `sweep pin: zero gate-ledger rid call sites say spec-slug (expected '0', got '15')`, which greps `commands/`, `AGENTS.md`, and `docs/WORKFLOW.md`, none of which this branch touches. Pre-existing on `master`. |
| 5 | `bash lib/registry/feature-registry.sh generate` | 0 | regenerated `docs/FEATURES.md`; the freshness pin went green afterwards, and it had also been stale on `master` for the `test-command-triggers.sh` rows |
| 6 | `bash lib/gate/doc-projection-check.sh <worktree>` | 0 | no projection drift |

Run 4 was executed twice. The first pass failed the FEATURES freshness pin and its determinism
sibling; run 5 fixed both, and the re-run left only the pre-existing `spec-slug` sweep pin.

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-gate-ledger-plan-record.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/_plan_record_apply ) || rc=/true ) || rc=/' lib/gate/gate-ledger.sh
Changed: lib/gate/gate-ledger.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/gate-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Reproduce:

```bash
bash lib/gate/negctl.sh . "bash tests/test-gate-ledger-plan-record.sh" "sed -i '' 's/_plan_record_apply ) || rc=/true ) || rc=/' lib/gate/gate-ledger.sh"
```

The mutation replaces the dry-run replay with `true`, so the scratch pass no longer runs and its
exit code is never consulted. Argument-level refusals still fire during the parse, but the rules
`record()` and `override()` own are then discovered mid-write: a bad grill reason and a reused
override reason both leave a partial ledger, and the C8, C9, and C10 write-nothing assertions go
red. Restoring the file returns the suite to green in the same run.

## After the review fixes

| # | Command | Exit | Verdict |
|---|---|---|---|
| 5 | `bash tests/test-gate-ledger-plan-record.sh` | 0 | PASS (`=== 37/37 passed ===`, two cases added: start-then-plan-record happy path) |
| 6 | `bash lib/gate/gate-ledger.sh plan-record gate-ledger-plan-record full --skipped grill:... (13 dispositions)` | 0 | PASS, the live primary flow: 13 GATE lines written for this branch's own rid in one call; `check` then listed only `ship`, which the push records |
| 7 | same call, one phase (`review`) left out | 64 | PASS (refused before any write: `phases with no disposition: review`) |

Run 6 is the real flow on the real ledger, not a fixture: this branch's full-lane gates were
recorded by the verb it adds. Run 7 was the first attempt, before the reviewer lens had run.
