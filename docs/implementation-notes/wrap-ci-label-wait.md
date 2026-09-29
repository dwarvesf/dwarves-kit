# Implementation notes -- wrap-ci-label-wait

Deltas from SPEC-360. Nothing here repeats what the spec already states.

## 2026-09-29 The re-gate takes the narrower `_pr_gate` change
- Context: round 1 of the spec refused on any pending entry before the group-by-name step. Validation flagged that a clause placed first would pre-empt `SKIP not mergeable (CONFLICTING)`, which `cmd_merge` compares exactly to drive the union re-merge and the squash fallback.
- Decision/Change: only the latest-per-name sort key changes. A pending entry with no timestamp sorts last, so it becomes the latest for its name, and the existing failing clause refuses it. No clause is added or moved.
- Alternatives considered: refuse on any pending entry, placed after the draft, base and mergeable clauses. Rejected: broader, and it would refuse PRs on repos without the `ci` label whose stale pending entry is superseded by a newer completed one.
- Impact: verdicts change only for a name group that holds a pending, untimestamped entry.

## 2026-09-29 Two gaps stay out of scope
- `cmd_land` has no re-gate after the ci wait, so a red label-started run still lands. Adding one alters what `land` promises; the lead holds it as a separate change.
- Label present, new push, then another label: the all-SKIPPED rollup on the new head reads as done and passes the gate. The sync records no baseline because it neither adds nor re-adds `ci`.
