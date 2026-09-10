# Sub-goal 00: the superseding ADR

**Merge policy:** gated-final (Han accepts the ADR; nothing downstream starts before)
**Time budget:** 1 hour
**Proof:** the ADR file exists at `docs/decisions/00NN-learning-lives-in-the-learners-kit.md`, Status `Proposed`, names ADR-0031 as superseded in placement only, lists every surface that moves and the kit it moves to, and `tests/test-meta.sh` is green (decision index regenerated).
**Depends on:** nothing.
Model: opus
Effort: high
**Branch:** docs/adr-learning-placement

## Outcome

One ADR that states the rule the operator gave on 2026-09-10 and the three-kit cut it implies: dwarves-kit is the process plane and keeps one seam key per hand-off; learning-kit owns every surface whose subject is a person understanding something, in a `study` lane and a `dev-learner` lane; context-kit owns every skill that writes knowledge into the tree. It names the concrete surfaces (the table in ROADMAP.md "Sub-goals" 02, 03, 04) and the one thing that stays: the DEBT ledger writer and reader, as engine data.

## Quality bar

Supersede placement, not substance: ADR-0031's significance classifier, nudge, and debt model stand and the ADR says so in its first paragraph. Name the failure that motivated it in one paragraph with the evidence path (`docs/verification/wrap-candidates-scan.md` and the weekend-batch test that grepped a dotfiles file). No re-litigation of whether an understanding gate should exist.

## How to close the loop

Write the ADR, regenerate the decisions index, open the PR, stop. The PR is Han's click. Its acceptance flips Status to Accepted in the same PR.

**Done =** PR open, ADR Proposed, index green, ROADMAP.md gate zero paragraph points at the file.

## Scope edges

**In:** the ADR, the index, the ROADMAP pointer.
**Out:** any code.
**Not:** re-opening ADR-0031's substance.
