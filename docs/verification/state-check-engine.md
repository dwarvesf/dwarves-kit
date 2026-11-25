# Verification -- state-check-engine

`board state-check` (`lib/board/state_check.py`) is the generic engine behind a consumer repo's state registry: it reads the repo's OWN TOML registry and reports, blocks or repairs drift in the state values stored in that repo's files. The proof below shows (1) the fixture suite on Python 3.12 and on the system Python 3.9, (2) a negative control, and (3) that the engine prints the same stdout, stderr and exit code as the repo-local checker it replaces, on a real consumer checkout and on planted drift. `$CONSUMER` is the consumer checkout, `$OLD` its repo-local checker, `$LEGACY_CMD` the command name that checker printed in its hints.

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Fixture suite, Python 3.12 | `bash tests/test-state-check.sh` | 124 run, 124 passed, 0 failed | PASS |
| 2 | Fixture suite, system Python 3.9 (no `tomllib`) | `PYTHON=/usr/bin/python3 bash tests/test-state-check.sh` | 124 run, 124 passed, 0 failed | PASS |
| 3 | Parity, real checkout, 3 modes x 6 ways to run the engine | harness below, section A | 18 SAME, 0 DIFF | PASS |
| 4 | Parity, planted drift, 15 scenarios on two identical copies | harness below, section B | 31 SAME, 1 DIFF (named below) | PASS |
| 5 | Negative control, one engine rule broken | see NEGATIVE CONTROL | 7 FAIL lines, restored | PASS |
| 6 | Narrow suites for the files the diff touches, one at a time | see Narrow suite runs | all green | PASS |

## Fixture suite
```
Command: bash tests/test-state-check.sh
Exit: 0
Output (tail):
    PASS 'strict-exit' case goes red when its rule is removed
    PASS 'mini-table-nesting' case goes red when its rule is removed
    PASS 'reader-closing-quote' case goes red when its rule is removed
    PASS 'mini-top-value' case goes red when its rule is removed
  
  == 124 run, 124 passed, 0 failed ==
Verdict: PASS
```

```
Command: PYTHON=/usr/bin/python3 bash tests/test-state-check.sh   (Python 3.9.6, no tomllib: the built-in TOML reader)
Exit: 0
Output (tail):
    PASS 'strict-exit' case goes red when its rule is removed
    PASS 'mini-table-nesting' case goes red when its rule is removed
    PASS 'reader-closing-quote' case goes red when its rule is removed
    PASS 'mini-top-value' case goes red when its rule is removed
  
  == 124 run, 124 passed, 0 failed ==
Verdict: PASS
```

The suite runs every rule twice (native `tomllib`, then `STATES_TOML=mini`), covers the argument and exit-code surface, compares the built-in reader to `tomllib` on the fixture registry, scans the engine and fixture for tenant names, and breaks 23 rules one at a time in a copy of the engine (Part 3, each line `case goes red when its rule is removed`).

## Parity with the repo-local checker

Read-only on `$CONSUMER` (nothing staged there; the planted cases use a copy). Per mode: run `$OLD` and the engine, then compare stdout, stderr and the exit code byte for byte.

```bash
# section A: real checkout; section B: the same plant applied to two identical git copies, old on one, new on the other
for mode in "--all" "--all --strict" "--staged"; do
  ( cd "$CONSUMER" && python3 "$OLD" $mode >old.out 2>old.err; echo $? >old.rc )
  ( cd "$CONSUMER" && STATES_PROG="$LEGACY_CMD" bash "$KIT/bin/board" state-check $mode >new.out 2>new.err; echo $? >new.rc )
  cmp old.out new.out && cmp old.err new.err && cmp old.rc new.rc && echo "SAME [$mode]"
done
```
The engine was also run as `python3.12`, `STATES_TOML=mini python3.12`, `/usr/bin/python3` (3.9), and `bin/board state-check --repo-root "$CONSUMER"` from another directory. `STATES_PROG` carries the legacy command name so the `--fix` hint and the internal-error prefix read as before.

```
Command: the harness above (every `cmp` is empty; a differing line would print as DIFF)
Exit: 0
Output:
  == A. real checkout, read-only (nothing staged: 0 paths)
  SAME  [--all] old (cwd root) vs old (STATES_ROOT) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all] old vs new python3.12 native (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all] old vs new python3.12 built-in TOML reader (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all] old vs new /usr/bin/python3 (3.9) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all] old vs new bin/board state-check (cwd root, no env) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all] old vs new bin/board state-check --repo-root (other cwd) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all --strict] old (cwd root) vs old (STATES_ROOT) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all --strict] old vs new python3.12 native (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all --strict] old vs new python3.12 built-in TOML reader (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all --strict] old vs new /usr/bin/python3 (3.9) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all --strict] old vs new bin/board state-check (cwd root, no env) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--all --strict] old vs new bin/board state-check --repo-root (other cwd) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  [--staged] old (cwd root) vs old (STATES_ROOT) (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  [--staged] old vs new python3.12 native (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  [--staged] old vs new python3.12 built-in TOML reader (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  [--staged] old vs new /usr/bin/python3 (3.9) (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  [--staged] old vs new bin/board state-check (cwd root, no env) (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  [--staged] old vs new bin/board state-check --repo-root (other cwd) (rc=0, stdout 0 lines, stderr 0 lines)
  == B. planted drift in two identical copies (old on one, new on the other)
  SAME  s01-undeclared [--staged] old vs new (3.12) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s01-undeclared [--staged] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s02-illegal-transition [--staged] old vs new (3.12) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s02-illegal-transition [--staged] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s03-projection-drift [--staged] old vs new (3.12) (rc=1, stdout 0 lines, stderr 4 lines)
  SAME  s03-projection-drift [--staged] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 0 lines, stderr 4 lines)
  SAME  s04-legacy-new [--staged] old vs new (3.12) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s04-legacy-new [--staged] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s05-past-verdict-row [--staged] old vs new (3.12) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s05-past-verdict-row [--staged] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 0 lines, stderr 3 lines)
  SAME  s06-escape-hatch [--staged] old vs new (3.12) (rc=0, stdout 0 lines, stderr 3 lines)
  SAME  s06-escape-hatch [--staged] old vs new (/usr/bin/python3 3.9) (rc=0, stdout 0 lines, stderr 3 lines)
  SAME  s07-nothing-staged [--staged] old vs new (3.12) (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  s07-nothing-staged [--staged] old vs new (/usr/bin/python3 3.9) (rc=0, stdout 0 lines, stderr 0 lines)
  SAME  s07b-base-all-strict [--all --strict] old vs new (3.12) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  s07b-base-all-strict [--all --strict] old vs new (/usr/bin/python3 3.9) (rc=0, stdout 12 lines, stderr 0 lines)
  SAME  s08-missing-registry [--staged] old vs new (3.12) (rc=2, stdout 0 lines, stderr 1 lines)
  SAME  s08-missing-registry [--staged] old vs new (/usr/bin/python3 3.9) (rc=2, stdout 0 lines, stderr 1 lines)
  SAME  s09-bad-registry [--all] old vs new (3.12) (rc=2, stdout 0 lines, stderr 1 lines)
    DIFF in err (s09-bad-registry [--all] old vs new (/usr/bin/python3 3.9))
  1c1
  < $LEGACY_CMD: internal error: TOMLDecodeError('Invalid value (at line 1, column 9)')
  ---
  > $LEGACY_CMD: internal error: TomlError('unsupported value: = true')
  DIFF  s09-bad-registry [--all] old vs new (/usr/bin/python3 3.9)
  SAME  s10-all-committed-undeclared [--all] old vs new (3.12) (rc=0, stdout 13 lines, stderr 0 lines)
  SAME  s10-all-committed-undeclared [--all] old vs new (/usr/bin/python3 3.9) (rc=0, stdout 13 lines, stderr 0 lines)
  SAME  s11-all-strict-committed-undeclared [--all --strict] old vs new (3.12) (rc=1, stdout 13 lines, stderr 0 lines)
  SAME  s11-all-strict-committed-undeclared [--all --strict] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 13 lines, stderr 0 lines)
  SAME  s12-all-strict-disk-drift [--all --strict] old vs new (3.12) (rc=1, stdout 13 lines, stderr 0 lines)
  SAME  s12-all-strict-disk-drift [--all --strict] old vs new (/usr/bin/python3 3.9) (rc=1, stdout 13 lines, stderr 0 lines)
  SAME  s13-fix-disk-drift [--fix] old vs new (3.12) (rc=0, stdout 1 lines, stderr 0 lines)
  SAME  s13-fix-disk-drift [--fix] old vs new (/usr/bin/python3 3.9) (rc=0, stdout 1 lines, stderr 0 lines)
  SAME  s13-fix-disk-drift: tree after the run is identical (diff -r, .git excluded)
  SAME  s14-fix-clean-noop [--fix] old vs new (3.12) (rc=0, stdout 1 lines, stderr 0 lines)
  SAME  s14-fix-clean-noop [--fix] old vs new (/usr/bin/python3 3.9) (rc=0, stdout 1 lines, stderr 0 lines)
  SAME  s14-fix-clean-noop: tree after the run is identical (diff -r, .git excluded)
  == total: 49 SAME, 1 DIFF
Verdict: PASS
```

Every planted scenario is non-vacuous: the blocking ones exit 1 with a banner on stderr (undeclared value, illegal transition, projection drift, newly written legacy value, edited past append-only row), the escape hatch exits 0 with the banner, a missing registry and an unparseable registry exit 2, `--all --strict` exits 1 on a committed undeclared value and on disk drift, and `--fix` leaves identical trees (`diff -r`, `.git` excluded). Section A is 18 SAME and section B 31 SAME with 1 DIFF; the 49 in the total is A plus B.

**The one DIFF.** An unparseable registry on Python 3.9: the old checker could not run there at all, and the engine exits 2 as before but its message reads `TomlError('unsupported value: ...')` instead of tomllib's `TOMLDecodeError(...)`. On Python 3.12 (native `tomllib`) the same scenario is SAME.

**Usage text.** Running with no mode flag exits 2 in both and prints the usage text; the engine's text names the command through `STATES_PROG` and lists the new `--repo-root`, `--states-file` and env lines. This is the only other intended text difference and no caller reads it.

## NEGATIVE CONTROL
One engine rule broken in place (`if new not in allowed:` replaced by `if False:`, the declared-transition check), the suite run, then the file restored with `git checkout -- lib/board/state_check.py`:
```
Command: bash tests/test-state-check.sh   (engine with the transition check removed)
Exit: 1
Output (FAIL lines and recap):
    FAIL illegal transition blocks (rc=0)
    FAIL escape hatch passes and prints the reason (rc=0)
    FAIL table machine enforces its transitions (rc=0)
  == 124 run, 117 passed, 7 failed ==
Verdict: FAIL as intended (restored; the green runs above are on the restored file)
```
The suite's own Part 3 repeats this for 23 rules in a copy of the engine, including the TOML reader, the root and registry arguments and the exit codes.

## Not changed
- The registry format stays TOML. `lib/board/states.tsv` (state, class, next) is advisory and permissive by decision (`docs/briefs/DECISION-BRIEF-declared-state-machines.md`); this engine blocks and needs transitions, legacy values and projections, so the two shapes were not merged.
- No kit hook runs the engine. A consumer wires `bin/board state-check --staged` into its own pre-commit hook.
- The old checker's behavior on a glob with a partial file name before `*` (`--all` finds nothing), on a failed `git` call (`--staged` reads as nothing staged), and on CRLF files is kept as is, so findings stay identical.

## Narrow suite runs
`tests/run-all.sh` was not run: the host was overloaded, so the lead asked for one narrow suite at a time instead, and CI for this org is down. Each suite ran in the foreground after merging the latest `origin/master`; the shared test lock was never held long enough to need `KIT_TEST_LOCK=0`.

```
Command: bash tests/test-state-check.sh
Exit: 0
Output (tail): == 124 run, 124 passed, 0 failed ==
Command: bash tests/test-board-states.sh
Exit: 0
Output (tail): All board-states tests passed.
Command: bash tests/test-board.sh
Exit: 0
Output (tail): TOTAL: 63   PASS: 62   FAIL: 0   SKIP: 1
Command: bash tests/test-registry-verbs.sh
Exit: 0
Output (tail): PASS=11 FAIL=0
Command: bash tests/test-bin-forwarders.sh
Exit: 0
Output (tail): test-bin-forwarders: all 48 passed, 0 skipped
Command: bash tests/test-no-personal-paths.sh
Exit: 0
Output (tail): Passed: 3 / 3
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output (tail): Passed: 120 / 120
Command: bash tests/test-meta.sh
Exit: 0
Output (tail): Passed: 934 / 934
Command: bash lib/registry/feature-registry.sh check
Exit: 0
Output: feature-registry: docs/reference/FEATURES.md is fresh
Verdict: PASS
```
