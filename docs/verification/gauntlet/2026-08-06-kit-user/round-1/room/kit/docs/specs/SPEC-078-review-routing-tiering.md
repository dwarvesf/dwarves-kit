# SPEC-078: review-team apply-class routing + model tiering (absorption pair)

Status: SHIPPED
Date: 2026-06-11
Lane: normal (classified: normal)
Type: spec-feature / behavioral (command-prose contract; no lib/hook change)
Board: ID-076, ID-078
Source: docs/absorption/2026-06-11-pinned-kits.md #2 (EveryInc action-class rubric,
MIT, @4719dc5) + #4 (EveryInc Stage 4 model tiering)

## Decision

1. **Apply-class routing (ID-076)**: every finding carries a `Route` ,
   `gated_auto` (concrete suggested fix exists -> dispatched to
   `responding-to-review` at the decision gate), `manual` (needs design input ->
   becomes a board row), `advisory` (report-only -> recorded in the spec's
   `## Review`). Severity stays urgency; class is the follow-up SHAPE. On
   reviewer disagreement about class, route conservatively (manual beats
   gated_auto). Upstream's deprecated `safe_auto` is deliberately absent. SCOPED OUT
   (review F3, recorded): upstream's `owner` field , the three route
   destinations already encode ownership (agent / board / spec record); and
   `requires_verification` , duplicated by the kit's universal proof-of-done
   gate, every behavioral fix owes verification regardless of a per-finding flag.
2. **Model tiering (ID-078)**: the security reviewer inherits the session model
   (high-stakes lens); architecture + test-coverage dispatch with the mid-tier
   model override. One fallback sentence: if the override is unavailable, omit
   it. Halves the command's own "3x the tokens" cost estimate.

## Acceptance criteria

- AC1: Step 3 merge instructs the Route classification (3 classes + the
  conservative-on-disagreement rule); the Step 4 report template carries a Route
  column/line; Step 5 routes each class to its named destination.
- AC2: Step 2 names the tiering (security inherits; the other two mid-tier) +
  the fallback sentence; the cost note reflects the reduction.
- AC3: meta pins for both wirings; suites green. (Prose contract: the executable
  surface is the command text agents follow; pins are the regression guard.)

## Test plan

Meta pins (failing-first): route classes present + conservative rule; Step 5
destinations; tiering sentence + fallback. NC: revert the prose -> pins RED.

## Verification

- Meta pins failing-first: 5 RED pre-edit -> green. Suites: meta 449/449, hooks
  398/398, e2e 20/20. NC: gated_auto prose reverted -> 1 RED -> restored.

## Review

Date: 2026-06-11. Single combined lens (consistency + absorption fidelity), 6/10
pre-fix. HIGH: "inherits the session model" was mechanically false , the
security-auditor agent frontmatter defaults to sonnet, so omitting an override
DOWN-tiers; the command now instructs an explicit session-model override.
MEDIUM: Route line was on the Critical template row only -> all severity rows;
owner/requires_verification scoped out WITH the recorded reasons (route
destinations encode ownership; proof-of-done universalizes verification).
Verdict: SHIP.
