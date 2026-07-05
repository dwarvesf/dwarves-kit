# Sub-goal 06: pitch-assembler (`/kit:pitch`, the outward twin of /kit:explain)

**Merge policy:** auto
**Time budget:** 2 hours of loop work
**Proof:** full reviewable proof: a REAL pitch generated from a shipped rid (committed as the sample artifact); degrades-gracefully fixture captures (missing grill record, missing impl-notes); the never-auto-post NC; coverage-delta row.
**Design:** bearing
**Depends on:** none in this stack (SPEC-136 merged 2026-07-04, the ship Step 8 seam is stable)
Model: sonnet
**Branch:** `feat/kit-pitch`
**PR base:** `feat/kit-emit-sweep`
**Over-test: yes** (an assembler that fabricates when a source is missing would poison buy-in docs)

## Outcome

ID-250 whole: a thin `commands/pitch.md`, an ASSEMBLER not a writer, re-audiencing artifacts every gated run already produces. Doc shape: 1 Outcome (demo first), 2 Unknowns-we-accounted-for (grill record + impl-notes Deviations + the proof's negative controls), 3 Evidence (proof run-table verbatim + PR links), 4 Cost/not-done, 5 The ask. Entry points: `/kit:pitch <rid|spec-slug>` on demand, plus ONE advisory line in ship Step 8 (after the SPEC-136 record + tap calls) offering it when the recorded verdict is `significance=high` AND the repo is team-shared. Output: markdown to stdout + `--out`; NEVER auto-posts anywhere.

## Quality bar

Assembles only what exists: a missing source produces an explicit "no grill record for this run" line, never invented content. `/kit:explain` stays the inward lens; zero duplication between the two (pitch references, never re-explains).

## How to close the loop

- Real run: `/kit:pitch` against a recently shipped rid (e.g. a kit-run-integrity PR); the 5-section doc committed as the sample.
- Degrades-gracefully fixtures: rid with no grill record; rid with no impl-notes; both produce the explicit-absence line (captured), never fabrication.
- Never-auto-post NC: the command's only outputs are stdout + `--out` file; grep the command doc + any helper for `gh pr comment|discord|slack|curl` (absent, captured).
- Ship advisory line: fixture with significance=high prints the offer; significance=low prints nothing (both captured).
- Kit-adopted: run the lane, record gates before push.

**Done =** the real sample pitch committed + both graceful-degradation captures + the never-auto-post NC green.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 07-lane-de-escalation. 3. `DECISIONS.md`: the team-shared repo detection rule chosen. 4. EXIT.

## Scope edges

**In:** `commands/pitch.md`, one advisory line in `commands/ship.md` Step 8, tests/fixtures.
**Out:** explain/quiz-gate content; any auto-posting integration.
**Not:** HTML surface (later, on demand); generating NEW analysis (assembly only).

## Where to look

`research/2026-07-04-fable-unknowns-absorption.md` Design 4; `commands/explain.md` (the inward twin's shape); `commands/ship.md` Step 8 post-SPEC-136; significance-classify.sh verdicts.

## PR body

`/kit:pitch`: outcome-first buy-in doc assembled from spec + proof + impl-notes + grill record; ship offers it only on significance=high in team-shared repos; never auto-posts. Stacked; review after emit-sweep. Covers ID-250.

## Notes

