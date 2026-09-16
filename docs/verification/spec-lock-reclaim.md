# spec-next reservation lock: dead-holder reclaim

`lib/spec/spec-next.sh` guards its reservation ledger with a mkdir mutex whose dir holds an `owner` file stamped `<pid>.<nonce>.<epoch>`. `_reserve_lock` reclaimed a held lock only when the dir's mtime exceeded `SPEC_RESERVE_TTL`, the 24-hour reservation TTL. A holder that died with the lock held therefore wedged every `reserve` on the machine for a full day: 600 spins, about 43 seconds, then `could not acquire lock after 600 tries`. The operator cleared one such lock by hand. The fix parses the pid out of the owner stamp and reclaims the lock at once when `kill -0` reports no such process, keeping the TTL path as the fallback for a lock whose owner file is missing or unparseable. A live holder is untouched, and a pid this user cannot signal (EPERM, another user) reads as alive. The same commit makes `reserve` and `next` reject arguments with exit 64, because `spec-next.sh reserve --help` used to ignore its argument and mint a real reservation.

## Green run

Command: `bash tests/test-spec-reserve.sh`
Exit: 0
Output: `Passed: 53 / 53` / `spec-reserve green.`
Verdict: PASS

Command: `bash tests/run-all.sh` (bare, diff-scoped plus the always-on lints)
Exit: 0
Output: `run-all: all 10 suites passed, 0 skipped for missing tooling`
Verdict: PASS

New cases in `tests/test-spec-reserve.sh`, each against a temp state dir via `SPEC_RESERVE_FILE`:

| Case | Plants | Asserts |
|---|---|---|
| T16 | lock dir + owner naming a dead pid, fresh mtime | reserve returns 006 on the first try, elapsed under 3s, ledger gains exactly one RESERVE line, lock freed |
| T17 | lock dir + owner naming a live `sleep 30` pid, `SPEC_RESERVE_MAX_TRIES=5` | reserve fails with `could not acquire lock`, exit 1, lock and owner stamp untouched, no ledger written |
| T18 | lock dir + empty owner file, fresh mtime | TTL path unchanged: reserve waits then fails, lock still held |
| T19 | a real ledger, then `reserve --help`, `reserve foo`, `next foo` | exit 64 each, usage on stderr, ledger byte-identical by `cksum` |

## Negative control

`git checkout origin/master -- lib/spec/spec-next.sh`, then `bash tests/test-spec-reserve.sh`. Exit 1, `Passed: 43 / 53`, `10 assertions failed`:

```
FAIL T16 reserve reclaims a dead holder's lock and claims (006) (want '006' got '')
FAIL T16 reclaim spun (49s >= 3s)
FAIL T16 the ledger gained exactly one RESERVE line (want '1' got '0')
FAIL T16 lock released after reserve (want 'free' got 'held')
FAIL T19 reserve --help exits 64 (missing 'rc=64' in: ...)
FAIL T19 reserve --help prints usage on stderr (missing 'usage: spec-next.sh reserve' in: ...)
FAIL T19 reserve foo exits 64 (missing 'rc=64' in: ...)
FAIL T19 reserve foo prints usage on stderr (missing 'usage: spec-next.sh reserve' in: ...)
FAIL T19 the ledger is byte-identical after both rejected calls (want '2782864173 70' got '3813415895 210')
FAIL T19 next also rejects an argument (missing 'rc=64' in: ...)
```

The 49-second spin and the ledger growing from 70 to 210 bytes are the two bugs measured directly. Restored with `git checkout HEAD -- lib/spec/spec-next.sh`; the suite returned to `Passed: 53 / 53`.

T17 and T18 pass on master as well, by design. They are regression guards that the reclaim did not widen into stealing a live or unreadable holder's lock, so master has nothing to fail.

## Not proven

- Only macOS was exercised. The pid parse and `kill -0` are POSIX, but no Linux run was made.
- Pid reuse is not covered: a dead holder whose pid the kernel has handed to an unrelated live process reads as alive and falls back to the TTL path, which is the safe direction and is untested.
- The EPERM case (a lock held by another user) was not staged; the comment states the behavior, no test pins it.
- The real operator lock at `~/.local/state/dwarves-kit/logs/spec-reservations.log.lock` was never touched; every case ran against a temp `SPEC_RESERVE_FILE`.
