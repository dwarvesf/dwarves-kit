# SPEC-079: The 12th task type: review

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery)
Type: spec-feature / behavioral
Board: ID-074

## Problem

Standalone review intent has NO route: all 3 real phrasings (`review this PR
adversarially`, `run a multi-lens review of the diff`, `audit the changes on this
branch for security issues`) fall to spec-feature while /kit:review[-team] sits
unrouted from intake (ID-065 trace, HIGH).

## Decision

Add `review` as the 12th type on EVERY SPEC-057 parity surface:

1. **Classifier rule** (position 6b, after research, before doc): anchored to
   review-of-a-code-artifact phrasings , review + pr/diff/branch/changes/code,
   adversarial/multi-lens/code review, audit + branch/diff/pr/changes/codebase.
   Negatives pinned: `address the review feedback` stays spec-feature (acting on
   a review is build work); `review the quarterly roadmap` stays planning-bound,
   not review; `peer review the research note` stays research.
2. **Registry row**: artifact = a review report/`## Review` section with verdict
   + findings (severity + Route per SPEC-078); owning skill = /kit:review[-team];
   default class = `inert` (a review yields a report, changes no behavior);
   agent = preassigned: reviewer (single) or review-team dispatch per the
   SPEC-069 escalation rule.
3. **Loops-table row**: scope the artifact (diff/PR/branch) -> pick lens count
   (single, or multi per the escalation rule) -> dispatch read-only reviewer(s)
   -> merge + Route findings (SPEC-078) -> verdict -> record (spec `## Review`
   or standalone report).
4. **test-design-standard 5b dialect**: a review's proof is the report itself ,
   verdict + findings each citing file:line (re-findable), Route per finding;
   falsifiability = a finding that cannot be located at its citation is killed.
5. **Sweeps**: assign.md + AGENTS.md type lists gain `review`; WORKFLOW preamble
   count "other ten" -> "other eleven". Parity pin is computed (no hardcode),
   so it follows automatically; its display name updated 11 -> 12.

## Acceptance criteria

- AC1: the 3 trace phrasings classify `review`; the 3 negatives hold;
  failing-first.
- AC2: parity holds at 12 (computed pin green: loops == registry).
- AC3: `proof-gate.sh contract` on a review phrasing -> `class=inert` (registry
  floor, SPEC-071 path).
- AC4: assign.md + AGENTS.md lists carry review; 5b dialect row exists.
- AC5: suites green; NC: reverting the classifier rule flips AC1 RED.

## Verification

- Failing-first: 4 RED pre-rule -> green; review fixes added 3 more pins
  (types-12, review-and-merge, self-review). Suites: hooks 408/408, meta
  449/449, e2e 20/20.
- NC: review rule disabled -> 4 RED -> restored green.

## Review

Date: 2026-06-11. Adversarial single agent with multi-probe brief, 6/10 pre-fix.
2 CRITICAL false-pass surfaces the computed parity could not see: the `types`
subcommand still enumerated 11, and the WORKFLOW loops meta-pin used a hardcoded
ALTERNATION that made the review row invisible (green at 11 with or without the
row). Both fixed + pinned. HIGH: grill bank for review added (SPEC-058 set).
MEDIUM: PHILOSOPHY counts 11->12; negative guard widened (self-review,
review-and-merge); incident/research precedence consequences documented in the
rule comment. Registry inert default argued both ways and kept: the report IS
the proof artifact; the rigor label wording is proof-gate territory, not this
row. Verdict: SHIP.
