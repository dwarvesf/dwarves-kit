# 0025. Proof-of-done ship gate (diff-keyed, spec-independent)

Date: 2026-06-07
Status: Accepted
Relates-to: ADR-0024 (lane gate + ship enforcement, extended here), the proof-of-done convention (docs/verification/README.md), lib/gate/proof-gate.sh (risk classes), SPEC-042 (proof of done)

## Decision (one line)

A load-bearing change cannot pass the ship/push boundary without a matching proof-of-done entry; the gate keys off the **branch diff** (not a spec), so it fires the same whether the work came from `/kit:execute` or a freeform `/goal` loop, and an explicit logged override is the only bypass.

## Context

The proof-of-done discipline (execution-backed verify + negative control + risk-class gating, SPEC-042 and its siblings) was command/agent **advice**: an agent could declare "done" without producing the proof and nothing stopped it. ADR-0024 already hard-refuses at ship when a lane's required gate is missing, but it is **spec-keyed**: it resolves branch slug -> SPEC file -> lane, and fails open when there is no spec. A freeform `/goal` that committed without a SPEC therefore slips the gate entirely. That is the gap: the proof is conventional, not enforced, and the one existing wall does not see spec-less work.

## Decision

1. **A diff-keyed proof gate, spec-independent.** `lib/gate/proof-ledger.sh` classifies the branch's aggregate diff into a proof class (`stateful` / `behavioral` / `inert`, consistent with `lib/gate/proof-gate.sh`) and requires a matching, FRESH proof-of-done entry (one the branch itself added/modified under `docs/verification/`): behavioral needs a green run + a `NEGATIVE CONTROL`; stateful needs a recorded run + a rollback note or `[UNAVAILABLE: reason]`; inert passes with no ritual. Keying on the diff (which every change has) instead of a spec (which is optional) is what bridges freeform `/goal` work into the same wall.

2. **Enforced at the ship boundary, inside the existing hook.** `hooks/ship-gate.sh` runs the proof check BEFORE its spec-based lane check, so the proof wall fires even when there is no spec. Exit 2 blocks; the message names the change's class and exactly what proof is missing.

3. **Opt-in per repo.** The gate engages only where the convention is adopted (`docs/verification/README.md` exists). A repo that never adopted proof-of-done is never gated (fail open). This keeps a globally-installed hook from blocking unrelated repos.

4. **An explicit, logged override is the only bypass.** `proof-ledger.sh override <slug> "<reason>"` writes a trace to the override log; the gate then passes. There is no silent escape; an emergency hotfix leaves an audit line.

5. **Fails open on ambiguity.** No repo, empty diff, unresolved base, or missing tooling -> pass. A gate bug must never block unrelated work (same stance as ADR-0024).

## Alternatives considered

- **Hook the `/goal` Stop hook directly.** Rejected: it lives outside the kit (the user's skill ecosystem), and a goal can finish without merging. The git ship boundary is the universal choke point every committable change passes through.
- **Keep the gate spec-keyed.** Rejected: that is the exact gap, freeform `/goal` work has no spec and would never be gated.
- **A hard wall with no override.** Rejected: a wall with no escape hatch gets disabled the first time it blocks a 2am hotfix. A logged override keeps the wall installed and honest.

## Consequences

- Proof of done stops being advice an agent can skip; for an opted-in repo it is a wall at ship.
- Out of scope (deliberately, separate concerns): enforcing verifier-implementer **independence** (the gate checks the entry exists and is valid-shaped, not who produced it), and proving the **stateful** path on a real deploy/migration repo (dwarves-kit has none).
- The gate fires at push/PR-create (where the branch diff is in hand); downstream `git merge` / `gh pr merge` is covered transitively (you cannot merge what you could not push).
