# Proof of done: runaway guards on the autonomous run queue (ID-460, SPEC-220)

2026-08-01. Acceptance: a run whose conductor dies gets a journal verdict on the next watcher
tick; a stalled row backs off and quarantines on the third stall; an explicit `EXIT_SIGNAL` always
outranks pane prose and a malformed one is never a completion. Lane: full. Spec:
`docs/specs/SPEC-220-runaway-guards.md`.

## Green run

Command: `bash tests/test-runaway-guards.sh`
Exit: 0
Output: `=== 44/44 passed, 0 failed ===`
Verdict: PASS. Three sections, one per mechanism, each carrying its own negative control.

Command: `bash tests/test-self-grill-watcher.sh` (regression: the watcher this branch extends)
Exit: 0
Output: `=== 38/38 passed, 0 failed ===`
Verdict: PASS. The shipped plan/skip behavior is unchanged when no sidecar exists.

Command: `bats tests/test-queue.bats` (regression: the conductor this branch extends)
Exit: 0
Output: 14/14 ok, including NC6 marker-wrap-false-positive and NC7 stalled-twice-stops-night
Verdict: PASS. No shipped completion-detection behavior moved.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 734 / 734`
Verdict: PASS. Includes the duplicate-SPEC-number guard and the `docs/FEATURES.md` freshness pin,
both of which went RED first and drove real fixes (see below).

Command: `bash tests/test-docs-wiring.sh`
Exit: 0
Output: `=== 22/22 passed ===`
Verdict: PASS.

Command: `bash lib/queue/watch-board.sh` (no flags, this repo's real `_meta/BACKLOG.md`)
Exit: 0
Output: `[watch] 0 rows to enqueue (0 skipped).`
Verdict: PASS. The honest real-board state: no row carries `#auto`, so the loop is armed by
nobody, and the reaper found no beat files to consume.

## Negative controls, one per mechanism

The load-bearing half. Each is the HEALTHY case that must NOT trip its guard.

| Mechanism | Negative control | Asserted result |
|---|---|---|
| Stale-window watchdog | a FRESH heartbeat (A2) | writes NO journal row, and the slug is refused a plan with `a run is in flight`, so a live run never gets a second window |
| Stale-window watchdog | a beat past STALE but before DEAD (A3) | warns `orphan: ...` and writes NO verdict; the conductor may be merely paused |
| Circuit breaker | a run reporting `FILES_CHANGED: 3` (B3) | four consecutive non-terminal runs, counter stays 0, never trips |
| Circuit breaker | a run that touched the repo tree (B4) | three consecutive runs, counter stays 0, never trips |
| Circuit breaker | a `done` verdict under a trip threshold of 1 (B6) | never rewritten to `error`; an investigate-and-report row changes no files legitimately |
| Exit gate | a malformed `EXIT_SIGNAL` against a `RUNNER_DONE` pane (C4) | `stalled`, reason `malformed_exit_signal`, never `done` |
| Exit gate | no status file at all (C5) | the shipped pane marker still yields `done`, byte-identical to today |

## Review round (two independent lenses, both dispatched on the finished diff)

A security lens and an architecture lens ran in parallel against the completed change. Both landed
on the SAME HIGH finding, from different directions.

**HIGH, fixed:** `_progress_evidence` returned one `yes` for all four hatches, and any `yes` zeroed
`stalls`. Hatches 2, 3, and 4 read `<slug>.status`, which the RUN writes about itself, so a run
emitting `FILES_CHANGED: 1` every attempt never accrued a stall, never backed off, and never
quarantined. The guard's central promise was opt-out by self-attestation. Fixed by splitting the
return into `verified` / `reported` / `freeze`: only a real repo delta clears the stall ladder.
Pinned by new tests B7 and B8, and proven by a second live revert-to-RED (below).

**MEDIUM, accepted as documented boundaries, not fixed:** a direct `queue run <tsv>` bypasses the
in-flight check (the plain TSV path is operator-authored, already the trust boundary per SPEC-148;
the spec's over-claiming "After state" line was narrowed instead), and sidecar writes are
unauthenticated against sibling sabotage (inside the existing same-user trust boundary, since every
launched session already runs `--dangerously-skip-permissions` as that user). Both now appear in
the spec's failure-modes table. Rationale in `docs/implementation-notes/runaway-guards.md`.

**LOW, fixed:** agent-controlled `REASON:` text now reaches the append-only journal, so it is
truncated at 500 characters.

## Revert-to-RED #2 (live, on the anti-self-attestation rule)

Mutation: let `reported` and `freeze` evidence zero the stall ladder again, in both the breaker and
the reaper, restoring the reviewed flaw.

RED output:
```
  FAIL B7: a self-reporting run STILL climbs the stall ladder (expected '4', got '0')
  FAIL B7: a self-reporting run is quarantined on the third stall anyway (expected '', got '1785519501')
  FAIL B7: self-attested progress cannot buy an exemption from quarantine
         -- got: [watch] skip ID-001: backing off until 1785519501
  PASS B8: a VERIFIED repo delta resets the stall ladder to zero
=== 41/44 passed, 3 failed ===
```

Exactly the three anti-self-attestation assertions failed. B8 stayed green, which is the right
shape: the mutation targets self-report handling and must not disturb verified evidence.

Restored output: `=== 44/44 passed, 0 failed ===`.

## Revert-to-RED #1 (live, on the exit gate)

The precedence rule is the spec's central claim, so it was broken on purpose to confirm the test
can see it.

Mutation: in `_launch_once`, let the `false` and `bad` branches fall through to the pane scan,
destroying "explicit signal outranks prose".

RED output:
```
--- Section C: the dual-condition exit gate ---
  PASS C1: explicit EXIT_SIGNAL true yields done with no pane marker
  PASS C2: EXIT_SIGNAL true + REASON yields gated
  PASS C2: the reason is carried through
  FAIL C3: explicit false beats a RUNNER_DONE pane (never done) (expected 'stalled', got 'done')
  FAIL C4 NC: a malformed EXIT_SIGNAL never yields done (expected 'stalled', got 'done')
  FAIL C4 NC: the verdict names the malformed signal (expected 'malformed_exit_signal', got '')
  PASS C5: no status file -> the pane marker still yields done
=== 35/38 passed, 3 failed ===
```

Exactly the three precedence assertions failed. C1 and C2 stayed green, which is the right shape:
the mutation does not touch explicit-`true` handling, so a test that had also gone RED there would
have been coupling, not coverage.

Restored output: `=== 38/38 passed, 0 failed ===`.

## Bugs the run actually caught

1. **`git -C "" ` reads the operator's current directory.** The reaper does not know which repo a
   slug ran against, so it passed an empty repo path to the progress check. `git -C ""` does not
   fail; it falls back to the cwd. The watcher's own dirty checkout was being counted as the
   stalled row's progress, resetting the stall counter and defeating quarantine outright. Caught
   by A4 (`the stall counter incremented` read 0 while the verdict itself was correct). Fixed by
   requiring a real directory before either git hatch runs.
2. **SPEC-218 was already taken.** `tests/test-meta.sh`'s duplicate-number guard went RED;
   renumbered to SPEC-220 per `lib/spec/spec-next.sh next`.
3. **`docs/FEATURES.md` went stale.** The generated projection needed a regenerate after the new
   spec landed; the freshness pin caught it.

## Reproduce

```
bash tests/test-runaway-guards.sh
bash tests/test-self-grill-watcher.sh
bats tests/test-queue.bats
bash tests/test-meta.sh && bash tests/test-docs-wiring.sh
```

Every case is hermetic: `KIT_LEDGER_DIR` points at a temp dir, so sidecars and the journal never
touch real machine state, and the mux is stubbed, so no window opens and no `claude` runs.
