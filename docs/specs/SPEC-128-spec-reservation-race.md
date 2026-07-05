# Spec: Close the wavefront SPEC-number reservation race

Generated: 2026-07-04
Status: VALIDATED
Lane: full (touches `lib/spec/spec-next.sh` , the number source , plus `lib/queue/orchestrate.sh`'s
wavefront dispatch path and a new concurrency test; the atomic-claim property is
correctness-critical, so it earns the deep lane even though the diff is small).

## Problem

`lib/spec/spec-next.sh` (SPEC-064 / ID-052) already scans every VISIBLE surface for used SPEC
numbers , `docs/specs/` filenames, local + remote branch names, and `SPEC-NNN` mentions in
the last 200 commit subjects , and prints `max + 1`. That scan is correct: SPEC-064 closed
the STALE-branch case (SPEC-047 / SPEC-041 collided because a number aged inside an unmerged
branch that a naive `ls docs/specs | max` missed).

The remaining hole is CONCURRENCY, not staleness. A parallel wave (orchestrate.sh's
`_wave_run`, WAVE_CAP>1, or a hand-dispatched Agent-tool fan-out) spawns N worker sessions
at once. Each worker, at spec-time, calls `spec-next.sh next` BEFORE any of them has created
its branch or written its spec file. So all N scan the SAME surfaces, see the SAME max, and
get the SAME number. The scan is a source of truth for "already realized"; it has no notion
of "handed out but not yet realized". The reservation happens too LATE , at branch/spec
creation , when it needs to happen at hand-out.

This is the general orchestrate.sh path. (For a specific Agent-tool run the conductor can
pre-assign a contiguous block by hand , the belt , but that does not fix the general
wavefront path , the suspenders , which is this spec.)

## Solution

### Approaches considered

1. **An atomic reservation ledger consulted by `spec-next.sh`, claimed at wavefront
   dispatch.** Add a `spec-next.sh reserve` subcommand that, under a process-wide lock,
   computes the next free number (now folding a reservations file into the same scan) AND
   appends the reserved number to that file , one indivisible critical section, so two
   concurrent `reserve` calls serialize and get DISTINCT numbers. `_numbers()` folds the
   live reservations into its union, so a reserved number reads as TAKEN by the very next
   `next` / `check` / `reserve`. orchestrate.sh's `_wave_run` claims one number per admitted
   sub-goal at spawn time (before the branch exists) and injects it into the worker prompt.
   REUSE: the scan is untouched; the reservation is an ADDITIONAL surface it consults.
   CHOSEN.

2. **Conductor pre-assigns a contiguous number block, no code change.** Rejected as the
   general fix: it only works for a run the conductor drives by hand (the Agent-tool
   fan-out). orchestrate.sh's own `_wave_run` path has no conductor in the loop , it spawns
   workers itself , so the race survives. Pre-assign is the per-run BELT; this spec is the
   general SUSPENDERS. (Both are kept; they are different surfaces.)

3. **Rewrite the scanner to lock docs/specs and reserve by touching a spec file.** Rejected:
   creating a placeholder spec file per worker at hand-out pollutes `docs/specs/`, races on
   the filesystem the same way, and violates the "REUSE the scan, do not rewrite" bar.

### Chosen shape

`spec-next.sh` gains one subcommand (`reserve`) and folds a reservations surface into its
existing `_numbers()` union. Nothing about `next` / `check`'s output contract changes; with
an empty reservations file the behavior is byte-identical to today (this is what keeps the
SPEC-064 tests green). orchestrate.sh's wavefront spawn loop calls `reserve` once per
admitted sub-goal and hands the number to the worker.

## Design

### (a) The reservation surface + its path

A single append-only reservations ledger under the kit's durable log dir (the same root
`gate-ledger.sh` writes to, resolved via `lib/telemetry/kit-log-dir.sh`):

```
$(kit_resolve_log_dir)/spec-reservations.log
```

Each line is the kit's canonical additive-marker shape (mirrors gate-ledger's
`ISO8601 | MARKER | k=v`):

```
2026-07-04T09:15:03Z | RESERVE | num=128 repo=dwarves-kit
```

Repo-scoped (`repo=<basename of git toplevel>`) so a reservation in one repo never inflates
another repo's numbering , `spec-next.sh` scans `$ROOT/docs/specs`, which is already
repo-local, so the reservation surface must match that scope. The lock is a sibling
directory `spec-reservations.log.lock/` (see (b)).

### (b) The atomic-claim protocol (portable mutex, NOT flock)

**Deviation from the roadmap's literal "flock":** macOS ships no `flock(1)` (verified: absent
on PATH) and `lib/queue/orchestrate.sh` is explicitly bash-3.2 / no-flock by contract. The BINDING
property the roadmap names is "two concurrent claims serialize" via "a file + a lock, no
daemon". A `mkdir`-based mutex delivers exactly that and is strictly MORE portable than flock
(POSIX `mkdir` is atomic , exactly one of N racers creates the dir; the rest get EEXIST).

`reserve` critical section:

```
acquire:  until `mkdir "$LOCK"` succeeds, sleep a short randomized backoff (bounded retries,
          then fail loud); on acquire, `trap 'rmdir "$LOCK"' EXIT INT TERM` so a crash frees it.
          A lock older than a bounded TTL is treated as stale and reclaimed (a dead holder
          must not wedge the wave forever).
critical: n = next free number (via _numbers, which now includes live reservations)
          append "ISO | RESERVE | num=$n repo=$REPO" to the ledger
          prune dead reservation lines (realized OR expired) while holding the lock
release:  rmdir "$LOCK"  (also via the EXIT trap)
print:    $n
```

Because acquire -> compute -> append -> release is indivisible, two concurrent `reserve`
calls cannot both read the same max: the second blocks on the lock until the first has
appended, then sees the first's number as taken. This is the load-bearing property the
concurrency test proves.

### (c) Where the claim moves to in orchestrate.sh

In `_wave_run`'s spawn loop (the `while ... done < <(_wave_gate ...)` block), for each
admitted sub-goal, AFTER the worktree is stood up and BEFORE `_run_one_session` /
`_pane_spawn` is called (i.e. before the worker session can run `/kit:spec` ->
`spec-next next`), call `spec-next.sh reserve` and inject the reserved `SPEC-NNN` into the
worker prompt (a `RESERVED SPEC NUMBER` block, same injection site as the flip-contract
block already appended to `$pfile`). The worker is TOLD its number, so it does not race
`next` at all; even if it did, the reservation is already folded into the scan, so it would
skip the sibling numbers. The claim is best-effort: a `reserve` failure logs and falls back
to the worker computing its own number (degrade, never block the wave) , the reservation is
an optimization on top of a correct scan, not a new hard dependency.

### (d) Reconciliation once the branch/spec exists

A reservation is a bridge between "number handed out" and "number realized in a scannable
surface" (branch name / spec file / commit subject). Two prune rules, both applied inside the
`reserve` critical section (so pruning is itself serialized):

- **Realized:** a reservation whose `num` now appears in the real scan surfaces
  (`_scan_numbers`, the pre-reservation union) is redundant , the branch/spec now covers it ,
  and is dropped.
- **Expired:** a reservation older than `SPEC_RESERVE_TTL` (default 24h, env-overridable) is
  assumed abandoned (worker died before creating its branch) and is dropped, so a crashed
  worker cannot permanently inflate the max.

`_numbers()` folds in only LIVE reservations (repo-match AND within TTL), so an expired line
stops counting even before the next `reserve` physically prunes it. This keeps the ledger
bounded and self-healing without a daemon or a separate GC.

## Acceptance criteria

1. **Atomic distinctness:** N concurrent `spec-next.sh reserve` calls (background subshells)
   return N DISTINCT numbers, zero collisions.
2. **Reserved reads as taken:** after `reserve` returns NNN (before any branch/spec exists),
   `spec-next.sh check NNN` reports TAKEN and `spec-next.sh next` returns > NNN.
3. **Negative control:** N concurrent `spec-next.sh next` (the OLD, un-reserved path) DO
   collide (>=2 identical numbers) , proving the test harness can observe a collision.
4. **SPEC-064 contract intact:** with an EMPTY reservations ledger, `spec-next.sh next` and
   `spec-next.sh check <NNN>` behave byte-identically to before (existing surfaces still
   scanned; output + exit codes unchanged).
5. **Reconciliation:** a realized reservation (its number now in a branch/spec/commit) and an
   expired reservation (older than TTL) both stop counting toward the max.
6. **orchestrate wiring:** `_wave_run` calls `reserve` per admitted sub-goal before spawning
   it and injects the number into the worker prompt; a `reserve` failure degrades (logs,
   worker self-computes) rather than failing the wave.

## Verification

```
# Acceptance 1-5 (the spec-next mechanism):
bash tests/test-spec-reserve.sh

# Acceptance 4 (SPEC-064 contract regression) also covered by the existing suite:
bash tests/test-meta.sh 2>&1 | tail -5   # (spec-next is exercised there if pinned)

# Acceptance 6 (orchestrate wiring): a unit test in test-spec-reserve.sh drives the
# reserve-injection helper with a MOCK spec-next and asserts the prompt carries the number.
```

## Test plan

Coverage matrix (categories x cases), derived from the acceptance criteria:

| # | Category | Case | Asserts |
|---|---|---|---|
| T1 | Happy path | single `reserve` on empty ledger | returns 128 (max+1), appends one RESERVE line |
| T2 | Concurrency (core) | 20 parallel `reserve` | 20 distinct numbers, 0 dup (atomic claim) |
| T3 | Fold-in | `reserve` NNN then `check` NNN / `next` | NNN reads TAKEN; next > NNN (before branch) |
| T4 | Negative control | 20 parallel `next` (no reserve) | >=2 identical (harness CAN see a collision) |
| T5 | Contract regression | empty ledger `next` / `check` | byte-identical to pre-change output + exit |
| T6 | Reconcile / realized | reservation whose num is now a branch | dropped; does not double-count |
| T7 | Reconcile / expired | reservation older than TTL | not counted; pruned |
| T8 | Repo scope | reservation for repo A | does not inflate repo B's next |
| T9 | Lock crash-safety | holder dies leaving stale lock dir | next `reserve` reclaims after TTL |
| T10 | orchestrate wiring | reserve-inject helper w/ mock spec-next | prompt carries `SPEC-NNN`; failure degrades |

COVERAGE-DELTA (to be recorded post-build): covered = T1-T10 above; uncovered = a genuine
kernel-level simultaneity race (the test uses OS process scheduling + a shared barrier, which
is the strongest portable approximation, not a hardware-simultaneous claim); and the full
end-to-end `_wave_run` spawn under a real multi-pane tmux wave (covered structurally by the
mock-injection unit + the existing test-orchestrate-wavefront.sh, not re-run live here).

## Out of scope

- The conductor's manual pre-assign for a specific Agent-tool run (the belt; done outside the
  kit).
- Changing the SPEC-064 `next` / `check` output contract (reuse it).
- A daemon or a lock service (a file + a mutex dir only).
- A new numbering scheme.
