# Proof of done: proof-verdict-hint (SPEC-330)

Names the file in `proof-ledger.sh check()`'s BLOCKED message when a behavioral proof has a
NEGATIVE CONTROL and a green run but is rejected solely because its own FINAL `Verdict:` line
reads FAIL/INCONCLUSIVE, instead of the pre-existing generic message that never says a file
was found at all. Does not change what passes or fails.

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | a per-file near miss (NEGATIVE CONTROL + green run + final Verdict: FAIL) gets a named `Hint:` line | `tests/test-proof-verdict-hint.sh` case 1 | PASS |
| AC2 | a pure set-wise near miss (neither member file alone qualifies) gets a named `Hint:`, identified by the group prefix | case 2a | PASS |
| AC3 | a set-wise near miss that overlaps a per-file near miss prints exactly ONE hint (dedupe) | case 2b | PASS |
| AC4 | a genuinely passing file (control's own outcome as `Result:`, file ends `Verdict: PASS`) is unaffected: exit 0, no message | case 3 | PASS |
| AC5 | no proof file at all still gets the pre-existing generic message, no `Hint:` | case 4 | PASS |
| AC6 | a plain FAIL with no NEGATIVE CONTROL marker never gets a `Hint:` (over-broad-match guard) | case 5 | PASS |
| AC7 | a mixed branch (one near miss + one unrelated rejection) prints exactly one hint, for the near miss | case 6 | PASS |
| AC8 | no change to what passes or fails: same `ok`/return-code semantics | full existing `tests/test-proof-*.sh` suite unchanged | PASS |

## Implementation

- `lib/gate/proof-ledger.sh` `check()` -- per-file loop and set-wise loop each restructure
  their existing win condition into named booleans (`has_negctl`/`has_green`/`last_ok`,
  functionally identical to the prior `&&`-chain) and additionally accumulate a `near_miss`
  list (`path<TAB>last_v`) whenever NEGATIVE CONTROL + green hold but the file's own last
  Verdict line is FAIL/INCONCLUSIVE. The set-wise loop skips its own group append when a
  per-file entry already covers a member of that group (dedupe). The BLOCKED message prints
  one `Hint:` line per `near_miss` entry for the `behavioral` class, naming the file/group and
  the exact fix.
- `tests/test-proof-verdict-hint.sh` -- 7 cases (see AC1-AC8 above), 10 assertions.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-proof-verdict-hint.sh` | 0 | ALL PASS (10/10) |
| `bash tests/test-proof-dir-layout.sh` | 0 | ALL PASS (3/3) |
| `bash tests/test-proof-experiment-verification-path.sh` | 0 | ALL PASS (4/4) |
| `bash tests/test-proof-negctl.sh` | 0 | all 33 passed |
| `bash tests/test-proof-override-order.sh` | 0 | ALL PASS (5/5) |
| `bash tests/test-proof-table-gen.sh` | 0 | 25/25 passed |
| `bash tests/test-proof-tool-verification-path.sh` | 0 | ALL PASS (1/1) |
| `bash tests/test-proof-visual-evidence.sh` | 0 | ALL PASS (4/4) |
| `bash tests/test-classify-md-inert.sh` | 0 | ALL PASS (13/13) |
| `bash tests/test-deployable-done.sh` | 0 | 17/17 passed |
| `bash tests/test-delivery-ratio.sh` | 0 | 8 passed, 0 failed |
| `bash tests/test-gate-opt-out.sh` | 0 | ALL PASS |

## Run detail

```
PASS case1: still BLOCKED (exit 1)
PASS case1: Hint names the file and states the fix
PASS case2a: still BLOCKED (exit 1)
PASS case2a: exactly one Hint, identified by the group prefix
PASS case2b: still BLOCKED (exit 1)
PASS case2b: exactly one Hint (per-file wins, group rollup deduped)
PASS case3: genuinely passing file still PASSes, no message
PASS case4: no proof file -> generic message, no Hint
PASS case5: a plain FAIL with no control never gets a Hint
PASS case6: exactly one Hint, naming only the near-miss file
---
ALL PASS (10/10)
```

## Negative control (mechanised, negctl.sh mutate mode)

Reverting `lib/gate/proof-ledger.sh` to its pre-fix state at `origin/master` (where the hint
logic does not exist) must turn `tests/test-proof-verdict-hint.sh` RED, proving the new test
suite actually exercises the new code, not a tautology; restoring must go GREEN again.

```
$ bash lib/gate/negctl.sh . 'bash tests/test-proof-verdict-hint.sh' 'git checkout origin/master -- lib/gate/proof-ledger.sh'
## Negative control (negctl)
Command: bash tests/test-proof-verdict-hint.sh
Exit: 0 (green before mutation)
Mutation: git checkout origin/master -- lib/gate/proof-ledger.sh
Changed: lib/gate/proof-ledger.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/proof-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Working tree confirmed clean (`git status --short` empty) after the restore.

## Reproduce

```
cd dwarves-kit
bash tests/test-proof-verdict-hint.sh                          # 10/10, exit 0
for t in tests/test-proof-*.sh; do bash "$t" || exit 1; done   # all green
bash lib/gate/negctl.sh . 'bash tests/test-proof-verdict-hint.sh' 'git checkout origin/master -- lib/gate/proof-ledger.sh'
```

## Not proven
- The `stateful` class's BLOCKED message is unchanged and untested by this suite (out of
  scope per SPEC-330 `## Solution` "Extensibility & boundaries").

Verdict: PASS
