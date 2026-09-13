# SPEC-287: `gate-ledger.sh plan-record` writes a whole lane plan in one call

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Source:** the draft at `.claude/goals/gate-ledger-plan-record.md`. **Board:** ID-877. **Proof:** `docs/verification/gate-ledger-plan-record.md`.

## Problem

A run that followed its lane has to tell the ledger so, one gate at a time. A normal-lane prose
PR needed nine hand-typed `record` and `override` calls at the end of the session. Nine calls is
nine chances to mistype a phase key, and one forgotten phase blocks the push at the ship-gate
with a `MISSING-GATE` the operator then has to chase.

The phase list is already known: `plan <lane>` prints it, derived from the WORKFLOW lane matrix.
Nothing reads that list on the write side, so the operator retypes it by hand every time.

## Solution

One verb that takes the rid, the lane, and a disposition per phase:

```
gate-ledger.sh plan-record <rid> <lane> [--ran <phase>[:<reason>]]...
                                       [--skipped <phase>:<reason>]...
                                       [--override <phase>:<reason>]...
```

The phase list comes from `plan()`, so the lane table stays read in exactly one place. Each
disposition is written by the existing `record()` or `override()` function, so the GATE line
format, the grill-skip reason enum, and the distinct-override-reason guard keep applying with no
second copy of those rules. Every reader of the ledger sees lines it already parses.

### Refuse before write

A rejected call must leave the ledger byte-identical, because a partial ledger is worse than no
ledger: it reports gates that did not run and hides the ones still owed. Argument-level faults
(an off-plan phase, a phase given twice, a reason-less `--skipped` or `--override`, an undisposed
plan phase) are caught during the parse, before anything is written.

The rules `record()` and `override()` own cannot be caught that way without copying them here.
Instead the whole set is first replayed against a scratch ledger root seeded with a copy of this
rid's real log, then replayed for real only if that dry run was clean. The seed copy matters: the
override guard judges a duplicate reason against the run's history, so the dry run has to see
both that history and the overrides the same call adds.

### Which phases must be named

Every phase in the lane's plan, lite and intake ones included. Naming them all is the point: one
call that leaves `check` clean. `ship` is the one exception, since the push records it.

### What the exit code means

It answers whether the write happened, not whether the lane is complete. `check`'s verdict prints
after the written lines, so a run that deliberately leaves `ship` to the push still exits 0 on its
happy path. A refusal returns the underlying code: 64 for an argument fault or a bad grill reason,
65 for a reason already used on another gate.

## Wiring (one edit per surface)

| Surface | Edit |
|---|---|
| `lib/gate/gate-ledger.sh` | `_plan_record_apply`, `plan_record`, the dispatcher case, the usage string, the header comment block |
| `tests/test-gate-ledger-plan-record.sh` | twelve cases |
| `docs/CHANGELOG.md` | one `### Added` bullet |
| `_meta/BACKLOG.md` | ID-877 flipped to shipped |

## Non-goals

- No change to `record`, `override`, `check`, `descent`, `show`, or the GATE line format.
- No new ledger marker and no new reader.
- No lane table of its own; `plan()` stays the only parse of the WORKFLOW matrix.
- No partial write and no rollback path. The dry run is how a bad call never lands.

## Tasks

| # | Task | Where |
|---|---|---|
| 1 | Add `plan-record`, wire the dispatcher and the usage header, and cover it with a test suite | `lib/gate/gate-ledger.sh`, `tests/test-gate-ledger-plan-record.sh` |

## Acceptance criteria

- A full normal-lane call writes one GATE line per named phase and leaves `check normal <rid>` clean with no further calls.
- A required plan phase with no disposition exits 64 and writes nothing.
- A lite plan phase with no disposition exits 64 and writes nothing.
- A phase that is not in the lane's plan exits 64 and writes nothing.
- The same phase given twice exits 64 and writes nothing.
- `--skipped` or `--override` with no reason exits 64 and writes nothing.
- A grill skip whose reason is outside the enum is refused by the existing rule, and nothing lands.
- An override reason already used on another gate, in this call or an earlier one, exits 65 and leaves the prior ledger untouched.
- Omitting `ship` is accepted: the call exits 0, writes the other phases, and surfaces `check`'s open-gate line.
- An unknown lane refuses before any write.

## Verification

- `bash tests/test-gate-ledger-plan-record.sh` exits 0.
- `bash tests/test-gate-ledger-history.sh` and `bash tests/test-gate-ledger-report.sh` exit 0 (the ledger's other readers are unchanged).
- `bash tests/test-meta.sh` leaves no failure that does not already fail on `master`.
- `bash lib/gate/negctl.sh . "bash tests/test-gate-ledger-plan-record.sh" "sed -i '' 's/_plan_record_apply ) || rc=/true ) || rc=/' lib/gate/gate-ledger.sh"` reports PASS: with the dry run replaced by `true`, a call the two writers reject writes a partial ledger and the refuse-before-write cases go red.

## After state

- `gate-ledger.sh plan-record` disposes a whole lane plan in one call, and `check` passes afterwards.
- A refused call leaves the rid's ledger byte-identical, whether the fault was an argument or a rule `record()`/`override()` owns.
- Every other `gate-ledger.sh` verb, and `hooks/ship-gate.sh`, behave exactly as before.
