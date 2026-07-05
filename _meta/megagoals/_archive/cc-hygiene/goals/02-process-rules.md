# Sub-goal 02: process-rules

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table (grep for each of the three rule lines in ops-toolkit CLAUDE.md, exit 0 each); trivial-doc scale, no heavier artifact
**Depends on:** none
Effort: low
**Branch:** docs/cc-hyg-02-process-rules (repo: tieubao/ops-toolkit)
**PR base:** main

## Outcome

ops-toolkit CLAUDE.md stops taxing every PR with ceremony nothing reads (audit: LAB_LOG + impl-notes are write-only; 5 of 10 recent PRs were 100% bookkeeping; median PR 83.8% process lines):

1. **Log hygiene**: LAB_LOG defaults to ONE line per entry, `YYYY-MM-DD · <slug>: <what>`; the multi-line budget survives ONLY for SDD ships, incidents, and non-obvious lessons (closes ID-234's rules half).
2. **Session close**: archive/retro/board-row updates ride the nearest feature PR or a batched housekeeping PR; never a dedicated PR for a single row flip (closes ID-235).
3. **Specs**: write a spec only when there is a gate it will hit; otherwise it is documentation and gets marked as such (ID-241's rule half; the sweep itself is sub-goal 06).

## Quality bar

Three one-liners that replace paragraphs. Net negative diff on rule text is a win, not a risk.

## How to close the loop

- Edit ops-toolkit CLAUDE.md (Log hygiene + Session close sections). Same-repo sub-goal: run the kit lane from this cwd (spec + spec-validate + gate-ledger; /kit:* allowed here).
- Run-table: three greps, one per rule line, each exit 0, committed in the proof.

**Done =** all three rule lines present in ops-toolkit CLAUDE.md, proven by the grep run-table.

## Handoff on completion

1. Flip the ROADMAP box + PR #. 2. Overwrite HANDOFF.md (next: 03, whose wording mirrors these rules). 3. Append to DECISIONS.md. 4. Exit immediately.

## Scope edges

**In:** ops-toolkit CLAUDE.md rule text only.
**Out:** the hook + skill edits that enforce these rules (03 owns them); the spec-status sweep (06); LAB_LOG history rewrites (never).
**Not:** no restructuring of CLAUDE.md sections, no new sections, no touching the proof-of-done gate text.

## Where to look

ops-toolkit CLAUDE.md "Log hygiene" and "Session close" sections; research/2026-07-02-process-effectiveness-audit.md R3/R4 for the numbers.

## PR body

One-line outcome; the three greps; link to ROADMAP.md; closes ID-235, half of ID-234, rule-half of ID-241.

## Notes

