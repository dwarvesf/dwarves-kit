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

## 2026-07-04 Linux-only mutex fail-open (CI on ubuntu caught what macOS masked)

**Context:** PR CI went RED on `test (ubuntu-latest)` while `macos-latest` passed. T2 (the CORE
20-way concurrency test) got 1 distinct instead of 20, and T9 (stale reclaim) failed with the
lock left held.
**Root cause:** `_lock_mtime_epoch` tried `stat -f %m` FIRST. On macOS that is the file mtime.
On **Linux** `stat -f` is `--file-system` format and `%m` is not a valid FS directive, so GNU
stat prints a NON-numeric token and EXITS 0 , the `|| stat -c %Y` fallback never fired. That
garbage fed the `lockage = now - mtime` age check, so every FRESH lock looked older-than-TTL and
every contender RECLAIMED a live sibling's lock , the mutex failed OPEN (all 20 read the same
max) and left the lock in an inconsistent held state. Pure `mkdir`/`cat`/`rmdir` are portable;
`stat` was the only platform-divergent call, which is why ONLY T2/T9 broke.
**Fix:** try GNU `stat -c %Y` FIRST, then BSD `stat -f %m`, and VALIDATE the result is a pure
integer (`case $v in *[!0-9]*) v="";; esac`). A non-numeric result becomes empty, and the caller
treats an unreadable mtime as not-yet-stale (waits rather than steals , safe by construction).
**Why macOS masked it:** on macOS `stat -c %Y` errors to stderr with empty stdout, so the code
always reached the correct `stat -f %m` , the bug was invisible without a Linux run.
**Regression tests:** T14 (a normal reserve FREES the lock, no held/owner leak) + T15 (a FRESH
non-stale foreign lock is RESPECTED, not stolen , the direct fail-open guard, `SPEC_RESERVE_MAX_TRIES`
env seam added to bound the spin for the test). Suite now 35/35 on macOS; CI confirms on Linux.
**Lesson:** `stat -f` vs `stat -c` is a classic BSD/GNU trap , `stat -f %m` is not portable and
silently returns garbage-with-exit-0 on Linux; always GNU-first + validate, or a `|| fallback`
that keys on exit code is defeated.
