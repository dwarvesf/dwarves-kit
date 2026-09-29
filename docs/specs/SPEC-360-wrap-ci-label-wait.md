# Spec: wrap waits for the runs a fresh ci label starts

Generated: 2026-09-29
Status: DRAFT (round 3: folds validation round 2, NEEDS REVISION, 1 critical, 9 warnings). Prior: round 1 (NEEDS REVISION, 2 critical, 8 warnings).
Lane: full (lib/ enforcement surface: the merge gate of `wrap merge --apply`, `wrap land` and the carry autoland)
Type: bug
File: `docs/specs/SPEC-360-wrap-ci-label-wait.md`
References: `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, and the three callers in `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the "ci label gate" sections for merge and land); `docs/implementation-notes/wrap-ci-label-wait.md` (deltas)

## Problem

Some repos run PR workflows only on `pull_request: types: [labeled]` with the label `ci`. `wrap` handles them in two steps. `_ci_label_sync` adds the label, and `_ci_checks_wait` waits for the runs the label starts. The wait grants its grace window (`KIT_WRAP_CI_GRACE_SECS`) only while the PR's `statusCheckRollup` is EMPTY.

A PR can carry completed check entries on its head before `ci` goes on. On dwarvesf/foundation-workers #971 they came from run 36370943441, a plain `pull_request` run from before foundation-workers #976 made `ci.yml` label-only. From now on such entries come from `labeled` events for other labels: the workflow fires, its jobs skip, and every entry reads SKIPPED. Either way, right after `ci` goes on the rollup holds only those old completed entries. None is pending. The runs `ci` starts register a few seconds later. The wait reads "0 pending" on its first read, ends at once, and the merge proceeds on an untested head.

Seen live on #971 (and #970). One `labeled` event fired at 10:21:52Z, and `wrap` printed `merged #971` 6 seconds later. A later `gh pr view 971 --json statusCheckRollup` showed the new `test` entry beside the old `test=SKIPPED`. Both late runs passed, so nothing broke. The gate still did not gate.

The real rollup of #971 shows the shape the fix keys on. Every CheckRun carries a `detailsUrl` that names its job, and that URL differs between the pre-label entry and the label-started one:

```
test     SKIPPED  2026-09-28T02:44  .../actions/runs/36370943441/job/108766979093   (before the label)
test     SUCCESS  2026-09-29T10:21  .../actions/runs/36555102629/job/109362252589   (label-started)
preview  SUCCESS  2026-09-28T02:44  .../actions/runs/36370943441/job/108766979586   (before the label)
preview  SUCCESS  2026-09-29T10:21  .../actions/runs/36555102629/job/109362256467   (label-started)
```

A second gap sits in the re-gate after the wait. `_pr_gate` groups the rollup by check name and keeps the entry that sorts last on `completedAt // startedAt // createdAt // ""`. A label-started run still queued when the wait bound expires can carry no timestamp. It then sorts before the old completed `test=SKIPPED`, and the gate reads that stale SKIPPED as the verdict for `test`. Self-hosted runner queues make a run that stays queued past `KIT_WRAP_CARRY_CHECKS_SECS` realistic.

## Picture

```
_ci_label_sync
  reads labels + rollup (already does)
  adds or re-adds `ci`  --->  CI_LABEL_BASE = keys of that pre-edit rollup  ('[]' if unreadable)
  label already fine    --->  CI_LABEL_BASE = '[]'   (today's behavior)
        |
        v
_ci_checks_wait  (one read every 10s)
  read failed                         -> wait, bound KIT_WRAP_CARRY_CHECKS_SECS
  pending > 0                         -> wait, bound KIT_WRAP_CARRY_CHECKS_SECS
  pending = 0 and NEW empty           -> wait, bound KIT_WRAP_CI_GRACE_SECS
  pending = 0 and NEW non-empty       -> done
     (NEW = rollup entries whose key is not in CI_LABEL_BASE;
      pending counts the whole rollup, pre-label entries included)
        |
        v
re-gate (cmd_merge only, unchanged call): _pr_gate on the same head
  draft / base / mergeable clauses first, unchanged
  latest-per-name pick: a pending entry with no timestamp sorts LAST, so it is the latest
  -> its empty conclusion trips "SKIP checks are pending or failing"
```

## Change

1. `_ci_label_sync` sets a global `CI_LABEL_BASE='[]'` on entry. When it adds the label, or removes and re-adds it, it first sets `CI_LABEL_BASE` to a compact JSON array of the entry keys in the `statusCheckRollup` it already read. No new `gh` call is made. The value is always valid JSON: when the read failed or `detail` is empty, the jq expression yields `[]` (`(.statusCheckRollup // [])`), and an empty jq output falls back to `'[]'`.
2. The entry key is defined once, as a shell variable holding a jq `def` next to the two functions:

   ```
   CI_ENTRY_KEY='def ckey: .detailsUrl // ((.name // .context // "") + "@" + (.startedAt // .createdAt // ""));'
   ```

   Both `_ci_label_sync` (building the baseline) and `_ci_checks_wait` (building NEW) prefix their jq program with `$CI_ENTRY_KEY` and call `ckey`. Neither spells the key out. `detailsUrl` names one job, and a queued run keeps it when it starts. A timestamp would change when a queued run starts, so it is only the fallback for check types with no URL.
3. `_ci_checks_wait` computes, per read, the pending count over the whole rollup (today's test) and NEW, the entries whose key is not in `CI_LABEL_BASE`. Precedence, in order: a failed read waits on the carry bound; pending > 0 waits on the carry bound; pending = 0 with NEW empty waits on the grace bound; pending = 0 with NEW non-empty ends the wait. With `CI_LABEL_BASE='[]'`, NEW equals the whole rollup, so a label already in place waits exactly as today.
4. `_pr_gate` changes only its latest-per-name sort key. A pending entry (`status` present and not `COMPLETED`, or `state` of `PENDING` or `EXPECTED`) whose `completedAt // startedAt // createdAt` is null or empty sorts after every other entry of its name. Live rollups report a queued CheckRun's times as null, so no zero-time case is handled. Every other entry keeps today's key. No clause is added or moved: the draft, base, mergeable and CONFLICTING verdicts come first exactly as today, so callers comparing `SKIP not mergeable (CONFLICTING)` (`cmd_merge`, the union re-merge and squash fallback) see no change.
5. Nothing else changes. The three callers keep their calls. `_autoland_carry` still lands through `cmd_merge --apply --pr`, which re-gates. The grace and carry bounds keep their names and defaults.

## Design

The flow is drawn once, under `## Picture`.

### Interfaces

| Surface | Before | After |
|---|---|---|
| `_ci_label_sync <url> <pr>` | returns 0/1/2 | same returns; also sets global `CI_LABEL_BASE` (JSON array of strings) |
| `_ci_checks_wait <url> <pr>` | reads nothing global | reads `CI_LABEL_BASE`, defaulting to `[]` when unset |
| `_pr_gate <detail> <def>` | verdict strings | same strings; only the latest-per-name tie-break changes |
| env knobs | `KIT_WRAP_CI_GRACE_SECS`, `KIT_WRAP_CARRY_CHECKS_SECS` | unchanged names and defaults |
| output lines | `labeled #N ci`, `re-labeled #N ci`, refusals | unchanged |

### Approaches considered

1. Diff the rollup against the pre-label snapshot (chosen). It needs no clock and no extra `gh` call, because the sync already holds the pre-label rollup. It also counts a queued new run as new before that run has a start time.
2. Record the local time when the label goes on, and count an entry as new when its `startedAt` is at or after that time. Rejected. Local and GitHub clocks can skew by seconds, which is the whole width of the race. A queued CheckRun can report no `startedAt`, so a new queued run would never count as new. Approach 1 costs the same code.
3. Sleep a fixed interval after the label edit. Rejected: it guesses the registration delay and still races on a slow day.

For the re-gate:

1. Sort a pending, untimestamped entry last in the latest-per-name pick (chosen). It fixes the stale-SKIPPED read and changes no verdict except where a group holds such an entry.
2. Refuse on any pending entry before grouping (rejected). It is broader: a stale pending entry superseded by a newer completed one of the same name would refuse a PR that is fine today, on repos with no `ci` label too. It also needs a new clause placed after the draft, base and mergeable clauses to keep the CONFLICTING verdict intact, which is one more thing to get wrong.

### Residual race

- Two workflows on one event. When one label event starts two workflows, the wait can end once the first workflow's runs appear and finish, before the second registers. In the observed repos one workflow holds every job, and GitHub registers a run's jobs together. Today's EMPTY test has the same race.
- The read-to-edit window. An entry that registers between the sync's rollup read and the label edit (another label's `labeled` event, say) is missing from the baseline, so it counts as NEW. If it completes before the `ci` runs register, the wait ends early. The window is one `gh pr edit` call wide.
- `needs:` chains. A job that `needs:` another registers its check run only after its dependency finishes. When the dependency completes green, the wait sees NEW non-empty and 0 pending, and ends before the dependent job registers. foundation-workers `ci.yml` avoids `needs:`, so its jobs register together.
- StatusContext keys shift. A third-party commit status keys on `context@createdAt`, and a status moving from pending to success gets a new `createdAt`. A status that settles inside the registration window therefore counts as NEW, and the wait can end on it before the `ci` runs register.

## Failure modes

| Failure | Caller | Behavior |
|---|---|---|
| The sync's `gh pr view` read fails | all three | label gets added (as today); `CI_LABEL_BASE='[]'`; the wait behaves as today (NEW = whole rollup) |
| A wait read fails | all three | counts as pending; carry bound, as today |
| No new entry ever appears (paths-filtered workflow) | `cmd_merge`, autoland | grace bound expires; the re-gate reads the pre-label rollup, as today for an empty rollup |
| No new entry ever appears | `cmd_land` | grace bound expires; land merges with no gate, as today |
| A new run stays queued past the carry bound | `cmd_merge`, autoland | the re-gate picks it as latest for its name and refuses |
| A new run stays queued past the carry bound | `cmd_land` | land merges with no gate (out of scope) |
| A new run completes red | `cmd_merge`, autoland | the re-gate picks it as latest (later `completedAt`) and refuses |
| A new run completes red | `cmd_land` | land merges with no gate (out of scope) |
| The label was already present, rollup non-empty | all three | no baseline; one wait read, as today |
| A stuck, untimestamped QUEUED entry (an orphaned job on a runner that is gone) | every `_pr_gate` read, eligibility included, on repos with or without the `ci` label | the entry is the latest for its name, so that PR reads `SKIP checks are pending or failing` until the job completes or is cancelled. This is fail-closed and deliberate. Today the same PR could pass on an older completed entry of that name. |

## Acceptance criteria

- AC1: On a label-gated repo, `wrap merge --apply` on a PR whose rollup holds only completed pre-label entries does not merge while no new entry has appeared. It waits until a label-started entry appears and completes, then re-gates and merges on green.
- AC2: In the AC1 setup, a label-started run that completes red refuses the merge with `FAILED merge #<n>: checks are pending or failing once the ci label's checks ran`. No `pr merge` call is made. The rollup at the re-gate holds both the old `test=SKIPPED` and the new `test=FAILURE`.
- AC3: When no new entry ever appears (a paths-filtered workflow that starts nothing), the wait ends after `KIT_WRAP_CI_GRACE_SECS` and the merge proceeds on the pre-label rollup, as it does today for an empty rollup.
- AC4: When the label was already present with a non-empty rollup (no add, no re-add), the wait makes exactly one rollup read before it ends, as today.
- AC5: When a label-started run is still queued with no timestamps at `KIT_WRAP_CARRY_CHECKS_SECS`, next to an old completed `test=SKIPPED`, on a `CLEAN` merge state, the re-gate refuses the merge and no `pr merge` call is made.
- AC6: `wrap land` on a label-gated repo with pre-label entries also waits for a new entry before its `pr merge` call.
- AC7: A `CONFLICTING` PR whose rollup holds a pending untimestamped entry still verdicts `SKIP not mergeable (CONFLICTING)`.
- AC8: `bash tests/test-wrap.sh` passes, including every existing ci-label case. `bash tests/test-meta.sh` passes.
- AC9: Two negative controls with `lib/gate/negctl.sh`: forcing the baseline to `[]` turns T1 red, and restoring the old `_pr_gate` sort key turns T5 red.

## Test plan

New cases go in `tests/test-wrap.sh`, next to the existing "merge --apply: the ci label gate" and "land: the ci label gate" sections. They use the existing `gh` stub. Read k of `pr view <n>` serves `GH_STUB_PR_<n>_<j>` for the highest set j <= k (j >= 2), else `GH_STUB_PR_<n>`. So the last fixture a case sets repeats for every later read, and T3 and T5 rely on that. The per-number read count lands in `$GH_STUB_CALLS.view-<n>`. `$TMPD/nosleep` stubs `sleep`. Each case uses a fresh PR number.

The pre-label rollup in every case is `test` SKIPPED with `detailsUrl` `.../job/1` and `preview` SUCCESS with `.../job/2`, both with timestamps. Label-started entries use `.../job/3` onward.

| Case | Setup (reads served) | Assert |
|---|---|---|
| T1 AC1 | 1 eligibility: full detail, old rollup, CLEAN. 2 sync: labels `[]`, old rollup. 3 wait: old rollup only. 4 wait: full detail (MERGEABLE, CLEAN), old plus `test` IN_PROGRESS job/3 with a `startedAt` later than the old entries. 5 wait: full detail (MERGEABLE, CLEAN), old plus `test` SUCCESS job/3. 6 re-gate: full detail, old plus new green, CLEAN | exit 0; `labeled #N ci`; `view-N` count is 6; merged, tree verified |
| T2 AC2 | as T1, with read 5 `test` FAILURE job/3 (`completedAt` later than the old SKIPPED) and read 6 the re-gate detail with old plus new red, UNSTABLE | exit 2; the refusal line; no `pr merge N` |
| T3 AC3 | as T1 reads 1-2, then read 3 onward the full detail with the old rollup only, repeating; `KIT_WRAP_CI_GRACE_SECS=20` | exit 0; the wait made 3 reads (0s, 10s, 20s) before the re-gate read; merged |
| T4 AC4 | read 1 eligibility full detail; read 2 labels `[ci]` with the old rollup; read 3 onward full detail (MERGEABLE, CLEAN), old rollup, repeating | no `pr edit N`; `view-N` count is 4 (eligibility, sync, one wait read, re-gate); merged |
| T5 AC5 | as T1 reads 1-2, then read 3 onward the full detail, CLEAN, with old plus `test` QUEUED job/3 and no timestamps, repeating; `KIT_WRAP_CARRY_CHECKS_SECS=10` | exit 2; the refusal line; no `pr merge N` |
| T6 AC6 | `wrap land`: read 1 labels `[]` plus the old rollup; read 2 old only; read 3 old plus new IN_PROGRESS; read 4 old plus new SUCCESS | exit 0; `pr merge` comes after the 4th `pr view`; merged |
| T7 AC7 | `wrap merge` dry run (no `--apply`), the way the existing CONFLICTING cases drive the gate: one open PR, detail `mergeable: CONFLICTING`, DIRTY, rollup the old entries plus a QUEUED untimestamped `test` | output holds `SKIP #N <title>: not mergeable (CONFLICTING)` |

Reads 4 and 5 in T1 are full detail on purpose. A wait that ends early falls into `_pr_detail_settled`, which loops past any read missing `mergeable`. With full detail at read 4, an early-ended wait re-gates on the pending run and refuses, so the case can fail. T4 pins that an operator whose label is already in place pays no extra wait. The existing cases pin the empty-rollup path, the re-label path, the label that will not set, and the autoland door.

## Negative control

After the feature commit, two runs, each restored before the next:

1. Baseline ignored: a `sed` that rewrites the `CI_LABEL_BASE=` assignment inside the add and re-add branches to `CI_LABEL_BASE='[]'`. T1 must go red: the wait ends on read 3, the re-gate reads read 4 with the IN_PROGRESS `test`, and the merge is refused. T6 is the second tripwire: `land` has no settle loop, so its `pr merge` comes right after the early-ended wait, before the 4th `pr view`.
2. Gate key reverted: a `sed` that restores the old sort key `sort_by(.completedAt // .startedAt // .createdAt // "")`. T5 must go red, because the stale SKIPPED wins and the merge runs.

Both run as `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`. The exact `sed` patterns are settled at build time against the final lines.

## Out of scope

- `cmd_land` does not re-gate after `_ci_checks_wait`. Its `pr merge` runs whatever state the label-started runs are in when the wait ends, so a red run still lands, and so does a run still queued past the carry bound. This predates the change. Adding a gate alters what `land` promises, so it is a separate change (lead decision).
- Label present, new push, then another label. The `ci` label is already on the PR, a new commit is pushed (a label-only workflow starts nothing on `synchronize`), and some other label is then added. Its `labeled` event puts all-SKIPPED entries on the new head. The rollup is non-empty, so the sync neither re-adds `ci` nor records a baseline, the wait reads 0 pending, and the all-SKIPPED rollup passes the gate. Named here, not fixed.
- The two residual races under "Residual race".

## Verification

`bash tests/test-wrap.sh` green with T1 to T7 present, then both negative controls above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap ci label wait"` names it.

## Tasks

- [ ] Task A: `CI_ENTRY_KEY`, the baseline in `_ci_label_sync`, and the NEW-entry precedence in `_ci_checks_wait` (`lib/wrap/wrap.sh`), plus cases T1 to T4 and T6 in `tests/test-wrap.sh`.
- [ ] Task B: the untimestamped-pending sort key in `_pr_gate` (`lib/wrap/wrap.sh`), plus cases T5 and T7.
