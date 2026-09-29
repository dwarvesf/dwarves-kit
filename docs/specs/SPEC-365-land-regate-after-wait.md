# Spec: land and the carry re-gate after the ci wait; the sync dates an existing label

Generated: 2026-09-29
Status: DRAFT (round 1 NEEDS REVISION, 7/7 reviewers in parallel, Reviewer 6 design-bearing=yes pass. Folded: the lead's two design decisions (the carry re-gates itself, and the sync dates a label that is already on) and every warning.)
Lane: full (lib/ enforcement surface: the merge gate of `wrap land`, of the carry autoland and of `wrap merge`; changes what `wrap land` and autoland promise on a label-gated repo)
Type: bug
File: `docs/specs/SPEC-365-land-regate-after-wait.md`
References: `docs/specs/SPEC-360-wrap-ci-label-wait.md` (the gaps its Out of scope and Failure modes name); `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, `_pr_detail_settled`, `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the gh stub, the "merge --apply: the ci label gate", "land: the ci label gate" and autoland ci sections); `commands/wrap.md` (the `land` paragraph and step 10's "Never `wrap land` here" line); `docs/implementation-notes/land-regate-after-wait.md` (deltas)

## Problem

SPEC-360 made `wrap` wait for the runs a fresh `ci` label starts. It left three gaps.

1. `cmd_land` syncs the label and waits, then calls `gh pr merge` with no gate. A label-started run that completes red still lands. So does a run still queued when `KIT_WRAP_CARRY_CHECKS_SECS` runs out. `--match-head-commit` pins the head, and nothing reads the checks.
2. The CLEAN rule does not reach autoland. The rule says: after a wait that ended `NONEW` with a non-empty pre-label snapshot, merge only on `mergeStateStatus == CLEAN`. `_autoland_carry` runs the sync and the wait itself, then lands through `cmd_merge --apply --pr` in a subshell. That inner merge runs its own sync. The label is on by then and the rollup is not empty, so the sync records `CI_PRELABEL_KEYS='[]'`. Every non-SKIPPED pre-label entry then reads as NEW, the inner wait ends on its first read with state `0`, and the CLEAN rule stays off. A carry PR whose label started nothing merges on `UNSTABLE`, on checks that predate the label.
3. The same `[]` snapshot applies to every pass that finds the label already on: a second autoland pass, a re-run of `wrap land` after a refusal, and `wrap merge --apply --pr <n>` as recovery. Each of them skips the CLEAN rule. Any fix for 1 and 2 that holds only on the first pass is undone by the recovery step.

## Picture

```
_ci_label_sync url n [pinned-oid]
  label probe (repo gates on ci?) ............ no -> return 1
  PR read: labels, rollup, headRefOid
    pinned-oid given: re-read while head != pinned, bound SETTLE ... never -> return 3
  label absent      -> snapshot = keys of the whole rollup; add label
  label on, empty   -> snapshot = []; remove + re-add
  label on, entries -> NEW: T = latest `labeled ci` event (issues events API)
                         snapshot = keys of entries whose real start < T
                         events read fails or no ci event -> [] (today)
        |
        v
_ci_checks_wait url n  ->  CI_WAIT_END
        |
        v
_ci_regate url n def pinned-oid   (new helper, cmd_merge's post-wait block moved)
  empty head         -> "could not re-read #n after the check wait"
  head != pinned     -> "head moved to <short> during the check wait"
  _pr_gate != OK     -> "<verdict> once the ci label's checks ran"
  NONEW + snapshot + state != CLEAN -> "no check reported after ... is not CLEAN"
```

Who calls the re-gate:

```
cmd_merge  (rc 0) ....... sync, wait, _ci_regate(head_oid)  -> FAILED merge #n: <reason>; left open
cmd_land   (rc 0) ....... sync(tip), wait, _ci_regate(tip)  -> MERGE FAILED #n: <reason>; left open
           (rc 3) ....... head never showed the pushed tip -> MERGE FAILED, left open
_autoland_carry (rc 0) .. sync, wait, head check, _ci_regate(want)
                            refuse -> SKIP land <branch>: PR #n: <reason>; left open
                            OK     -> cmd_merge --apply --pr n  (its own sync, wait, re-gate: a second check)
```

## Change

1. **`_ci_regate <url> <pr> <def> <pinned-oid>`**, a new helper holding `cmd_merge`'s post-wait block. It reads the PR once through `_pr_detail_settled "$url" "$pr"`, then checks in this order:
   - an empty head: `could not re-read #<pr> after the check wait`;
   - a head other than `<pinned-oid>`: `head moved to <short> during the check wait`;
   - `_pr_gate` not `OK`: `<verdict without SKIP> once the ci label's checks ran`;
   - `${CI_WAIT_END:-}` is `NONEW`, `${CI_PRELABEL_KEYS:-[]}` is not `[]`, and `mergeStateStatus` is not `CLEAN`: `no check reported after the ci label went on, and merge state <S> is not CLEAN`.

   On a refusal it prints the reason on stdout and returns 1. On OK it prints nothing and returns 0. Every caller uses the form `local reason; reason="$(_ci_regate ...)" || { <print refusal>; return <rc>; }`.
2. **`cmd_merge`** replaces its inline post-wait block with `_ci_regate "$url" "$first_eligible" "$def" "$head_oid"`. Its refusal lines keep their text, `FAILED merge #<n>: <reason>; left open`, exit 2, with one exception: an empty re-read now says `could not re-read` instead of `head moved to ` with an empty sha.
3. **`cmd_land`** passes the pushed tip to the sync: `_ci_label_sync "$url" "$n" "$tip"`. In the return-0 branch it calls `_ci_regate "$url" "$n" "$def" "$tip"` after `_ci_checks_wait`. On a refusal it prints `     MERGE FAILED #<n>: <reason>; left open` on stderr and returns 2 before `_gh_merge_retry`. A new return-3 branch prints `     MERGE FAILED #<n>: the PR head never showed the pushed <short>; left open` and returns 2. Nothing is merged, deleted or removed. The PR, the pushed branch, the worktree and the local branch all stay. The return-1 branch (no `ci` label) and the return-2 branch (the label could not be set, or the PR read failed) do not change.
4. **`_autoland_carry`** keeps its sync, its wait and its head check, and when its sync returned 0 it then calls `_ci_regate "$url" "$n" "$def" "$want"`, while it still holds its own snapshot and `CI_WAIT_END`. A refusal prints `     SKIP land ${branch}: PR #${n}: <reason>; left open` and returns 1 without setting `FAILURES`. That is the existing convention for every `SKIP land` line: the PR stays open and `apply` exits 0. On OK the carry lands through `cmd_merge --apply --pr` exactly as today, and that merge re-gates on its own path as a second check.
5. **`_ci_label_sync <url> <pr> [<pinned-oid>]`**:
   - The PR read gains `headRefOid`: `--json labels,statusCheckRollup,headRefOid`. With a pinned oid, the sync re-reads every 2s, up to `KIT_WRAP_SETTLE_SECS`, while the read is a JSON object whose `headRefOid` is not the pinned oid. The snapshot is then taken on the pushed head's rollup. If the head never arrives, the sync prints `     PR #<n> never showed the pushed head <short>` on stderr and returns 3. Without a pinned oid (`cmd_merge`, the carry) it makes one read, as today.
   - A new branch covers the label already on over a non-empty rollup, which today falls through with `[]`. It derives `<owner>/<name>` from the url (`slug="${url#*github.com[:/]}"; slug="${slug%.git}"`). It reads `gh api --paginate "repos/${slug}/issues/${n}/events?per_page=100"` and takes `T`, the latest `created_at` among events with `event == "labeled"` and `label.name == "ci"` (`jq -rs '[.[][] | select(.event == "labeled" and .label.name == "ci") | .created_at] | max // ""'`). When `T` is non-empty, `CI_PRELABEL_KEYS` becomes the `ckey` of every rollup entry whose real start (`[.startedAt, .createdAt] | map(real) | .[0] // ""`) is non-empty and sorts before `T`. That assignment is one line, so a negative-control `sed` can replace it whole. `T` comes in only through `--arg`. When `gh api` exits non-zero (even after printing earlier pages), prints no JSON, or finds no `ci` labeled event, `CI_PRELABEL_KEYS` stays `[]`, which is today's behavior.
   - The absent-label branch and the empty-rollup re-add branch keep their logic.
6. **`_pr_detail_settled`** sets `m="${m:-UNKNOWN}"`, so an empty or failed read keeps the wait going instead of ending it. Without a pushed oid it also re-reads while `mergeStateStatus` reads `UNKNOWN` (`.mergeStateStatus // ""`, so a record without the field does not loop). The pushed-oid branch does not change.
7. **Load-time reset.** Beside the `KIT_WRAP_CI_GRACE_SECS` defaults, `wrap.sh` sets `CI_WAIT_END=''`, so an exported value in the operator's shell never reaches `_ci_regate`.
8. **Comments and docs.** The comments above `cmd_land`, `_autoland_carry`, `_ci_label_sync` and `_pr_detail_settled` name the new behavior. `commands/wrap.md` line 104 (the `land` paragraph) gains the re-gate and the head wait. Line 323 changes "because `land` merges right after it opens a PR and never reads the checks" to "because `land` reads the checks only on a repo that gates on the `ci` label".

`_pr_gate`, `_ci_checks_wait`, `CI_JQ_DEFS`, the env knobs and their defaults stay as they are.

## Contract changes

These change what `wrap land`, autoland and `wrap merge` promise. The operator must accept each one before the build starts.

| # | Surface | Before | After |
|---|---|---|---|
| C1 | `wrap land`, repo gates on `ci` | merges once the wait ends, whatever the checks read | merges only when `_ci_regate` returns OK and the PR showed the pushed head before the sync. Otherwise it prints `MERGE FAILED #<n>: <reason>; left open` and exits 2, and the PR, the pushed branch, the worktree and the local branch stay. The CLEAN rule holds on a re-run too, because the sync dates the label that is already on |
| C2 | same | red or pending checks, `CHANGES_REQUESTED`, `mergeable` still `UNKNOWN`: `land` calls `gh pr merge`, which GitHub refuses in some of these cases (required checks, required reviews, the `BEHIND` state under "require branches to be up to date", all without `--admin`) and accepts in others | `_pr_gate` refuses each of them before any merge call, as `wrap merge --apply` already does. The practical change is non-required checks that are red or pending, and a changes-requested review on a repo that does not require reviews. `BEHIND` mostly changes only the message and the timing, because GitHub reports it only when the up-to-date rule already refuses the merge |
| C3 | same | no read after the wait; one sync read | the sync re-reads up to `KIT_WRAP_SETTLE_SECS` until the pushed head shows; the re-gate adds one `_pr_detail_settled` read, up to `KIT_WRAP_SETTLE_SECS` while `mergeable` or `mergeStateStatus` reads `UNKNOWN` |
| C4 | autoland, label-gated repo | the carry merges through `cmd_merge --pr` on any state `_pr_gate` allows once the wait ends | the carry re-gates first. On a refusal, including a `NONEW` hold with a non-empty snapshot on a state other than `CLEAN`, it prints `SKIP land <branch>: PR #<n>: <reason>; left open`, merges nothing, and `apply` exits 0. A later pass finds the label on, dates it, and applies the same rule |
| C5 | every sync that finds the label on over a non-empty rollup (`wrap merge`, `land` re-runs, autoland passes) | snapshot `[]`: the wait ends on the first read with nothing pending | the snapshot holds the entries that started before the latest `ci` labeled event. When no entry started after it, the wait holds the grace window (`KIT_WRAP_CI_GRACE_SECS`, default 90s) and the CLEAN rule applies. A pass that finds label-started runs already done still ends on one read |
| C6 | autoland on the `NONEW` path with a `CLEAN` state | the grace hold ran once | it runs twice: once in the carry's wait and once in the inner merge's wait, because the inner sync now dates the label. That costs up to `KIT_WRAP_CI_GRACE_SECS` extra per carry and changes no verdict. T13 serves no events, so it does not see the second hold |
| C7 | `_pr_detail_settled` without a pushed oid (every eligibility read and re-gate in `wrap merge`) | an empty read, or a `mergeStateStatus` of `UNKNOWN` over a known `mergeable`, ends the settle at once | both re-read until `KIT_WRAP_SETTLE_SECS` |
| C8 | `wrap merge`, empty re-gate read | `FAILED merge #<n>: head moved to  during the check wait; left open` | `FAILED merge #<n>: could not re-read #<n> after the check wait; left open` |

### Recovery, per refusal reason

| Reason | What the operator does |
|---|---|
| checks are pending or failing (red) | fix the branch in the worktree, commit, and re-run `wrap land <worktree>`. The new push starts nothing on a label-only repo, so the new head's rollup is empty and the sync re-adds the label |
| checks are pending (queued past the carry bound) | wait for the runs, then re-run `land` (or `wrap merge --apply --pr <n>`, or the next autoland pass). The runs started after the `ci` labeled event, so they count as NEW, and the wait ends when they complete |
| no check reported after the ci label went on, state not CLEAN | investigate why the label started nothing: a paths filter, a slow webhook, or a workflow that does not fire on `labeled`. A re-run refuses again until a new check appears or the state reads `CLEAN`, because the sync dates the label |
| merge state BEHIND | update the branch (`gh pr update-branch <n>`, or merge the base in the worktree and push), then re-run `land`. The update push leaves the new head's rollup empty, so the sync re-adds the label |
| changes requested | address the review, then re-run |
| not mergeable (CONFLICTING or UNKNOWN) | `UNKNOWN`: re-run later. `CONFLICTING`: resolve in the worktree, or run `wrap merge --apply --pr <n>`, whose union re-merge and squash fallback handle the log-file case |
| head moved during the check wait / the PR head never showed the pushed head | someone else pushed, or GitHub had not caught up: inspect the PR, then re-run `land` |
| could not re-read the PR | a transient gh failure: re-run |

## Design

### Diagram

The flow and the caller map are drawn once, under `## Picture`.

### Interfaces

| Surface | Before | After |
|---|---|---|
| `_ci_regate <url> <pr> <def> <pinned-oid>` | none | new. Stdout is the refusal reason with rc 1; empty stdout with rc 0 is OK. Reads `${CI_WAIT_END:-}` and `${CI_PRELABEL_KEYS:-[]}` |
| `_ci_label_sync <url> <pr> [<pinned-oid>]` | two args, returns 0/1/2 | optional pinned oid; returns 3 when the pinned head never shows; dates a label that is already on |
| `CI_WAIT_END` | set by the wait | also reset to `''` at load |
| `cmd_land` refusals | `MERGE FAILED #<n>: the ci label could not be set` | adds `MERGE FAILED #<n>: <reason>; left open` and the head-never-showed line |
| `_autoland_carry` lines | `SKIP land ...` set | adds `SKIP land <branch>: PR #<n>: <reason>; left open` |
| gh calls | `gh label list`, `gh pr view`, `gh pr edit` in the sync | adds one paginated `gh api repos/<o>/<r>/issues/<n>/events` read, only when the label is already on over a non-empty rollup |
| test stub | `gh api` answers the login | `gh api .../issues/<n>/events...` prints `GH_STUB_EVENTS_<n>` (default `[]`), then exits `GH_STUB_EVENTS_RC` (default 0); every other `gh api` call is unchanged |

### Approaches considered

For `land`:

1. **One helper shared with `cmd_merge` (chosen).** The post-wait block is an enforcement rule, and two copies of it would drift. With the carry as its third caller, the kit's three-use rule is met anyway. The helper is the block moved as-is, so `cmd_merge`'s tests pin it before `land` uses it.
2. Route `land` through `cmd_merge --apply --pr` (rejected). `cmd_merge` needs the PR to be the operator's own and eligible on its first gate, runs the union re-merge and the squash fallback, and pins the head from its own read, while `land` pins the tip it pushed.
3. Gate `land` on every repo, not only label-gated ones (rejected here). Without the label `land` never waited, so there is no wait to re-gate after, and the change would reach every repo. Named under Out of scope.

For autoland:

1. **The carry re-gates itself with its own snapshot (chosen; round-1 review, Reviewer 5).** The carry holds the real snapshot and `CI_WAIT_END` at the moment the wait ends, so it applies the rule with no state crossing into a subshell. The inner merge keeps its own re-gate as a second check.
2. An env handoff: `CI_CARRY_OID` and `CI_CARRY_KEYS` set in the merge subshell, the inner merge adopting the snapshot with a grace of 0 (rejected in round 1). The adopt condition could fire after the inner sync re-added the label on a moved head. The handoff also needed a grace override, a load-time reset and a head bind no stub case could test.
3. Hand off `CI_WAIT_END` and skip the inner wait (rejected). The carried state is stale by one subshell start, and skipping drops today's second pending hold.

For a label that is already on:

1. **Date the label from the issue events API and keep the entries that started before it (chosen).** Both times are GitHub's own clock. SPEC-360 rejected a local-clock cut for skew, and this cut avoids it. The cost is one paginated read, made only on this branch.
2. Keep `[]` (today, rejected by round 1). Every recovery pass skips the CLEAN rule, which undoes the fix on the second try.
3. Remove and re-add the label on every pass so the sync always has a snapshot (rejected). It fires a new `labeled` event and a new CI run on every pass, even for a head already tested.

### Boundaries

- The label date keys on the latest `ci` labeled event. An `unlabeled` event is not read: the sync reaches this branch only while the label is on, so the latest `labeled` event is the one that put it there.
- An entry with no real start time is left out of the snapshot. It counts as NEW when it completes, and while it is pending the pending count already holds the wait.

## Failure modes

| Failure | Caller | Behavior |
|---|---|---|
| The label-started run completes red | `land`, carry | the re-gate picks the red run as latest for its name and refuses; PR open |
| The run is still queued at the carry bound | `land`, carry | the pending entry sorts last and trips the checks clause; refuses |
| The head moved during the wait | `land`, carry | refuses with `head moved to <short>` |
| GitHub has not shown the pushed head yet when `land` syncs | `land` | the sync re-reads up to `KIT_WRAP_SETTLE_SECS`; the head never shows -> `MERGE FAILED`, left open, nothing labeled |
| The re-gate read fails or is empty | all three | `_pr_detail_settled` re-reads to its bound; still empty -> `could not re-read`; refuses |
| No new entry, state not CLEAN | all three, every pass | refuses with the non-CLEAN line |
| The events read fails, returns no JSON, or holds no `ci` labeled event (a label added before the events retention window, a non-GitHub remote) | every sync with the label on | snapshot `[]`, today's behavior: the wait ends on the first read, and the CLEAN rule does not apply on that pass |
| A pre-label check started in the same second as the `ci` labeled event | every sync with the label on | its start is not before `T`, so it counts as NEW and can end the wait early; the `_pr_gate` re-gate still reads it |
| `mergeable` or `mergeStateStatus` stays `UNKNOWN` past `KIT_WRAP_SETTLE_SECS` | all three | `_pr_gate` refuses (`not mergeable (UNKNOWN)` or `merge state UNKNOWN`) |
| The repo has no `ci` label | `land`, carry | unchanged: no head wait and no re-gate in `land`; the carry's plain pending wait, then `cmd_merge`'s own gates |

## Acceptance criteria

- AC1: `wrap land` on a label-gated repo whose label-started run completes red refuses with `MERGE FAILED #<n>: checks are pending or failing once the ci label's checks ran; left open`, exits 2, and makes no `pr merge` and no `pr close` call. The worktree directory and the local branch still exist.
- AC2: `wrap land` whose label-started run is still queued at `KIT_WRAP_CARRY_CHECKS_SECS` refuses with the same line.
- AC3: `wrap land` refuses with `head moved to <short> during the check wait; left open` when the re-gate read shows a head other than the pushed tip.
- AC4: `wrap land` after a `NONEW` grace expiry with a non-empty snapshot on `UNSTABLE` refuses with the non-CLEAN line.
- AC5: `wrap land` with green new checks and `mergeStateStatus: BEHIND` refuses with `merge state BEHIND (an unresolved thread or a blocked merge) once the ci label's checks ran; left open`.
- AC6: `wrap land` re-run with the label already on, a `ci` labeled event after the old checks started, no new check, and `UNSTABLE` refuses with the non-CLEAN line.
- AC7: `wrap land` whose sync read never shows the pushed tip refuses before any `pr edit` or `pr merge` call.
- AC8: `wrap land` on a repo without the `ci` label makes no `_pr_detail` read (`--json number,title,body`) and no events read, and merges as before.
- AC9: The existing land ci cases (ci-gated, T6, ci-armed, ci-stale, ci-noset) pass with `headRefOid` at the tip on the sync read and full detail on the re-gate read. T6 shows exactly 4 rollup reads from the sync and the wait, and the merge follows the 5th, which is the `_pr_detail` read.
- AC10: Autoland on a label-gated repo whose carry PR holds only pre-label checks, with no new entry and `UNSTABLE`: `apply` exits 0, the output holds `SKIP land <branch>: PR #42: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`, and no `pr merge 42` call is made.
- AC11: A second autoland pass, where the carry PR already carries the label and a `ci` labeled event dates it, refuses the same way.
- AC12: `wrap merge --apply` on a PR with the label already on applies the CLEAN rule from the dated snapshot. It keys on the latest of two `ci` labeled events, ignores a later labeled event for another label, and falls back to today's behavior when the events read fails.
- AC13: T13 passes with exactly 20 reads of #42: 18 today, plus one carry re-gate read for each of its two carries.
- AC14: `cmd_merge`'s existing ci-wait cases (T1 to T5, T3b, T8 to T12) and the settle cases pass unchanged.
- AC15: `bash tests/test-wrap.sh` and `bash tests/test-meta.sh` pass.
- AC16: Each negative control below turns red exactly the traced `chk` lines, read from the failing `chk` names, not only the exit code.

## Test plan

Every case goes in `tests/test-wrap.sh`, beside the "land: the ci label gate", "merge --apply: the ci label gate" and autoland ci sections. The existing `gh` stub serves read k of `pr view <n>` from `GH_STUB_PR_<n>_<j>` for the highest set j <= k (j >= 2), else from `GH_STUB_PR_<n>`. A `--json state,mergeCommit` read neither counts nor steps. The count lands in `$GH_STUB_CALLS.view-<n>`, and a `gh api` call does not count. The stub gains an events branch: `gh api ... /issues/<n>/events...` prints `GH_STUB_EVENTS_<n>` (default `[]`), then exits `GH_STUB_EVENTS_RC` (default 0). A failed later page of real `--paginate` behaves the same way: earlier pages print, then gh exits non-zero. `$TMPD/nosleep` stubs `sleep`, and the harness exports `KIT_WRAP_SETTLE_SECS=0`, so the sync's head wait and the re-gate are one read each.

Fixtures reuse SPEC-360's rollups: `CW_OLD` (`test` SKIPPED on `.../job/1`, `preview` SUCCESS on `.../job/2`, both started and completed 2026-09-28T02:44:01Z), `CW_RUN`, `CW_QUEUED` (zero `completedAt`, empty `conclusion`, real `startedAt` 2026-09-29T10:21:58Z, `.../job/3`), `CW_GREEN`, `CW_RED`. "Full detail at tip" means the whole record `_pr_detail` reads: `headRefOid` = the land tip, `baseRefName: main`, `mergeable: MERGEABLE`, the named `mergeStateStatus`, `reviewDecision: APPROVED`, labels `[ci]`, `isDraft: false`, and the named rollup. A new helper builds it, as `cw_full` does with `PR50_OID`. "Sync at tip" is `{labels, statusCheckRollup, headRefOid: tip}`. `EV_CI` is `[{"event":"labeled","label":{"name":"ci"},"created_at":"2026-09-29T10:21:52Z"}]`. Land cases use PR 42 (`GH_STUB_CREATE_NUM=42`), a fresh `build_land` fixture each, and set `GH_STUB_LAND_REPO`, `GH_STUB_LAND_REMOTE`, `GH_STUB_LAND_BRANCH=feat/land` and `GH_STUB_LAND_DEF=main`, so a merge that should not happen lands for real and the worktree checks can go red.

| Case | Setup (reads served) | Assert |
|---|---|---|
| L1 AC1 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 wait: `CW_OLD`. 3 wait: `CW_RUN`. 4 onward: full detail at tip, UNSTABLE, `CW_RED` | exit 2; the refusal line; no `pr merge 42`; no `pr close`; worktree dir and branch `feat/land` exist; `view-42` count is 5 |
| L2 AC2 | `KIT_WRAP_CARRY_CHECKS_SECS=10`. 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, CLEAN, `CW_QUEUED` | exit 2; the refusal line; no `pr merge 42`; `view-42` count is 4 |
| L3 AC3 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail, CLEAN, `CW_GREEN`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: head moved to 3333333 during the check wait; left open`; no `pr merge 42` |
| L4 AC4 | `KIT_WRAP_CI_GRACE_SECS=20`. 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, UNSTABLE, `CW_OLD` | exit 2; the non-CLEAN line; no `pr merge 42`; `view-42` count is 5 |
| L5 AC5 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, BEHIND, `CW_GREEN` | exit 2; the BEHIND line; no `pr merge 42` |
| L6 AC6 | `KIT_WRAP_CI_GRACE_SECS=20`, `GH_STUB_EVENTS_42="$EV_CI"`. Every read: full detail at tip, UNSTABLE, `CW_OLD` (labels `[ci]`) | exit 2; the non-CLEAN line; no `pr edit 42`; no `pr merge 42`; `view-42` count is 5 |
| L7 AC7 | every read: labels `[]`, `CW_OLD`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: the PR head never showed the pushed <tip short>; left open`; no `pr edit 42`; no `pr merge 42` |
| ci-fuzzy AC8 | unchanged fixture | add: no `--json number,title,body` call and no `/events` call for #42 |
| ci-gated AC9 | read 1 gains `headRefOid` at tip; read 3 becomes full detail at tip, CLEAN, `pr-check` SUCCESS | the "waited out" check rises to `-ge 4`; the other asserts pass unchanged |
| T6 AC9 | read 1 gains `headRefOid` at tip; reads 3 and 4 become full detail at tip, CLEAN, with `CW_RUN` and `CW_GREEN`; the case comment names the 5th read as the re-gate | the merge follows the 5th rollup-bearing read; the 5th read is the `_pr_detail` field list; merged |
| ci-armed, ci-stale, ci-noset AC9 | the sync read gains `headRefOid` at tip. ci-armed's single fixture becomes full detail at tip, CLEAN, `pr-check` SUCCESS. ci-stale's read 2 becomes the same | unchanged asserts pass |
| T13b AC10 | as T13 (`KIT_WRAP_CI_GRACE_SECS=20`, the carry PR on `CW_OLD`, labels `[ci]` from read 2), with `mergeStateStatus: UNSTABLE` on both fixtures | apply exits 0; the `SKIP land` line with the non-CLEAN reason for #42; no `pr merge 42`; `view-42` count is 6 |
| T13c AC11 | as T13b, but labels `[ci]` from read 1 and `GH_STUB_EVENTS_42="$EV_CI"` | apply exits 0; the same `SKIP land` line; no `pr edit 42`; no `pr merge 42` |
| E1 AC12 | `wrap merge --apply`, PR 73, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_full 73 UNSTABLE "$CW_OLD"`; events: `ci` labeled at 2026-09-20T00:00:00Z and at 2026-09-29T10:21:52Z | exit 2; `FAILED merge #73: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`; no `pr merge 73`; `view-73` count is 6 |
| E2 AC12 | PR 74, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_full 74 UNSTABLE "$CW_GREEN"`; events: `EV_CI` plus `labeled` `docs` at 2026-09-29T11:00:00Z | exit 0; merged; `view-74` count is 4 (one wait read: `test@.../job/3` started after `T`) |
| E3 AC12 | PR 75, every read `cw_full 75 UNSTABLE "$CW_OLD"`; `GH_STUB_EVENTS_75="$EV_CI"`, `GH_STUB_EVENTS_RC=1` | exit 0; merged; `view-75` count is 4 (the fallback `[]` snapshot: the events printed, but gh exited 1) |
| T13 AC13 | unchanged fixture | 20 reads of #42 |

## Grounding

**Live rollup shape.** `gh` 2.101.0, read-only, today, public PRs with running checks:

```
gh pr list -R microsoft/vscode --limit 30 --json number,statusCheckRollup,mergeStateStatus
  #338669 BLOCKED  {"name":"Compile & Hygiene","status":"IN_PROGRESS","conclusion":"",
                    "startedAt":"2026-09-29T13:28:56Z","completedAt":"0001-01-01T00:00:00Z",
                    "detailsUrl":"https://github.com/microsoft/vscode/actions/runs/36575231928..."}
gh pr list -R rust-lang/rust --limit 30 --json number,statusCheckRollup,mergeStateStatus
  #163486 BLOCKED  {"name":"PR - test-aarch64-gnu-llvm-21-1","status":"IN_PROGRESS","conclusion":"",
                    "startedAt":"2026-09-29T13:26:38Z","completedAt":"0001-01-01T00:00:00Z",
                    "detailsUrl":"https://github.com/rust-lang/rust/actions/runs/36575034118/j..."}
```

A running CheckRun carries the zero `completedAt`, an empty `conclusion` and a real `startedAt`, the shape of `CW_RUN`. The QUEUED shape (`CW_QUEUED`) was not sampled today: no listed PR had a queued check. It rests on SPEC-360's round-3 sample of four public PRs. The PR record `_pr_detail` reads, sampled with `gh pr view 163486 -R rust-lang/rust --json headRefOid,baseRefName,mergeable,mergeStateStatus,reviewDecision,isDraft,labels`, returns `{"headRefOid":"d8ff9a0c6611…","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","isDraft":false,"labels":[…]}`. The full-detail fixtures use those field names and value spellings. A live `BEHIND` sample was not taken, because the one list call that could have found one returned HTTP 504.

**Live events shape.** Read-only, today:

```
gh api 'repos/rust-lang/rust/issues/163486/events?per_page=100' \
  | jq -c '[.[] | select(.event=="labeled" or .event=="unlabeled") | {event, label, created_at}][0:2]'
[{"event":"labeled","label":{"name":"rollup","color":"f1ffa5"},"created_at":"2026-09-29T13:25:51Z"},
 {"event":"labeled","label":{"name":"S-waiting-on-review","color":"d3dddd"},"created_at":"2026-09-29T13:25:54Z"}]
```

The endpoint serves PR events by issue number. Each labeled event carries `event`, `label.name` and a `created_at` in the same `Z` format as `startedAt`, so a string compare orders them. The PR had 11 events and no `Link` header, so one page held them all. `--paginate` plus `jq -s` covers longer histories. `EV_CI` uses this shape, less the fields the filter never reads.

**Read paths, from the code.** `_autoland_carry` calls `_ci_label_sync` (wrap.sh:1376) and `_ci_checks_wait` (1378), reads `headRefOid`, then runs the subshell merge (1398). `cmd_merge` calls `_ci_label_sync` (2260) and `_ci_checks_wait` (2263). The sync resets `CI_PRELABEL_KEYS='[]'` (1262), and with the label on over a non-empty rollup today it takes neither edit branch and returns 0.

**T13's count.** Today's 18 reads of #42 come from two carries. Carry 1 (the orphan): 1 sync, 3 grace-hold wait reads, 1 head read, then the inner merge's 5 (draft check, eligibility, sync, one wait read, re-gate). Carry 2 (the remainder): 1 sync, 1 wait read, 1 head read, and the inner 5. The carry re-gate adds one read to each, so the total is 20. The events read is `gh api`, which the counter skips, and the stub's default `[]` leaves both inner syncs on today's `[]` snapshot.

**Dry traces of the negative controls.** Each mutation is applied after the feature commit and restored before the next.

NC1: the `cmd_land` call to `_ci_regate` replaced by `:`.
- L1: read 1 snapshots `[test@…/job/1, preview@…/job/2]` at tip. Read 2 (`CW_OLD`) is `NONEW`, read 3 (`CW_RUN`) is pending, read 4 (`CW_RED`) has pending 0 and NEW job/3, so the wait ends. `_gh_merge_retry` runs, the stub lands `feat/land`, the tree verifies, and land removes the worktree and deletes the branch. Red: "L1 exits 2", "L1 refusal line", "L1 no pr merge", "L1 worktree exists", "L1 branch exists", "L1 5 reads" (4).
- L2: read 2 is pending, and read 3 is pending with waited=10, which ends the wait. The merge runs. Red: exit, refusal line, no pr merge, 4 reads (3).
- L3: read 2 has pending 0 and NEW job/3; the merge runs, because the stub ignores `--match-head-commit`. Red: exit, refusal line, no pr merge.
- L4: reads 2 to 4 are `NONEW` until grace 20 runs out; the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- L5: read 2 has pending 0 and NEW job/3; the merge runs. Red: exit, refusal line, no pr merge.
- L6: the dated snapshot holds both old keys; reads 2 to 4 are `NONEW`; the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- T6: the merge follows the 4th rollup read. Red: "the merge follows the 5th read", "the 5th read is `_pr_detail`". L7, ci-gated, ci-armed and ci-stale stay green.

NC2: the `_autoland_carry` call to `_ci_regate` replaced by `:`.
- T13b: the carry's wait holds reads 2 to 4 (`NONEW`), and its head read passes. In the subshell, `cmd_merge`'s sync sees labels `[ci]` over `CW_OLD`, and its events read gets the stub default `[]`, so the snapshot is `[]`. Its one wait read counts `preview@…/job/2` as NEW, state `0`, and its re-gate passes `UNSTABLE`. The merge runs. Red: "T13b SKIP land line", "T13b no pr merge 42", "T13b 6 reads".
- T13c: the carry's hold ends `NONEW` on the dated snapshot. The inner sync dates the label too (`GH_STUB_EVENTS_42` is set), holds its own grace, and its re-gate refuses. `cmd_merge` returns 2, so the carry sets `FAILURES` and `apply` exits 2. Red: "T13c exits 0", "T13c SKIP land line". "T13c no pr merge 42" stays green, because the inner re-gate is the second check doing its job.
- T13: 18 reads instead of 20. Red: "T13 20 reads".

NC3: the dated-snapshot assignment in `_ci_label_sync` replaced by `CI_PRELABEL_KEYS='[]'`.
- L6: the snapshot is `[]`, so read 2 ends the wait with state `0`. The re-gate passes `UNSTABLE`, because the CLEAN rule needs a snapshot, and the merge runs. Red: exit, refusal line, no pr merge, 5 reads (3).
- T13c: the carry's wait ends on state `0`, the carry re-gate passes, and the inner merge, also on `[]`, merges. Red: "T13c SKIP land line", "T13c no pr merge 42".
- E1: one wait read with state `0`, the re-gate passes, and the PR merges. Red: exit, refusal line, no pr merge, 6 reads (4).
- E2, E3, T13 and T13b stay green: they never reach the dated branch with a `ci` event, or the dated branch yields no key they depend on.

NC4: the `.label.name == "ci"` filter dropped.
- E2: `T` becomes 2026-09-29T11:00:00Z (the `docs` event), so job/3 (started 10:21:58) joins the snapshot. The wait holds 3 `NONEW` reads, and the CLEAN rule refuses `UNSTABLE`. Red: "E2 exits 0", "E2 merged", "E2 4 reads".

NC7: the events read's exit code ignored (the sync parses whatever gh printed).
- E3: `EV_CI`, printed before the non-zero exit, dates the label, so the snapshot holds both old keys. The wait holds for the default grace (9 more reads), and the CLEAN rule refuses `UNSTABLE`. Red: "E3 exits 0", "E3 merged", "E3 4 reads".

NC5: `max` replaced by `min`.
- E1: `T` becomes 2026-09-20T00:00:00Z. No entry started before it, so the snapshot is `[]`, one wait read gives state `0`, and the PR merges. Red: exit, refusal line, no pr merge, 6 reads.

NC6: the pinned-head re-read in `_ci_label_sync` dropped (the sync ignores the pinned oid).
- L7: the sync adds the label on the wrong head. The wait runs on `CW_OLD` (`NONEW`, default grace 90, 10 reads). The re-gate then reads head 3333333, not the tip, and refuses with `head moved`. Red: "L7 head-never-showed line", "L7 no pr edit 42". "L7 exits 2" and "L7 no pr merge" stay green.

## Negative control

After the feature commit, one run per control through `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`, each restored before the next: NC1 to NC7 as traced under `## Grounding`. The record quotes the failing `chk` names from each run and checks them against the traced lists. A suite exit code alone does not pass a control. The exact `sed` patterns are set at build time against the final lines.

## Out of scope

- `land` on a repo without the `ci` label still merges with no gate. It never waits there, and a gate there would change `land` on every repo.
- An adopted PR with the label on, a new push, and checks outside the `ci` workflow. On a label-only repo the push starts no `ci` run, but other checks (a third-party app, a workflow on `synchronize`) register on the new head. The rollup is non-empty, so the sync neither re-adds the label nor finds entries that predate the old `ci` event. Every new-head entry started after that event and reads as NEW. The wait ends on them, and the re-gate reads a head the `ci` workflow never ran on. The same shape exists in SPEC-360 (its "Label present, new push, then another label" case).
- The autoland exit-code asymmetry inside `cmd_merge`. A post-wait refusal in the inner merge returns 2 and sets `FAILURES`, while the carry's own re-gate refusal now returns 1 with `apply` exit 0. The inner merge refuses only when the state changed between the two checks.
- The residual races SPEC-360 names: two workflows on one event, the read-to-edit window, `needs:` chains, StatusContext key shifts, delayed webhooks.

## Verification

Iterate with `bin/test-affected`. At the end, run `bash tests/test-wrap.sh` in full once, with L1 to L7, T13b, T13c, E1 to E3 and the updated land cases present, plus `bash tests/test-meta.sh`, then the negative controls above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap land regate after wait"` names it.

## Tasks

- [ ] Task A: extract `_ci_regate` from `cmd_merge`, including the `could not re-read` line; the `_pr_detail_settled` change; the `CI_WAIT_END` load reset (`lib/wrap/wrap.sh`). Check: the existing merge ci-wait and settle cases pass unchanged.
- [ ] Task B (depends on Task A): the pinned-head re-read and return 3 in `_ci_label_sync`; the `cmd_land` re-gate and the return-3 branch (`lib/wrap/wrap.sh`); cases L1 to L5 and L7; the fixture updates for ci-gated, T6, ci-armed, ci-stale and ci-noset; the ci-fuzzy assert (`tests/test-wrap.sh`).
- [ ] Task C (depends on Task A): the carry re-gate in `_autoland_carry` (`lib/wrap/wrap.sh`); case T13b; T13's count and comment (`tests/test-wrap.sh`).
- [ ] Task D (depends on Tasks B and C): the dated snapshot in `_ci_label_sync` (`lib/wrap/wrap.sh`); the stub's events branch; cases L6, T13c and E1 to E3 (`tests/test-wrap.sh`).
- [ ] Task E: the comments named in Change 8; `commands/wrap.md` lines 104 and 323; regenerate `docs/FEATURES.md` if `feature-registry.sh check` reports drift.
