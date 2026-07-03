# Proof of done: design record before build (SPEC-122 / ADR-0031 §1)

Behavioral change: `commands/spec.md`'s SPEC.md template gains a required `## Design` block;
`commands/spec-validate.md` gains a BLOCKING Reviewer 6 that refuses `VALIDATED` on a
design-bearing spec with an empty Design block; `commands/design.md` seeds the block's diagram
+ ADR link(s) when the design is design-bearing; `WORKFLOW.md`'s Lane×phase depth matrix gains
one row naming the ceremony per lane.

## Green run

Command: `bash tests/test-design-record.sh`
Exit: 0
Output (tail):
```
Passed: 26 / 26
All design-record tests passed.
```

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail):
```
Passed: 663 / 663
All meta tests passed.
```

## The 3 named controls (SPEC-122 Test plan)

1. **NEGATIVE CONTROL** -- `tests/fixtures/design-record/design-bearing-empty.md`: declared
   design-bearing, `## Design` section empty. Reviewer 6's structural logic (reproduced as a
   pure function in the test harness) returns `REFUSE`. Assertion: `Reviewer 6 REFUSES a
   design-bearing spec with an empty Design block` -- PASS (i.e. the refusal fires correctly).
2. **POSITIVE** -- `tests/fixtures/design-record/design-bearing-filled.md`: declared
   design-bearing, `## Design` carries a mermaid sequence diagram + chosen approach. Verdict
   `PASS`. Assertion: `Reviewer 6 PASSES a design-bearing spec with a filled Design block`.
3. **PROPORTIONALITY CONTROL** -- `tests/fixtures/design-record/obvious-collapse.md`: declared
   NOT design-bearing, `## Design` collapses to a bare `obvious: <why>` line, no diagram.
   Verdict `PASS` with no diagram required. Assertion: `Reviewer 6 PASSES an obvious spec with
   no diagram (proportionality)`.

All three, plus the fixtures' own emptiness/diagram/collapse sub-assertions, are green (9/9 in
that section of the 26).

## NEGATIVE CONTROL (regression class): the depth-matrix ripple

Adding the WORKFLOW.md row is parsed at runtime by `lib/gate-ledger.sh` (the single source for
"which gates a lane requires"), which changed the normal-lane plan from 8 steps to 9 and made
the phase a required ship-gate item for the full lane. This broke 7 hardcoded assertions in
`tests/test-hooks.sh` and 3 in `tests/test-e2e.sh` on first full-suite run (real regression,
not test flakiness). Fixed by renumbering the expected `step k/n` values and adding a
`design-record ran` ledger line to the "fully disposed run" fixtures. Detail in
`docs/implementation-notes/design-record.md`.

Re-verified the coupling directly: with the renumbered tests in place, deleting the WORKFLOW.md
row (line 358) and re-running turned both suites RED again (`test-hooks.sh` 446/452, 6 failed;
`test-e2e.sh` 17/20, 3 failed) -- confirming the tests are actually sensitive to the matrix row,
not coincidentally green. Restoring the row (`git diff WORKFLOW.md` clean, 9 insertions, 0
deletions) returned both to green.

```
bash tests/test-hooks.sh   # 452/452 (446/452 with the row removed)
bash tests/test-e2e.sh     # 20/20  (17/20 with the row removed)
```

## Dotfiles half

`~/workspace/tieubao/dotfiles` branch `feat/ug-01-design-record` (commit `27a21e1`, off
`main`, NOT merged/pushed): `home/dot_claude/skills/plan-for-mega-goal/references/
subgoal-template.md` gains a `**Design:** <bearing | obvious>` top-level field plus a matching
bullet in the "Deltas from `plan-for-goal`" section.

## Known pre-existing failure (out of scope, confirmed on master)

`bash tests/test-classify-md-inert.sh` -- 1 failure (`stripped lib should reproduce the
stateful bug`), a `/tmp`-relative-path sourcing fragility in a `lib/proof-ledger.sh` test,
unrelated to anything this spec touches. Reproduced identically on the unmodified master
checkout before this branch existed; left alone.

## Reproduce

```bash
cd dwarves-kit   # or the ug-01 worktree
bash tests/test-design-record.sh   # 26/26
bash tests/test-meta.sh            # 663/663
bash tests/test-hooks.sh           # 452/452
bash tests/test-e2e.sh             # 20/20
```

VERDICT: PASS
