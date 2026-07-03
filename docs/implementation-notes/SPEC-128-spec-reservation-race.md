# Implementation notes , SPEC-128 spec-reservation-race

Delta from the spec. Reference SPEC-128 + the kit-run-integrity ROADMAP; do not restate them.

## 2026-07-04 mkdir-mutex instead of flock

**Context:** ROADMAP open-fork 1 + the sub-goal contract both say the reservation is claimed
"under `flock`".
**Decision:** use a POSIX `mkdir`-based mutex, not `flock`.
**Why:** `flock(1)` is absent on stock macOS (verified: not on PATH) and `lib/orchestrate.sh`
is explicitly bash-3.2 / no-flock by contract (its own comment at the wavefront primitive).
The binding property is "two concurrent claims serialize , a file + a lock, no daemon".
`mkdir` is atomic on POSIX (exactly one racer creates the dir), so a lock DIR delivers the
same mutual exclusion and is strictly more portable.
**Alternatives:** `flock` (rejected: not portable to the target host); `set -o noclobber` +
`>` (works but the mkdir form is the idiomatic shell mutex and carries an obvious stale-lock
reclaim path).
**Impact:** none to the contract's property; the spec's Design (b) documents the protocol.

## 2026-07-04 repo-scoped reservations

**Decision:** each reservation line carries `repo=<basename>` and the scan filters to the
current repo.
**Why:** `spec-next.sh` scans `$ROOT/docs/specs` (repo-local). A single global reservations
file shared across repos would make repo B skip numbers repo A reserved. Scoping keeps the
one-file-under-log-dir shape the contract asked for while staying correct across repos.
**Impact:** `_reservations()` greps `repo=$REPO`.
