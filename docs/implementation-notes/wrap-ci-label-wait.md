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

## 2026-09-29 Build deltas
- `_pr_gate` defines its own `pending` jq def with the same predicate the wait uses. The two stay separate programs, so the predicate is written twice, not shared through a variable the way `CI_ENTRY_KEY` is. Sharing it would touch the wait's jq and the ordinary carry wait for no behavior change.
- The add-branch `CI_LABEL_BASE=` assignment is one line; the `'[]'` fallback sits on the next line, so the negative-control `sed` replaces the assignment and leaves valid shell.
- T6 counts rollup reads in the gh call log (`pr view 42 ... statusCheckRollup` lines before `pr merge 42`), because land shares PR number 42 with the other land cases and reads no settle detail.
- T7 drives `wrap merge` without `--apply` against `clone-scan-main`; the verdict line is all it asserts.
- `docs/FEATURES.md` was regenerated (`feature-registry.sh check --fix`): the new spec file moved four `SPEC-` reference counts, and `tests/test-meta.sh` plus the ship-gate refuse a stale registry.
- The first negctl pair wrote one log path per control, so the green-after-restore run overwrote the red run's output. Both controls were rerun with one `mktemp` log per run; the proof quotes the rerun, and both runs of each control passed.
- `commands/greenlight.md` Step 1b gained one bullet naming the same pre-label race for its snapshot. Greenlight never merges, but its "every check passing and none pending -> done" rule reads the same stale rollup.

## 2026-09-29 Review-team fix batch (security 7/10, architecture 8/10, test-coverage 8/10, 0 critical)
- Gate key: every pending entry now sorts last, not only one with no real time. A SKIPPED run from a later `labeled` event completed after an IN_PROGRESS `ci` run started, and the time key let it stand in. Accepted cost: a superseded pending entry blocks its name until it clears.
- Sync read: a PR read that is not a JSON object on a gating repo returns 2. `cmd_merge` and `cmd_land` print their existing "the ci label could not be set" refusal, which is slightly off for a read failure; the sync's own stderr line names the read.
- NEW excludes SKIPPED entries. Side effect: with the label already on and an all-SKIPPED rollup (the named out-of-scope case), the wait now holds the grace window before the gate still passes it.
- `cmd_merge` needs `CLEAN` after a NONEW hold when the snapshot was non-empty. The rule does not carry into autoland: its `cmd_merge --pr` runs its own sync with the label already on, so the snapshot is `[]` there and the rule is off. Named in Failure modes, not fixed.
- `CI_JQ_DEFS` replaces `CI_ENTRY_KEY` and the two inline pending predicates; `rtime` stays local to `_pr_gate`, built on `real`. `CI_LABEL_BASE` became `CI_PRELABEL_KEYS`, and the wait's out-param `CI_WAIT_END` is new.
- T12 puts the pre-label check and the two new ones on one URL. Two new checks alone on a shared URL would read NEW either way, so that shape pins nothing about the name prefix.
- T13's exact count (18 reads of #42) was measured on the green run, not derived; the NC4 control below confirms that dropping the sync's reset on entry changes it.
- T6 now asserts exactly 4 rollup reads before the merge.
- NC4 (the sync's reset on entry removed) was added beside NC1 to NC3, because T13 exists to pin that reset; it turned only T13 red.
