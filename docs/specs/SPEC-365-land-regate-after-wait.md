# Spec: land and the carry re-gate after the ci wait; the sync dates or re-adds an existing label

Generated: 2026-09-29
Status: DRAFT (rounds 1 and 2 folded. Round 1: NEEDS REVISION, 7/7 reviewers in parallel. Round 2: NEEDS REVISION, 7/7. Round 3 is the operator-directed final round. Every round-2 critical, lead call and warning is folded or cut with a Decision Log entry.)
Lane: full (lib/ enforcement surface: the merge gate of `wrap land`, of the carry autoland and of `wrap merge`; changes what `wrap land` and autoland promise on a label-gated repo)
Type: bug
File: `docs/specs/SPEC-365-land-regate-after-wait.md`
References: `docs/specs/SPEC-360-wrap-ci-label-wait.md` (the gaps its Out of scope and Failure modes name); `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, `_pr_detail_settled`, `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the gh stub, the "merge --apply: the ci label gate", "land: the ci label gate" and autoland ci sections); `commands/wrap.md` (the `land` paragraph and step 10's "Never `wrap land` here" line); `docs/implementation-notes/land-regate-after-wait.md` (deltas)

## Problem

SPEC-360 made `wrap` wait for the runs a fresh `ci` label starts. It left three gaps.

1. `cmd_land` syncs the label and waits, then calls `gh pr merge` with no gate. A label-started run that completes red still lands. So does a run still queued when `KIT_WRAP_CARRY_CHECKS_SECS` runs out. `--match-head-commit` pins the head, and nothing reads the checks.
2. The CLEAN rule does not reach autoland. The rule says: after a wait that ended `NONEW` with a non-empty pre-label snapshot, merge only on `mergeStateStatus == CLEAN`. `_autoland_carry` runs the sync and the wait itself, then lands through `cmd_merge --apply --pr` in a subshell. That inner merge runs its own sync. The label is on by then and the rollup is not empty, so the sync records `CI_PRELABEL_KEYS='[]'`. Every non-SKIPPED pre-label entry then reads as NEW, the inner wait ends on its first read with state `0`, and the CLEAN rule stays off. A carry PR whose label started nothing merges on `UNSTABLE`, on checks that predate the label.
3. The same `[]` snapshot applies to every pass that finds the label already on: a second autoland pass, a re-run of `wrap land` after a refusal, and `wrap merge --apply --pr <n>` as recovery. Each of them skips the CLEAN rule. Any fix for 1 and 2 that holds only on the first pass is undone by the recovery step. Worse, after a fix push the label stays on and the `ci` workflow does not run on the new head, while other checks (a workflow on `synchronize`, a third-party app) do. Those checks start after the label went on, so any time cut reads them as the label's runs, and the merge lands a head the `ci` workflow never tested.

## Picture

```
_ci_label_sync url n [pinned-oid [moved]]
  label probe: read fails or is not a JSON array ....... return 2
               no exact `ci` label .................... return 1
  PR read: labels, statusCheckRollup, headRefOid, url, commits
    pinned oid given: re-read every 2s, bound SETTLE, while the read is
      not a JSON object or its head != pinned
      still not an object -> return 2;  head never pinned -> return 3
  label absent          -> snapshot = every rollup key; add label
  label on, empty rollup -> snapshot = []; remove + re-add
  label on, entries:
    moved == 1 ............................................ RE-ADD
    PR url not https://github.com/<owner>/<name>/pull/<n> .. return 2
    events read exits non-zero or prints no JSON .......... return 2
    T = latest `labeled ci` created_at; T empty ........... RE-ADD
    head commit date empty or not before T ................ RE-ADD
    else DATED: snapshot = keys of entries whose start is empty or <= T,
                or whose URL is outside https://github.com/<slug>/actions/
  RE-ADD: snapshot = every rollup key; remove + re-add the label
        |
        v
_ci_checks_wait url n  ->  CI_WAIT_END
        |
        v
_ci_regate url n def pinned-oid   (new helper: cmd_merge's post-wait block, moved)
  empty head ...................................... "could not re-read #n after the check wait"
  head != pinned .................................. "head moved to <short> during the check wait"
  _pr_gate != OK .................................. "<verdict> once the ci label's checks ran"
  CI_WAIT_END != 0, snapshot != [], state != CLEAN  "no check reported after ... is not CLEAN"
```

Who calls what:

```
cmd_merge   sync(no pin) --rc 0--> wait --> _ci_regate(head_oid) --refuse--> FAILED merge #n: <reason>; left open
                         --rc 1--> merge as today
                         --other-> FAILED merge #n: the ci label could not be set

cmd_land    prior = ls-remote origin <branch>, before the push
            moved = 1 when ls-remote fails, or prior is set and != tip
            sync(tip, moved) --rc 0--> wait --> _ci_regate(tip) --refuse--> MERGE FAILED #n: <reason>; left open
                             --rc 1--> merge as today
                             --rc 3--> MERGE FAILED #n: the PR head never showed the pushed <short>; left open
                             --other-> MERGE FAILED #n: the ci label could not be set

_autoland_carry  sync(no pin) --rc 0--> wait --> head check --> _ci_regate(want)
                                  CONFLICTING ----> cmd_merge --apply --pr n (union re-merge, own re-gate)
                                  other refusal --> SKIP land <branch>: PR #n: <reason>; left open
                                  OK -------------> cmd_merge --apply --pr n (own sync, wait, re-gate)
                              --rc 1--> the plain pending wait, as today
                              --other-> SKIP land <branch>: PR #n is unlabeled on a ci-gated repo; left open
```

## Change

1. **`_ci_regate <url> <pr> <def> <pinned-oid>`**, a new helper holding `cmd_merge`'s post-wait block. It reads the PR once through `_pr_detail_settled "$url" "$pr"`, then checks in this order:
   - an empty head: `could not re-read #<pr> after the check wait`;
   - a head other than `<pinned-oid>`: `head moved to <short> during the check wait`;
   - `_pr_gate` not `OK`: `<verdict without SKIP> once the ci label's checks ran`;
   - `${CI_WAIT_END:-}` is not `0`, `${CI_PRELABEL_KEYS:-[]}` is not `[]`, and `mergeStateStatus` is not `CLEAN`: `no check reported after the ci label went on, and merge state <S> is not CLEAN`. Today the clause fires only on `NONEW`. It now also fires when the wait ended on an unreadable read or on the pending bound (the pending case refuses one clause earlier, in `_pr_gate`).

   On a refusal it prints the reason on stdout and returns 1. On OK it prints nothing and returns 0. Every caller uses the form `local reason; reason="$(_ci_regate ...)" || { <print refusal>; return <rc>; }`.
2. **`cmd_merge`** replaces its inline post-wait block with `_ci_regate "$url" "$first_eligible" "$def" "$head_oid"`. Its refusal lines keep their text, `FAILED merge #<n>: <reason>; left open`, exit 2, with one exception: an empty re-read now says `could not re-read` instead of `head moved to ` with an empty sha. Its sync call and its `case` arms do not change: every rc other than 0 and 1 already refuses.
3. **`cmd_land`**:
   - Before its push it reads `git -C "$wt" ls-remote origin "refs/heads/${branch}"`. `moved` is 1 when that read exits non-zero, or when it names an oid other than the tip. It is 0 when the branch is absent on origin or already at the tip.
   - It passes the tip and `moved` to the sync: `_ci_label_sync "$url" "$n" "$tip" "$moved"`.
   - In the return-0 branch it calls `_ci_regate "$url" "$n" "$def" "$tip"` after `_ci_checks_wait`. On a refusal it prints `     MERGE FAILED #<n>: <reason>; left open` on stderr and returns 2 before `_gh_merge_retry`.
   - A new return-3 arm prints `     MERGE FAILED #<n>: the PR head never showed the pushed <short>; left open` and returns 2.
   - Every other rc except 1 keeps today's `MERGE FAILED #<n>: the ci label could not be set`. Nothing is merged, deleted or removed on any refusal. The PR, the pushed branch, the worktree and the local branch all stay.
4. **`_autoland_carry`**:
   - Its sync `case` gains a catch-all: rc 0 waits, rc 1 takes the plain pending wait, and every other rc (2 today, and any later code) prints the existing `SKIP land ${branch}: PR #${n} is unlabeled on a ci-gated repo; left open` and returns 1. The carry passes no pinned oid, so rc 3 cannot occur today. The catch-all keeps a new code from falling through to the merge.
   - After its head check, when its sync returned 0, it calls `_ci_regate "$url" "$n" "$def" "$want"`, while it still holds its own snapshot and `CI_WAIT_END`.
   - A refusal whose reason is exactly `not mergeable (CONFLICTING) once the ci label's checks ran` is not a refusal here. The carry falls through to `cmd_merge --apply --pr`, whose union re-merge resolves the log-file conflict, and whose own sync, wait and re-gate then check the re-merged head.
   - Any other refusal prints `     SKIP land ${branch}: PR #${n}: <reason>; left open` and returns 1 without setting `FAILURES`. That is the existing convention for every `SKIP land` line: the PR stays open and `apply` exits 0.
   - On OK the carry lands through `cmd_merge --apply --pr` exactly as today, and that merge re-gates on its own path as a second check.
5. **`_ci_label_sync <url> <pr> [<pinned-oid> [<moved>]]`**:
   - **The label probe fails closed.** `gh label list` exiting non-zero, or printing anything that is not a JSON array, prints `     could not read the labels of <url>` on stderr and returns 2. Today it returns 1, and the merge runs with no ci gate. An array without an exact `ci` returns 1, as today.
   - **The PR read** becomes `--json labels,statusCheckRollup,headRefOid,url,commits`.
   - **The head wait.** With a pinned oid, the sync re-reads every 2s, up to `KIT_WRAP_SETTLE_SECS`, while the read is not a JSON object or its `headRefOid` is not the pinned oid. When the bound runs out on a read that is still not an object, it prints the existing `could not read the labels and checks of #<n>` and returns 2. When it runs out on a wrong head, it prints `     PR #<n> never showed the pushed head <short>` on stderr and returns 3. The snapshot is always taken on the pinned head's rollup. Without a pinned oid (`cmd_merge`, the carry) it makes one read, as today.
   - **Label absent** and **label on over an empty rollup** keep their logic.
   - **Label on over a non-empty rollup** (today: falls through with `[]`) decides in this order:
     1. `moved` is 1: RE-ADD, reason `the push moved the head`.
     2. The slug comes from the PR's own `url` field, never from the origin remote: it must match `^https://github\.com/([A-Za-z0-9-]+/[A-Za-z0-9._-]+)/pull/<n>$`. Anything else prints `     could not resolve the repo of #<n> from its url` on stderr and returns 2.
     3. It reads `gh api --paginate "repos/${slug}/issues/${n}/events?per_page=100"`. A non-zero exit (even after earlier pages printed), or output `jq -s` cannot parse, prints `     could not read the label events of #<n>` on stderr and returns 2.
     4. `T` is the latest `created_at` among events with `event == "labeled"` and `label.name == "ci"`: `jq -rs '[.[][] | select(.event == "labeled" and .label.name == "ci") | .created_at] | max // ""'`. An empty `T` is RE-ADD, reason `no ci labeled event dates the label`.
     5. `C` is the head commit's `committedDate`: `(.headRefOid // "") as $h | [.commits[]? | select(.oid == $h) | .committedDate] | .[0] // ""`. An empty `C`, or a `C` not before `T` (bash `[[ ! "$C" < "$T" ]]`), is RE-ADD, reason `the head commit is not older than the label`.
     6. Otherwise DATED. `CI_PRELABEL_KEYS` becomes the `ckey` of every entry whose start (`[.startedAt, .createdAt] | map(real) | .[0] // ""`) is empty or `<= T`, or whose `(.detailsUrl // .targetUrl // "")` does not start with `https://github.com/<slug>/actions/`. `T` and the prefix come in only through `--arg`. The assignment is one line, so a negative-control `sed` can replace it whole.
   - **RE-ADD** sets `CI_PRELABEL_KEYS` to every rollup key (the absent-label expression), removes and re-adds the label (failure: the existing `could not re-add` line, return 2), and prints `     re-labeled #<n> ci (<reason>)`. The new `labeled` event starts a `ci` run on the current head, and that run's key is outside the snapshot.
6. **Comments and docs.** The comments above `cmd_land`, `_autoland_carry` and `_ci_label_sync` name the new behavior, including that a failed label read now refuses. `commands/wrap.md` line 104 (the `land` paragraph) gains the re-gate, the head wait and the re-add on a moved head. Line 323 changes "because `land` merges right after it opens a PR and never reads the checks" to "because `land` reads the checks only on a repo that gates on the `ci` label".

`_pr_detail_settled`, `_pr_gate`, `_ci_checks_wait`, `CI_JQ_DEFS`, `CI_WAIT_END`'s handling, the env knobs and their defaults stay as they are. Round 1's `_pr_detail_settled` change and its `CI_WAIT_END` load reset are cut (DEC-H).

## Contract changes

These change what `wrap land`, autoland and `wrap merge` promise. The operator must accept each one before the build starts.

| # | Surface | Before | After |
|---|---|---|---|
| C1 | `wrap land`, repo gates on `ci` | merges once the wait ends, whatever the checks read | merges only when `_ci_regate` returns OK and the PR showed the pushed head before the sync. Otherwise it prints `MERGE FAILED #<n>: <reason>; left open` and exits 2, and the PR, the pushed branch, the worktree and the local branch stay. The CLEAN rule holds on a re-run too, because the sync dates or re-adds the label that is already on |
| C2 | same | red or pending checks, `CHANGES_REQUESTED`, `mergeable` still `UNKNOWN`: `land` calls `gh pr merge`, which GitHub refuses in some of these cases (required checks, required reviews, the `BEHIND` state under "require branches to be up to date", all without `--admin`) and accepts in others | `_pr_gate` refuses each of them before any merge call, as `wrap merge --apply` already does. The practical change is non-required checks that are red or pending, and a changes-requested review on a repo that does not require reviews. `BEHIND` mostly changes only the message and the timing, because GitHub reports it only when the up-to-date rule already refuses the merge |
| C3 | same | no read after the wait; one sync read | the sync re-reads up to `KIT_WRAP_SETTLE_SECS` until the pushed head shows; the re-gate adds one `_pr_detail_settled` read (it re-reads only while `mergeable` reads `UNKNOWN`, as today); `land` adds one `git ls-remote` before its push, on every repo |
| C4 | autoland, label-gated repo | the carry merges through `cmd_merge --pr` on any state `_pr_gate` allows once the wait ends | the carry re-gates first. On a refusal, including a `NONEW` hold with a non-empty snapshot on a state other than `CLEAN`, it prints `SKIP land <branch>: PR #<n>: <reason>; left open`, merges nothing, and `apply` exits 0. A `CONFLICTING` verdict is handed to `cmd_merge`, whose union re-merge runs as today. A later pass finds the label on and applies the same rule |
| C5 | every sync that finds the label on over a non-empty rollup (`wrap merge`, `land` re-runs, autoland passes) | snapshot `[]`: the wait ends on the first read with nothing pending | DATED when the head is older than the latest `ci` labeled event: the snapshot holds every entry that started at or before it, has no start, or sits outside this repo's `actions/` URLs. RE-ADD otherwise (below). When nothing new starts, the wait holds the grace window (`KIT_WRAP_CI_GRACE_SECS`, default 90s) and the CLEAN rule applies. A pass that finds the label's own `actions/` runs already done still ends on one read |
| C6 | autoland on the `NONEW` path with a `CLEAN` state | the grace hold ran once per carry | it runs twice per carry: once in the carry's wait and once in the inner merge's wait, because the inner sync dates the label. Up to `KIT_WRAP_CI_GRACE_SECS` extra per carry, no verdict changes, no flag. Accepted by the lead (DEC-D); T13 and T13d pin the count |
| C7 | the label probe, on every repo (`land`, `merge`, the carry) | a probe that fails reads as "no `ci` label", and the merge runs ungated | a probe that exits non-zero or prints no JSON array refuses: `land` and `merge` print `the ci label could not be set` (after the sync's own `could not read the labels` line) and exit 2; the carry prints its `SKIP land` line. This reaches repos without the label too |
| C8 | the label-on branch | round 1 fell back to `[]` when the events read failed | a failed events read, or a PR url that is not `https://github.com/<owner>/<name>/pull/<n>`, refuses the same way as C7. A GHES repo with the label already on refuses every pass (Out of scope) |
| C9 | the label-on branch | the label was never touched while on over a non-empty rollup | RE-ADD fires a new `labeled` event and a new `ci` run when `land`'s push moved the head, when no `ci` labeled event exists, or when the head commit is not older than the label |
| C10 | the CLEAN rule | applies after a wait that ended `NONEW` | applies after any wait that did not end on state `0`; the new reach is a wait whose last read was unreadable |
| C11 | `wrap merge`, empty re-gate read | `FAILED merge #<n>: head moved to  during the check wait; left open` | `FAILED merge #<n>: could not re-read #<n> after the check wait; left open` |

### Recovery, per refusal reason

| Reason | What the operator does |
|---|---|
| checks are pending or failing (red) | fix the branch in the worktree, commit, and re-run `wrap land <worktree>`. The push moves the head, so the sync removes and re-adds the label and the new head gets its own `ci` run |
| checks are pending (queued past the carry bound) | wait for the runs, then re-run `land` (or `wrap merge --apply --pr <n>`, or the next autoland pass). The runs started after the `ci` labeled event under this repo's `actions/` URLs, so they count as NEW, and the wait ends when they complete |
| no check reported after the ci label went on, state not CLEAN | investigate why the label started nothing: a paths filter, a slow webhook, or a workflow that does not fire on `labeled`. A re-run refuses again until a new check appears or the state reads `CLEAN` |
| merge state BEHIND | update the branch (`gh pr update-branch <n>`, or merge the base in the worktree and push), then re-run `land`. The update commit is newer than the label (GitHub dates its own update commit at push time), so the sync re-adds the label |
| changes requested | address the review, then re-run |
| not mergeable (CONFLICTING or UNKNOWN) | `UNKNOWN`: re-run later. `CONFLICTING`: resolve in the worktree, or run `wrap merge --apply --pr <n>`, whose union re-merge and squash fallback handle the log-file case. Autoland hands this case to that path itself |
| head moved during the check wait / the PR head never showed the pushed head | someone else pushed, or GitHub had not caught up: inspect the PR, then re-run `land` |
| could not re-read the PR / could not read the labels / could not read the label events | a transient gh failure: re-run |
| could not resolve the repo of #n from its url | the PR lives on a host other than github.com. Remove the `ci` label by hand, then re-run: the sync takes the absent-label branch |

## Design

### Diagram

The flow and the caller map are drawn once, under `## Picture`.

### Interfaces

| Surface | Before | After |
|---|---|---|
| `_ci_regate <url> <pr> <def> <pinned-oid>` | none | new. Stdout is the refusal reason with rc 1; empty stdout with rc 0 is OK. Reads `${CI_WAIT_END:-}` and `${CI_PRELABEL_KEYS:-[]}` |
| `_ci_label_sync <url> <pr> [<pinned-oid> [<moved>]]` | two args, returns 0/1/2; a failed probe returns 1 | optional pinned oid and moved flag; returns 3 when the pinned head never shows; a failed probe returns 2; dates or re-adds a label that is already on |
| `cmd_land` refusals | `MERGE FAILED #<n>: the ci label could not be set` | adds `MERGE FAILED #<n>: <reason>; left open` and the head-never-showed line |
| `_autoland_carry` lines | `SKIP land ...` set | adds `SKIP land <branch>: PR #<n>: <reason>; left open`; the unlabeled line now covers every sync rc other than 0 and 1 |
| sync stderr | `could not read the labels and checks`, `could not add`, `could not re-add` | adds `could not read the labels of <url>`, `PR #<n> never showed the pushed head <short>`, `could not resolve the repo of #<n> from its url`, `could not read the label events of #<n>`; stdout adds `re-labeled #<n> ci (<reason>)` for the three RE-ADD reasons |
| gh and git calls | `gh label list`, `gh pr view --json labels,statusCheckRollup`, `gh pr edit` in the sync | the sync read adds `headRefOid,url,commits`; one paginated `gh api repos/<o>/<r>/issues/<n>/events` read, only when the label is on over a non-empty rollup and `moved` is not 1; `land` adds `git ls-remote origin refs/heads/<branch>` before its push |
| test stub | `gh api` answers the login | a `gh api` call whose argument matches `repos/*/issues/<n>/events*` prints `GH_STUB_EVENTS_<n>` (default `[]`), then exits `GH_STUB_EVENTS_RC` (default 0); every other `gh api` call is unchanged. The call is logged like every other |

### Approaches considered

For `land`:

1. **One helper shared with `cmd_merge` (chosen).** The post-wait block is an enforcement rule, and two copies of it would drift. With the carry as its third caller, the kit's three-use rule is met anyway. The helper is the block moved as-is, so `cmd_merge`'s tests pin it before `land` uses it.
2. Route `land` through `cmd_merge --apply --pr` (rejected). `cmd_merge` needs the PR to be the operator's own and eligible on its first gate, runs the union re-merge and the squash fallback, and pins the head from its own read, while `land` pins the tip it pushed.
3. Gate `land` on every repo, not only label-gated ones (rejected here). Without the label `land` never waited, so there is no wait to re-gate after, and the change would reach every repo. Named under Out of scope.

For autoland:

1. **The carry re-gates itself with its own snapshot (chosen; DEC-A).** The carry holds the real snapshot and `CI_WAIT_END` at the moment the wait ends, so it applies the rule with no state crossing into a subshell. The inner merge keeps its own re-gate as a second check. A `CONFLICTING` verdict passes through to the inner merge (DEC-G).
2. An env handoff: `CI_CARRY_OID` and `CI_CARRY_KEYS` set in the merge subshell, the inner merge adopting the snapshot with a grace of 0 (rejected in round 1). The adopt condition could fire after the inner sync re-added the label on a moved head. The handoff also needed a grace override, a load-time reset and a head bind no stub case could test.
3. Hand off `CI_WAIT_END` and skip the inner wait (rejected). The carried state is stale by one subshell start, and skipping drops today's second pending hold.

For a label that is already on over a non-empty rollup:

1. **Date the label from the issue events API; re-add when the head is newer than the label or nothing dates it (chosen; DEC-B, DEC-E, DEC-F).** Both times in the cut are GitHub's own clock. SPEC-360 rejected a local-clock cut for skew, and this cut avoids it. The head-age test uses the committer's clock, which is the one residual (Failure modes). The cost is one paginated read, made only on this branch, plus a new `ci` run when the sync re-adds.
2. Keep `[]` (today, rejected by round 1). Every recovery pass skips the CLEAN rule, which undoes the fix on the second try.
3. Remove and re-add the label on every pass (rejected). It fires a new `labeled` event and a new CI run on every pass, even for a head the `ci` workflow already tested. The chosen approach re-adds only when the head is newer than the label, or nothing dates the label.
4. Snapshot the whole rollup with no date (rejected in round 2). A pass after the label's own runs completed would count those runs as pre-label, hold the grace window, and refuse an `UNSTABLE` PR whose `ci` runs are green. On a moved head it hides nothing either: every entry reads as old, so the CLEAN rule alone would decide whether a head the `ci` workflow never ran on merges.

For a failed label or events read:

1. **Refuse with rc 2 (chosen; DEC-F).** Nothing merges on a read the sync could not trust.
2. Snapshot every key with a real start and print a stderr line (rejected in round 2, the fail-open half of a reviewer conflict). It leaves the CLEAN rule as the only check, and a `CLEAN` state merges a head whose `ci` status nobody read.
3. Fall back to `[]` (round 1, rejected). The wait ends on the first read and the CLEAN rule is off.

### Boundaries

- The label date keys on the latest `ci` labeled event. An `unlabeled` event is not read: the sync reaches this branch only while the label is on, so the latest `labeled` event is the one that put it there.
- An entry with no real start goes in the dated snapshot. It never counts as NEW. While it is pending the pending count holds the wait, and once it completes the wait holds to the grace bound and the CLEAN rule applies.
- The start of an entry is `startedAt`, then `createdAt`. `completedAt` is not a fallback (DEC-I).
- On the dated path only entries under `https://github.com/<slug>/actions/` can count as NEW. A third-party app check on the dated path never ends the wait. The absent-label and RE-ADD paths keep SPEC-360's rule, where any entry outside the snapshot counts (DEC-J).
- The cut is `<= T`: an entry that started in the same second as the label joins the snapshot.

## Failure modes

| Failure | Caller | Behavior |
|---|---|---|
| The label-started run completes red | `land`, carry | the re-gate picks the red run as latest for its name and refuses; PR open |
| The run is still queued at the carry bound | `land`, carry | the pending entry sorts last and trips the checks clause; refuses |
| The head moved during the wait | `land`, carry | refuses with `head moved to <short>` |
| GitHub has not shown the pushed head yet when `land` syncs | `land` | the sync re-reads up to `KIT_WRAP_SETTLE_SECS`; the head never shows -> `MERGE FAILED`, left open, nothing labeled |
| The re-gate read fails or is empty | all three | `_pr_detail_settled` ends on it at once (unchanged) -> `could not re-read`; refuses |
| The wait's last read is unreadable | all three | the CLEAN rule applies (C10); a non-CLEAN state refuses |
| No new entry, state not CLEAN | all three, every pass | refuses with the non-CLEAN line |
| The label probe exits non-zero or prints no JSON array | all three, every repo | refuses (C7); the operator re-runs |
| The events read fails, prints no JSON, or the PR url is not a github.com PR url | every sync with the label on over a non-empty rollup | refuses (C8) |
| No `ci` labeled event (a label added before the events retention window) | same | RE-ADD: a new `ci` run on the current head, the whole rollup in the snapshot |
| `land` pushed a new head onto a PR whose label is on | `land` | RE-ADD before any events read; the push-started checks are in the snapshot, so only the new `ci` run ends the wait |
| A head commit whose committer date predates `T`, pushed after `T` by something other than `land` (a hand push, then `wrap merge --apply --pr`), or a committer clock behind GitHub's | `wrap merge`, carry | residual: the sync takes the DATED path, so a push-started check under this repo's `actions/` URLs counts as NEW and can end the wait on a head the `ci` workflow never ran on. `_pr_gate` still reads every check. `land` does not have this gap, because it knows its own push |
| A check started in the same second as the `ci` labeled event | every dated sync | it joins the snapshot; the wait holds to the grace bound and the CLEAN rule applies (fail closed) |
| The carry PR reads `CONFLICTING` at the carry re-gate | carry | handed to `cmd_merge --apply --pr`: the union re-merge, then its own sync, wait and re-gate on the new head |
| `mergeable` stays `UNKNOWN` past `KIT_WRAP_SETTLE_SECS` | all three | `_pr_gate` refuses (`not mergeable (UNKNOWN)`) |
| The repo has no `ci` label | `land`, carry | unchanged apart from `land`'s `ls-remote`: no head wait and no re-gate in `land`; the carry's plain pending wait, then `cmd_merge`'s own gates |

## Acceptance criteria

- AC1: `wrap land` on a label-gated repo whose label-started run completes red refuses with `MERGE FAILED #<n>: checks are pending or failing once the ci label's checks ran; left open`, exits 2, and makes no `pr merge` and no `pr close` call. The worktree directory and the local branch still exist.
- AC2: `wrap land` whose label-started run is still queued at `KIT_WRAP_CARRY_CHECKS_SECS` refuses with the same line.
- AC3: `wrap land` refuses with `head moved to <short> during the check wait; left open` when the re-gate read shows a head other than the pushed tip.
- AC4: `wrap land` after a `NONEW` grace expiry with a non-empty snapshot on `UNSTABLE` refuses with the non-CLEAN line.
- AC5: `wrap land` with green new checks and `mergeStateStatus: BEHIND` refuses with `merge state BEHIND (an unresolved thread or a blocked merge) once the ci label's checks ran; left open`.
- AC6: `wrap land` re-run on the operator's open PR (adopted, not created), with the branch already at the tip on origin, the label on, a `ci` labeled event after the old checks started, no new check, and `UNSTABLE`, refuses with the non-CLEAN line and makes no `pr edit`.
- AC7: `wrap land` whose sync reads never show the pushed tip within `KIT_WRAP_SETTLE_SECS` refuses before any `pr edit` or `pr merge` call, after exactly the bounded number of reads.
- AC8: `wrap land` whose first sync read shows a stale head and whose second shows the tip labels the PR after the second read and merges.
- AC9: `wrap land` whose push moved the head of an open PR with the label on removes and re-adds the label without reading events, and merges only after the new `ci` run reports.
- AC10: `wrap land` whose label probe prints no JSON array refuses with `MERGE FAILED #<n>: the ci label could not be set` and makes no `pr merge` call.
- AC11: `wrap land` on a repo without the `ci` label makes no `_pr_detail` read (`--json number,title,body`) and no events read, and merges as before.
- AC12: The existing land ci cases (ci-gated, T6, ci-armed, ci-stale, ci-noset) pass with `headRefOid` at the tip on the sync read and full detail on the re-gate read. ci-gated shows exactly 4 counted reads of #42. T6's merge follows the 5th rollup-bearing read, which is the `_pr_detail` read.
- AC13: Autoland on a label-gated repo whose carry PR holds only pre-label checks, with no new entry and `UNSTABLE`: `apply` exits 0, the output holds `SKIP land <branch>: PR #42: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`, and no `pr merge 42` call is made.
- AC14: A second autoland pass, where the carry PR already carries the label and a `ci` labeled event dates it, refuses the same way.
- AC15: T13 passes with exactly 26 reads of #42 (two grace holds per carry, C6). T13d, the same fixture at a 40s grace, passes with exactly 34, which pins four holds.
- AC16: Autoland whose carry PR reads `CONFLICTING` at the carry re-gate hands the PR to `cmd_merge`: the output holds `retry #42: one re-merge of main into` and no carry `SKIP land` line naming `not mergeable (CONFLICTING)`.
- AC17: `wrap merge --apply` on a PR with the label on applies the CLEAN rule from the dated snapshot. It keys on the latest of two `ci` labeled events, keeps in the snapshot an entry started exactly at `T`, an entry with no start, and an entry outside this repo's `actions/` URLs.
- AC18: `wrap merge --apply` ignores a later labeled event for another label, and ends the wait on an `actions/` run that started after `T`.
- AC19: `wrap merge --apply` refuses with `the ci label could not be set` when the events read exits non-zero, when it prints no JSON, and when the PR url is not a github.com PR url, with no `pr edit` and no `pr merge` call.
- AC20: `wrap merge --apply` on a PR whose head commit is newer than the label re-adds the label, holds the grace window, and refuses `UNSTABLE` with the non-CLEAN line.
- AC21: `wrap merge --apply` on a PR with the label on and no `ci` labeled event re-adds the label and merges on `CLEAN` after the grace hold (T4, rewritten).
- AC22: `wrap merge --apply` whose re-gate read is unreadable refuses with `could not re-read #<n> after the check wait; left open`.
- AC23: `wrap merge --apply` whose label probe exits non-zero refuses with `the ci label could not be set` after one read of the PR.
- AC24: `wrap merge --apply` whose wait ended on an unreadable read refuses `UNSTABLE` with the non-CLEAN line.
- AC25: `cmd_merge`'s other ci-wait cases (T1 to T3, T3b, T5, T8 to T12) and the settle cases pass unchanged.
- AC26: `bash tests/test-wrap.sh` and `bash tests/test-meta.sh` pass.
- AC27: Each negative control below turns red exactly the traced `chk` lines, read from the failing `chk` names, not only the exit code.

## Test plan

Every case goes in `tests/test-wrap.sh`, beside the "land: the ci label gate", "merge --apply: the ci label gate" and autoland ci sections. The existing `gh` stub serves read k of `pr view <n>` from `GH_STUB_PR_<n>_<j>` for the highest set j <= k (j >= 2), else from `GH_STUB_PR_<n>`. A `--json state,mergeCommit` read neither counts nor steps. The count lands in `$GH_STUB_CALLS.view-<n>` (`cw_views <n>` reads it), and a `gh api` call does not count. The stub gains the events branch named under Interfaces. A failed later page of real `--paginate` behaves the way `GH_STUB_EVENTS_RC` models it: earlier pages print, then gh exits non-zero. `$TMPD/nosleep` stubs `sleep`, and the harness exports `KIT_WRAP_SETTLE_SECS=0`, so the sync's head wait and the re-gate are one read each unless a case sets the knob.

Fixtures reuse SPEC-360's rollups: `CW_OLD` (`test` SKIPPED on `https://gh/job/1`, `preview` SUCCESS on `https://gh/job/2`, both started and completed 2026-09-28T02:44:01Z), `CW_RUN`, `CW_QUEUED` (zero `completedAt`, empty `conclusion`, real `startedAt` 2026-09-29T10:21:58Z, `https://gh/job/3`), `CW_GREEN`, `CW_RED`. New fixtures:

- `EV_CI`: `[{"event":"labeled","label":{"name":"ci"},"created_at":"2026-09-29T10:21:52Z"}]`. `EV_CI2`: `EV_CI` plus a `ci` labeled event at 2026-09-20T00:00:00Z. `EV_CI_DOCS`: `EV_CI` plus a `docs` labeled event at 2026-09-29T11:00:00Z.
- `CA_OLD`: `CW_OLD` with `detailsUrl` `https://github.com/o/r/actions/runs/1/job/1` and `.../job/2`. `CA_GREEN`: `CA_OLD` plus `test` SUCCESS started 2026-09-29T10:21:58Z on `https://github.com/o/r/actions/runs/2/job/3`.
- `CA_E1`: `CA_OLD` plus three entries: `build` SUCCESS started and completed at exactly 2026-09-29T10:21:52Z on `.../actions/runs/2/job/5`; a StatusContext `legacy`, state SUCCESS, no times, `targetUrl` `https://github.com/o/r/actions/runs/3`; `netlify/deploy-preview` SUCCESS started 2026-09-29T11:00:00Z on `https://app.netlify.com/sites/x/deploys/2`.
- `CW_PUSH`: `CW_OLD` plus `lint` SUCCESS started 2026-09-29T11:00:00Z on `https://github.com/o/r/actions/runs/9/job/9` (a push-started workflow). `CW_PUSH_CI`: `CW_PUSH` plus `test` SUCCESS started 2026-09-29T11:05:00Z on `.../actions/runs/10/job/10` (the re-added label's run).
- `cw_dated <n> <mergeStateStatus> <rollup> [<committedDate>]`: `cw_full`'s record plus `url` `https://github.com/o/r/pull/<n>` and `commits` `[{"oid":PR50_OID,"committedDate":<date>}]`, default date 2026-09-28T02:40:00Z.
- "Full detail at tip" (land): the whole `_pr_detail` record with `headRefOid` = the land tip, `baseRefName: main`, `mergeable: MERGEABLE`, the named `mergeStateStatus`, `reviewDecision: APPROVED`, labels `[ci]`, `isDraft: false`, the named rollup, `url` `https://github.com/o/r/pull/42`, and `commits` at the tip dated 2026-09-28T02:40:00Z. A new helper `ld_full` builds it. "Sync at tip" is `{labels, statusCheckRollup, headRefOid: tip}`.

Land cases use PR 42 and a fresh `build_land` fixture each, and set `GH_STUB_LAND_REPO`, `GH_STUB_LAND_REMOTE`, `GH_STUB_LAND_BRANCH=feat/land` and `GH_STUB_LAND_DEF=main`, so a merge that should not happen lands for real and the worktree checks can go red. They create the PR (`GH_STUB_CREATE_NUM=42`) unless the row says adopted: an adopted case sets `GH_STUB_OPEN_HEAD_feat_land='[{"number":42,"baseRefName":"main","author":{"login":"me"},"isDraft":false}]'`. Merge cases use PR numbers no other fixture uses.

| Case | Setup (reads served) | Assert |
|---|---|---|
| L1 AC1 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 wait: `CW_OLD`. 3 wait: `CW_RUN`. 4 onward: full detail at tip, UNSTABLE, `CW_RED` | exit 2; the refusal line; no `pr merge 42`; no `pr close`; worktree dir and branch `feat/land` exist; `view-42` count is 5 |
| L2 AC2 | `KIT_WRAP_CARRY_CHECKS_SECS=10`. 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, CLEAN, `CW_QUEUED` | exit 2; the refusal line; no `pr merge 42`; `view-42` count is 4 |
| L3 AC3 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail, CLEAN, `CW_GREEN`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: head moved to 3333333 during the check wait; left open`; no `pr merge 42` |
| L4 AC4 | `KIT_WRAP_CI_GRACE_SECS=20`. 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, UNSTABLE, `CW_OLD` | exit 2; the non-CLEAN line; no `pr merge 42`; `view-42` count is 5 |
| L5 AC5 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, BEHIND, `CW_GREEN` | exit 2; the BEHIND line; no `pr merge 42` |
| L6 AC6 | adopted; `feat/land` pushed to the bare remote at the tip before the run (so `moved` is 0); `KIT_WRAP_CI_GRACE_SECS=20`, `GH_STUB_EVENTS_42="$EV_CI"`. Every read: full detail at tip, UNSTABLE, `CW_OLD` | exit 2; `adopted PR #42`; no `pr create`; the non-CLEAN line; no `pr edit 42`; no `pr merge 42`; `view-42` count is 5 |
| L7 AC7 | `KIT_WRAP_SETTLE_SECS=4`. Every read: labels `[]`, `CW_OLD`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: the PR head never showed the pushed <tip short>; left open`; no `pr edit 42`; no `pr merge 42`; `view-42` count is 3 |
| L8 AC8 | `KIT_WRAP_SETTLE_SECS=4`. 1: labels `[]`, `CW_OLD`, `headRefOid` `3333333333333333333333333333333333333333`. 2 sync at tip: labels `[]`, `CW_OLD`. 3 onward: full detail at tip, CLEAN, `CW_GREEN` | exit 0; merged; `view-42` count is 4; the `--add-label ci` edit comes after the second `pr view 42` line of the call log |
| L9 AC9 | adopted; the tip's parent pushed to the bare remote as `feat/land` before the run (so `moved` is 1); `GH_STUB_EVENTS_42="$EV_CI"`. 1 and 2: full detail at tip, CLEAN, `CW_PUSH`. 3 onward: full detail at tip, CLEAN, `CW_PUSH_CI` | exit 0; `re-labeled #42 ci (the push moved the head)`; the remove precedes the add precedes the merge; no `/events` call; `view-42` count is 4 |
| L10 AC10 | `GH_STUB_LABELS='not json'` | exit 2; `MERGE FAILED #42: the ci label could not be set`; `could not read the labels of`; no `pr merge 42` |
| ci-fuzzy AC11 | unchanged fixture | add: no `--json number,title,body` call and no `/events` call for #42 |
| ci-gated AC12 | read 1 gains `headRefOid` at tip; read 3 becomes full detail at tip, CLEAN, `pr-check` SUCCESS | the "waited out" check becomes `cw_views 42` equal to 4. Today's `grep -c '^pr view 42 '` also counts the post-merge `state,mergeCommit` read, so its `-ge 3` (and round 1's `-ge 4`) holds with no re-gate. The other asserts pass unchanged |
| T6 AC12 | read 1 gains `headRefOid` at tip; reads 3 and 4 become full detail at tip, CLEAN, with `CW_RUN` and `CW_GREEN`; the case comment names the 5th read as the re-gate | the merge follows the 5th rollup-bearing read; the 5th read is the `_pr_detail` field list; merged |
| ci-armed AC12 | the single fixture becomes full detail at tip, CLEAN, with `pr-check` SUCCESS started 2026-09-29T10:22:00Z on `https://github.com/o/r/actions/runs/1/job/9`; `GH_STUB_EVENTS_42="$EV_CI"` | unchanged asserts pass (no `pr edit`, merged) |
| ci-stale, ci-noset AC12 | the sync read gains `headRefOid` at tip. ci-stale's read 2 becomes full detail at tip, CLEAN, `pr-check` SUCCESS | unchanged asserts pass |
| autoland ci-gated | `AL_PR_CI_2` gains `url` `https://github.com/o/r/pull/42`, `commits` `[{"oid":"%CARRY_TIP%","committedDate":"2026-09-28T02:40:00Z"}]`, and a `pr-check` started 2026-09-29T10:22:00Z on `.../actions/runs/1/job/9`; `GH_STUB_EVENTS_42="$EV_CI"` | unchanged asserts pass |
| T13b AC13 | as T13 below, with `mergeStateStatus: UNSTABLE` on both fixtures | apply exits 0; the `SKIP land` line with the non-CLEAN reason for #42; no `pr merge 42`; `view-42` count is 6 |
| T13c AC14 | as T13b, but read 1 already carries labels `[ci]`, `url` and `commits` (the reads-2-onward fixture serves every read) | apply exits 0; the same `SKIP land` line; no `pr edit 42`; no `pr merge 42`; `view-42` count is 6 |
| T13 AC15 | renamed "autoland on a ci-gated repo: the carry and the merge each hold the grace window (T13)". `KIT_WRAP_CI_GRACE_SECS=20`, the carry PR on `CW_OLD`, labels `[ci]` from read 2. Reads 2 onward gain `url` and `commits` as in autoland ci-gated; `GH_STUB_EVENTS_42="$EV_CI"` | apply exits 0; tree verified; `view-42` count is 26 |
| T13d AC15 | T13 at `KIT_WRAP_CI_GRACE_SECS=40` | apply exits 0; `view-42` count is 34 (each of the four holds reads 2 more times) |
| T13e AC16 | as T13, with `mergeable: CONFLICTING` and `mergeStateStatus: DIRTY` from read 2 | the output holds `retry #42: one re-merge of main into`; no `SKIP land` line containing `not mergeable (CONFLICTING)`. The re-merge's outcome is not asserted: the union re-merge cases own it |
| E1 AC17 | `wrap merge --apply`, PR 73, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_dated 73 UNSTABLE "$CA_E1" 2026-09-19T00:00:00Z`, `GH_STUB_EVENTS_73="$EV_CI2"` | exit 2; `FAILED merge #73: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`; no `pr edit 73`; no `pr merge 73`; `view-73` count is 6 |
| E2 AC18 | PR 74, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_dated 74 UNSTABLE "$CA_GREEN"`, `GH_STUB_EVENTS_74="$EV_CI_DOCS"` | exit 0; merged; `view-74` count is 4 (one wait read: `test@.../job/3` started after `T`) |
| E3 AC19 | PR 76, every read `cw_dated 76 UNSTABLE "$CA_OLD"`, `GH_STUB_EVENTS_76="$EV_CI"`, `GH_STUB_EVENTS_RC=1` | exit 2; `FAILED merge #76: the ci label could not be set`; `could not read the label events of #76`; no `pr edit 76`; no `pr merge 76`; `view-76` count is 2 |
| E3b AC19 | PR 77, as E3 with `GH_STUB_EVENTS_77='not json'` and rc 0 | the same four asserts for #77; `view-77` count is 2 |
| E5 AC19 | PR 79, every read `cw_dated 79 UNSTABLE "$CA_OLD"` with `url` `https://ghe.example.com/o/r/pull/79` | exit 2; `could not resolve the repo of #79 from its url`; no `/events` call; no `pr merge 79` |
| E4 AC20 | PR 78, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_dated 78 UNSTABLE "$CW_PUSH" 2026-09-29T11:00:00Z`, `GH_STUB_EVENTS_78="$EV_CI"` | exit 2; `re-labeled #78 ci (the head commit is not older than the label)`; the non-CLEAN line; no `pr merge 78`; `view-78` count is 6 |
| T4 AC21 | renamed "the label is already on and no ci labeled event dates it: remove and re-add". `KIT_WRAP_CI_GRACE_SECS=20`; `GH_STUB_PR_63_2` gains `url` `https://github.com/o/r/pull/63`; events default `[]` | exit 0; `re-labeled #63 ci (no ci labeled event dates the label)`; the remove precedes the add; `view-63` count is 6; merged. Today's "a label already on is not edited" assert is replaced |
| T14 AC22 | PR 81: 1 `cw_full 81 CLEAN "$CW_OLD"`; 2 labels `[]`, `CW_OLD`; 3 `cw_full 81 CLEAN "$CW_GREEN"`; 4 `not json` | exit 2; `FAILED merge #81: could not re-read #81 after the check wait; left open`; no `pr merge 81` |
| T15 AC23 | PR 83, `GH_STUB_LABEL_RC=1`, every read `cw_full 83 CLEAN "$CW_GREEN"` | exit 2; `FAILED merge #83: the ci label could not be set`; `could not read the labels of`; no `pr edit 83`; no `pr merge 83`; `view-83` count is 1 |
| T16 AC24 | PR 85, `KIT_WRAP_CARRY_CHECKS_SECS=10`: 1 `cw_full 85 UNSTABLE "$CW_OLD"`; 2 labels `[]`, `CW_OLD`; 3 `not json`; 5 `cw_full 85 UNSTABLE "$CW_OLD"` | exit 2; the non-CLEAN line for #85; no `pr merge 85`; `view-85` count is 5 |

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

A running CheckRun carries the zero `completedAt`, an empty `conclusion` and a real `startedAt`, the shape of `CW_RUN`. An Actions run's `detailsUrl` sits under `https://github.com/<owner>/<name>/actions/`, the prefix the dated snapshot keys on. The QUEUED shape (`CW_QUEUED`) was not sampled today: no listed PR had a queued check. It rests on SPEC-360's round-3 sample of four public PRs. The PR record `_pr_detail` reads, sampled with `gh pr view 163486 -R rust-lang/rust --json headRefOid,baseRefName,mergeable,mergeStateStatus,reviewDecision,isDraft,labels`, returns `{"headRefOid":"d8ff9a0c6611…","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","isDraft":false,"labels":[…]}`. The full-detail fixtures use those field names and value spellings. A live `BEHIND` sample was not taken, because the one list call that could have found one returned HTTP 504.

**Live url and commits shape.** Read-only, today:

```
gh pr view 163486 -R rust-lang/rust --json url,headRefOid,commits \
  --jq '{url, headRefOid, n: (.commits|length), last: (.commits[-1] | {oid, committedDate})}'
{"headRefOid":"d8ff9a0c6611d4b22f1ee3e58a96e805c12aa8d5",
 "last":{"committedDate":"2026-09-29T13:25:46Z","oid":"d8ff9a0c6611d4b22f1ee3e58a96e805c12aa8d5"},
 "n":12,"url":"https://github.com/rust-lang/rust/pull/163486"}
```

`url` has the `https://github.com/<owner>/<name>/pull/<n>` form the slug check expects. Each commit carries `oid` and a `committedDate` in the same `Z` format as `created_at`, so the head-age test is a string compare. On this PR the head commit (13:25:46) predates its first labeled events (13:25:51), the normal order the DATED path relies on.

**Live events shape.** Read-only, today:

```
gh api 'repos/rust-lang/rust/issues/163486/events?per_page=100' \
  | jq -c '[.[] | select(.event=="labeled" or .event=="unlabeled") | {event, label, created_at}][0:2]'
[{"event":"labeled","label":{"name":"rollup","color":"f1ffa5"},"created_at":"2026-09-29T13:25:51Z"},
 {"event":"labeled","label":{"name":"S-waiting-on-review","color":"d3dddd"},"created_at":"2026-09-29T13:25:54Z"}]
```

The endpoint serves PR events by issue number. Each labeled event carries `event`, `label.name` and a `created_at` in the same `Z` format as `startedAt`, so a string compare orders them. The PR had 11 events and no `Link` header, so one page held them all. `--paginate` plus `jq -s` covers longer histories. `EV_CI` uses this shape, less the fields the filter never reads.

**Read paths, from the code.** `_autoland_carry` calls `_ci_label_sync` (wrap.sh:1376) and `_ci_checks_wait` (1378), reads `headRefOid`, then runs the subshell merge (1398); its `case` has arms for 0 and 2 only. `cmd_merge` calls `_ci_label_sync` (2260) and `_ci_checks_wait` (2263), and its `case` refuses every rc other than 0 and 1. The sync resets `CI_PRELABEL_KEYS='[]'` (1262). Its probe (1263 to 1264) returns 1 on any failure of `gh label list`, and with the label on over a non-empty rollup it takes neither edit branch and returns 0. `_pr_detail_settled` (1824) without a pushed oid breaks on the first read whose `mergeable` is not `UNKNOWN`, which includes an empty read, so an unreadable re-gate read reaches `_ci_regate` at once as an empty head.

**T13's count.** Grace 20 makes each `NONEW` hold 3 wait reads. Carry 1 (the orphan): 1 sync (label absent), 3 hold reads, 1 head read, 1 carry re-gate read, then the inner merge: draft check, eligibility, sync (label on, dated on `EV_CI`, `CW_OLD` in the snapshot), 3 hold reads, re-gate. That is 13. Carry 2 (the remainder) finds the label on: 1 sync (dated), 3 hold reads, 1 head read, 1 carry re-gate read, and the same inner 7. That is 13 more, 26 in all. The events read is `gh api`, which the counter skips. At grace 40 each hold is 5 reads, so T13d reads 26 + 4 x 2 = 34. T13b and T13c refuse at carry 1's re-gate, read 6.

**Dry traces of the negative controls.** Each mutation is applied after the feature commit and restored before the next.

NC1: the `cmd_land` call to `_ci_regate` replaced by `:`.
- L1: read 1 snapshots `[test@…/job/1, preview@…/job/2]` at tip. Read 2 (`CW_OLD`) is `NONEW`, read 3 (`CW_RUN`) is pending, read 4 (`CW_RED`) has pending 0 and NEW job/3, so the wait ends. `_gh_merge_retry` runs, the stub lands `feat/land`, the tree verifies, and land removes the worktree and deletes the branch. Red: "L1 exits 2", "L1 refusal line", "L1 no pr merge", "L1 worktree exists", "L1 branch exists", "L1 5 reads" (4).
- L2: read 2 is pending, and read 3 is pending with waited=10, which ends the wait. The merge runs. Red: exit, refusal line, no pr merge, 4 reads (3).
- L3: read 2 has pending 0 and NEW job/3; the merge runs, because the stub ignores `--match-head-commit`. Red: exit, refusal line, no pr merge.
- L4: reads 2 to 4 are `NONEW` until grace 20 runs out; the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- L5: read 2 has pending 0 and NEW job/3; the merge runs. Red: exit, refusal line, no pr merge.
- L6: the dated snapshot holds both old keys; reads 2 to 4 are `NONEW`; the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- T6: the merge follows the 4th rollup read. Red: "the merge follows the 5th read", "the 5th read is `_pr_detail`". ci-gated: 3 counted reads. Red: "ci-gated 4 reads". L7 to L10, ci-armed and ci-stale stay green.

NC2: the `_autoland_carry` call to `_ci_regate` replaced by `:`.
- T13b: the carry's hold ends `NONEW` and its head read passes. In the subshell, `cmd_merge`'s sync dates the label on `EV_CI`, holds its own grace, and its re-gate refuses `UNSTABLE`. `cmd_merge` returns 2, so the carry sets `FAILURES` and `apply` exits 2. Red: "T13b exits 0", "T13b SKIP land line", "T13b 6 reads" (13). "T13b no pr merge 42" stays green: the inner re-gate is the second check doing its job.
- T13c: the same path. Red: "T13c exits 0", "T13c SKIP land line", "T13c 6 reads".
- T13: 24 reads instead of 26. Red: "T13 26 reads". T13d: 32 instead of 34. Red: "T13d 34 reads". T13e stays green: with no carry re-gate the carry reaches `cmd_merge` anyway.

NC3: the DATED assignment in `_ci_label_sync` replaced by `CI_PRELABEL_KEYS='[]'`.
- L6: read 2 ends the wait with state `0`. The re-gate passes `UNSTABLE`, because the CLEAN rule needs a snapshot, and the merge runs. Red: exit, refusal line, no pr merge, 5 reads (3).
- T13c: the carry's wait ends on state `0`, the carry re-gate passes, and the inner merge, also on `[]`, merges. Red: "T13c SKIP land line", "T13c no pr merge 42", "T13c 6 reads".
- T13: carry 2 and both inner merges end their waits on one read: 20 reads. Red: "T13 26 reads", "T13d 34 reads".
- E1: one wait read with state `0`, the re-gate passes, and the PR merges. Red: exit, refusal line, no pr merge, 6 reads (4).
- E2 stays green (its one NEW entry ends the wait either way). T4, E4 and L9 take RE-ADD before the DATED line and stay green.

NC4: the `.label.name == "ci"` filter dropped.
- E2: `T` becomes 2026-09-29T11:00:00Z (the `docs` event). The head (2026-09-28T02:40:00Z) is still older, so the path stays DATED, and job/3 (started 10:21:58) joins the snapshot. The wait holds 3 `NONEW` reads, and the CLEAN rule refuses `UNSTABLE`. Red: "E2 exits 0", "E2 merged", "E2 4 reads".

NC5: `max` replaced by `min`.
- E1: `T` becomes 2026-09-20T00:00:00Z. The head (2026-09-19) is older, so the path stays DATED. `preview@…/job/2` (started 2026-09-28, under `actions/`) is now NEW, one wait read gives state `0`, and the PR merges. Red: exit, refusal line, no pr merge, 6 reads.

NC6: the pinned-head re-read in `_ci_label_sync` dropped (the sync ignores the pinned oid).
- L7: the sync adds the label on the wrong head. The wait runs on `CW_OLD` (`NONEW`, default grace 90, 10 reads). The re-gate then reads head 3333333 and refuses with `head moved`. Red: "L7 head-never-showed line", "L7 no pr edit 42", "L7 3 reads". "L7 exits 2" and "L7 no pr merge" stay green.
- L8: the sync labels after read 1. Read 2 holds `NONEW`, read 3 ends the wait, read 4 re-gates, and the merge runs. Red: "L8 edit after the second read". The exit, the merge and the count (4) stay green.

NC7: the events read's exit code ignored (the sync parses whatever gh printed).
- E3: `EV_CI`, printed before the non-zero exit, dates the label, so the snapshot holds both old keys. The wait holds for the default grace (10 reads), and the CLEAN rule refuses `UNSTABLE` with the non-CLEAN line. Red: "E3 refusal line", "E3 events line", "E3 2 reads". The exit, no pr edit and no pr merge stay green.

NC8: the carry's `CONFLICTING` pass-through dropped (every refusal prints `SKIP land`).
- T13e: the carry prints `SKIP land …: not mergeable (CONFLICTING) once the ci label's checks ran; left open` and never calls `cmd_merge`. Red: "T13e retry line", "T13e no CONFLICTING SKIP line".

NC9: the `moved` arm dropped.
- L9: the path goes DATED on `EV_CI` (the fixture's head date, 2026-09-28T02:40:00Z, is older than `T`). `lint@…/runs/9/job/9` started after `T` under `actions/`, so read 2 ends the wait with state `0`, the re-gate passes, and the merge runs on a head the label's run never reached. Red: "L9 re-label line", "L9 remove, add, merge order", "L9 no events call", "L9 4 reads" (3). The exit and the merge stay green: this is the round-2 critical, and the proof that the fix is live is the order and the count.

NC10: the head-age arm dropped.
- E4: the path goes DATED; `lint` is NEW, read 3 ends the wait with state `0`, and the re-gate passes `UNSTABLE`. Red: exit, re-label line, non-CLEAN line, no pr merge, 6 reads (4).

NC11: the empty-`T` arm returns 0 with the `[]` snapshot instead of RE-ADD (round 1's behavior). Dropping the arm outright is not a control: the head-age arm would then RE-ADD on the empty `T` anyway.
- T4: one wait read ends on `preview` as NEW. Red: "T4 re-label line", "T4 remove precedes add", "T4 6 reads" (4). Exit and merged stay green.

NC12: the DATED cut `<= T` replaced by `< T`.
- E1: `build@…/job/5` (started exactly at `T`) is NEW; the wait ends on read 3 and the PR merges. Red: exit, refusal line, no pr merge, 6 reads.

NC13: the empty-start arm of the DATED cut dropped.
- E1: `legacy@…/runs/3` (no times, under `actions/`) is NEW; the PR merges. Red: the same four lines.

NC14: the `actions/` prefix arm of the DATED cut dropped.
- E1: `netlify/deploy-preview` (started 11:00, outside `actions/`) is NEW; the PR merges. Red: the same four lines.

NC15: the probe's failure arm returns 1 (today's behavior).
- T15: no gate; the eligibility read passed on `CLEAN`, so the PR merges. Red: exit, refusal line, labels line, no pr merge. L10: land merges ungated. Red: exit, refusal line, labels line, no pr merge.

NC16: the CLEAN clause keyed back on `CI_WAIT_END == NONEW`.
- T16: the wait ends on state `""`; the clause does not fire and the PR merges on `UNSTABLE`. Red: exit, non-CLEAN line, no pr merge.

NC17: a failed `jq -s` parse of the events ignored (only gh's exit code checked).
- E3b: `T` comes back empty, so the sync takes RE-ADD, holds the default grace, and refuses `UNSTABLE` with the non-CLEAN line. Red: "E3b refusal line", "E3b events line", "E3b no pr edit", "E3b 2 reads".

## Negative control

After the feature commit, one run per control through `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`, each restored before the next: NC1 to NC17 as traced under `## Grounding`. The record quotes the failing `chk` names from each run and checks them against the traced lists. A suite exit code alone does not pass a control. The exact `sed` patterns are set at build time against the final lines.

## Out of scope

- `land` on a repo without the `ci` label still merges with no gate. It never waits there, and a gate there would change `land` on every repo.
- A PR on a host other than github.com (GHES) with the `ci` label already on over a non-empty rollup. The slug check refuses it every pass. The recovery row names the manual step. Supporting it needs the events read to target the PR's own host.
- The `actions/` prefix rule on the absent-label and RE-ADD paths. There a third-party check that registers after the label still counts as NEW and can end the wait early, as in SPEC-360 (its T12 depends on it).
- A head commit dated before the label but pushed after it by something other than `land`, and committer clock skew (Failure modes). No GitHub field dates a push.
- The autoland exit-code asymmetry inside `cmd_merge`. A post-wait refusal in the inner merge returns 2 and sets `FAILURES`, while the carry's own re-gate refusal now returns 1 with `apply` exit 0. The inner merge refuses only when the state changed between the two checks.
- The residual races SPEC-360 names: two workflows on one event, the read-to-edit window, `needs:` chains, StatusContext key shifts, delayed webhooks.

## Verification

Iterate with `bin/test-affected`. At the end, run `bash tests/test-wrap.sh` in full once, with L1 to L10, T13 to T13e, E1 to E5, E3b, T4, T14 to T16 and the updated land and autoland cases present, plus `bash tests/test-meta.sh`, then the negative controls above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap land regate after wait"` names it.

## Tasks

- [ ] Task A: extract `_ci_regate` from `cmd_merge`, with the `could not re-read` line and the CLEAN clause on `CI_WAIT_END != 0` (`lib/wrap/wrap.sh`); cases T14 and T16 (`tests/test-wrap.sh`). Check: the existing merge ci-wait and settle cases pass unchanged.
- [ ] Task B1 (depends on Task A): in `_ci_label_sync`, the fail-closed probe, the wider PR read and the pinned-head wait with return 3; in `cmd_land`, the `ls-remote` before the push, the new sync arguments and the return-3 arm (`lib/wrap/wrap.sh`). Cases L7, L8, L10 and T15; `headRefOid` at tip on the sync reads of ci-gated, T6, ci-armed, ci-stale and ci-noset (`tests/test-wrap.sh`). Check: every land ci case passes.
- [ ] Task B2 (depends on Task B1): the `cmd_land` re-gate (`lib/wrap/wrap.sh`); cases L1 to L5; the full-detail re-gate fixtures of ci-gated, T6, ci-armed and ci-stale; ci-gated's count on `cw_views`; the ci-fuzzy asserts (`tests/test-wrap.sh`).
- [ ] Task C (depends on Task A): the carry re-gate, the `CONFLICTING` pass-through and the catch-all `case` arm in `_autoland_carry` (`lib/wrap/wrap.sh`); cases T13b and T13e; T13's count becomes 20 for this task (18 plus one carry re-gate read per carry) (`tests/test-wrap.sh`).
- [ ] Task D (depends on Tasks B2 and C): the label-on branch of `_ci_label_sync` (the `moved` arm, the slug check, the events read, the empty-`T` and head-age RE-ADD arms, the DATED cut, the RE-ADD helper) (`lib/wrap/wrap.sh`); the stub's events branch; cases L6, L9, T13c, T13d, E1 to E5, E3b; T4 rewritten; T13 renamed with events and 26 reads; the ci-armed and autoland ci-gated fixtures (`tests/test-wrap.sh`).
- [ ] Task E: the comments named in Change 6; `commands/wrap.md` lines 104 and 323; regenerate `docs/FEATURES.md` if `feature-registry.sh check` reports drift.

## Touches

- lib/wrap/**
- tests/**
- commands/**
- docs/implementation-notes/**

## Decision Log

- DEC-A: The carry re-gates itself with its own snapshot and `CI_WAIT_END` (round-1 lead call, kept). Rationale: no state crosses into the `cmd_merge` subshell, and the inner merge's re-gate stays as a second check. Rejected: the env handoff with a grace override, and handing off `CI_WAIT_END` (Approaches considered).
- DEC-B: A label already on over a non-empty rollup is dated from the issue events API (round-1 lead call, kept and extended by DEC-E and DEC-F). Rationale: both times in the cut come from GitHub's clock. Rejected: `[]`, re-add on every pass, and (round 2) a whole-rollup snapshot with no date.
- DEC-C: The pushed-head wait lives inside `_ci_label_sync` behind an optional pinned oid, with a distinct return 3 (round-2 lead call, kept). Rationale: it runs only after the probe says the repo gates, reuses the sync's own read, and keeps its message apart from "could not be set". Rejected: a separate read in `cmd_land` ahead of the sync, which would reach every repo. R2's warning folds in: a read that is not a JSON object keeps the wait going until the bound.
- DEC-D: The C6 double grace hold (up to `KIT_WRAP_CI_GRACE_SECS` extra per carry) is accepted with no flag (round-2 lead call). Rationale: it changes no verdict, and a flag to skip the inner hold would bring back the subshell handoff DEC-A removed. T13 now serves `EV_CI` and asserts the real count (R5), and T13d pins four holds at a second grace value (R2).
- DEC-E: Round-2 critical R1(a), a merge on a head the `ci` workflow never ran on. After a fix push the label stays on, push-started checks start after `T`, and the DATED cut read them as NEW. Fix: RE-ADD instead of dating when `land`'s push moved the head (`ls-remote` before the push, a failed read counting as moved), or when the head commit is not older than `T`. Tests: L9, E4; controls NC9, NC10. The head-age arm uses the committer's clock; its gap is named under Failure modes and Out of scope.
- DEC-F: Round-2 critical R1(b), fail-open reads, with R2's conflicting fallback. One fail-closed rule: a label probe or events read that exits non-zero or prints no JSON returns 2 and refuses; a PR url that is not a github.com PR url returns 2 as well. When the events read works and holds no `ci` labeled event, the sync RE-ADDs. Rejected: R2's "snapshot every key with a real start, plus a stderr line", because it leaves the CLEAN rule as the only check on a `CLEAN` PR whose `ci` status nobody read. Tests: T15, L10, E3, E3b, E5, T4; controls NC7, NC11, NC15, NC17.
- DEC-G: Round-2 critical R3, the carry re-gate refusing a `CONFLICTING` carry PR and so blocking the inner union re-merge. Fix: the carry treats exactly `not mergeable (CONFLICTING) once the ci label's checks ran` as a pass-through to `cmd_merge --apply --pr`, whose union re-merge, sync, wait and re-gate then run on the re-merged head. The match is on the full reason text, the same way `cmd_merge` matches `SKIP not mergeable (CONFLICTING)`. Test: T13e; control NC8.
- DEC-H: Round 1's Change 6 (`_pr_detail_settled` re-reading an empty read and an `UNKNOWN` merge state) and round 1's contract row C7 are cut (R4 and R5: untested settle retries; cut preferred over new cases). Round 1's Change 7 (the `CI_WAIT_END` load reset) is cut too (R4): every `_ci_regate` call runs right after `_ci_checks_wait`, which assigns `CI_WAIT_END` unconditionally, and the clause now fires on any value other than `0`, so an unset or stale value fails closed. With Change 6 cut, an empty re-gate read ends the settle at once and refuses as `could not re-read` (T14).
- DEC-I: R2's "start time falls back to `completedAt`" is cut, in favor of R1's "no-real-start entries go in the snapshot". With R1's rule, the fallback could only move an entry from the snapshot to NEW (an entry with no start that completed after `T`), which is the fail-open direction. R1's rule already covers the case R2 raised.
- DEC-J: R1's "only `github.com/<slug>/actions/` URLs count as NEW" applies to the DATED cut only, not inside `_ci_checks_wait`. Rationale: the DATED path is where a time cut meets checks the label did not start; putting the rule in the wait would change SPEC-360's fresh-label path, whose T12 ends the wait on new third-party checks. Named under Out of scope. Control: NC14.
- DEC-K: R2's "add an rc 3 arm to the carry" is folded as a catch-all arm: every sync rc other than 0 and 1 prints the existing unlabeled `SKIP land` line. The carry passes no pinned oid (its own post-wait head check and the re-gate's head check cover a moved head), so rc 3 cannot occur there today, and the catch-all keeps any later code fail-closed.
- DEC-L: R1's "apply CLEAN when `CI_WAIT_END != 0`" is folded with the existing message text, so T3b's assert stands. The new reach is the unreadable-last-read end (T16, NC16); the pending-bound end already refuses in `_pr_gate`.
- DEC-M: R1's slug validation and R2's "owner/name from the PR's own url" fold together: the slug comes from the PR's `url` field, never from the origin remote (which can be an ssh host alias), and must match the github.com PR url pattern. Anything else refuses (fail closed); a GHES repo with the label on is Out of scope.
- DEC-N: R1's `<=` cut is folded: an entry that started in the same second as `T` joins the snapshot. Control: NC12. R1's "no-real-start entries go in the snapshot" is folded (Boundaries). Control: NC13.
- DEC-O: R2's "test the settle defaults" is read as the head wait's bound under a non-zero `KIT_WRAP_SETTLE_SECS`, which the harness default of 0 never exercises: L7 and L8 run at 4s and assert the read counts (3 and 4). Change 6 is cut (DEC-H), so no other settle default changes.
- DEC-P: R4's test fixes fold: the could-not-re-read refusal gets T14; the head appearing on a later read gets L8; ci-gated's count moves to the stub's `cw_views` counter, because `grep -c '^pr view 42 '` also counts the post-merge `state,mergeCommit` read and passes with no re-gate; L6 adopts the operator's open PR with the branch already at the tip, the real re-run shape; Task B splits into B1 (the sync and land's call site) and B2 (the land re-gate).
- DEC-Q: R5's T13 fix folds: T13 serves `EV_CI`, is renamed for what it now shows, and asserts 26 reads. The whole-rollup snapshot becomes rejected alternative 4.
