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

## 2026-09-29 A third validation round, at the operator's direction
- Round 2 found that negative control 1 could not turn T1 red: the settle loop skipped the minimal wait fixtures. T1 now serves full detail at reads 4 and 5, and T6 is the second tripwire. The zero-time sort clause was dropped on the belief that live rollups report null. That was wrong; see the reversal below.

## 2026-09-29 Reversed: the zero-time clause comes back
- Context: round 3 dropped the `0001-01-01T00:00:00Z` case from the `_pr_gate` sort key, on the belief that live rollups report a pending run's times as null.
- Evidence: the round-3 validator ran gh 2.101 against four public PRs with pending checks. Every QUEUED and IN_PROGRESS CheckRun carried `"completedAt":"0001-01-01T00:00:00Z"` and `"conclusion":""`, and QUEUED entries also carried a real `startedAt`. jq `//` falls through only on null or false, so both today's key and the round-2 key picked the stale SKIPPED.
- Decision/Change: the key is the first real time among `completedAt`, `startedAt`, `createdAt`, skipping null, empty and the zero time. A pending entry with no real time still sorts last. Every pending test fixture is live-shaped, so T5 fails under the old key.
- Impact: the bug in `_pr_gate` was wider than the queued case: any pending run lost to an older completed run of its name.
