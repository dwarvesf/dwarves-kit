# SPEC-081: Anchored-confidence merge for review-team

Status: SHIPPED
Date: 2026-06-11
Lane: normal (classified: normal)
Type: spec-feature / behavioral (command-prose contract)
Board: ID-075
Source: docs/absorption/2026-06-11-pinned-kits.md #1 (15/16; EveryInc
ce-code-review Stage 5 + findings-schema, MIT, @4719dc5)

## Decision

1. **Structured findings (Step 2)**: every reviewer returns each finding as a
   structured block , title, file:line, severity, Route (SPEC-078), a
   CONFIDENCE at one of 5 behavioral anchors, and the anchor's self-test:
   0 (hunch, no location), 25 (pattern suspicion , "I'd need to run it"),
   50 (located + plausible mechanism , "another lens would likely agree"),
   75 (traced the path , "I can name the failing input"),
   100 (proved , "I ran it / the logic is airtight, I can show the output").
2. **Fingerprint dedup (Step 3)**: fingerprint = file + line-bucket (+-3 lines)
   + normalized title (lowercase, punctuation stripped). Same fingerprint
   across reviewers = ONE finding listing all lenses.
3. **Corroboration promotion**: each ADDITIONAL lens sharing the fingerprint
   promotes confidence ONE anchor step (max 100).
4. **LATE confidence gate**: AFTER dedup + promotion (so weak findings get
   their promotion chance first , the upstream rationale), findings below 75
   are suppressed from the main report, EXCEPT CRITICAL severity which
   survives at 50+. Suppressed findings move to a collapsed appendix with
   their self-tests , never silently dropped.
5. **Report**: finding lines gain `Confidence: NN`; the appendix section is
   part of the template.

## Acceptance criteria

- AC1: Step 2 carries the 5-anchor table with a self-test per anchor; pins.
- AC2: Step 3 carries fingerprint (file + line-bucket +-3 + normalized title),
  the one-step promotion rule, and the LATE gate (<75; CRITICAL at 50+) with
  the appendix never-drop rule; pins.
- AC3: the report template carries Confidence + the suppressed appendix; pin.
- AC4: ordering pinned: the gate paragraph appears AFTER the promotion
  paragraph in the file (late-gate is the point).
- AC5: suites green; NC: prose revert flips pins RED.

## Verification

- 10 meta pins failing-first -> green (incl. the file-order late-gate pin + its
  uniqueness guard). Suites: meta 465/465, hooks 412/412, e2e 20/20.
- NC: the promotion-rule token reverted -> 2 RED -> restored.

## Review

Date: 2026-06-11. Single combined lens, 6/10 pre-fix. 2 HIGH logic holes: a
SUPPRESSED finding could still be routed gated_auto at the decision gate (now
unsuppressed-only, stated at both ends); telemetry findings=K was ambiguous
post-suppression (now K = main-report only + suppressed=S). MEDIUM: the 0-anchor
self-test contradicted the mandatory file:line block (0-anchor is now HOLD, not
a formal finding); the verdict is stated as unsuppressed-driven. LOW: ordering
pin gained a uniqueness guard; uniform row-format note. Verdict: SHIP.
