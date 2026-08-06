# Sub-goal 02: understanding-worthiness classifier (two signals)

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table: a change that is significant AND worthy (new primitive / irreversible / novel / high-blast / must-explain) ★-taps · a significant-but-LOW-worthiness change (mechanical, test-covered, reversible) is WAVED+logged, NOT tapped (negative control , the anti-fatigue guard) · an obvious change is not-significant · an impl-note entry raises worthiness (feed test) · each verdict writes the debt-ledger marker · deterministic.
**Depends on:** none.
Model: sonnet
Effort: high
**Branch:** feat/ug-02-worthiness
**PR base:** master

## Outcome

`lib/significance-classify.sh` , deterministic pure-bash (sibling to `lane-classify.sh`) emitting TWO signals per ADR-0031's Refinement: **significance** (full lane OR design-bearing OR new public surface = did a lot change) AND **understanding-worthiness** (will not-understanding cost a later loop , triggers: new primitive future work builds on / irreversible-or-costly-to-reverse / first-of-kind / high blast radius / human-must-explain-defend-decide). It ★-taps ONLY high×high; significant-but-low-worthiness is waved+logged (the anti-fatigue guard). It reads `docs/implementation-notes/<slug>.md` as a worthiness FEED (an unspecified-decision entry raises worthiness). Each verdict writes the debt-ledger marker (reusing the kit-face additive-marker convention) that SG-04's nudge and SG-05's paydown both read. This is the load-bearing knob: over-tap = fatigue (fights Han's hands-off default), under-tap = debt returns untracked.

## Quality bar

Deterministic + testable in isolation (the `lib/` earns-its-place rule). The default heuristic is DEFENSIBLE and TUNABLE, not magic , documented, one flag to adjust. The ledger marker reuses the existing additive-marker shape, does not invent a third convention.

## How to close the loop

`/spec` + `/spec-validate` first (pin the exact heuristic + marker format; resolve ROADMAP open-fork 1). Then `bash tests/test-significance-classify.sh` (significant cases + the obvious NC + determinism + the marker write). Assumptions: ROADMAP 02 + open-fork 1.

**Done =** the classifier returns both signals deterministically, ★-taps only high×high, WAVES significant-but-low-worthiness (anti-fatigue NC), raises worthiness on an impl-note feed, writes the debt-ledger marker, tests green.

## Scope edges

**In:** lib/significance-classify.sh, its ledger marker, tests, a WORKFLOW/AGENTS line on when it fires.
**Out:** what to DO on significant (03 explainer, 04 quiz); the design-bearing trigger (01 owns that , related but distinct: design-bearing gates the BEFORE record, significance gates the AFTER explainer).
**Not:** an LLM classifier (deterministic bash, like lane-classify); a fourth ledger convention.

## Where to look

lib/lane-classify.sh (the sibling pattern , structure + test shape), lib/role-classify.sh (another deterministic classifier), lib/gate-ledger.sh (the marker convention to reuse), `docs/implementation-notes/` (the worthiness FEED , read these), ADR-0031 §3 + Refinement (two signals + impl-notes feed + debt ledger), kit-face SG-03/05 (the additive-marker shape).

## PR body

Significance classifier (ADR-0031 §3): deterministic `lib/significance-classify.sh` deciding when the understanding-gate fires (full-lane OR design-bearing OR new-public-surface, tunable), recording collectible markers for the weekend batch. Verify: `bash tests/test-significance-classify.sh` (significant + obvious-NC + determinism). Roadmap: ops-toolkit `_meta/megagoals/understanding-gate/ROADMAP.md`.

## Notes

<empty>
