# Sub-goal 06: planning-sweep

**Merge policy:** gate
**Time budget:** 2-4 hours of loop work
**Proof:** the sweep script + a run-table of automated flips (spec -> merged-PR evidence per flip) + the residue decision table in the PR body
**Depends on:** none (but do not run in parallel with 02: both touch _meta/BACKLOG.md)
Effort: medium
**Branch:** chore/cc-hyg-06-sweep (repo: tieubao/ops-toolkit)
**PR base:** main

## Outcome

Planning inventory tells the truth (closes ID-240 + ID-241 pending Han's per-item sign-off):

1. **Spec statuses**: a scripted sweep greps every ops-toolkit spec's Status and cross-refs merged PRs; specs a merged PR demonstrably shipped get flipped to shipped BY SCRIPT (each flip cites its PR). Evidence: June cohort 153 specs at 24% shipped vs May 55%; 84 parked at validated/accepted; half the graveyard is suspected status-flip lag.
2. **Residue table**: every spec the script cannot prove shipped gets a PROPOSED state (parked / dropped / documentation) with a one-line reason, in a table Han can mark up.
3. **Stale scaffolds**: the 8 untouched mega-goal roadmaps (agent-method, repo-to-workboard, safari-lab, safari-net-complete, cf-quota-tracker, dictate-overlay, icy-mint-burn x2 repos) + 4 roadmap-less folders (homelab-net-research, safari-net-app, safari-net-panel, visibility-comms-plan) each get a proposed decision: park-with-trigger / fold into a live goal / close. NOTHING is deleted or archived without Han's explicit per-item say-so; this PR only proposes.

## Quality bar

The script's flips are individually evidenced (spec -> PR #), so Han reviews decisions, not detective work. The residue table fits on one screen per category.

## How to close the loop

- Same-repo: kit lane from this cwd (spec + spec-validate + gate-ledger). The sweep script lands in the PR (scratch under the mega-goal folder or _meta/, not tools/).
- Run-table: script run output (N flips, each `SPEC-xxx -> shipped (PR #yyy)`); manual verification of 3 random flips.
- Open the PR, log to NOTES.md Event log once, emit the NEEDS-APPROVAL banner, hop to the next workable sub-goal. NEVER merge this PR.

**Done =** script-proven flips committed + every residue item and every stale scaffold has a proposed decision in the PR body, PR open and held for Han.

## Handoff on completion

1. Flip the ROADMAP box + PR # only after Han merges (until then it stays `- [ ] ... PR #N` + blocked-on-gate). 2. Overwrite HANDOFF.md (next: 07). 3. Append to DECISIONS.md. 4. Exit immediately.

## Scope edges

**In:** ops-toolkit spec Status fields, the decision tables, board rows for ID-240/241 status.
**Out:** other repos' specs (dwarves-kit is healthy: 83% June ship rate), the dictate SPEC-010..020 CONTENT (only their status), deleting anything.
**Not:** no archiving, no folder moves, no roadmap edits inside the 8 stale scaffolds, no new spec-tooling.

## Where to look

`docs/specs/` + per-tool `tools/*/docs/specs/` Status lines; `_meta/megagoals/` for the stale list; research/2026-07-02-process-benchmark.md section 3 for the piles (dictate 11, homelab-net-research 6, vibedex).

## PR body

The three tables (flips with PR evidence, residue proposals, scaffold proposals); reproduce command; link to ROADMAP.md; closes ID-240 + ID-241 on Han's sign-off.

## Notes

