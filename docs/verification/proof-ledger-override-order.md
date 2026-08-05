# Proof of done: proof-ledger.sh check() ordering fix

Change: `lib/gate/proof-ledger.sh` `check()` now evaluates the fresh proof-file check
BEFORE the override check (previously the reverse).

## Problem

Once a slug had ANY override logged (`proof-ledger.sh override <slug> <reason>`),
`check()` short-circuited straight into the override branch on every later call for
that slug. The override branch always REJECTS a diff touching a source file (`.sh`,
`.py`, etc. outside a sanctioned `deploy/` path), by design (cc-hyg-04). Because the
override log is append-only, this meant: log an override before writing the real
proof doc (a reasonable order of operations), add a legitimate proof-of-done with a
NEGATIVE CONTROL later in the same branch, and the slug was blocked FOREVER, since
the override was always checked first and a real proof file was never even looked at.

Found 2026-08-06 in `tieubao/ops-toolkit`: a docs-only branch with one `.sh`
one-line fix logged an override, then added a proper `docs/verification/*.md`
proof with a green run + negative control, and still could not push.

## Fix

Reorder `check()`: run the existing fresh-proof-file logic (`_fresh_proof_files` +
the per-file and set-wise verdict checks) first; only fall through to the
override branch (unchanged logic, still source-code-exempt) when no fresh proof
satisfies the requirement.

## Test / negative control

`tests/test-proof-override-order.sh` (5 assertions), added by this branch:

```
$ bash tests/test-proof-override-order.sh
PASS unproven behavioral change correctly BLOCKED
PASS override logged
PASS override alone correctly still REJECTED for the .sh source file
PASS fixed lib: real proof-of-done wins even though an override was also logged
PASS negative control: reverting the fix correctly goes RED (old order re-blocks a real proof)
---
ALL PASS (5/5)
```

Exit: 0
Verdict: PASS

The test's own step 5 IS the negative control: it stashes the working-tree fix
(reverting `check()` to the pre-fix ordering), re-runs the identical scenario
against the same fixture, and asserts it goes RED (still BLOCKED) before restoring
the fix. That run:

```
FAIL (expected RED under old ordering) -> observed: exit=1, "REJECTED -- the branch
changes source files with no proof of done: lib/thing.sh"
```

confirming the bug reproduces without the fix and the fix's reordering is what
closes it, not a coincidental pass.

## Scope check

Unrelated behavior is unchanged: an override still cannot excuse an unproven
`.sh`/`.py`/etc. source-code change (test assertions 1-3); deploy-path exemptions,
stateful-class handling, and the set-wise `docs/verification/<slug>/` layout are
untouched (only the two blocks were reordered relative to each other, no internal
logic edited).
