# Proof of done: proof-class-one-table

The proof class names, their rank, and the stateful words both classifiers share are declared once in `lib/gate/proof-classes.tsv`. `proof-ledger.sh classify` (diff) and `proof-gate.sh class` (task text) both read it.

| Check | Result |
|---|---|
| New suite `tests/test-proof-class-table.sh` | 25 PASS, ALL PASS (includes fail-closed on a malformed ERE row, a spaces-not-tabs row, a bad rank, and `coverage` with the table missing) |
| 48 affected suites, run directly, twice (before and after the fail-closed fix) | 47 rc 0 each time; the 1 failure each time (FEATURES.md fresh) fixed with `check --fix`, rerun 120/120 |
| Old vs new, ledger over the last 60 master commit diffs | 0 changed, 0 moved down |
| Old vs new, gate over the same 60 commit subjects | 0 changed |
| Negative control | old `proof-gate.sh` restored: 3 FAILED; loader before the fail-closed fix restored: 10 FAILED |

## New suite

```
Command: bash tests/test-proof-class-table.sh
Exit: 0
Output:
PASS an added word reaches both classifiers (and not the unedited copy)
PASS proof-ledger.sh: missing table is fatal
PASS proof-gate.sh: missing table is fatal
PASS malformed ERE row: proof-ledger.sh classify fails closed
PASS malformed ERE row: proof-gate.sh class fails closed
PASS spaces-not-tabs row: proof-ledger.sh classify fails closed
PASS spaces-not-tabs row: proof-gate.sh class fails closed
PASS class row with a non-integer rank: proof-gate.sh contract fails closed
PASS coverage still answers with the table missing
PASS no classifier in lib/gate types the shared words or the class list inline
PASS copy detector catches a planted shared word list
PASS copy detector catches a planted class list
PASS copy detector ignores comments

ALL PASS
Verdict: PASS
```

## Neighbouring suites

```
Command: bash tests/test-hooks.sh
Exit: 0
Output:
Passed: 830 / 830 All tests passed.
Verdict: PASS
```

```
Command: bash tests/test-meta-docs-registry.sh   (after bash lib/registry/feature-registry.sh check --fix)
Exit: 0
Output:
=== Results ===
Passed: 120 / 120
All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-lane-classify.sh
Exit: 0
Output:
=== 46/46 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-classify-md-inert.sh
Exit: 0
Output:
--- ALL PASS (13/13)
Verdict: PASS
```

```
Command: bash tests/test-deployable-done.sh
Exit: 0
Output:
=== 17/17 passed, 0 failed ===
Verdict: PASS
```

The other proof, gate-ledger, and meta suites that name these files also exited 0.

## Measurement

Each of the last 60 first-parent commits on master, old scripts (master at 52b6cefb) against new. The ledger classified each commit's diff against its parent; the gate classified each commit subject.

```
Command: bash measure.sh <clone> <old lib/gate> <new lib/gate> 60
Exit: 0
Output:
ledger changed 0 gate changed 0 of 60
ledger old behavioral 44 / inert 6 / stateful 10
gate old behavioral 57 / inert 3
Verdict: PASS
```

## Negative control

Restored the old `proof-gate.sh` (inline word list, literal class list) over the committed one and reran the new suite.

```
Command: git show 52b6cefb:lib/gate/proof-gate.sh >| lib/gate/proof-gate.sh && bash tests/test-proof-class-table.sh
Exit: 3
Output:
FAIL added word: ledger=stateful gate= unedited-ledger=behavioral
FAIL proof-gate.sh ran with no table: stateful
FAIL hardcoded vocabulary, read proof-classes.tsv instead:
proof-gate.sh: 12 table words typed inline:   if printf '%s' "$lc" | grep -qE 'deploy|rollout|release to|ship to prod|production|migrat|schema|data[ -
proof-gate.sh: all three class names on one line:     case "$rclass" in stateful|behavioral|inert) echo "$rclass"; return 0;; esac
proof-gate.sh: all three class names on one line:     classes)     printf 'stateful\nbehavioral\ninert\n';;
3 FAILED
Verdict: RED as intended
```

Restored with `git checkout -- lib/gate/proof-gate.sh`; the suite is green again (ALL PASS).

### Fail-closed guards

The loader validates the table at load: every row has exactly 3 tab fields, class ranks are unique integers, each stateful word and the joined pattern are valid EREs. Any fault is FATAL with exit 1. `proof-gate.sh` loads the table only in the verbs that classify (`class`, `requirement`, `contract`, `skeleton`, `classes`), so `coverage` still answers with the table missing.

```
Command: git show 1943a3ee:lib/gate/proof-classes.sh >| lib/gate/proof-classes.sh && git show 1943a3ee:lib/gate/proof-gate.sh >| lib/gate/proof-gate.sh && bash tests/test-proof-class-table.sh
Exit: 10
Output:
FAIL malformed ERE row: ledger rc=0 out=grep: parentheses not balanced
FAIL malformed ERE row: gate rc=2 out=grep: parentheses not balanced
FAIL spaces-not-tabs row: ledger rc=0 out=stateful
FAIL class row with a non-integer rank: gate rc=2 out=
FAIL coverage with no table: rc=1 out=FATAL: lib/gate/proof-classes.tsv missing, unreadable, or lacks a class or statefu
10 FAILED
Verdict: RED as intended
```

Restored with `git checkout --`; the suite is green again (ALL PASS, 25 PASS).
