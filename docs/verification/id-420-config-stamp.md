# Proof of done: bench-plane config stamp (ID-420)

Date: 2026-08-11. Branch: `feat/id-420-config-stamp`.
Source: DECISION-BRIEF-bench-plane.md §1, "small write-plane diff, do FIRST".

## What shipped

`gate-ledger.sh config` (function `config_stamp`), a new additive `| CONFIG |` marker
mirroring the existing `| TOKENS |`/`| DEBT |`/`| MUTATION |` shape: `model`, `effort`,
`kit_version` (defaults to `$KIT_ROOT/VERSION`), `modules`, `lane`, `task_type`,
`suite_hash` (never invented, stays absent unless the caller passes it, per the brief's
"null for real work" contract), `session_id`, and an optional `phase=` (same idiom as
`tokens()`'s `phase=`) so one rid can carry a different `model=` per stage
("model-per-stage"). Purely additive: `check()`/`override()`/`descent()`/`_rows()` all
key on `$2` and never match `CONFIG`, so no existing reader changes behavior.

Files: `lib/gate/gate-ledger.sh`, `tests/test-config-stamp.sh`.

## Scope note

This diff adds the CAPABILITY (the ledger accepts and round-trips these dimensions). It
does not wire every existing caller (`/kit:assign`, `/kit:execute`, the future `bench`
runner) to actually call `config`, that is brief items #2/#3 (the matrix runner, ID-421),
consuming rows in their own right. The brief is explicit this stamping step should ship
alone first ("every unstamped day is comparison data lost forever").

## Green run

```
Command: bash tests/test-config-stamp.sh
=== config-stamp (ID-420 AC1-AC6) ===
  PASS AC1 model round-trips
  PASS AC1 effort round-trips
  PASS AC1 kit_version round-trips
  PASS AC1 modules round-trips
  PASS AC1 lane round-trips
  PASS AC1 task_type round-trips
  PASS AC1 suite_hash round-trips
  PASS AC1 session_id round-trips
  PASS AC2 kit_version defaults to VERSION file
  PASS AC3 suite_hash absent for real work (omitted by caller)
  PASS AC4 think stage stamped opus
  PASS AC4 build stage stamped sonnet
  PASS AC5 check() byte-identical with CONFIG present
  PASS AC5 descent() byte-identical with CONFIG present
  PASS AC5 progress() byte-identical with CONFIG present
  PASS AC5 _rows()/lane-telemetry byte-identical with CONFIG present
  PASS AC6 descent() unchanged by CONFIG via the real verb (additive property; negative-control target)

=== 17/17 passed, 0 failed ===
Exit: 0
```

No regression in the adjacent suites that share `gate-ledger.sh`:

| Suite | Result |
|---|---|
| `tests/test-gate-outcome.sh` | 22/22 passed |
| `tests/test-lane-telemetry.sh` | 25/25 passed |
| `tests/test-mutation-smoke.sh` | 32/32 passed |
| `tests/test-gate-vocab-recording.sh` | 20/20 passed |
| `tests/test-wave-rid-check.sh` | ALL PASS |

## Negative control (stash the fix, run the new test, restore)

```
Command: git stash push -- lib/gate/gate-ledger.sh && bash tests/test-config-stamp.sh
  PASS AC3 suite_hash absent for real work (omitted by caller)   <- trivially true, config never ran
  FAIL AC4 think stage stamped opus (got: (no ledger for 'c4'))
  FAIL AC4 build stage stamped sonnet (got: (no ledger for 'c4'))
  PASS AC5/AC6 (equivalence checks trivially hold when nothing changed)
=== 6/17 passed, 11 failed ===
```

Confirmed RED without the `config` subcommand (the `config` verb falls through to the
unknown-command branch, so every AC that reads the CONFIG line back fails). Restored via
`git stash pop`; re-ran `tests/test-config-stamp.sh`, 17/17 passed again.

## Rollback

`git revert <this commit>` removes `config_stamp` and its dispatch-table entry. No state,
no schema, no existing caller depends on it yet; the additive property means removal is
exactly as safe as the addition was.
