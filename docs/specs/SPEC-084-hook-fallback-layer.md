# SPEC-084: Hook fallback layer (closing the ID-036 layering contract)

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery hard-gate)
Type: spec-feature / doc-contract + pins
Board: ID-036 (I3, rescoped 2026-05-23 to the hooks-as-fallback layer)

## Problem

The layering contract has three layers; two are declared, one is open:

| Layer | Declared where | State |
|---|---|---|
| Orchestration (LLM-driven) | AGENTS.md operate-contract + SPEC-083 entry wire | declared |
| Agents (step-actors) | `docs/architecture.md` "Command vs agent" | declared |
| Hooks (fallback enforcement) | nowhere; architecture.md line marks it "still open" | OPEN |

Without the declaration, two standing confusions persist: (a) conflict C3,
"Guardrails over guidance" read as "hook everything", vs the orchestration-first
doctrine; (b) no placement rule for the next proposed hook, so hooks accrete by
vibes. 16 hooks exist today with three de-facto classes nobody has named.

## Decision

One new `docs/architecture.md` section, "Hook fallback layer (closing the
layering contract)", directly after "Command vs agent":

1. **The 3-layer rule**: orchestration decides and acts (guidance lives here);
   agents isolate and parallelize steps; hooks exist ONLY as fallback for
   failure modes that survive prose instruction.
2. **Placement decision test** (in order): trusted-in-prose -> orchestration,
   not a hook; survives-prose + irreversible damage -> HARD hook (blocks);
   survives-prose + recoverable drift -> ADVISORY hook (warns, exit 0);
   no judgment involved -> CONVENIENCE hook (declared non-enforcement).
3. **The 16-row hook table**: name | event | class | the failure mode it
   backstops. Classes from measured behavior: 5 hard (safety-gate,
   secrets-guard, ship-gate, commit-format, anti-rationalization), 3 advisory
   (spec-drift-guard, slop-cleaner, context-readiness), 8 convenience
   (auto-format, statusline, notification, permission-auto-approve,
   session-state-save, pre-compact-backup, post-compact-reinject,
   codebase-index).
4. **C3 reconciliation**: "Guardrails over guidance" is bounded, guardrail =
   the hard subset where trust fails AND damage is irreversible; everything
   else stays guidance, because every hard hook costs latency and
   false-positive friction. ADR-0024 is the boundary discipline (collect
   mid-flight, enforce at ship).
5. **Folded concerns, dispositioned**: ID-012 P2 (loop QA gate) = a worked
   example of the placement rule, the autonomous loop's QA stays orchestration
   (/kit:verify) + ship-gate at the boundary, NOT a new hook. ID-027
   (autonomy-gate lens) = one bullet added to `/kit:spec-validate` Reviewer 4:
   a spec whose behavior runs inside an autonomous loop must not let the loop
   make a scope / architecture / risk decision without a human gate.
6. **Parity pin**: table row count == `hooks/*.sh` file count, the same
   anti-drift trick as the V-model inventory table.
7. The "still open" sentence in "Command vs agent" flips to a closed pointer.

## Acceptance criteria

- AC1: the section exists with the 3-layer rule + placement decision test; pins.
- AC2: the hook table has exactly one row per `hooks/*.sh` file (parity pin,
  count-robust: computed, not hardcoded).
- AC3: each of the 5 hard hooks is listed with class hard; pin per hook.
- AC4: C3 reconciliation paragraph present (bounded-guardrail tokens); pin.
- AC5: folded dispositions present (ID-012 P2 + ID-027 named); pin.
- AC6: spec-validate Reviewer 4 carries the autonomy-gate bullet; pin.
- AC7: the "still open" marker is gone from "Command vs agent"; negative pin.
- AC8: suites green; NC: drop one table row -> parity pin RED.

## Test plan

| # | Case | Proof | Expected |
|---|---|---|---|
| 1 | section + decision test | meta pins on tokens | green post-edit |
| 2 | parity | awk row count vs ls hooks/*.sh count | equal; computed both sides |
| 3 | hard-hook classes | pin per blocking hook row | 5 green |
| 4 | folds + lens | pins on ID-012 P2 / ID-027 / Reviewer 4 bullet | green |
| 5 | NC | delete one table row | parity pin RED; restore |

## Tasks

- [x] Failing-first meta pins (section, parity, classes, folds, lens, negative)
- [x] architecture.md section + still-open flip
- [x] spec-validate Reviewer 4 bullet
- [x] NC measured; suites green

## Verification

- 13 meta pins failing-first (13 RED) -> green; +1 review-added AGENTS pointer
  pin. Parity computed both sides (ls hooks/*.sh vs table rows), no hardcoded
  16.
- NC: statusline row deleted -> parity RED (expected 16, got 15) -> restored.
- Suites: meta 493/493, hooks 426/426, e2e 20/20.
- One pin re-anchored during build (survives -> survive, the single-line
  literal rule).

## Review

Date: 2026-06-11. Multi-lens inline (correctness / interface-contract /
robustness), 7.5/10 pre-fix. MEDIUM: AGENTS.md (the read-first front door)
described the enforcement boundary but never pointed at the new contract,
fixed with a pointer line + pin. LOW (accepted): permission-auto-approve
loosens rather than tightens, so its convenience class is right, but its
conservative allowlist is the load-bearing detail, left to the hook's own
header. LOW (accepted): the awk section range ends at the first non-H
heading; a future "## Hot..." section would extend the range, the parity
count's row regex keeps it safe. Verdict: SHIP.
