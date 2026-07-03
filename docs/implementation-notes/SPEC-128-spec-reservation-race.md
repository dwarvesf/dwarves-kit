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

## 2026-07-04 concurrency-review fixes (fresh-context reviewer, 6/10 -> addressed)

A dispatched concurrency reviewer found two MAJOR holes the happy-path tests missed
(they simulate a DEAD holder, never a live-but-slow/signalled one). Fixed all four
actionable findings:

- **MAJOR #1 , stale-reclaim could drop a LIVE holder's lock.** The mkdir-mutex had no
  ownership token, so a TTL-stale reclaim (reachable via clock skew / suspend-resume across
  the TTL window mid-critical-section) could hand a live holder's lock to another process,
  and both could append the same number. Fix: stamp a per-acquire owner token
  (`pid.nonce.epoch`) into `$RES_LOCK/owner`; `reserve` RE-VALIDATES ownership after the scan
  and before the append (discards + retries, up to 5x, if it lost the lock); `_reserve_unlock`
  only removes a lock it still owns.
- **MAJOR #2 , `trap ... INT TERM` without `exit` resumed the critical section unprotected.**
  Bash runs a trapped-signal handler then RESUMES; the old single `trap ... EXIT INT TERM`
  released the lock but let `reserve` finish appending with the mutex already gone. Fix: split
  traps , `EXIT` cleans up; `INT`/`TERM` clean up AND `exit 130/143` so the process actually
  stops.
- **MEDIUM #3 , expired-prune was repo-scoped, so the machine-global ledger grew unbounded**
  across repos. Fix: EXPIRED lines are pruned for EVERY repo on any `reserve` (expiry is pure
  timestamp math); only the REALIZED check stays repo-scoped.
- **LOW #4 , unanchored `repo=$REPO` substring** matched `foo-bar` for repo `foo`. Fix:
  anchored end-of-line match (`repo=` is always the trailing field).
- **LOW #5 , `check()` TAKEN message changed even on an empty ledger** (AC4 says byte-identical).
  Fix: the reservation clause is appended only when `_reservations` is non-empty.

Regression tests added: T11 (cross-repo expired prune + foreign-live preserved), T12 (anchored
repo match), T13 (empty-ledger message byte-identical). Suite now 28/28.
