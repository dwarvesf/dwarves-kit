# Sub-goal 10: briefs-out

**Merge policy:** auto
**Time budget:** 1-2 hours
**Proof:** run-table showing the moved briefs at the new path + the repointed readers still resolve them (the commands that reference DECISION-BRIEF/CONTEXT). Rung 2.
**Design:** obvious
**Depends on:** none (Track B)
Model: sonnet
**Branch:** fix/harness-ops-10-briefs-out
**PR base:** main

## Outcome

`docs/specs/` holds only `SPEC-NNN-*.md` again: the pre-spec artifacts (`DECISION-BRIEF*.md`, `CONTEXT.md`) move to `docs/briefs/`, and every reader is repointed. Cleaner specs/ dir; the brief-vs-spec lifecycle stages no longer share one folder.

## How to close the loop

- Move `docs/specs/DECISION-BRIEF*.md` + `docs/specs/CONTEXT.md` → `docs/briefs/` (git mv; includes DECISION-BRIEF-config-layer.md).
- Repoint the readers: `commands/ui-design.md`, `commands/devs-team.md`, `commands/visual-team.md`, `commands/next.md`, and `lib/goal/goal-drafts.sh` (`GOAL_SPECS_DIR` / brief path). Grep for `docs/specs/DECISION-BRIEF` + `docs/specs/CONTEXT` to find all.
- Test: the commands/goal-drafts that read a brief resolve it at the new path; run the meta/relevant tests. Capture the run-table.

**Done =** `docs/specs/` contains only SPEC-NNN files, the briefs live at `docs/briefs/`, and every reader (4 commands + goal-drafts) resolves them at the new path (captured run-table, no dangling reference).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → next; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** the brief/CONTEXT files + their readers (4 commands + goal-drafts.sh).
**Out:** the SPEC-NNN files (stay), the spec-drift/context hooks that glob `docs/specs/SPEC-*` (unaffected).
**Not:** moving specs/, renaming briefs, restructuring the spec lifecycle.

## PR body

Moves the pre-spec briefs (DECISION-BRIEF*, CONTEXT.md) out of `docs/specs/` into `docs/briefs/` and repoints the 4 command files + goal-drafts. Verify: the repointed-readers run-table. Part of `harness-ops` (Track B), see ROADMAP.md.

## Notes
