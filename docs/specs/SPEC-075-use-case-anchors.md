# SPEC-075: Use-case path audit + eval/research anchor recall

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery)
Type: eval / behavioral (two anchor edits ride the audit)
Board: ID-065 (+ enqueues ID-074)

## Problem

The operator's three real loop shapes (research, autoreview, build-experiment)
had never been traced end to end through routing. The trace
(docs/research/2026-06-11-use-case-path-audit.md) found: research routes 2/3,
build-experiment 1/3, autoreview 0/3 (no `review` type exists at all).

## Decision

1. Eval anchors widened (SPEC-060 narrow method): spin-up/run-a-quick-experiment,
   experiment-to-test/see/check, trial-a-library/tool/service/framework,
   throwaway-code/prototype/script. Negatives pinned: `experimental flag` stays
   spec-feature; `clinical trial data importer` not eval.
2. Research anchor gains deep-dive..snapshot/write-up phrasing; bare `snapshot`
   deliberately NOT an anchor (`snapshot the database` negative-pinned).
3. The autoreview gap is a TAXONOMY decision (12th type), not an anchor tweak:
   enqueued as ID-074 for the operator gate, with the 3 misfire phrasings as its
   ready-made truth-table rows.

## Acceptance criteria

- AC1: misfire phrasings 1/5/6 classify research/eval/eval; failing-first.
- AC2: the 3 negatives hold (no over-anchor).
- AC3: audit report committed; ID-074 row on the board; suites green.
- AC4: NC, self-contained: reverting the eval-anchor branch (spin-up/run/do-experiment + trial + throwaway alternatives in rule 5) flips the 3 eval pins RED; reverting the research-anchor branch (deep-dive..snapshot/write-up alternatives in rule 6) flips the research pin RED; restore both -> green.

## Verification

- Failing-first: 3 RED pre-fix -> green. Suites post-review: hooks 372/372, meta 439/439, e2e 20/20.
- NC run live at build: eval anchor reverted -> 2 RED; research anchor reverted
  -> 1 RED; restored green.

## Review

Date: 2026-06-11. Multi-lens (2 lenses: regex 6/10, audit-integrity 7/10). Fixed
in-branch: HIGH trial-article gate (trial the/this/our missed) -> article-free +
pin; MEDIUM deep-dive window 40->60; the run-arm precedence dependency documented
in code; the db-snapshot negative upgraded to assert its REAL route (migration) +
a deep-dive-non-research negative added; single-bookkeeping overclaim reworded;
ID-074 row extended to ALL SPEC-057 parity surfaces (5b dialect, parity pin
11->12, assign list); AC4 made self-contained. Verdict: SHIP.
