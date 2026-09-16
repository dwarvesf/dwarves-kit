# Cut four suites: one retired, two folded, one trimmed

The 2026-09-16 test-value audit (`docs/test-value-audit.md`) recommended four cuts and the operator approved them. `tests/test-reflect-propose-precision.sh` is retired: it printed a precision percentage from a 17-item synthetic sample and its own header called that sample too small to mean anything. `tests/test-advisor-ledger-emit.sh` folded into `tests/test-advisor.sh`, which already opens the same two files. `tests/test-references-field.sh` folded into `tests/test-design-record.sh`, which already owns the Reviewer 6 pure function that suite re-derived; 10 of its 15 assertions moved and 5 were dropped as exact duplicates (the host file already asserts Reviewers 1 to 5 present unchanged). `tests/test-multiplexer.sh` kept every assertion and lost its cost: 210 of its 220 seconds went to the real `lib/spec/spec-next.sh reserve` behind the `$SPEC_NEXT_CMD` seam, which nothing in that file asserts on, so the seam is now mocked. `docs/FEATURES.md` was regenerated because the registry greps `tests/*.sh` for feature tokens.

## Green run

Bare diff-scoped run plus the six always-on lints.

```
Command: bash tests/run-all.sh
Exit: 0
run-all: all 11 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Standalone run of each merged suite's new home.

```
Command: bash tests/test-advisor.sh
Exit: 0
=== 42/42 passed, 0 failed ===   (15 original + 27 folded)
Verdict: PASS
```

```
Command: bash tests/test-design-record.sh
Exit: 0
Passed: 36 / 36                  (26 original + 10 folded)
Verdict: PASS
```

```
Command: bash tests/test-multiplexer.sh
Exit: 0
ALL PASS                          (15 PASS lines, byte-identical to the pre-change list)
Verdict: PASS
```

## Negative control

Each fold below is a NEGATIVE CONTROL on the moved assertion: break the input it reads, see the new home go red, restore.

Advisor fold. Broke the emit grammar in the file the moved assertion reads, ran the new home, saw red, restored.

```
Command: sed -i '' 's|mode=P5 findings=<N> actor=|mode=BROKEN findings=<N> actor=|g' commands/review-team.md
Command: bash tests/test-advisor.sh
  FAIL AC1: review-team.md emit uses the mode=P5 findings=<N> actor= grammar
=== 41/42 passed, 1 failed ===
Command: git checkout -- commands/review-team.md
Command: bash tests/test-advisor.sh   -> exit 0
```

References fold. Broke the fixture the moved assertion reads, ran the new home, saw red, restored.

```
Command: sed -i '' 's|^References:|Refs-removed:|' tests/fixtures/references-field/with-references.md
Command: bash tests/test-design-record.sh
  FAIL fixture carries a 'References:' field (expected 'yes', got 'no')
Passed: 35 / 36
Command: git checkout -- tests/fixtures/references-field/with-references.md
Command: bash tests/test-design-record.sh   -> exit 0
```

Retirement. Nothing executes the retired file. `git grep` over tracked files finds `reflect-propose-precision` only in prose: `docs/test-value-audit.md`, `docs/verification/reflect-propose-precision.md` (the measurement's own record), and gauntlet transcripts. No lib script, test, hook, or workflow invokes it.

Multiplexer timing.

```
Command: /usr/bin/time -p bash tests/test-multiplexer.sh   (before)
real 220.66   ALL PASS
Command: /usr/bin/time -p bash tests/test-multiplexer.sh   (after)
real 5.43     ALL PASS
```

Where the time went: a `set -x` trace with `PS4='+[$SECONDS] ...'` inside `_wave_run` showed a single 42-second gap per dispatched sub-goal at `_wave_reserve_spec`, which shells out to the real `lib/spec/spec-next.sh reserve`. That call spins on a lock in the operator's own state dir and then gives up (`spec-next reserve: could not acquire lock after 600 tries`), so the suite paid 42 seconds per sub-goal for a reservation that failed anyway, five sub-goals across sections A, B and C. The suite asserts nothing about spec reservation (`tests/test-spec-reserve.sh` owns that contract), so `$SPEC_NEXT_CMD` now points at a mock that prints a fixed number. The PASS list is byte-identical before and after (`diff` of the `^PASS` lines: no output).

## Not proven

- The stale lock directory under the operator's state dir is untouched and still there. It is a pre-existing machine condition, not a repo change, and it was not diagnosed further.
- The mock makes `_wave_run` take the reservation-SUCCESS branch, where the unmocked run took the failure branch. No assertion in the suite reads either branch, so the change is invisible to the verdict, but the failure branch is no longer exercised here.
- The full `tests/run-all.sh --all` glob was not run; the recorded run is the bare diff-scoped selection plus the six always-on lints, which is what the push gate runs.
- The audit's seconds for the other suites were not re-measured.
