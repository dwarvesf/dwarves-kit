# Sub-goal 04: grill-conditioning (3-signal precheck + blindspot pass + `reason=` emit)

**Merge policy:** auto
**Time budget:** 2-2.5 hours of loop work
**Proof:** full reviewable proof: grill fixture captures (home-turf auto-skip WITH the `reason=density-low` line; declared-novelty fires the interview; S2 domain-novelty emits the blindspot table first); a live `reason=` skip line in a real ledger log; coverage-delta row.
**Design:** bearing
**Depends on:** none in this stack. **CROSS-MEGA HOLD (reader-first):** do not start until harness-observatory sub-goal 01 (`kit_gates` reader) has MERGED, verify `gh pr view`; until then this is a blocker fingerprint, hop to other work.
Model: sonnet
**Branch:** `feat/grill-conditioning`
**PR base:** `feat/kit-template-fields`
**Over-test: yes** (the precheck decides when the kit's highest-leverage step runs; wrong conditioning silently degrades every future run)

## Outcome

ID-247 whole: `/kit:grill` fires only where unknowns live. (a) 3-signal unknown-density precheck in grill.md's preamble (S1 territory: target paths' git history empty or >90d stale; S2 domain: task nouns absent from repo + specs/ADRs; S3 declared novelty); fire on >= 2 signals or S3 alone, else AUTO-SKIP; (b) the skip is auditable: `gate-ledger.sh` skip lines gain `reason=<home-turf|density-low|operator-wave>` (grammar matched to the observatory parser's tolerance); (c) interview reordered by blast radius: contradictions, architecture-changing answers, silent-defaults-stated, taste questions offered as prototypes not questions; (d) blindspot pass as step 0 when S2 fires: a 5-8 row unknown-unknowns table (what / why it matters / the question to ask), operator picks rows to drill.

## Quality bar

No new command, no new agent, no gate-REQUIREMENT change: grill stays the universal-prepend advisory gate, only its firing gets conditioned and its skips get reasons. Precheck signals are checkable in seconds (one git log, one rg), never a research project.

## How to close the loop

- Three fixture scenarios captured (auto-skip + reason line; interview fired; blindspot table emitted).
- Live capture: one real run's ledger log line carrying `reason=`; cross-check the grammar against harness-observatory's `kit_gates` parser (its DECISIONS.md names it).
- Over-test: threshold edges (exactly 2 signals; S3-only; stale-vs-fresh 90d boundary); coverage-delta row.
- Kit-adopted: run the lane, record gates before push.

**Done =** all three fixture captures committed + a live `reason=` line proven parseable by the sibling's kit_gates grammar.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 05-emit-sweep (grammar + exemption pointers). 3. `DECISIONS.md`: precheck thresholds + reason grammar verbatim. 4. EXIT.

## Scope edges

**In:** `commands/grill.md`, `lib/gate-ledger.sh` (reason token on skip lines only), tests.
**Out:** other commands' emits (05); templates (03); the ledger reader (sibling mega).
**Not:** a learned router; changing which lanes REQUIRE grill; new interview content beyond the ordering + blindspot step.

## Where to look

`research/2026-07-04-fable-unknowns-absorption.md` Design 1 (the full mechanic); `commands/grill.md` current contradiction-first shape; ledger probe data (82% skip over 63 runs) in cockpit row ID-247.

## PR body

Grill unknown-density conditioning: 3-signal precheck, blindspot pass step 0, blast-radius ordering, `reason=` auditable skips. Stacked on kit-template-fields; review after it. Reader-first honored (kit_gates merged in the sibling mega before this). Covers ID-247.

## Notes

