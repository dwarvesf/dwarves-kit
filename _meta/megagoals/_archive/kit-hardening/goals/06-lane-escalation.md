# Sub-goal 06: lane mid-flight escalation on emergent scope

**Merge policy:** auto , a new classify trigger + gate-ledger re-plan, testable.
**Time budget:** 2-3 hours.
**Proof:** run-table , a `tiny`/`normal` task whose SPEC introduces auth/data-model/migration scope re-classifies to a heavier lane at the spec->build boundary; the escalation re-plans the gate-ledger (up-only); the downgrade guard still blocks a lighter re-class; it is advisory + recorded.
**Depends on:** none (independent).
Model: sonnet
Effort: medium
**Branch:** feat/kit-harden-06-laneesc
**PR base:** mega/kit-hardening

## Outcome

The lane is no longer frozen only at classify-time. `lane-classify` re-runs against the SPEC at the spec->build boundary (the first point real scope is concrete). A heavier-lane trip escalates the lane + re-plans the gate-ledger; the change is up-only (the downgrade guard stays), advisory, and recorded. This catches a `tiny`/`normal` task that grows into an auth / data-model / migration change , the same "untrustable autonomous run silently under-sizing its lane" failure class the whole ADR targets.

## Quality bar

UP-ONLY: escalation can only add rigor, never remove it , the existing downgrade guard must still block a lighter re-classification. Advisory + recorded, not a hard block. Reuses the kit's existing heavy destinations (full lane, ADR-0017 mega-goal promotion); this supplies only the missing TRIGGER (re-classify at the spec boundary), not a new lane.

## How to close the loop

Add the spec->build-boundary re-classify trigger to the lane machinery; on a heavier result, re-plan the gate-ledger up-only. Verify:

```
cd dwarves-kit && bash tests/test-lane-escalation.sh   # tiny+auth-spec -> full; gate-ledger re-planned; downgrade blocked; advisory+recorded
```

Captured evidence: run-table at `docs/verification/lane-escalation.md` , a positive row (tiny task + auth-scoped SPEC escalates to full, gate-ledger gains the heavier phases), a downgrade-guard row (a lighter re-class is refused), and an advisory row (escalation records but does not halt the run).

**Done =** `test-lane-escalation.sh` proves a heavier-scope SPEC escalates the lane at the spec->build boundary + re-plans the gate-ledger up-only, the downgrade guard still holds, and the escalation is advisory + recorded.

**Kit-adopted repo? Record the gates.** `bash lib/lane-classify.sh classify "lane mid-flight escalation: re-classify at spec->build boundary, up-only gate-ledger re-plan"`, record build + review via `lib/gate-ledger.sh` before push.

## Handoff on completion

1. Flip 06's box, PR # + SHA.
2. HOT `HANDOFF.md`: next is whatever remains (05 if its deps landed, else 07).
3. WARM `DECISIONS.md`: the lane can now escalate up-only at the spec boundary; the classify-time freeze is relaxed for emergent scope only.
4. Report IN records, EXIT.

## Scope edges

**In:** the spec->build re-classify trigger, the up-only gate-ledger re-plan, tests.
**Out:** the classify-time triggers (task text, grill answers, spec-drift text , unchanged); the downgrade guard (preserved, not touched beyond confirming it still blocks).
**Not:** a full re-plan of the run; downgrade/relaxation of any kind; a new lane.

## Where to look

`lib/lane-classify.sh` (the classifier + its triggers), `lib/gate-ledger.sh` (plan/re-plan + the downgrade guard), the spec->build phase boundary in WORKFLOW.md / `commands/`, ADR-0028 refinement point 4.

## PR body

Adds mid-flight lane escalation on emergent scope (kit-hardening SG-07, ADR-0028): re-runs `lane-classify` against the SPEC at the spec->build boundary; a heavier-lane trip escalates + re-plans the gate-ledger up-only (downgrade guard preserved), advisory + recorded.

Verify: `bash tests/test-lane-escalation.sh`. Proof: `docs/verification/lane-escalation.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. Independent; on the integration branch.

## Notes

<empty>
