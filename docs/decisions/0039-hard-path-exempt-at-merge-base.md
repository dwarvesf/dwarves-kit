# 0039. A per-repo hard-path exemption, read at the merge base

Date: 2026-10-09
Status: Accepted (operator decision on the spec's open question)
Relates-to: ADR-0037 (lanes as data and the diff floor), `docs/specs/SPEC-400-shipgate-fixture-hardpath.md`, `docs/WORKFLOW.md`

## Context

The auth hard path matches any basename that contains `login`, `password`, `passwd` or `jwt`. A consumer repo pushed a test oracle, `experiments/qa-runner/cases/oracle/sd-login-locked.mjs`, that checks the login page of a public practice site. The floor demanded every full-lane gate: twelve overrides for a file with no auth code. ADR-0037 allowed config to add hard paths only, so overrides were the one way through.

## Decision

1. A repo may set `[lanes] hard_path_exempt`, one ERE, in its committed `.kit.toml`.
2. The floor and `classify --files` read it only from the `.kit.toml` at the merge base. The working tree, HEAD, the operator overlay and the kit root never count.
3. An exempt path skips every built-in kind except kit config. `extra_hard_paths`, submodules and data-loss lines still apply.
4. The reader drops an entry that is not a valid ERE, matches the empty string, or matches a canary hard path (`src/auth/login.ts`, `lib/session.ts` and others).
5. Every exempted path leaves an `EXEMPT | floor |` line in `ship-gate.log`.

## Consequences

This reverses the ADR-0037 rule that config only adds hard paths. The guard is that creating an exemption edits `.kit.toml`, a kit-config hard path that no entry can exempt. So a human reviews each exemption once in a full-lane PR, and no PR can use its own entry.

An exemption covers secrets and CI paths under its directory too. A broad entry that dodges the canaries can still hide a real hard path. The full-lane review of the `.kit.toml` change and the `EXEMPT` log lines are the checks on that.

Removing an entry on the default branch reaches a branch only after that branch moves its merge base.
