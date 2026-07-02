# Proof of done , deploy-rollout (fixture)

A well-formed DEPLOYABLE proof: the ADR-0025 stateful shape (recorded run + rollback)
PLUS the deployable-done contract's UAT/acceptance line (AGENTS.md "Deployable-done").

## Deploy-proof (ADR-0025 stateful shape)
- Command: `bash tests/fixtures/deployable-done/deploy-rollout.sh`
- Exit: 0
- Output (excerpt):
  ```
  rolling out service to production
  ```
- rollback: `git revert HEAD` restores the prior rollout script; verified reversible.

## UAT / acceptance
- UAT: exercised in the target environment (staging) 2026-07-02; the rollout script ran
  end-to-end and the deployed service responded healthy; accepted by the operator.
