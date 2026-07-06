# Proof of done: UI done-modes + quiescence loop (SPEC-112, kit-face wave)

`/kit:ui-design` gains a `Done-mode:` flag (proof | over-test | quiescence). proof is the mandatory
floor; over-test adds a test-plan + coverage-delta; quiescence extends Phase B into a converging
loop with a TWO-SIDED stop. Final acceptance stays a `gate` in every mode.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Done-mode flag consumed + branches (proof default, over-test, quiescence) | PASS |
| 2 | quiescence stop is TWO-SIDED: zero NEW >=HIGH AND no OPEN >=HIGH | PASS |
| 3 | NEGATIVE CONTROL: a re-found unresolved CRITICAL does NOT quiesce (falsely-calm trap) | PASS (trace 3) |
| 4 | quiescence caps at 3; capped-out findings -> Deferred findings | PASS (trace 2) |
| 5 | plain REVISE still caps at 2 (regression control) | PASS (trace 4) |
| 6 | QL-VERDICT markers + resolved/OPEN tags; Deferred findings appended by loop lead post-termination | PASS |
| 7 | over-test coverage-delta row defined (ACs-covered / tests-added) | PASS |
| 8 | Done-mode field in the subgoal-template (dotfiles half, UI-only/optional) | PASS (dotfiles `ac2c6a4`) |
| 9 | test-meta green (contract pins + fixture-trace pins) | PASS |

## Fixture traces

These are worked round-sequence TRACES: `/kit:ui-design` (like `/kit:visual-team`) is a prose loop
with no shell dispatcher and is not in CI (it is downstream-facing; the kit has no UI to dogfood).
The traces demonstrate the stop logic; the contract text is pinned in `test-meta.sh`.

### Trace 1 , CONVERGE (quiescence stops clean at round 2)

- Round 1: visual-team returns 2 findings , HIGH "contrast 3.1:1 on the CTA", MEDIUM "inconsistent
  8px/12px spacing". `[[QL-VERDICT round=1 clean=false findings=2]]`. Apply the accepted fixes.
- Round 2: re-render, re-critique. Zero NEW >=HIGH; the round-1 HIGH is now `[resolved in round 2]`;
  no OPEN >=HIGH remains (the MEDIUM defers). `[[QL-VERDICT round=2 clean=true findings=0]]` -> STOP.
- Deferred findings: the MEDIUM spacing note (sub-floor) appended to the final `## Visual critique`.

### Trace 2 , CAP-OUT (a never-satisfied critic caps at round 3)

- Round 1: HIGH A. Round 2: A resolved, but NEW HIGH B surfaces (`clean=false`). Round 3: B
  resolved, NEW HIGH C surfaces (`clean=false`). Round cap 3 reached -> STOP with the last critique.
- Deferred findings: OPEN HIGH C (capped-out) + any sub-floor findings appended to the final
  `## Visual critique` , surfaced to the human, not silently dropped.

### Trace 3 , NO-FALSE-QUIESCENCE (the load-bearing NC: a re-found CRITICAL does NOT quiesce)

- Round 1: CRITICAL "focus trap in the modal" + HIGH "contrast". `clean=false`.
- Round 2: the contrast HIGH is fixed, and the round surfaces zero NEW findings , BUT the CRITICAL
  focus-trap is RE-FOUND unresolved (the applied fix did not land). Under a "zero NEW" ONLY stop this
  would falsely quiesce. Under the TWO-SIDED stop it does NOT: there is an OPEN >=HIGH (the CRITICAL),
  so `clean=false` and the loop continues. `[[QL-VERDICT round=2 clean=false findings=0]]` with the
  CRITICAL tagged `[OPEN]`. This is the trap the two-sided condition exists to catch.

### Trace 4 , PLAIN REVISE regression (proof mode, cap unchanged at 2)

- Done-mode: proof (default). A `REVISE` verdict runs the plain Phase B loop: max 2 regenerations,
  terminate on SOLID / RECONSIDER / cap 2. No quiescence extension, no QL-VERDICT markers. Cap stays
  2 (fix-agent parity); the quiescence cap of 3 does not leak into proof mode (DEC-018).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| Done-mode flag | `grep -qiE 'Done-mode' commands/ui-design.md` | match | match |
| two-sided stop | `grep -qiE 'zero NEW findings >=HIGH AND no OPEN' commands/ui-design.md` | match (full conjunction) | match |
| NC stated | `grep -qiE 'does NOT quiesce\|re-finds' commands/ui-design.md` | match | match |
| QL-VERDICT | `grep -qF '[[QL-VERDICT' commands/ui-design.md` | match | match |
| cap divergence | `grep 'Round cap: 3'` + `grep 'cap of 2'` | both | both |
| coverage-delta | `grep -qiE 'COVERAGE-DELTA\|ACs-covered'` | match | match |
| dotfiles field | `grep '^**Done-mode:**' <subgoal-template>` | match | match (ac2c6a4) |
| suite | `bash tests/test-meta.sh` | green incl. SPEC-112 block | (see run) |

## Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh
grep -qiE 'zero NEW findings >=HIGH AND no OPEN finding >=HIGH' commands/ui-design.md
grep -q '^\*\*Done-mode:\*\*' ~/workspace/tieubao/dotfiles/home/dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md
```

## Notes

- DEC-018: quiescence caps at 3 (test-plan-review-team parity); plain REVISE keeps 2 (fix-agent
  parity). The divergence is deliberate, not an inconsistency.
- The `### Deferred findings` subsection is authored by the ui-design LOOP LEAD, appended to the
  FINAL `## Visual critique` AFTER the loop terminates (a carve-out to Step 3's "do not write the
  critique yourself" rule) , visual-team rewrites that section each round and is stateless.
