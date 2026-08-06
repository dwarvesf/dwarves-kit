# Sub-goal 03: harvest-dedup-land

**Merge policy:** auto
**Time budget:** under 1 hour
**Proof:** `Done =` evidence line + the existing regression row (test-kit-foldin-hooks row 4c, the 8/8 Barrier harness) green on the PR head and on master post-merge. Ladder rung 1 (the PR carries its own rung-2 test already).
**Design:** obvious
**Depends on:** none
Model: sonnet
**Branch:** (none, this sub-goal's PR IS the existing #226)
**PR base:** master

## Touches

hooks/harvest.py, tests/test-kit-foldin-hooks.sh (both already changed inside PR #226; this sub-goal adds no new files)

## Outcome

PR #226 (fix(harvest): dedup insights on append, the fcntl.flock fix for the N-concurrent-sessions 6x-duplicate race) is reviewed against master, brought current if behind, and merged. The one open defect in the Learn capture plane is closed before SG-05 builds on the ledger it feeds.

## Quality bar

A review-and-land, not a rewrite. If the review finds a real defect in the PR, fix on ITS branch with a fix-up commit; do not fork a competing fix.

## How to close the loop

1. `gh pr view 226 --json state,mergeable,statusCheckRollup,reviewDecision` and `gh pr diff 226`; rebase on master if behind.
2. Run the regression: `bash tests/test-kit-foldin-hooks.sh` on the PR head; row 4c (locked-append Barrier test) must be 8/8.
3. Merge per the auto-merge gates (CI green, no CHANGES_REQUESTED, proof present in the PR).
4. Post-merge: re-run the suite on master; capture the pass line.

**Done =** PR #226 merged into master AND `tests/test-kit-foldin-hooks.sh` green on master with row 4c passing, evidence line in the ROADMAP entry (merge SHA).

Kit-adopted repo: this is a merge of an existing gated PR; record a `review ran` gate row with the run output as evidence.

## Handoff on completion

1. Flip ROADMAP box + record `PR #226` + merge SHA. 2. HANDOFF.md: next = 07 (if 02 done) else assist 02; first action per its file. 3. DECISIONS.md: nothing unless the review found something. 4. EXIT.

## Scope edges

**In:** review, rebase-if-needed, merge, post-merge suite run.
**Out:** any new harvest feature, the staging drain (06).
**Not:** widening the lock to backlog-stage.py "for symmetry" (propose in NOTES if the race is shown real there; do not build).

## Where to look

PR #226 diff; `hooks/harvest.py` `_harvest_payload`; the Barrier test in tests/.

## PR body

(rides PR #226's existing body; append the roadmap link: `_meta/megagoals/harness-loop/ROADMAP.md` SG-03)

## Notes
