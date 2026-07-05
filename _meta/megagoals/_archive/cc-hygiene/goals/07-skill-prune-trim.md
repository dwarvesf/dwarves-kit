# Sub-goal 07: skill-prune-trim

**Merge policy:** gate
**Time budget:** 3-4 hours of loop work
**Proof:** byte-count before/after table for the split skills + the prune proposal table + 3 spot-check greps proving trigger phrases survived the split
**Depends on:** none
Effort: medium
**Branch:** chore/cc-hyg-07-skill-prune (repo: tieubao/dotfiles)
**PR base:** main

## Outcome

The ~17K-token skill-description chunk and the oversized skill bodies stop taxing every session (closes ID-209, unparks the two Fable-5 checklist items):

1. **Top-5 body split, approach (b)** (per the row's 2026-06-27 decision; approach (a) rephrase stays rejected): plan-for-mega-goal (33.7KB), learning-day-process (39.8KB), knowledge-capture (35.1KB), image-spec (26.8KB), goal-craft (25.2KB) each become a thin trigger SKILL.md + references/GUIDE.md, meaning-preserving. Trigger phrases and the description frontmatter stay identical (they are the auto-fire surface).
2. **Prune proposal table**: every skill with 0 fires in 30d and 60d (cc-observe skills view), classified keep (seasonal/gated) / disable / delete with a one-line reason each. PROPOSAL ONLY: Han flips each row; the loop disables or deletes NOTHING (never-delete rule).
3. **Fable-5 reasoning-echo audit**: grep all skills for instructions that ask the model to echo or extract its reasoning (Fable refuses reasoning_extraction); list offenders + proposed rewording in the same table.

## Quality bar

A split skill fires exactly as before and its GUIDE holds every removed byte; zero meaning lost. The prune table is honest about seasonal skills (a 0-fire tax skill in June is not rot).

## How to close the loop

- Cross-repo (dotfiles owns ~/.claude/skills sources): lane via `lib/lane-classify.sh` + spec + spec-validate + gate-ledger, never /kit:*. Coordinate with 03's plan-for-mega-goal edits: if 03 already merged, split ON TOP of its version.
- Run-table: `wc -c` before/after per split skill; `grep` 3 known trigger phrases still in the thin SKILL.md; `cc-observe skills --days 60` output feeding the prune table.
- Open the PR, log once to NOTES.md, emit the NEEDS-APPROVAL banner. NEVER merge; NEVER disable/delete a skill.

**Done =** 5 skills split with byte-table + trigger-greps green AND the prune + reasoning-echo proposal tables are in the PR, PR open and held for Han.

## Handoff on completion

1. ROADMAP line gets the PR # (box flips only after Han merges). 2. Overwrite HANDOFF.md (next: 08). 3. Append to DECISIONS.md. 4. Exit immediately.

## Scope edges

**In:** the 5 named skills' file layout, the proposal tables.
**Out:** actually disabling/deleting anything, plugin skills (superpowers/kit/ponytail are upstream-owned), skill CONTENT rewrites beyond the mechanical split.
**Not:** no approach (a) rewording, no new skills, no touching the skill-listing budget setting.

## Where to look

`~/.claude/skills/` chezmoi sources in dotfiles; cc-observe skills views for fire counts; research/2026-06-25-claude-token-audit-findings.md "Skills / MCP" for sizes; the Fable-5 migration checklist memory for the two parked items.

## PR body

Byte table, trigger-greps, prune proposal table (keep/disable/delete columns for Han), reasoning-echo offender list; link to ROADMAP.md; closes ID-209 on Han's sign-off.

## Notes

