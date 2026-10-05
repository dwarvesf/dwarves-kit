# Spec: mega gate parity with the ship-gate

Generated: 2026-10-05
Status: VALIDATED (design call made in the kit-speed run; no validation fan-out)
Lane: full
Type: spec-bugfix
Source: kit-speed mega-goal, sub-goal 10 (R24).

## Problem

`lib/goal/mega-merge.sh gate <rid> <lane>` passed three times in one run while `hooks/ship-gate.sh` then blocked the push. The mega gate runs only the ledger check. The hook applies two more rules that read the diff and the spec:

1. A normal-lane spec that `spec.sh depth size` sizes as large needs a `validate` ran or override record.
2. A diff that touches a hard path owes the full lane's gates, whatever lane the ledger START line says.

A green mega gate therefore proved less than a passing push, and the loop auto-merged on it.

## Design

- **One helper, two callers.** `lib/gate/ship-rules.sh` is a sourced file. It holds the default-branch base resolver, the merge-base helper, the `[gate]` switch reader, `ship_rule_large_spec` and `ship_rule_floor`. The two rule functions print the BLOCKED message on stderr and return 2, or return 0 on a pass and on any ambiguity (the ship-gate stays a fail-open quality gate).
- **The hook calls the helper.** `hooks/ship-gate.sh` deletes its inline copies, sources the helper, and keeps its own exit codes (2) and audit log lines. The helper writes the log only when `SHIP_RULES_LOG=1`, which only the hook sets. Messages are byte-identical to the previous hook for the same inputs, apart from the kit path in the printed override command.
- **The mega gate calls the same helper.** After the unchanged ledger check passes, `gate` resolves the repo (`MEGA_MERGE_ROOT`, else the cwd's repo), finds the spec with `spec_for_slug` (the resolver the hook and validate-round use), takes the diff base as the merge base of HEAD and the remote default branch, and runs the two rules with the caller's lane and its own ledger script. A failing rule exits 1 with the same message the hook prints. `gate` stays free of file writes.
- **Rule order matches the hook.** Ledger check first, then the large-spec rule (normal lane, spec found, `[gate] lane_gates` on at the repo), then the floor (any lane, spec or not, lane_gates read at the merge base).
- **Inputs the mega gate cannot see.** The hook's lane is the ledger START-AMEND over the spec header and its head is the pushed ref. The mega gate uses the lane argument and the cwd's HEAD. A merge run from a checkout that is not on the PR branch sees that checkout's diff, as the existing ledger check already keys on rid only. The hook's full-lane implementation-notes rule stays unmirrored (the PR was pushed through the hook).

## Tasks

- [ ] TASK-1: extract the two rules and the base helpers into `lib/gate/ship-rules.sh`
- [ ] TASK-2: `hooks/ship-gate.sh` sources the helper; messages and exit codes unchanged
- [ ] TASK-3: `lib/goal/mega-merge.sh gate` runs both rules through the helper
- [ ] TASK-4: `tests/test-mega-gate-parity.sh` pins five parity cases plus a no-spec floor case

## Acceptance

- A large normal-lane spec with no validate record: the hook blocks and `gate` exits 1 with the same message.
- The same spec with a validate override: both pass.
- A diff touching a hard path under a normal-lane ledger missing full-lane phases: both block with the same message; with every full phase recorded, both pass.
- A small normal spec with no hard path: both pass.
- `tests/test-ship-gate-*.sh`, `tests/test-mega-merge.sh` and `tests/test-hooks.sh` stay green.

## Verification

```
bash tests/test-mega-gate-parity.sh
bash tests/test-mega-merge.sh
bash tests/test-ship-gate-coverage-map.sh
bash tests/test-ship-gate-fail-closed.sh
bash tests/test-ship-gate-impl-notes.sh
bash tests/test-ship-gate-profiles.sh
bash tests/test-hooks.sh
# negative control: a saved copy of mega-merge.sh without the helper call; cases a and c go red
```
