# Battery size gate

`/kit:battery` now runs `lib/gate/battery-gate.sh` before any dispatch. A small change prints `SKIP` and owes a proof of done instead of three fresh-context subagents. The lane classifier could not say "small", because `normal` is its default lane for every non-cosmetic change.

## Captured output: the incident that triggered this

The battery ran on a family-office change (one helper call swapped, one helper added, one test updated). Replayed on a throwaway clone pinned at that merge:

```
Command: lib/gate/battery-gate.sh <clone at 3692808> 6d602b2
Exit: 0
Output:
SKIP: small change (74 changed lines, 4 files); owe proof of done, not the battery
```

## Negative control

The size comparison replaced with `if false` in a temp copy of `lib/` and `tests/`:

```
Command: bash tests/test-battery-gate.sh   (temp copy, size check disabled)
Exit: 1
Output:
FAIL T4 got: RUN
2 FAIL
Result: RED as expected
```

The working tree was not touched.

## Green run

```
Command: bash tests/test-battery-gate.sh
Exit: 0
Output:
PASS T1 small diff -> SKIP, exit 0
PASS T2 large diff -> RUN
PASS T3 small diff on a hard path -> RUN
PASS T4 markdown + docs/verification growth does not flip SKIP
PASS T5 uncommitted working-tree lines count
PASS T6 BATTERY_SMALL_FLOOR overrides the default
PASS T7 [battery] size_floor in .kit.toml overrides the default
ALL PASS
Verdict: PASS
```

## Full suite

`bash tests/run-all.sh --all` stops on `test-stats-no-persist` (2 FAIL: `stats gate-yield did not run cleanly`). The same test fails the same way on master at 15427bc7 in the primary checkout, so it is a pre-existing failure, not this change. Every other suite test before it passed.

## Not proven

- The gate is advisory: it prints a line and exits 0. `/kit:battery` stops on `SKIP` because its command text says so, not because a hook enforces it.
- The 150-line floor is a judgment call. `BATTERY_SMALL_FLOOR` or `[battery] size_floor` in `.kit.toml` moves it.
