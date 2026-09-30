# 0037. Lanes as data, a light default, and a diff floor at ship

Date: 2026-09-30
Status: Accepted (operator decision, recorded in the spec's decision log)
Relates-to: ADR-0024 (gate ledger and ship enforcement), `docs/specs/SPEC-368-lanes-as-data.md`, `docs/WORKFLOW.md`

## Context

The kit sized most work heavier than needed. The rule said to take the heavier lane when unsure. One keyword in a task title made the classifier return the full lane. Four measured false hits ("token count", "queue timeout", "webhook retry log", "user role label") all became full. Full-lane phases were overridden far more often than they ran: think, reflect, design, and design-critique were overridden 14 to 21 times each across 149 run ledgers.

The lane rules also lived in prose. The gate ledger parsed the markdown table in `docs/WORKFLOW.md` at run time, so no repo could change a lane without editing kit prose.

## Decision

1. Lanes are data. `kit.toml` holds `[lane.<name>]` blocks with `phases` and `light` arrays. `lib/gate/lane-data.sh` is the one reader. A committed project `.kit.toml` may override a lane. The `WORKFLOW.md` matrix is the human view, pinned equal by a test.
2. The default lane is `normal`. Words never pick `full`. The classifier prints a suggestion and records it in the run ledger. The operator assigns `full`.
3. The normal lane requires `validate` and `review`. They catch the triggers no diff path shows: authz, API contract, external provider, weakened validation.
4. The ship-gate applies the full lane's gates to any diff that touches a hard path: migrations, auth, secrets, CI workflows, kit config, added data-loss lines, and the add-only `extra_hard_paths` list. The floor ignores project lane overrides. It reads `[gate] lane_gates` as of the merge base, so a PR cannot switch off its own floor.

## Consequences

This reverses the "when in doubt, take the heavier one" posture and the earlier call that `validate` on the normal lane stays light. The safety moves from words in a task title to files in the diff, where the risk is.

Repos with `lane_gates = false` on their base branch lose both the automatic full lane and the floor. They keep the proof gate and the safety gates.

Normal-lane runs in flight that skipped `validate` or `review` are blocked at the next push. The fix is to run the gate or record an override with a reason.

A hard path the built-in list misses ships on normal-lane gates. A repo adds it to `extra_hard_paths`. The built-in list widens when two repos need the same path.
