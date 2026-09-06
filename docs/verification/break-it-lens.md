# Proof of done: SPEC-247 break-it prober lens

Class: `behavioral` (`bash lib/gate/proof-gate.sh contract "SPEC-247 break-it lens"` returns
`type=spec-feature class=behavioral`). Owed: the real primary flow run end to end, plus a
negative control that proves the check discriminates.

Branch: `feat/break-it-lens`. Run date: 2026-09-07.

## Green run

The spec's `## Verification` block, run verbatim as one chain.

Command: `bash tests/test-break-it.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh`
Exit: 0

```
=== break-it prober lens (SPEC-247) ===
...
=== 68/68 passed, 0 failed ===

=== Results ===          <- tests/test-meta.sh
Passed: 837 / 837
All meta tests passed.

=== Results ===          <- tests/test-hooks.sh
Passed: 497 / 497
All tests passed.
```

`grep -c FAIL` over the whole combined output: `0`. The three suites are recorded separately
below because a single chained tail shows only the last one's counter, which the first version
of this file mistook for the whole chain.

## Per-suite detail

| Suite | Command | Exit | Result |
|---|---|---|---|
| break-it | `bash tests/test-break-it.sh` | 0 | 68/68 passed, 0 failed |
| meta | `bash tests/test-meta.sh` | 0 | 837/837, all meta tests passed |
| hooks | `bash tests/test-hooks.sh` | 0 | 497/497, all tests passed |
| effectiveness gate | `bash tests/test-agent-effectiveness.sh agents/break-it.md` | 0 | 3/3 passed (read-only tools, model tier `opus`, name not a retired suffix) |

## Negative control

The spec names it: strip the guard line from `tests/fixtures/break-it/tight/impl.sh`, re-run
`bash tests/test-break-it.sh`, and it must fail the "tight fixture constrains the boundary"
assertion. Restore, re-run, green.

```
### 1. baseline (guard in place)
exit=0
=== 68/68 passed, 0 failed ===

### 2. guard line removed
exit=1
  FAIL T3-AC3: the tight suite is GREEN with the guard in place
  PASS T3-AC3 [NEGATIVE CONTROL]: without the guard the tight suite goes RED
=== 66/68 passed, 2 failed ===

### 3. restored
exit=0
=== 68/68 passed, 0 failed ===
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

## Live dispatch (the lens's own judgment), 2026-09-07

The suite cannot dispatch a live prober in CI, so the judgment was exercised by hand once,
outside CI, against a BLIND copy of the fixture pair: the two directories were copied to neutral
names (`probe-a` = leaky, `probe-b` = the pre-fix tight half) with the kit-role commentary
stripped, so neither dispatch could read which half it held. Each ran at `model: opus`, handed
only `agents/break-it.md` as its operating prompt.

**probe-a (leaky).** Verdict `PROBE: 1 finding`, in grammar:

```
PROBE: the suite does not constrain the upper bound of the accepted range
  probe:            bash impl.sh 11
  expected:         "reject" -- CONTRACT (impl.sh:2-4) makes 1..10 a closed range
  observed:         "ok" (also "ok" for 100)
  unconstrained-by: test.sh:21
  severity:         HIGH
```

**probe-b (the pre-fix tight half).** Expected `NO-PROBE`. Returned `PROBE: 1 finding` instead,
and the finding was REAL:

```
PROBE: the suite does not constrain non-integer input
  probe:            bash impl.sh abc        (same class: "3.5", "1e3", "+5", "0x5")
  expected:         "reject" for anything outside 1..10
  observed:         "ok". Both numeric tests exit 2 on non-integer input, `2>/dev/null`
                    hides it, the failed test reads false, control falls through to "ok"
  unconstrained-by: test.sh:20-24
  severity:         HIGH
```

Reproduced against the committed fixture: `bash tests/fixtures/break-it/tight/impl.sh abc`
printed `ok`. The "tight" half was not tight. It has since been fixed (an input-shape guard plus
four shape cases in its suite, pinned by a new `tests/test-break-it.sh` assertion), and the
guard-strip negative control still discriminates. This is the finding no grep could have
produced, and it is why the live dispatch is recorded here rather than claimed as untestable.

**probe-c (the FIXED tight half), same blind protocol.** Verdict `PROBE: 5 findings`, no HIGH:
2 MEDIUM (a leading-zero numeral where the length guard and the arithmetic guard disagree, so
`09` is accepted and `009` rejected for the same value; and the library path, where sourcing the
file runs `batch_size "$@"` and clobbers an un-`local` global `n`) and 3 LOW (arity, exit status,
and a test comment that asserts a conclusion, correctly reported rather than obeyed).

**Stated plainly: no dispatch returned `NO-PROBE`, and that is the honest result.** What the fix
moved is severity, from a HIGH that falsified the fixture's own claim to a residue of MEDIUM and
LOW findings that are all real. A `NO-PROBE` verdict is not reachable on a fixture of this shape:
a bash entry point carries arity, exit status, sourcing, and numeral canonicalization surfaces
that a nine-case suite does not pin, and chasing them to zero is the ceremony the spec's own
failure-mode table warns about. The `NO-PROBE` direction is therefore proven only as a documented
verdict shape in the prompt and its test pins, never by a live run. Anyone reading the fixture
pair as a demonstration of `NO-PROBE` is reading more than it carries.

Two contract behaviours the third run does confirm, and they are the ones DEC-010 changed:
every finding carried `observed: UNVERIFIED: probe not executable through the granted roster`
rather than an asserted behaviour, and the run closed with `tried:` lines for all six families
plus `families-unattempted: none`, the grammar DEC-011 added. The narrowed roster and the new
grammar both hold under a live model.

## What is NOT proven here

A live dispatch on every future run. The suite's prompt arm is STRUCTURAL, not behavioral: it
proves each load-bearing token sits under the section that owns it, never that a live run
concludes correctly. Section-scoping is what makes that arm discriminate at all; a flat
file-wide grep passes on a bag of words, proven on 2026-09-07 by a gutted 12-line agent file
that carried every pinned phrase in one paragraph and passed the earlier greps AND the SG-01
gate. The same file fails 7 of the section pins.

Probe yield is unmeasured by design. Open question 5 settled as manual review for v1; no counter
ships.

## /kit:verify run (the full right arm), 2026-09-07

Restated claim: SPEC-247 holds when the break-it lens exists, is reachable from `/kit:battery`,
and its suite discriminates. Measured by the spec's own `## Verification` chain plus the four
right-arm verifiers, each in fresh context. Passing threshold: exit 0 on the chain, and no NEW
failure anywhere in the unscoped project suite relative to the merge-base `682dda91`.

Base ref: `682dda91` (`git merge-base HEAD origin/master`). Working tree clean at dispatch.
No `Model:` header on the spec, so each verifier ran at its frontmatter default.

| Level | Agent | Verdict | Evidence |
|---|---|---|---|
| Unit / task | task-verifier | PASS | 5/5 tasks, all AC met. Effectiveness gate 3/3, break-it 53/53, meta 837/837, hooks 497/497 |
| Integration | integration-verifier | PASS | 4/4 components reach their activation point; the three-rung order is consistent across `docs/WORKFLOW.md`, `commands/battery.md`, and `agents/break-it.md`; `lib/gate/mutation-smoke.sh` keeps its single call site at `commands/verify.md:62` |
| Acceptance | acceptance-verifier | PASS | 10/10 after-state items plus every task AC re-derived independently; negative control run and restored, `git status --short` clean after |
| System | system-verifier | FAIL:escalate (pre-existing, not a regression) | 68/69 suites green. `tests/test-orchestrate-wavefront.sh` fails 3 concurrency assertions, byte-identical at the merge-base tree, and this branch touches no file under `lib/queue/` |
| Mutation smoke (advisory) | `lib/gate/mutation-smoke.sh run` | SKIP | `no mutable changed code lines (only tests/docs, or no operator match)`, exit 0. Normal for a markdown-and-bash-tests change, never a verdict change |

Command: `bash lib/gate/mutation-smoke.sh run`
Exit: 0
Output: `[MUTATION-SMOKE] SKIP: no mutable changed code lines (only tests/docs, or no operator match)`

**Verdict: PASS for SPEC-247.**

Baseline correction, stated plainly: the "zero known failures" baseline this build worked from
holds for the spec's verification chain, and NOT for the unscoped project suite.
`tests/test-orchestrate-wavefront.sh` was already red at `682dda91`, proven by re-running it
against a `git archive` of the merge-base. It is an orchestrate-module concurrency test with
hardcoded sleep and poll windows, outside this spec's touched area. Whether that is a local
timing flake or a latent defect is a maintainer call, not this branch's to make.

## Test plan coverage

The spec's `## Test plan` matrix has 26 rows. Runs referenced below: **R1** the green-run chain
(`bash tests/test-break-it.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh`, exit 0);
**R2** the guard-strip negative control; **R3** the naming-axis arm negative control; **R4** the
fixture's own exit-code proof (`leaky/probe-check.sh`); **R5** the blind live dispatch.

| Row | Run / skip reason |
|---|---|
| 1 | R1 (`tests/test-agent-effectiveness.sh agents/break-it.md`, exit 0) |
| 2 | R1 (`tools_violation()` assertion, plus the exact-set roster assertion added by DEC-010) |
| 3 | R1 (meta 837/837) |
| 4 | R3 |
| 5 | R1 |
| 6 | R1 |
| 7 | R1 |
| 8 | R1 |
| 9 | R4 |
| 10 | R1 |
| 11 | R2 |
| 12 | R1, re-shaped: the invariant pins are section-scoped under `## Invariants` and the count is derived, not a literal |
| 13 | R1, re-shaped: the edge-case pins are section-scoped under `## Edge cases` |
| 14 | R1, re-worded by DEC-010: the rule is now "executes no code from the branch", pinned under `## Command safety` together with the runner-load reason |
| 15 | R1 (masking pins under `## Masking`, including the any-output-field scope) |
| 16 | R1, with the honest-scope note: SG-01 duplicates checks the assertions above already make, so the section pins are what discriminate |
| 17 | R1 |
| 18 | R1 |
| 19 | R1, extended: a ledger row introduced by the diff under review is checked for provenance |
| 20 | R1 |
| 21 | R1 |
| 22 | R1 |
| 23 | R1 (meta) |
| 24 | R1 (meta) |
| 25 | R1 |
| 26 | R1 (hooks 497/497) |

Row 10's claim was FALSIFIED by R5 before this map was written: the tight fixture pinned the
boundary but not the input shape. The fixture and its suite were fixed, and the shape cases are
pinned in `tests/test-break-it.sh` as well as in the fixture's own suite. See `## Live dispatch`.
