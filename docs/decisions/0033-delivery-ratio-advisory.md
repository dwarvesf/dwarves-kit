# 0033 - Delivery-ratio advisory (proportionality nudge, never a gate)

Status: accepted (2026-07-05)

## Context

A 2026-07-05 delivery audit of ~258 mega-goal sub-goals (triggered when a "rewrite the
README" sub-goal turned out to be a +29-line append) found a real, patterned failure:
the proof-of-done gate checks that a proof EXISTS, not that delivery is PROPORTIONATE to
the claim. A thin docs / reconcile / audit sub-goal can pass the gate by wrapping a
near-zero real change in 200-300 lines of self-grading proof-of-done + verification. The
rot concentrated exactly in sub-goal types with no external "does it run" signal
(docs/reconcile), where ceremony fills the void.

## Decision

Add `proof-ledger.sh delivery-ratio <root> <base>`: split the branch's ADDED lines into
real-deliverable (code + user-facing docs) vs proof/ceremony (proof-of-done, verification,
specs, impl-notes, ADRs, tests) and print `real=N proof=M | <verdict>`. Wire it as an
ADVISORY line in the ship-gate hook: fires only on THIN-WARN / NOTICE, silent on OK,
**never blocks** (no exit 2).

## Why it is advisory, not a gate (the honest limit)

Line count cannot distinguish hollow from load-bearing. The audit itself proved both
failure directions: a 4-line rule injected into 3 live review surfaces is load-bearing
(would false-flag), and a 47-line append to a README is thin-for-a-"rewrite" but reads OK
because it clears the `real < 40` floor (`test-delivery-ratio.sh` CASE4 pins this blind
spot on purpose). So this is a VISIBILITY nudge for a human/`mega status` to spot-check,
not a verdict. Making it blocking would reproduce the very mechanical-gate brittleness it
is meant to compensate for.

The real fix for "claim > delivery" is judgment at review time (a capable model checking
the diff against the sub-goal's claim), plus routing judgment-heavy docs/design sub-goals
to a higher model tier and dropping "surgical, not a rewrite" default scoping language
that makes workers append instead of rework. This ADR is the cheap, always-on half; the
judgment half lives in the mega scaffolder and the reviewer.

Tunable: `KIT_DELIVERY_RATIO_WARN` (default 3), `KIT_DELIVERY_REAL_FLOOR` (default 40).

## Consequences

- One more advisory line at ship for proof-heavy branches; zero behavior change otherwise.
- Proof: `docs/verification/delivery-ratio-gate.md`; tests: `tests/test-delivery-ratio.sh` (wired into CI).
