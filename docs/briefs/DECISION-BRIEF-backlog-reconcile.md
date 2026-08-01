# Decision Brief: backlog-reconcile audit-loop instance

Produced by `/kit:think`, questions asked interactively (`AskUserQuestion`, one recommended
answer per question, operator picked or overrode each). The task completes an already-accepted
pattern slot (`docs/patterns/audit-loop.md`'s "Backlog reconcile" SDLC-instances row), shape and
scope were discussed with the operator in prior conversation turns before this brief ran, but
each of the 6 forcing questions below was still put to the operator directly, not assumed.

## Verdict: BUILD

## Core thesis

`docs/patterns/audit-loop.md` names "Backlog reconcile" as one of five SDLC instances of the
audit-loop pattern; three of the five are built (memory-tidy, doc-drift, topology-drift/
feature-map) and one is design-only. This closes that gap the same way topology-drift closed
the feature-inventory gap: a real skill, not a table row.

## Q1: real user pain (operator-picked: recommended)

"Audit the backlog" has nowhere to route today: the personal `audit` front-door skill's routing
table has no backlog row. The closest thing, a reconcile mode bolted onto `work-intake`, has no
contract, no verdict grammar, and no PR gate, so a bad reconcile lands straight on `BACKLOG.md`
with no review step. The moment: an operator asks "is the board still true" and the honest
answer today is "nobody checked, and if someone did, nothing reviewed their edit." (That
`work-intake` front door lives outside dwarves-kit entirely, in a personal ops-toolkit skill;
wiring it to route into this in-kit skill is explicitly OUT OF SCOPE for this brief, a follow-up
in the consumer repo, not this build.)

## Q2: 10x version (operator-picked: recommended)

Every adopter repo's backlog self-heals: one command surfaces every row whose `→` pointer no
longer matches its Notes/Status, applies the mechanical fixes automatically (status flips via
`backlog.sh set`), and gates anything requiring judgment through one PR. "Is the board lying"
stops being a question anyone has to remember to ask.

## Q3: simplest version that proves the thesis (operator-picked: full Tier 1 + Tier 2 from day one)

Operator overrode the staged recommendation: ship the complete topology-drift-mirrored shape in
one pass, mechanical pass plus audit-scanner dispatch on the delta, no separate Tier-1-only
milestone. Reasoning: the shape is already precedented twice (memory-tidy, topology-drift), so
staging buys little, and the kit ships to adopters soon.

## Q4: what gets cut (operator-picked: recommended)

- No auto-resolution of UNSURE, ever, matches the pattern's own hard rule, not new.
- No new verdict grammar. Reuse OK/FIX/REMOVE/UNSURE/DANGER verbatim, do not invent a backlog-
  specific vocabulary.
- No cadence/scheduling built into the skill itself. If a recurring cadence is ever wanted, that
  is `loop-engineering`'s job (wrap the skill in `/loop` or a schedule), not this skill's.

## Q5: what breaks at scale (operator-picked: recommended)

A repo with hundreds of backlog rows makes Tier 2 (audit-scanner dispatch) expensive if not
delta-gated. Mitigation: the same cheap-first split topology-drift already proved, Tier 1 runs
mechanically on every row, Tier 2 dispatches only for rows Tier 1 flags, one scanner call per
cluster of flagged rows, not one per row.

## Q6: exit criteria (no real alternative existed, fixed by proof-gate.sh's own contract)

The skill catches a SEEDED drifted row in a dogfood run against dwarves-kit's own
`_meta/BACKLOG.md` (per `proof-gate.sh contract`'s own bar: "a seeded drifted item is caught"),
with a negative control, revert the fix, drift reappears, restore, recorded at
`docs/verification/backlog-reconcile.md`.

## Strongest argument for

Three of four precedent instances (memory-tidy, doc-drift, topology-drift) already prove the
shape works and ships cleanly; this is pattern completion with a known-good template, not a
novel design risk, right before the kit goes out to adopters who will expect the pattern's own
table to be true.

## Strongest argument against

`work-intake`'s existing reconcile mode already covers ~80% of the same ground informally; a
new formal instance risks two half-overlapping backlog-reconcile paths (informal in work-intake,
formal in-kit) confusing future maintainers about which one to use, unless the informal path is
explicitly noted as personal/out-of-kit and left alone (it is, `work-intake` lives outside the
kit entirely, so no actual collision, but worth naming so nobody merges them later without
reading this brief).

## Recommended scope for v1

Tier 1 (mechanical) + Tier 2 (audit-scanner dispatch on the delta only) + PR gate, mirroring
topology-drift exactly, general-purpose scope, refusal guard for a repo with no `backlog.sh` or
no `_meta/BACKLOG.md` (unadopted repo, nothing to reconcile).
