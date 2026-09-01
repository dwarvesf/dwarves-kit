# Sub-goal 05: emit-sweep (the 18 dark commands: emit-owed vs documented exemption)

**Merge policy:** auto
**Time budget:** 2-2.5 hours of loop work
**Proof:** full reviewable proof: the emit-coverage sweep table (every command -> embedded emit OR documented exemption); the no-orphan sweep TEST green; one live emit per newly-wired phase-owning command captured from a real ledger log; coverage-delta row.
**Design:** bearing
**Depends on:** 04 (the `reason=` grammar + emit conventions it establishes)
Model: sonnet
**Branch:** `feat/kit-emit-sweep`
**PR base:** `feat/grill-conditioning`
**Over-test: yes** (a test-understanding-wiring-style no-orphan sweep so no command can silently stay dark again)

## Outcome

ID-256 whole: RUN_REPORT stops under-counting. The 2026-07-04 measurement (29 commands, 11 embedded emitters, 18 dark) gets closed out: phase-owning dark commands (spec, spec-validate, verify, think, design, ui-design, docs, retro, explain) each gain an embedded `gate-ledger.sh` start/record call consistent with 04's conventions; utility commands (next, start, kit-health, absorb, adopt, draft-agent, visual-team, mega*, dispatch*) get a documented no-emit exemption table (mega/dispatch already emit via the driver, SPEC-101, the table says so). A sweep TEST asserts the invariant forever: every command in `commands/` either contains a gate-ledger call or is listed in the exemption table.

## Quality bar

Observability only: the lane matrix (which gates a lane REQUIRES) is untouched; a command that ran unrecorded yesterday just becomes visible, never newly-blocking. Emit placement mirrors the freshest precedent (SPEC-136's record-before-tap wiring).

## How to close the loop

- The no-orphan sweep test green (and RED on a fixture command with neither emit nor exemption, the negative control).
- Sweep table committed in the proof: 29 rows, each = emit line reference OR exemption row.
- Live captures: run one newly-wired command per phase family; capture its ledger line.
- Cross-check: the sibling mega's `ledger gate-yield` ingests the new lines (or the golden fixture proves the format if the sibling lags).
- Kit-adopted: run the lane, record gates before push.

**Done =** sweep test green (with its red-NC), the 29-row table committed, live captures present.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 06-pitch-assembler. 3. `DECISIONS.md`: the exemption table rationale per command. 4. EXIT.

## Scope edges

**In:** `commands/*.md` emit lines, the exemption table (WORKFLOW.md or a docs page), `tests/` sweep test.
**Out:** grill (04, merged below); gate requirements; the observatory reader (sibling).
**Not:** new gates; changing any lane's matrix cells; emit content beyond the established grammar.

## Where to look

The 11-vs-18 measurement in cockpit row ID-256; `tests/test-understanding-wiring.sh` for the sweep-test pattern; SPEC-136 for emit-wiring precedent; 04's DECISIONS.md for grammar.

## PR body

Emit sweep: 18 dark commands classified emit-owed vs exempt, no-orphan sweep test locks the invariant, RUN_REPORT now reflects the full matrix. Stacked on grill-conditioning; review after it. Covers ID-256.

## Notes

