# SPEC-188: reserved-keys-guard ([features]/[team] stay honestly inert)

Status: SHIPPED (test + doc-tags confirmed)
Lane: normal
Backlog: harness-ops sub-goal 08 (`_meta/megagoals/harness-ops/goals/08-reserved-keys-guard.md`)
Branch: feat/harness-ops-08-reserved
Relates-to: SPEC-183 (manifest-reconcile, the `kit.toml` chain that ships these
sections), `lib/config/kit-config.sh` (the resolver)

## Problem

`kit.toml` (repo-root, SPEC-183) ships two forward-looking-but-not-built sections:
`[features]` (`auto_improvement`, `learning_ledger`) and `[team]` (`actor_identity`,
`attestation`, `ci_recheck`, `spec_reservation`, `policy`, `onboarding`, `pilot`). Both
are resolver-readable via `kit_config_get` (the resolver reads whatever section/key is
asked, unconditionally). Nothing GUARANTEED, before this sub-goal, that flipping one of
these keys stays a genuine no-op: a reader could plausibly assume a status-tag comment
is enough, but nothing tested it, and a future change could silently wire a key without
anyone noticing it had graduated from documentation-only to live.

## Design

**Confirm, then lock with a test.** This sub-goal does not build anything new; it
verifies the current state (no live code path reads `features.*`/`team.*`) and adds a
standing test so a future accidental wire-up fails CI instead of shipping silently.

- **Grep-based no-live-path lint** (`tests/test-reserved-config-guard.sh`), mirroring
  SPEC-183's hooks-only `kit.toml` lint: assert no file under `lib/`, `commands/`, or
  `hooks/` calls `kit_config_get features.<key>` or `kit_config_get team.<key>` for any
  of the nine reserved keys.
- **Load-bearing NC for the lint itself**: a planted fake consumer that DOES call
  `kit_config_get team.actor_identity` is caught by the same grep, so the lint is proven
  to catch a real violation, not vacuously green.
- **Resolver-readable, positive check**: a project `.kit.toml` setting
  `[features] auto_improvement = true` and `[team] actor_identity = true` resolves via
  `kit_config_get` to `"true"` -- the keys ARE reachable, by design (a future consumer
  can read them without any resolver change).
- **Behavioral negative control (the goal's Rung-2 proof)**: run two spine surfaces
  (`lib/config/kit-config.sh selftest`, `lib/classify/lane-classify.sh classify`) once
  under baseline config and once under the project override flipping both reserved
  keys to `true`; assert byte-identical output. If either key had a live path, one of
  these runs would differ.
- **Status-tag documentation check**: `kit.toml`'s comments already carry `[design]` on
  `auto_improvement` and every `[team].*` key, and `[consumer]` on `learning_ledger`
  (SPEC-183's status-tag legend); the test greps for these tags so a future edit that
  drops a tag (making an inert key look live) fails.

No code under `lib/`, `commands/`, or `hooks/` changes. `kit.toml` itself is untouched
(sub-goal 04 owns its shape; this sub-goal only confirms + tests its existing tags).

## Scope edges

**In:** the inert-key guard test, confirming the existing status-tag documentation.
**Out:** actually building `auto_improvement`/`learning_ledger`/`[team].*` (their own
future work, each with its own design doc referenced in `kit.toml`'s comments).
**Not:** wiring any reserved key to a live path, removing the reserved keys, changing
`kit.toml`'s section shape.

## Verification

1. `bash tests/test-reserved-config-guard.sh` -- new, all green (9 assertions: no-live-
   path lint x2 incl. its own load-bearing NC, resolver-readable x2, inert-flip-NC x2,
   status-tag documentation x3).
2. `bash lib/config/kit-config.sh selftest` -- unchanged resolver mechanics, still green
   (regression check; this spec does not touch the resolver).
3. `bash tests/test-install-modules.sh` -- unchanged, still green (regression check;
   confirms this sub-goal did not disturb SPEC-183's manifest chain).

## After state

- A new standing test (`tests/test-reserved-config-guard.sh`) proves, with a captured
  run-table, that `[features]`/`[team]` keys are resolver-readable but inert: flipping
  either `auto_improvement` or `actor_identity` changes no observed behavior across two
  representative spine commands.
- The lint's own load-bearing-ness is demonstrated (a planted live-path read IS caught).
- The status tags (`[design]`/`[consumer]`) on these keys are asserted by the test, so
  a future edit that silently drops one fails CI instead of shipping unnoticed.
- Proof: `docs/verification/reserved-keys-guard/proof-of-done.md`.
