# Proof of done: SPEC-246 break-it prober lens

Class: `behavioral` (`bash lib/gate/proof-gate.sh contract "SPEC-246 break-it lens"` returns
`type=spec-feature class=behavioral`). Owed: the real primary flow run end to end, plus a
negative control that proves the check discriminates.

Branch: `feat/break-it-lens`. Run date: 2026-09-07.

## Green run

The spec's `## Verification` block, run verbatim as one chain.

Command: `bash tests/test-break-it.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh`
Exit: 0

```
=== break-it prober lens (SPEC-246) ===
...
=== 53/53 passed, 0 failed ===

=== Results ===
Passed: 497 / 497
All tests passed.
```

`grep -c FAIL` over the whole combined output: `0`.

## Per-suite detail

| Suite | Command | Exit | Result |
|---|---|---|---|
| break-it | `bash tests/test-break-it.sh` | 0 | 53/53 passed, 0 failed |
| meta + hooks | `bash tests/test-meta.sh && bash tests/test-hooks.sh` | 0 | 497/497, all tests passed |
| effectiveness gate | `bash tests/test-agent-effectiveness.sh agents/break-it.md` | 0 | 3/3 passed (read-only tools, model tier `opus`, name not a retired suffix) |

## Negative control

The spec names it: strip the guard line from `tests/fixtures/break-it/tight/impl.sh`, re-run
`bash tests/test-break-it.sh`, and it must fail the "tight fixture constrains the boundary"
assertion. Restore, re-run, green.

```
### 1. baseline (guard in place)
exit=0
=== 53/53 passed, 0 failed ===

### 2. guard line removed
exit=1
  FAIL T3-AC3: the tight suite is GREEN with the guard in place
  PASS T3-AC3 [NEGATIVE CONTROL]: without the guard the tight suite goes RED
=== 51/53 passed, 2 failed ===

### 3. restored
exit=0
=== 53/53 passed, 0 failed ===
```

The suite discriminates: removing the one guard line flips it red, restoring it flips it back.

## Second negative control (the naming-axis arm)

TASK-001 AC4 asks that the `break-it)` arm in `is_on_review_axis()` be load-bearing.
`tests/test-break-it.sh` extracts that function from the live `tests/test-meta.sh`, evaluates it
as shipped and again with the arm stripped, and asserts the two disagree:

```
  PASS T1-AC3: the shipped axis ACCEPTS 'break-it'
  PASS T1-AC4 [NEGATIVE CONTROL]: without the arm the axis REJECTS 'break-it'
  PASS T1-AC4: the strip actually removed a line (control not vacuous)
```

A full `tests/test-meta.sh` run takes minutes, so the control exercises the same function the
roster scan calls rather than running the suite twice. See
`docs/implementation-notes/break-it-prober-lens.md`.

## Third negative control (the fixture pair proves its own claim)

DEC-009 requires each fixture to prove its claim by exit code, never in prose.

Command: `bash tests/fixtures/break-it/leaky/probe-check.sh`
Exit: 0

```
probe: batch_size 11
expected (contract): reject
observed:            ok
HOLE CONFIRMED: the contract says reject, the code says ok, and test.sh stays green.
```

Command: `bash tests/fixtures/break-it/leaky/test.sh`
Exit: 0 (the suite is green over that hole, which is the fixture's whole point)

## What is NOT proven here

The lens's own judgment. `break-it` cannot be dispatched live in CI, the same limit
`tests/test-agent-effectiveness.sh` and `tests/test-review-team-plants.sh` already carry. Every
assertion about what the agent CONCLUDES is a prompt-completeness grep: it proves the prompt
carries the vocabulary to name each class, never that a live run names it. The mechanism (the
fixtures, the axis arm, the battery and docs wiring) is proven by real exit codes.

Probe yield is unmeasured by design. Open question 5 settled as manual review for v1; no counter
ships.
