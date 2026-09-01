# Sub-goal 02: mega-mirror-triage

**Merge policy:** auto
**Time budget:** 30-60 minutes after 01 merges
**Proof:** run-table: mirror-block shasum matches 01's recorded shasum (byte-identical inside the markers) + the never-diverge checklist row added
**Design:** obvious (mirror paragraph, never-diverge mechanism already exists)
**Depends on:** 01 MERGED (verify `gh pr view` on 01's PR before starting)
Model: sonnet
**Branch:** `docs/mega-mirror-triage` (in dwarves-kit)
**PR base:** master (dwarves-kit default branch)

## Outcome

`/kit:mega` (dwarves-kit `commands/mega.md`) carries the SAME marker-fenced triage ladder at its intake step, and the never-diverge table in `docs/specs/SPEC-142-mega-mirror-sync.md` (the mechanism kit-absorptions 09 / PR #171 shipped; there is no standalone checklist file) gains a row so future edits to either copy fail the sync check.

## Quality bar

Byte-identical inside the `<!-- BEGIN/END triage-ladder -->` markers (shasum equality with 01's DECISIONS.md record). The mirror is a projection, never a rewrite.

## How to close the loop

dwarves-kit IS kit-adopted: read AGENTS.md + WORKFLOW.md first, lane-classify (expect tiny/docs), record the phases via `bash lib/gate-ledger.sh` (rid, then `record` per phase) BEFORE the push, or the ship-gate blocks.

Verification (captured run-table):

    a=$(awk '/BEGIN triage-ladder/,/END triage-ladder/' commands/mega.md | shasum)
    # compare against the shasum recorded in runner-fastpath DECISIONS.md by 01
    rg -n "triage-ladder" docs/ commands/mega.md   # never-diverge row present

**Done =** mega.md's fenced block shasum equals 01's recorded shasum AND the SPEC-142 never-diverge table lists the goal-craft/plan-for-goal <-> mega.md triage-ladder pair.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. Overwrite HANDOFF.md: next = whatever the ops lane needs (03 is independent; if 03 already runs, point at 04/06 state).
3. Append to DECISIONS.md only if the mirror needed any adaptation (it should not; record "byte-identical" with the shasum).
4. Report IN the records, then EXIT IMMEDIATELY.

## Scope edges

**In:** `commands/mega.md` intake step; the never-diverge checklist file.
**Out:** the plan-for-mega-goal skill bundle (01 owns skill-side); any other mega.md knob.
**Not:** restructuring mega.md; adding kit commands.

## Where to look

dwarves-kit `commands/mega.md` (the model-routing + remega knobs already mirror skill sections; follow that precedent); `docs/specs/SPEC-142-mega-mirror-sync.md` (the never-diverge table, from kit-absorptions 09 / PR #171, merged 8849467).

## PR body

- Outcome: /kit:mega mirrors the intake triage ladder (skill-side landed in dotfiles PR <01's #>), never-diverge row added.
- Verification: shasum-equality run-table inline.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`. Stacked note not needed (base master).

## Notes

