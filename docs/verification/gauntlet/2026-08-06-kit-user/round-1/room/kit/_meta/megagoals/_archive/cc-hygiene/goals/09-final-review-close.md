# Sub-goal 09: final-review-close

**Merge policy:** gate
**Time budget:** 2-4 hours of loop work, after 01-08 are merged or held
**Proof:** the merged review report committed under the mega-goal folder + a run-table of fixes applied for CRITICAL/MAJOR findings
**Depends on:** 01, 02, 03, 04, 05, 06, 07, 08 (fan-in)
Effort: high
**Branch:** docs/cc-hyg-09-close (repo: tieubao/ops-toolkit)
**PR base:** main

## Outcome

The mega-goal closes only after a fresh adversarial pass over everything that merged (Han's directive 2026-07-02):

1. **Review round**: dispatch /kit:review-team across the merged set (security, architecture, test-coverage lenses) AND the kit advisor in BOTH modes: critique (extra uniform lens) and over-suggest (additional improvement ideas surfaced to Han). Input = the diff set of every merged cc-hyg PR (pull the list from ROADMAP.md PR numbers).
2. **Findings**: CRITICAL/MAJOR fixed on this branch with a run-table; MINOR + over-suggest ideas filed as board rows or NOTES Proposed additions, not built.
3. **Close-out**: cluster board rows updated in _meta/BACKLOG.md (ID-148 closed as satisfied-by the research trilogy + this mega-goal; 209/219/234/235/236/238/239/242/243/152 closed per their sub-goal outcomes; 237 noted batch-1 shipped, remainder queued; 240/241 per Han's 06 sign-off). One-paragraph LAB_LOG arc entry (slug, sub-goal count, PR range, key lessons) as the newest entry on THIS branch. NOTES.md Event log final summary.

## Quality bar

The review round is real: fresh-context reviewers over the actual merged diffs, findings verified before fixing, no rubber stamp. The close-out leaves the board telling the truth with zero dedicated bookkeeping PRs (this PR carries it all, dogfooding 02's rule).

## How to close the loop

- Same-repo: /kit:review-team + advisor from this cwd; commit the merged report under `_meta/megagoals/cc-hygiene/docs/` (or the repo's review output convention).
- Fix run-table for each CRITICAL/MAJOR: finding, fix commit, re-verify command + exit.
- Audit every ROADMAP PR # via `gh pr view` before claiming the set complete.
- Open this PR, log the final summary once, emit `NEEDS APPROVAL`; the PR is held for Han's single click (gated-final).

**Done =** review report + fixes committed, board rows + LAB_LOG entry riding this branch, all other sub-goals audited merged-or-held, PR open and held for Han.

## Handoff on completion

1. ROADMAP line gets the PR # (box flips when Han merges; that click closes the mega-goal). 2. Overwrite HANDOFF.md with "mega-goal complete pending Han's merge of #N". 3. Append final invariants to DECISIONS.md. 4. Exit; the loop stops here.

## Scope edges

**In:** the review round, CRITICAL/MAJOR fixes, board + LAB_LOG close-out.
**Out:** building over-suggest ideas (file them), archiving the mega-goal folder (rides a later feature PR per the 02 rule), kit-telemetry's scope.
**Not:** no new sub-goals, no scope creep from review findings beyond CRITICAL/MAJOR, no bookkeeping-only follow-up PR.

## Where to look

ROADMAP.md PR numbers for the merged set; `_meta/BACKLOG.md` cluster rows; the kit's review-team + advisor agent docs.

## PR body

Review verdict summary (per lens), fixes run-table, the board-row diff summary, the LAB_LOG entry; link to ROADMAP.md; closes ID-148 and the cluster.

## Notes

