# Sub-goal 01: triage-ladder

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table (grep of the ladder text in both skill files + the three worked examples rendered) + a shasum of the shared ladder block recorded for 02 to mirror against
**Design:** obvious (contract text in two existing skills; no new component)
**Depends on:** none
Model: sonnet
**Branch:** `feat/triage-ladder` (in dotfiles)
**PR base:** main (dotfiles)

## Outcome

goal-craft and plan-for-goal both open with the same intake triage ladder: before any goal/scaffold is drafted, classify the task DIRECT kit lane (one file / one behavior / obvious proof: lane-classify tiny-small, 1 worker + verify + 1 PR, no scaffold, no conductor, gate-ledger still records) vs single /goal (one objective, multiple steps) vs mega-goal (multiple objectives / repos / gates). Each rung carries one worked example. A task that fits a lower rung NEVER gets the higher rung's ceremony.

## Quality bar

The ladder is a routing rule, not advice: phrased as a MUST-check step at intake, with the exact escape hatch named (the user explicitly asking for a mega overrides the ladder). Wording is written ONCE here; 02 mirrors it. No em dashes.

## How to close the loop

This is the dotfiles repo (chezmoi SOURCE). Non-negotiables for the worker:

- Edit `home/dot_claude/skills/goal-craft/SKILL.md` + `home/dot_claude/skills/plan-for-goal/SKILL.md` (SOURCE paths, never `~/.claude` directly), then a SCOPED `chezmoi apply` on exactly those two targets.
- dotfiles has the S-64 watcher: stage+commit in ONE shell call.
- dotfiles is NOT kit-adopted: put the proof run-table in the PR body, no gate ledger.

Verification (captured as a run-table in the PR body):

    rg -n "triage ladder|DIRECT kit lane" ~/.claude/skills/goal-craft/SKILL.md ~/.claude/skills/plan-for-goal/SKILL.md
    # the two in-repo copies MUST be byte-identical to each other FIRST:
    a=$(awk '/BEGIN triage-ladder/,/END triage-ladder/' ~/.claude/skills/goal-craft/SKILL.md | shasum)
    b=$(awk '/BEGIN triage-ladder/,/END triage-ladder/' ~/.claude/skills/plan-for-goal/SKILL.md | shasum)
    [ "$a" = "$b" ] && echo IDENTICAL   # only then record $a for 02

Wrap the shared block in `<!-- BEGIN triage-ladder -->` / `<!-- END triage-ladder -->` markers so the shasum and 02's mirror check are mechanical.

**Done =** both skill files contain the marker-fenced ladder with three rungs + three worked examples, the two copies byte-identical (IDENTICAL line in the run-table), scoped apply done, shasum recorded in the PR body and in this mega's DECISIONS.md.

## Handoff on completion

1. Flip this sub-goal's ROADMAP.md box to `[x]` + PR #. The orchestrator advances only on the box flip.
2. Overwrite HANDOFF.md: next = 02 (dwarves-kit mirror), first action = copy the marker-fenced block from 01's merged diff into `commands/mega.md`, pointer to the shasum in DECISIONS.md.
3. Append the ladder shasum + any wording decisions to DECISIONS.md (append-only).
4. Report IN the records, then EXIT IMMEDIATELY.

Working rhythm: one-line progress note every 3-5 tool calls.

## Scope edges

**In:** the two skill files' intake sections; the marker-fenced ladder block; worked examples.
**Out:** /kit:mega (that is 02); lane-classify itself (already ships tiny); any behavior change to /goal.
**Not:** a scoring rubric, a size-estimator script, auto-classification. The ladder is prose a planner reads.

## Where to look

dotfiles `home/dot_claude/skills/{goal-craft,plan-for-goal}/`; the design source `ops-toolkit/research/2026-07-04-mega-runner-fastpath-design.md` section 1; kit-absorptions PR #170 (lane de-escalation nudge) for the post-hoc half already shipped.

## PR body

- Outcome: intake triage ladder (DIRECT / single goal / mega) in goal-craft + plan-for-goal, marker-fenced, mirrored to /kit:mega in the next PR.
- Verification: run-table (rg + shasum above) inline.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes

