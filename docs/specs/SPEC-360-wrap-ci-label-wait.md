# Spec: wrap waits for the runs a fresh ci label starts

Generated: 2026-09-29
Status: DRAFT
Lane: full (lib/ enforcement surface: the merge gate of `wrap merge --apply`, `wrap land` and the carry autoland)
Type: bug
File: `docs/specs/SPEC-360-wrap-ci-label-wait.md`
References: `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, and the three callers in `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the "ci label gate" sections for merge and land)

## Problem

Some repos run PR workflows only on `pull_request: types: [labeled]` with the label `ci`. `wrap` handles them in two steps. `_ci_label_sync` adds the label, and `_ci_checks_wait` waits for the runs the label starts. The wait grants its grace window (`KIT_WRAP_CI_GRACE_SECS`) only while the PR's `statusCheckRollup` is EMPTY.

A PR that was opened before the label already carries completed check runs. The unlabeled `pull_request` run reports `test=SKIPPED` and `preview=SUCCESS`. Right after the label goes on, the rollup still holds only those old entries, and none of them is pending. The label-started runs register a few seconds later. The wait reads "0 pending" on its first read and ends at once. The merge then proceeds on an untested head.

Seen live on dwarvesf/foundation-workers PRs #970 and #971. `wrap` printed `labeled #971 ci ...` and then `merged #971` within seconds. A later `gh pr view 971 --json statusCheckRollup` showed a new `test` entry with an empty conclusion next to the old `test=SKIPPED`. Both late runs passed, so nothing broke. The gate still did not gate.

The real rollup of #971 shows the shape the fix keys on. Every CheckRun carries a `detailsUrl` that names its job, and that URL differs between the pre-label run and the label-started run:

```
test     SKIPPED  2026-09-28T02:44  .../actions/runs/36370943441/job/108766979093   (before the label)
test     SUCCESS  2026-09-29T10:21  .../actions/runs/36555102629/job/109362252589   (label-started)
preview  SUCCESS  2026-09-28T02:44  .../actions/runs/36370943441/job/108766979586   (before the label)
preview  SUCCESS  2026-09-29T10:21  .../actions/runs/36555102629/job/109362256467   (label-started)
```

A second gap sits in the re-gate after the wait. `_pr_gate` groups the rollup by check name and keeps the entry that sorts last on `completedAt // startedAt // createdAt`. A label-started run that is still queued when the wait bound expires can have no timestamp yet. It then sorts before the old completed `test=SKIPPED`, and the gate reads that stale SKIPPED as the verdict. Self-hosted runner queues make a run that stays queued past `KIT_WRAP_CARRY_CHECKS_SECS` realistic.

## Change

```
_ci_label_sync
  reads labels + rollup (already does)
  adds or re-adds `ci`  --->  CI_LABEL_BASE = keys of the rollup read before the edit
  label already fine    --->  CI_LABEL_BASE = []   (today's behavior)
        |
        v
_ci_checks_wait  (one read every 10s)
  NEW  = rollup entries whose key is not in CI_LABEL_BASE
  NEW empty          -> wait, bounded by KIT_WRAP_CI_GRACE_SECS
  pending > 0        -> wait, bounded by KIT_WRAP_CARRY_CHECKS_SECS
  unreadable         -> wait, bounded by KIT_WRAP_CARRY_CHECKS_SECS
  NEW non-empty and 0 pending -> done
        |
        v
re-gate (cmd_merge only, unchanged call): _pr_gate on the same head
  any entry still pending -> "SKIP checks are pending or failing"
```

1. `_ci_label_sync` sets a global `CI_LABEL_BASE` to `[]` on entry. When it adds the label, or removes and re-adds it, it first sets `CI_LABEL_BASE` to a JSON array of the entry keys in the `statusCheckRollup` it already read. No new `gh` call is made.
2. The entry key is `.detailsUrl` when present, else `(.name // .context) + "@" + (.startedAt // .createdAt)`. `detailsUrl` names one job, and a queued run keeps it when it starts. A timestamp would change when a queued run starts, so it is only the fallback for check types with no URL.
3. `_ci_checks_wait` computes NEW as the rollup entries whose key is not in `CI_LABEL_BASE`. "NEW is empty" replaces today's "rollup is EMPTY" test, with the same grace bound. With `CI_LABEL_BASE = []`, NEW equals the whole rollup, so a label that was already in place waits exactly as today. The pending count still covers the whole rollup, pre-label entries included.
4. `_pr_gate` returns `SKIP checks are pending or failing` when any rollup entry is pending (`status` present and not `COMPLETED`, or `state` of `PENDING` or `EXPECTED`), before the group-by-name step. This is the same pending test the wait uses.
5. Nothing else changes. The three callers keep their calls. `_autoland_carry` still lands through `cmd_merge --apply --pr`, which re-gates. The grace and carry bounds keep their names and defaults.

## Design

### Approaches considered

1. Diff the rollup against the pre-label snapshot (chosen). It needs no clock and no extra `gh` call, because the sync already holds the pre-label rollup. It also counts a queued new run as new before that run has a start time.
2. Record the local time when the label goes on, and count an entry as new when its `startedAt` is at or after that time. The lead's first sketch. It was rejected for two reasons. Local and GitHub clocks can skew by seconds, which is the whole width of the race. A queued CheckRun can report no `startedAt`, so a new queued run would never count as new. Approach 1 costs the same code.
3. Sleep a fixed interval after the label edit. Rejected: it guesses the registration delay and still races on a slow day.

### Residual race

When one label event starts two workflows, the wait can end once the first workflow's runs appear and finish, before the second registers. In the observed repos one workflow holds every job, and GitHub registers a run's jobs together. Today's EMPTY test has the same race. It is out of scope here.

## Acceptance criteria

- AC1: On a label-gated repo, `wrap merge --apply` on a PR whose rollup holds only completed pre-label entries does not merge while no new entry has appeared. It waits until a label-started entry appears and completes, then re-gates and merges on green.
- AC2: In the AC1 setup, a label-started run that completes red refuses the merge with `FAILED merge #<n>: checks are pending or failing once the ci label's checks ran`. No `pr merge` call is made. The rollup at the re-gate holds both the old `test=SKIPPED` and the new `test=FAILURE`.
- AC3: When no new entry ever appears (a paths-filtered workflow that starts nothing), the wait ends after `KIT_WRAP_CI_GRACE_SECS` and the merge proceeds on the pre-label rollup, as it does today for an empty rollup.
- AC4: When the label was already present with a non-empty rollup (no add, no re-add), the wait makes exactly one rollup read before it ends. That is today's behavior.
- AC5: When a label-started run is still queued at `KIT_WRAP_CARRY_CHECKS_SECS`, with no timestamps, next to an old completed `test=SKIPPED`, the re-gate refuses the merge and no `pr merge` call is made.
- AC6: `wrap land` on a label-gated repo with pre-label entries also waits for a new entry before its `pr merge` call.
- AC7: `bash tests/test-wrap.sh` passes, including every existing ci-label case. `bash tests/test-meta.sh` passes.
- AC8: A negative control with `lib/gate/negctl.sh` turns the AC1 test red when the baseline is ignored (`CI_LABEL_BASE` forced to `[]`).

## Test plan

New cases go in `tests/test-wrap.sh`, next to the existing "merge --apply: the ci label gate" and "land: the ci label gate" sections. They use the existing `gh` stub. Read k of `pr view <n>` serves `GH_STUB_PR_<n>_<k>`, and the call count lands in `$GH_STUB_CALLS.view-<n>`. `$TMPD/nosleep` stubs `sleep`. Each case uses a fresh PR number, so the per-number read counters never collide.

The pre-label rollup in every case is `test` SKIPPED with `detailsUrl` `.../job/1` and `preview` SUCCESS with `.../job/2`. Label-started entries use `.../job/3` onward.

| Case | Setup (reads served) | Assert |
|---|---|---|
| T1 AC1 | 1 eligibility: old rollup, CLEAN. 2 sync: labels `[]`, old rollup. 3 wait: old rollup only. 4 wait: old plus `test` IN_PROGRESS job/3. 5 wait: old plus `test` SUCCESS job/3. 6 re-gate: old plus new green | exit 0; `labeled #N ci`; `view-N` count is 6; merged, tree verified |
| T2 AC2 | as T1, with read 5 `test` FAILURE job/3 (completedAt later than the old SKIPPED) and read 6 re-gate old plus new red, UNSTABLE | exit 2; the refusal line; no `pr merge N` |
| T3 AC3 | as T1 reads 1-2, then every read old rollup only; `KIT_WRAP_CI_GRACE_SECS=20` | exit 0; the wait made 3 reads (0s, 10s, 20s); merged |
| T4 AC4 | labels `[ci]`, old rollup, no edit | no `pr edit N`; one wait read between the sync read and the re-gate read |
| T5 AC5 | as T1 reads 1-2, then old plus `test` QUEUED job/3 with no timestamps on every read; `KIT_WRAP_CARRY_CHECKS_SECS=10` | exit 2; the refusal line; no `pr merge N` |
| T6 AC6 | `wrap land`, first read labels `[]` plus the old rollup; read 2 old only; read 3 old plus new IN_PROGRESS; read 4 old plus new SUCCESS | exit 0; `pr merge` comes after the 4th `pr view`; merged |

T4 pins that an operator whose label is already in place pays no extra wait. The existing cases pin the empty-rollup path, the re-label path, the label that will not set, and the autoland door.

## Negative control

After the feature commit:

```
bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" \
  "sed -i.bak 's/^\(  *\)CI_LABEL_BASE=\"\$(/\1CI_LABEL_BASE=\"[]\" #(/' lib/wrap/wrap.sh"
```

The mutation makes the sync record an empty baseline. T1 must go red, because the wait ends on its first read. T2 must go red too, because the merge proceeds before the red run appears. The exact `sed` pattern is settled at build time against the final line.

## Out of scope

- `cmd_land` does not re-gate after `_ci_checks_wait`. Its `pr merge` runs whatever the label-started runs concluded, so a red run still lands. This predates the change. It is a separate decision: land has no gate step at all today, and adding one changes what `land` promises. The lead should decide it.
- The two-workflow race named under "Residual race".

## Verification

`bash tests/test-wrap.sh` green with T1 to T6 present, then the negative control above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap ci label wait"` names it.

## Tasks

- [ ] T1: baseline in `_ci_label_sync`, the NEW-entry test in `_ci_checks_wait`, and the pending short-circuit in `_pr_gate` (`lib/wrap/wrap.sh`), plus cases T1 to T6 in `tests/test-wrap.sh`.
