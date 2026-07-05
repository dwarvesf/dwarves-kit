# Sub-goal 03: process-plumbing

**Merge policy:** auto
**Time budget:** 2-3 hours of loop work
**Proof:** run-table (grep the hook's spec-only condition; grep wrap-session's one-line default; grep plan-for-mega-goal for FEEDBACK removal + the habit line)
**Depends on:** 02 (wording mirrors its rules; cross-repo so logical only)
Effort: low
**Branch:** feat/cc-hyg-03-plumbing (repo: tieubao/dotfiles)
**PR base:** main

## Outcome

The plumbing that enforced the diary tax now matches the trimmed rules (closes ID-234's plumbing half):

1. The **impl-notes UserPromptSubmit hook** (dotfiles) fires only for spec-implementation work; the non-spec mandate is dropped.
2. The **wrap-session skill** drafts one-line LAB_LOG entries by default, multi-line only for SDD ships/incidents (same budget language as 02).
3. The **plan-for-mega-goal skill template** retires FEEDBACK.md from the scaffold: skill-meta observations route to NOTES.md `## Proposed additions` (the one channel the audit proved is read). Also add ID-240's habit line: scaffold a successor mega-goal only when starting it.

## Quality bar

The hook and skills enforce exactly what CLAUDE.md says after 02, nothing more. No orphaned references to FEEDBACK.md survive in the template or its references/.

## How to close the loop

- Edits live in ~/workspace/tieubao/dotfiles (hooks + `~/.claude/skills/{wrap-session,plan-for-mega-goal}` chezmoi sources). Cross-repo: lane via `lib/lane-classify.sh` + spec + spec-validate + gate-ledger, never /kit:*.
- Run-table: grep hook for the spec-gating condition; grep wrap-session for the one-line default; `rg -c FEEDBACK ~/.claude/skills/plan-for-mega-goal/` shows only the retirement note; grep the habit line. All committed.
- Dotfiles watcher: stage+commit in ONE shell call.

**Done =** hook fires spec-only, wrap-session defaults to one line, plan-for-mega-goal scaffold list has no FEEDBACK.md and carries the habit line, proven by the run-table.

## Handoff on completion

1. Flip the ROADMAP box + PR #. 2. Overwrite HANDOFF.md (next: 04 in dwarves-kit). 3. Append to DECISIONS.md. 4. Exit immediately.

## Scope edges

**In:** the impl-notes hook condition, wrap-session, plan-for-mega-goal template + its references.
**Out:** ops-toolkit CLAUDE.md (02), any other skill (07 owns pruning), existing mega-goal folders' FEEDBACK.md files (history, leave them).
**Not:** no hook deletions, no new skills, no rewriting plan-for-mega-goal beyond the FEEDBACK retirement + habit line.

## Where to look

dotfiles hooks dir (the UserPromptSubmit impl-notes hook); `~/.claude/skills/wrap-session/` and `~/.claude/skills/plan-for-mega-goal/` (+ references/feedback-template.md); audit R3 for the evidence.

## PR body

One-line outcome; the run-table; link to ROADMAP.md; closes the plumbing half of ID-234 (rules half in the 02 PR).

## Notes

