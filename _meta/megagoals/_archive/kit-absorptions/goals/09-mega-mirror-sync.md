# Sub-goal 09: mega-mirror-sync (never-diverge holds for the new knobs)

**Merge policy:** auto
**Time budget:** 45-60 minutes of loop work
**Proof:** run-table: grep rows for the two mirror paragraphs in `commands/mega.md`; the never-diverge checklist (skill beats vs mega.md beats, cell by cell) committed in the proof; `Done =` line evidence.
**Design:** obvious
**Depends on:** 07, 08
Model: sonnet
**Branch:** `feat/mega-mirror-sync`
**PR base:** `feat/lane-de-escalation`

## Outcome

`commands/mega.md`'s own contract ("the two must never diverge... a drift here is a bug in this file") holds for this run's new knobs: the tiny-decompose rule (from sub-goal 02's skill half) and the Consolidate mode (from 08) each get their kit-native mirror paragraph, same projection style as the 2026-07-04 #164 mirror sync. A short never-diverge checklist (beat-by-beat: decompose, front-load-once, merge config, run-mode, close, tiny-rule, consolidate) is committed so the NEXT skill change has a diff target.

## Quality bar

Projection, not fork: mirror the semantics, reference the skill for depth, keep mega.md's kit-native scoping (orchestrate.sh shapes, gate-ledger lanes). No behavioral lib changes.

## How to close the loop

- `rg -n 'tiny|consolidat' commands/mega.md` grep rows showing both paragraphs.
- The checklist committed (docs/ or inline in the PR body) with every beat marked synced.
- Kit-adopted: run the lane, record gates before push.

**Done =** both mirror paragraphs present + the beat checklist shows zero divergence.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: kit stack complete; remaining = TIER-4 close. 3. `DECISIONS.md`: none expected. 4. EXIT.

## Scope edges

**In:** `commands/mega.md`, the checklist artifact.
**Out:** the skill itself (dotfiles, merged upstream); any lib.
**Not:** new mega.md features; reformatting untouched sections.

## Where to look

dwarves-kit #164 (this morning's mirror sync, the style precedent); sub-goal 02 + 08 merged content; mega.md's mirror preamble.

## PR body

Mirror the tiny-decompose rule + Consolidate mode into /kit:mega, never-diverge checklist committed. Stacked; review after lane-de-escalation. Closes the mirror contract for this run.

## Notes

