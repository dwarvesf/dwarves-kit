# Sub-goal 04: quiz gate (Flow A, the speed regulator)

**Merge policy:** auto (building + testing the mechanism is auto; the gate is USED interactively by Han on future runs)
**Time budget:** 3-4 hours.
**Proof:** run-table: a high×high change generates 5 quiz questions FROM the actual diff + test results (not narrative) · the three responses (engage/defer/wave) each land in the debt ledger (fixture per branch) · engage routes through deep-understand's mastery-gate engine · WIRING NC: the tap fires on a significant+worthy gate PR, is ABSENT on a significant-but-low-worthiness change AND on a non-significant change · NEVER must-pass: a waved change still merges.
**Depends on:** 02 (significance decides WHEN) + 03 (the explainer material the quiz is built from).
Model: opus
Effort: high
**Branch:** feat/ug-04-quiz-gate
**PR base:** feat/ug-03-explain (stacked on 03)

## Outcome

The ★-tap NUDGE (Litt's speed regulator, tuned to Han's debt-budget model): when SG-02 flags a change high×high (significant AND understanding-worthy) on a `gate`/gated-final PR, the human gets a one-line tap ("worth understanding: <why>") and THREE responses , **engage now** (pull the 5-question quiz, generated from the ACTUAL diff + tests, via `deep-understand`'s mastery-gate engine), **defer** (to the weekend batch, SG-05), or **wave** (accept the debt knowingly). All three write to the **debt ledger**. This is Flow A (inline, default). It is a NUDGE, NEVER must-pass-to-merge (ADR-0031 Refinement): it gates the human's attention, not the merge, and never hard-blocks a correct build. A significant-but-low-worthiness change gets NO tap (SG-02's anti-fatigue guard), preserving Han's hands-off default.

## Quality bar

Questions from the DIFF + tests, never the agent's narrative (a quiz on the agent's misconceptions is worse than none). Reuse deep-understand's engine, do not build a second quiz system. The three-way choice (engage/defer/wave) is always available and always logged , waving is a first-class, RECORDED option, not a failure. Never must-pass-to-merge (open-fork 2 RESOLVED: nudge).

## How to close the loop

`/spec` + `/spec-validate` first (resolve open-fork 2). Then `bash tests/test-quiz-gate.sh`: the 5-Q-from-diff generation, the grounded-NC (narrative-differs fixture), the deep-understand routing, and the WIRING NC (fires on significant gate-PR, absent on non-significant). Assumptions: ROADMAP 04 + ADR-0031 §2/§3.

**Done =** a high×high gate-PR taps with engage/defer/wave (all logged to the debt ledger), engage generates a 5-Q quiz from the diff+tests via deep-understand, the tap is absent on low-worthiness + non-significant changes (wiring NC), waving still merges (never must-pass); tests green.

## Scope edges

**In:** the quiz generator (from diff+tests), the deep-understand routing, the merge-boundary wiring keyed on significance-classify, tests.
**Out:** the explainer artifact (03); the batch flow (05 , the batch consumes the same material asynchronously); the significance heuristic (02).
**Not:** a hard build-block (advisory per ADR-0031); a new quiz engine (route through deep-understand); a quiz on non-significant changes (that IS the fatigue failure mode).

## Where to look

the ops-toolkit `deep-understand` skill (its AskUserQuestion quiz + mastery-gate engine , route through it), SG-03's explainer material, lib/significance-classify.sh (02, the WHEN), the merge/ship boundary (commands/ship.md, mega-merge, the gated-final hold), ADR-0031 §2/§3.

## PR body

Quiz gate (ADR-0031 §2/§3, Flow A): a 5-question quiz from the actual diff+tests, routed through deep-understand's mastery gate, wired as the speed-regulator before merging a significant gate PR; advisory. Stacked on #<03's PR>. Verify: `bash tests/test-quiz-gate.sh` (5-Q-from-diff + grounded-NC + wiring-NC). Roadmap: ops-toolkit `_meta/megagoals/understanding-gate/ROADMAP.md`.

## Notes

<empty>
