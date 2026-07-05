# Sub-goal 07: conditional deployable-done

**Merge policy:** auto , a ship-gate condition + AGENTS.md zone, testable via fixtures.
**Time budget:** 2-4 hours.
**Proof:** run-table , a DEPLOYABLE work item cannot be marked done without a deploy-proof + UAT (blocked / logged-override at ship); an INERT/library item is unaffected; reuses the ADR-0025 stateful proof shape.
**Depends on:** none (independent).
Model: sonnet
Effort: medium
**Branch:** feat/kit-harden-07-deploydone
**PR base:** mega/kit-hardening

## Outcome

For DEPLOYABLE work (a service, daemon, feature behind a flag, anything that runs somewhere), `done` = deploy-proof + UAT, enforced at ship , reusing the ADR-0025 stateful proof shape. Inert / library / refactor work with no runtime surface is unchanged. AGENTS.md gains a zone-3 clause defining "deployable" and the ship-gate reads it. A deployable item marked done without a deploy-proof + UAT is blocked (or requires a logged override).

## Quality bar

The condition must fire ONLY on genuinely deployable work , a false positive on inert work would gate every doc change behind a phantom deploy. The classification of "deployable" is explicit + testable (a fixture for each side). Reuses ADR-0025's stateful proof machinery; does not invent a parallel proof system.

## How to close the loop

Add the deployable-done condition to the ship-gate + the zone-3 clause to AGENTS.md; wire the deploy-proof + UAT requirement through the ADR-0025 stateful proof path. Verify:

```
cd dwarves-kit && bash tests/test-deployable-done.sh   # deployable blocked sans deploy-proof+UAT; inert unaffected; override logs
```

Captured evidence: run-table at `docs/verification/deployable-done.md` , a deployable-blocked row (no deploy-proof -> ship-gate blocks), an inert-unaffected row (a doc/library change ships normally), and an override row (a logged override is accepted + audited).

**Done =** `test-deployable-done.sh` proves a deployable item cannot be marked done without a deploy-proof + UAT (blocked or logged-override), an inert item ships unaffected, and the condition reuses the ADR-0025 stateful proof shape.

**Kit-adopted repo? Record the gates.** `bash lib/lane-classify.sh classify "conditional deployable-done: ship-gate requires deploy-proof+UAT for deployable work"`, record build + review via `lib/gate-ledger.sh` before push.

## Handoff on completion

1. Flip 07's box, PR # + SHA.
2. HOT `HANDOFF.md`: if this is the last sub-goal, the next action is the TIER-4 close gate on the assembled `mega/kit-hardening` stack (integration + review-team + deep security), then draft the LAB_LOG entry (see pointer prompt success-stop).
3. WARM `DECISIONS.md`: deployable work now owes deploy-proof + UAT at ship; inert work unchanged.
4. Report IN records, EXIT.

## Scope edges

**In:** the ship-gate deployable-done condition, the AGENTS.md zone-3 clause, the deploy-proof + UAT wiring via ADR-0025, the deployable/inert classifier, tests.
**Out:** the every-step review (05); the actual deploy/UAT of any real service (this BUILDS the gate, it does not deploy anything , see ROADMAP terminus note).
**Not:** a new proof system (reuse ADR-0025); gating inert/library/doc work; defining deployability per-repo (keep it a general classifier).

## Where to look

AGENTS.md (the zones + operate-contract), `lib/gate-ledger.sh` + the ship-gate hook, ADR-0025 (proof-of-done ship gate, the stateful shape to reuse), ADR-0028 "Conditional deployable-done", ADR-0026 (co-located table-first proof).

## PR body

Adds conditional deployable-done (kit-hardening SG-B, ADR-0028): deployable work's `done` = deploy-proof + UAT, enforced at ship via the ADR-0025 stateful proof shape + an AGENTS.md zone-3 clause; inert/library work unchanged.

Verify: `bash tests/test-deployable-done.sh`. Proof: `docs/verification/deployable-done.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. Independent; on the integration branch.

## Notes

<empty>
