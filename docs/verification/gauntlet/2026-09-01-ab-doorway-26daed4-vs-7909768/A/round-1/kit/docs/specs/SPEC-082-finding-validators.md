# SPEC-082: Per-finding validator wave for review-team

Status: SHIPPED
Date: 2026-06-11
Lane: normal (classified: normal)
Type: spec-feature / behavioral (command-prose contract)
Board: ID-079
Source: docs/absorption/2026-06-11-pinned-kits.md #5 (13/16; EveryInc
ce-code-review Stage 5b, MIT, @4719dc5)

## Decision

New **Step 3b: Validate verdict-driving findings** in review-team, between the
confidence gate and the report:

1. Scope: every UNSUPPRESSED finding with severity CRITICAL or HIGH (the ones
   that drive a FIX-THEN-SHIP / DO-NOT-SHIP verdict). MEDIUM/LOW are not
   validated (scaled down from upstream's all-survivors wave: 3 lenses produce
   far fewer findings than 9 personas). Anchor-100 MEDIUM/LOW findings are deliberately not
   validated: the anchor-100 self-test ("I ran it") substitutes for an external
   validator at lower severity (review F5, silence made intentional).
2. Shape: ONE independent read-only validator subagent PER finding, never
   batched , a single batched validator pattern-matches across findings and
   recreates the persona-bias problem (the upstream rationale, quoted).
3. Framing: the validator is an adversarial REFUTER , it tries to disprove the
   finding at its file:line citation; it returns confirmed (with evidence) or
   refuted (with the counter-evidence).
4. Disposition: refuted findings DEMOTE to the suppressed appendix carrying the
   refutation; confirmed findings stay, marked validated.
5. Fail-safe: validator infra failure (error/timeout) NEVER drops a
   CRITICAL/HIGH finding , it stays in the main report marked `unvalidated`,
   and the verdict treats it as live.

## Acceptance criteria

- AC1: Step 3b exists between the gate step and Step 4, with the per-finding
  never-batch rule + the upstream rationale; pins.
- AC2: the refuter framing + both dispositions (refuted -> appendix with
  refutation; confirmed -> marked validated) present; pin.
- AC3: the infra-failure fail-safe present (never drops, marked unvalidated,
  verdict treats as live); pin.
- AC4: scope line (unsuppressed CRITICAL/HIGH only) present; pin.
- AC5: suites green; NC: prose revert flips pins RED.

## Verification

- 8 meta pins failing-first -> green (incl. the placement-order pin). Suites:
  meta 473/473, hooks 412/412, e2e 20/20.
- NC: the never-batch token reverted -> 1 RED -> restored.

## Review

Date: 2026-06-11. Single combined lens, 6/10 pre-fix. 2 HIGH template gaps: the
appendix header covered only below-gate findings (refuted ones had no slot ,
header + reason field widened); validated/unvalidated had no place in the row
format (Status field added). MEDIUM: Step 5 now states the unvalidated-is-live
read-path; cost note + validator mid-tier model sentence added. LOW: the
anchor-100 skip made an intentional recorded decision. Verdict: SHIP.
