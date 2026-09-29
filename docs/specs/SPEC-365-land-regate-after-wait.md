# Spec: land and the carry re-gate after the ci wait; the sync dates or re-adds an existing label

Generated: 2026-09-29
Status: VALIDATED (rounds 1 to 3 NEEDS REVISION, each folded. Round 4 APPROVED, 0 criticals, 7/7; its warnings are folded as wording, test additions and rule clarifications, DEC-AC to DEC-AL.)
Lane: full (lib/ enforcement surface: the merge gate of `wrap land`, of the carry autoland and of `wrap merge`; changes what `wrap land` and autoland promise on a label-gated repo)
Type: bug
File: `docs/specs/SPEC-365-land-regate-after-wait.md`
References: `docs/specs/SPEC-360-wrap-ci-label-wait.md` (the gaps its Out of scope and Failure modes name); `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, `_pr_detail_settled`, `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the gh stub, the "merge --apply: the ci label gate", "land: the ci label gate" and autoland ci sections); `commands/wrap.md` (the `land` paragraph and step 10's "Never `wrap land` here" line); `docs/implementation-notes/land-regate-after-wait.md` (deltas)

## Problem

SPEC-360 made `wrap` wait for the runs a fresh `ci` label starts. It left four gaps.

1. `cmd_land` syncs the label and waits, then calls `gh pr merge` with no gate. A label-started run that completes red still lands. So does a run still queued when `KIT_WRAP_CARRY_CHECKS_SECS` runs out. `--match-head-commit` pins the head, and nothing reads the checks.
2. The CLEAN rule does not reach autoland. The rule says: after a wait that ended `NONEW` with a non-empty pre-label snapshot, merge only on `mergeStateStatus == CLEAN`. `_autoland_carry` runs the sync and the wait itself, then lands through `cmd_merge --apply --pr` in a subshell. That inner merge runs its own sync. The label is on by then and the rollup is not empty, so the sync records `CI_PRELABEL_KEYS='[]'`. Every non-SKIPPED pre-label entry then reads as NEW, the inner wait ends on its first read with state `0`, and the CLEAN rule stays off. A carry PR whose label started nothing merges on `UNSTABLE`, on checks that predate the label.
3. The same `[]` snapshot applies to every pass that finds the label already on: a second autoland pass, a re-run of `wrap land` after a refusal, and `wrap merge --apply --pr <n>` as recovery. Each of them skips the CLEAN rule. Any fix for 1 and 2 that holds only on the first pass is undone by the recovery step. Worse, after a fix push the label stays on and the `ci` workflow does not run on the new head, while other checks (a workflow on `synchronize`, a third-party app) do. Those checks start after the label went on, so any time cut reads them as the label's runs, and the merge lands a head the `ci` workflow never tested. The fix re-adds the label on a head wrap pushed. That puts in the snapshot only the push-started runs that registered before the sync's read. A push-started Actions run that registers after the read, and completes before the `ci` run registers, stays a named residual (Failure modes).
4. The label probe fails open. `_ci_label_sync` returns 1 ("no `ci` label", so no gate) whenever `gh label list` fails or prints something unreadable, and every caller then merges ungated. A fail-closed probe must still read gh's real no-match answer: `gh label list --search <no match> --json name` exits 0 and prints zero bytes, not `[]` (Grounding). Round 2's fix refused on "not a JSON array", which would have refused every repo without a `ci` label. The probe now refuses only on a non-zero exit, or on output that is not empty or whitespace-only and is not an array. It reads exit 0 with empty or whitespace-only output as "no `ci` label".

## Picture

```
_ci_label_sync url n [pinned-oid [moved]]
  CI_PRELABEL_KEYS = []; CI_NEW_SCOPE = ""        (cleared on every call, before the probe)
  label probe: exits non-zero ............................ return 2
               exits 0, empty or whitespace-only output .. return 1   (ungated, as today)
               any other output that is not a JSON array . return 2
               array without an exact `ci` label ......... return 1
  PR read: labels, statusCheckRollup, headRefOid, url, commits
    pinned oid given: re-read every 2s, bound SETTLE, while the read is
      not a JSON object or its head != pinned
      still not an object -> return 2;  head never pinned -> return 3
  label absent  -> snapshot = every rollup key; add label            (scope stays "")
  label on:
    PR url not https://github.com/<owner>/<name>/pull/<n> ... return 2
    CI_NEW_SCOPE = <owner>/<name>
    empty rollup -> snapshot = []; remove + re-add
    entries      -> _ci_label_date  ->  READD <reason>  |  DATED <T>   (rc 2 on a failed read)
        moved == 1 ............................................ READD
        events read exits non-zero or prints unparseable text .. return 2
        events read exits 0 with zero bytes .................... no events: T empty
        T = latest `labeled ci` created_at; T empty ............ READD
        head commit date empty or not before T ................. READD
        else DATED
      READD: snapshot = every rollup key; remove + re-add the label
      DATED: snapshot = keys of entries whose start is empty or <= T
      a snapshot the jq cannot build (empty output) ............ return 2, no edit made
        |
        v
_ci_checks_wait url n  ->  CI_WAIT_END
  NEW = an entry outside the snapshot that is not SKIPPED.
  When CI_NEW_SCOPE is set, only an Actions run of this repo counts as NEW:
  non-empty workflowName AND detailsUrl/targetUrl under https://github.com/<scope>/actions/
        |
        v
_ci_regate url n def pinned-oid   (new helper: cmd_merge's post-wait block, moved)
  empty head ...................................... "could not re-read #n after the check wait"
  head != pinned .................................. "head moved to <short> during the check wait"
  _pr_gate != OK .................................. "<verdict> once the ci label's checks ran"
                                                     (rc 3 when the verdict is CONFLICTING, else rc 1)
  CI_WAIT_END != 0, snapshot != [], state != CLEAN:
      CI_WAIT_END NONEW, CI_NEW_SCOPE empty ....... "no check reported after ... is not CLEAN"
      CI_WAIT_END NONEW, CI_NEW_SCOPE set ......... "no Actions run of this repo reported after ... is not CLEAN"
      any other end ............................... "the check wait ended with checks unfinished or unreadable, and merge state <S> is not CLEAN"
```

Who calls what:

```
cmd_merge   sync(no pin; moved = 1 after a union re-merge) --rc 0--> wait --> _ci_regate(head_oid)
                                                                           --refuse--> FAILED merge #n: <reason>; left open
                                                           --rc 1--> merge as today
                                                           --other-> FAILED merge #n: the ci label could not be set

cmd_land    prior = ls-remote origin <branch>, before the push
            moved = 1 when ls-remote fails, or prior is set and != tip
            sync(tip, moved) --rc 0--> wait --> _ci_regate(tip) --refuse--> MERGE FAILED #n: <reason>; left open
                             --rc 1--> merge as today
                             --rc 3--> MERGE FAILED #n: the PR head never showed the pushed <short>; left open
                             --other-> MERGE FAILED #n: the ci label could not be set

_autoland_carry  sync(no pin) --rc 0--> wait --> head check --> _ci_regate(want)
                                  rc 3 (CONFLICTING) --> cmd_merge --apply --pr n (union re-merge, own re-gate)
                                  other refusal -------> SKIP land <branch>: PR #n: <reason>; left open
                                  OK ------------------> cmd_merge --apply --pr n (own sync, wait, re-gate)
                              --rc 1--> the plain pending wait, as today
                              --other-> SKIP land <branch>: PR #n: the ci label could not be set or read; left open
```

## Change

1. **`_ci_regate <url> <pr> <def> <pinned-oid>`**, a new helper holding `cmd_merge`'s post-wait block. It reads the PR once through `_pr_detail_settled "$url" "$pr"`, then checks in this order:
   - an empty head: `could not re-read #<pr> after the check wait`;
   - a head other than `<pinned-oid>`: `head moved to <short> during the check wait`;
   - `_pr_gate` not `OK`: `<verdict without SKIP> once the ci label's checks ran`. When the `_pr_gate` verdict is exactly `SKIP not mergeable (CONFLICTING)`, the helper returns 3 instead of 1 and prints the same reason (DEC-Y);
   - `${CI_WAIT_END:-}` is not `0`, `${CI_PRELABEL_KEYS:-[]}` is not `[]`, and `mergeStateStatus` is not `CLEAN`. The reason depends on how the wait ended. `NONEW` with `${CI_NEW_SCOPE:-}` empty keeps today's text: `no check reported after the ci label went on, and merge state <S> is not CLEAN`. `NONEW` with a scope set says `no Actions run of this repo reported after the ci label went on, and merge state <S> is not CLEAN`, because the scoped wait ignored every other entry (DEC-AF). Any other end (the pending bound, or an unreadable last read) prints `the check wait ended with checks unfinished or unreadable, and merge state <S> is not CLEAN`. Today the clause fires only on `NONEW`. The pending-bound end usually refuses one clause earlier, in `_pr_gate`, because the run is still pending at the re-gate read. The helper reaches this clause with a pending-bound end only when the runs finished between the wait's last read and the re-gate read (DEC-W).

   On a refusal it prints the reason on stdout and returns 1 (3 for CONFLICTING). On OK it prints nothing and returns 0. It reads `${CI_WAIT_END:-}`, `${CI_PRELABEL_KEYS:-[]}` and `${CI_NEW_SCOPE:-}`, all set by the sync and the wait that ran just before it in the same shell. Every caller uses `reason="$(_ci_regate ...)"; rrc=$?` and treats any non-zero `rrc` as a refusal. Only the carry reads the difference between 1 and 3.
2. **`cmd_merge`** replaces its inline post-wait block with `_ci_regate "$url" "$first_eligible" "$def" "$head_oid"`. Its refusal lines keep their text, `FAILED merge #<n>: <reason>; left open`, exit 2, with one exception: an empty re-read now says `could not re-read` instead of `head moved to ` with an empty sha. It also tracks whether its own union re-merge pushed the head it is about to merge. `first_eligible` becomes `conflict_n` in the re-merge block, and there `moved` is set to 1. The sync call becomes `_ci_label_sync "$url" "$first_eligible" "" "$moved"`, with an empty pinned oid, because `_pr_detail_settled ... "$REMERGE_OID"` has already waited for the pushed head. `moved` stays 0 on every other path, including the squash fallback, whose `-squash` PR carries no label yet. The `case` arms do not change: every rc other than 0 and 1 already refuses.
3. **`cmd_land`**:
   - Before its push it reads `git -C "$wt" ls-remote origin "refs/heads/${branch}"`. `moved` is 1 when that read exits non-zero, or when it names an oid other than the tip. It is 0 when the branch is absent on origin or already at the tip.
   - It passes the tip and `moved` to the sync: `_ci_label_sync "$url" "$n" "$tip" "$moved"`.
   - In the return-0 branch it calls `_ci_regate "$url" "$n" "$def" "$tip"` after `_ci_checks_wait`. On a refusal it prints `     MERGE FAILED #<n>: <reason>; left open` on stderr and returns 2 before `_gh_merge_retry`.
   - A new return-3 arm prints `     MERGE FAILED #<n>: the PR head never showed the pushed <short>; left open` and returns 2.
   - Every other rc except 1 keeps today's `MERGE FAILED #<n>: the ci label could not be set`. Nothing is merged, deleted or removed on any refusal. The PR, the pushed branch, the worktree and the local branch all stay.
4. **`_autoland_carry`**:
   - Its sync `case` gains a catch-all: rc 0 waits, rc 1 takes the plain pending wait, and every other rc prints `     SKIP land ${branch}: PR #${n}: the ci label could not be set or read; left open` and returns 1. The old line said "unlabeled on a ci-gated repo", which is wrong for a failed probe or a failed read (DEC-Y). The carry passes no pinned oid, so rc 3 cannot occur today. The catch-all keeps a new code from falling through to the merge.
   - After its head check, when its sync returned 0, it calls `_ci_regate "$url" "$n" "$def" "$want"`, while it still holds its own snapshot and `CI_WAIT_END`.
   - A refusal with `rrc` 3 (CONFLICTING) is not a refusal here. The carry falls through to `cmd_merge --apply --pr`, whose union re-merge resolves the log-file conflict, and whose own sync, wait and re-gate then check the re-merged head. The carry no longer matches reason text.
   - Any other refusal prints `     SKIP land ${branch}: PR #${n}: <reason>; left open` and returns 1 without setting `FAILURES`. That is the existing convention for every `SKIP land` line: the PR stays open and `apply` exits 0.
   - On OK the carry lands through `cmd_merge --apply --pr` exactly as today, and that merge re-gates on its own path as a second check.
5. **`_ci_label_sync <url> <pr> [<pinned-oid> [<moved>]]`**:
   - **Entry.** Every call first sets `CI_PRELABEL_KEYS='[]'` and `CI_NEW_SCOPE=""`, before the probe, so every return path leaves both defined. The carry calls the sync once per carry branch in one shell. Without the clear, a label-absent carry would inherit the scope a label-on carry before it set, and its unscoped wait would turn scoped (T20, NC26).
   - **The label probe fails closed and reads gh's real no-match answer.** It captures `labels="$(gh label list --repo "$url" --search ci --limit 200 --json name 2>/dev/null)"` and its exit code:
     - exit non-zero: prints `     could not read the repo labels for #<n>` on stderr and returns 2. The line names the PR number, never `$url`: `_origin_url` returns the raw remote url, which can carry userinfo such as a token (DEC-AH);
     - exit 0 and empty or whitespace-only output, which is what gh prints when no label matches: returns 1, exactly as today, so the merge runs ungated;
     - any other output that `jq -e 'type == "array"'` rejects: the same stderr line and return 2;
     - an array without an exact `ci`: returns 1.
   - **The PR read** becomes `--json labels,statusCheckRollup,headRefOid,url,commits`. `commits` is capped by GitHub at the first 100 commits of the PR (Failure modes).
   - **The head wait.** With a pinned oid, the sync re-reads every 2s, up to `KIT_WRAP_SETTLE_SECS`, while the read is not a JSON object or its `headRefOid` is not the pinned oid. When the bound runs out on a read that is still not an object, it prints the existing `could not read the labels and checks of #<n>` and returns 2. When it runs out on a wrong head, it prints `     PR #<n> never showed the pushed head <short>` on stderr and returns 3. The snapshot is always taken on the pinned head's rollup. Without a pinned oid (`cmd_merge`, the carry) it makes one read, as today.
   - **Label absent** keeps its logic, and `CI_NEW_SCOPE` stays empty, so SPEC-360's rule (any new entry counts) holds there.
   - **Label on** first resolves the slug from the PR's own `url` field, never from the origin remote. The url must match `^https://github\.com/([A-Za-z0-9-]+/[A-Za-z0-9._-]+)/pull/<n>$`, and the repo-name part must not consist only of dots. Anything else prints `     could not resolve the repo of #<n> from its url` on stderr and returns 2. The slug becomes `CI_NEW_SCOPE`. The order of the rest:
     1. **Empty rollup** (as today): `CI_PRELABEL_KEYS='[]'`, remove and re-add, `re-labeled #<n> ci (the label predates the head)`.
     2. **Non-empty rollup**: `_ci_label_date "$slug" "$n" "$detail" "$moved"` decides, then the sync acts on the answer (below).
   - **`_ci_label_date <slug> <pr> <detail> <moved>`**, a new helper (DEC-AA). It prints `READD<TAB><reason>` or `DATED<TAB><T>` on stdout and returns 0, or prints a stderr line and returns 2. It decides in this order:
     1. `moved` is 1: `READD`, reason `the push moved the head`.
     2. It reads `gh api --hostname github.com --paginate "repos/${slug}/issues/${n}/events?per_page=100"`. The slug check already pinned github.com, and `--hostname` keeps a `GH_HOST` exported for a GHES session from sending the read elsewhere (gh 2.101.0: with `GH_HOST=ghe.invalid`, `gh api --hostname github.com repos/cli/cli` answers from github.com, and the same call without the flag tries `ghe.invalid`). A non-zero exit (even after earlier pages printed), or output `jq -s` cannot parse, prints `     could not read the label events of #<n>` and returns 2. An exit 0 with zero bytes is an empty history, not a failure: `jq -s` reads it as `[]`, so `T` comes back empty (DEC-X).
     3. `T` is the latest `created_at` among events with `event == "labeled"` and `label.name == "ci"`: `jq -rs '[.[][] | select(.event == "labeled" and .label.name == "ci") | .created_at] | max // ""'`. An empty `T` is `READD`, reason `no ci labeled event dates the label`.
     4. `C` is the head commit's `committedDate`: `(.headRefOid // "") as $h | [.commits[]? | select(.oid == $h) | .committedDate] | .[0] // ""`. An empty `C`, or a `C` not before `T` (bash `[[ ! "$C" < "$T" ]]`), is `READD`, reason `the head commit is not older than the label`.
     5. Otherwise `DATED`.
   - **Acting on the answer.** `READD` sets `CI_PRELABEL_KEYS` to every rollup key (the absent-label expression). `DATED` sets it to the `ckey` of every entry whose start (`[.startedAt, .createdAt] | map(real) | .[0] // ""`) is empty or `<= T`. `T` comes in only through `--arg`. The `DATED` assignment is one line, so a negative-control `sed` can replace it whole. **A jq that yields no output stops the sync**: it prints `     could not build the check snapshot of #<n>` on stderr and returns 2 before any label edit, and never falls back to `[]` (DEC-V; the label-absent branch keeps SPEC-360's `[]` fallback). Then `READD` removes and re-adds the label (failure: the existing `could not re-add` line, return 2) and prints `     re-labeled #<n> ci (<reason>)`. The new `labeled` event starts a `ci` run on the current head, and that run's key is outside the snapshot.
6. **`_ci_checks_wait`** gains one filter and `CI_JQ_DEFS` gains one def, and nothing else in either changes. The def is `def actions($s): ((.workflowName // "") != "") and ((.detailsUrl // .targetUrl // "") | startswith("https://github.com/" + $s + "/actions/"));`. The wait passes `--arg scope "${CI_NEW_SCOPE:-}"` and counts an entry toward NEW only when `$scope == "" or actions($scope)`. `workflowName` is set only on Actions CheckRuns, and the url prefix pins the repo, so a fast DCO or lint app status, a Bors or CodeQL check, a StatusContext and another repo's Actions run can never end a label-on wait (DEC-S). Pending entries of any kind still hold the wait. The filter assumes the CI the label starts is a GitHub Actions workflow of this repo; a label that starts only other CI pays the cost named under Failure modes (DEC-AD).
7. **Comments and docs.** The comments above `cmd_land`, `_autoland_carry`, `_ci_label_sync` and `_ci_checks_wait` name the new behavior, including that a failed label read now refuses and that the wait scopes NEW on a label that was already on. `commands/wrap.md` line 104 (the `land` paragraph) gains the re-gate, the head wait and the re-add on a moved head. Line 323 changes "because `land` merges right after it opens a PR and never reads the checks" to "because `land` reads the checks only on a repo that gates on the `ci` label".

`_pr_detail_settled`, `_pr_gate`, the rest of `_ci_checks_wait` and `CI_JQ_DEFS`, `CI_WAIT_END`'s handling, the env knobs and their defaults stay as they are. Round 1's `_pr_detail_settled` change and its `CI_WAIT_END` load reset are cut (DEC-H).

## Contract changes

These change what `wrap land`, autoland and `wrap merge` promise. The operator must accept each one before the build starts.

| # | Surface | Before | After |
|---|---|---|---|
| C1 | `wrap land`, repo gates on `ci` | merges once the wait ends, whatever the checks read | merges only when `_ci_regate` returns OK and the PR showed the pushed head before the sync. Otherwise it prints `MERGE FAILED #<n>: <reason>; left open` and exits 2, and the PR, the pushed branch, the worktree and the local branch stay. The CLEAN rule holds on a re-run too, because the sync dates or re-adds the label that is already on. Two early-end races stay: on a first `land` (label absent, unscoped wait, SPEC-360's rule) any check that registers and completes before the `ci` run, such as a DCO status, ends the wait; on a label-on pass, a push-started Actions run that registers after the sync's read and completes before the `ci` run registers does the same. `_pr_gate` then reads a rollup without the `ci` run (Failure modes) |
| C2 | same | red or pending checks, `CHANGES_REQUESTED`, `mergeable` still `UNKNOWN`: `land` calls `gh pr merge`, which GitHub refuses in some of these cases (required checks, required reviews, the `BEHIND` state under "require branches to be up to date", all without `--admin`) and accepts in others | `_pr_gate` refuses each of them before any merge call, as `wrap merge --apply` already does. The practical change is non-required checks that are red or pending, and a changes-requested review on a repo that does not require reviews. `BEHIND` mostly changes only the message and the timing, because GitHub reports it only when the up-to-date rule already refuses the merge |
| C3 | same | no read after the wait; one sync read | the sync re-reads up to `KIT_WRAP_SETTLE_SECS` until the pushed head shows; the re-gate adds one `_pr_detail_settled` read (it re-reads only while `mergeable` reads `UNKNOWN`, as today); `land` adds one `git ls-remote` before its push, on every repo |
| C4 | autoland, label-gated repo | the carry merges through `cmd_merge --pr` on any state `_pr_gate` allows once the wait ends | the carry re-gates first. On a refusal, including a `NONEW` hold with a non-empty snapshot on a state other than `CLEAN`, it prints `SKIP land <branch>: PR #<n>: <reason>; left open`, merges nothing, and `apply` exits 0. A `CONFLICTING` verdict (`_ci_regate` rc 3) is handed to `cmd_merge`, whose union re-merge runs as today. A later pass finds the label on and applies the same rule |
| C5 | every sync that finds the label on over a non-empty rollup (`wrap merge`, `land` re-runs, autoland passes) | snapshot `[]`: the wait ends on the first read with nothing pending | DATED when the head is older than the latest `ci` labeled event: the snapshot holds every entry that started at or before it or has no start. RE-ADD otherwise (below). When nothing new starts, the wait holds the grace window (`KIT_WRAP_CI_GRACE_SECS`, default 90s) and the CLEAN rule applies. A pass that finds the label's own Actions runs already done still ends on one read |
| C6 | autoland on the `NONEW` path with a `CLEAN` state | the grace hold ran once per carry | it runs twice per carry: once in the carry's wait and once in the inner merge's wait, because the inner sync dates the label. Up to `KIT_WRAP_CI_GRACE_SECS` extra per carry, no verdict changes, no flag. Accepted by the lead (DEC-D); T13 and T13d pin the count |
| C7 | the label probe, on every repo (`land`, `merge`, the carry) | any probe failure reads as "no `ci` label", and the merge runs ungated | a probe that exits non-zero, or prints output that is neither empty or whitespace-only nor a JSON array, refuses: `land` and `merge` print `the ci label could not be set` (after the sync's own `could not read the repo labels for #<n>` line) and exit 2; the carry prints `SKIP land <branch>: PR #<n>: the ci label could not be set or read; left open`. A probe that exits 0 with empty or whitespace-only output, which is what gh prints when no label matches, still means "no `ci` label": the merge runs ungated, as today. A repo without the label sees no change (T17, T17b, L11) |
| C8 | the label-on branch | round 1 fell back to `[]` when the events read failed | a failed events read, or a PR url that is not `https://github.com/<owner>/<name>/pull/<n>`, refuses the same way as C7. The url check now also runs on the empty-rollup and moved arms, so a GHES repo with the label already on refuses every pass (Out of scope). An events read that exits 0 with no output is an empty history, not a failure: RE-ADD |
| C9 | the label-on branch | the label was never touched while on over a non-empty rollup | RE-ADD fires a new `labeled` event and a new `ci` run when the push that made the head was wrap's own (`land`'s push, or `cmd_merge`'s union re-merge push), when no `ci` labeled event exists, or when the head commit is not older than the label. The snapshot then holds the push-started runs that registered before the sync's read; one that registers later is outside it and, when it is an Actions run of this repo, counts as NEW (Failure modes) |
| C10 | the CLEAN rule | applies after a wait that ended `NONEW` | applies after any wait that did not end on state `0`; the new reach is a wait whose last read was unreadable, or a pending-bound wait whose runs finished before the re-gate read. The refusal text differs by end (Change 1) |
| C11 | `wrap merge`, empty re-gate read | `FAILED merge #<n>: head moved to  during the check wait; left open` | `FAILED merge #<n>: could not re-read #<n> after the check wait; left open` |
| C12 | the wait, on every label-on path (empty rollup, RE-ADD, DATED) | any entry outside the snapshot counted as NEW, so a fast DCO, lint or app status that registered after the snapshot could end the wait before the `ci` run started | only an Actions run of this repo counts as NEW (non-empty `workflowName`, url under `https://github.com/<owner>/<name>/actions/`). The absent-label path keeps the any-entry rule (SPEC-360 T12). Another Actions workflow that registers after the snapshot can still end the wait (Failure modes). The rule assumes the label-started CI is a GitHub Actions workflow of this repo. A repo whose label starts Prow, Jenkins, Netlify or CircleCI statuses gets a wait that never sees them as NEW: a grace hold, then the CLEAN rule, on every label-on pass (Failure modes, Out of scope) |
| C13 | the carry, sync rc other than 0 and 1 | `SKIP land <branch>: PR #<n> is unlabeled on a ci-gated repo; left open` | `SKIP land <branch>: PR #<n>: the ci label could not be set or read; left open` |

### Recovery, per refusal reason

| Reason | What the operator does |
|---|---|
| checks are pending or failing (red) | fix the branch in the worktree, commit, and re-run `wrap land <worktree>`. The push moves the head, so the sync removes and re-adds the label and the new head gets its own `ci` run. The snapshot holds only the push-started runs that registered before the sync's read, so a fast push-started Actions workflow can still end the wait first (Failure modes); `_pr_gate` reads every check either way |
| checks are pending (queued past the carry bound) | wait until the runs complete, then re-run `land` (or `wrap merge --apply --pr <n>`, or the next autoland pass). A completed run carries a real `startedAt` after the `ci` labeled event under this repo's `actions/` URLs, so it counts as NEW and the wait ends on it. A re-run while a `ci` run is still queued with the zero `startedAt` puts that run in the dated snapshot (no real start), so it never counts as NEW: the wait holds while it is pending, then the grace window, and the CLEAN rule decides |
| no check (or no Actions run of this repo) reported after the ci label went on, state not CLEAN | investigate why the label started nothing, or started only non-Actions CI: a paths filter, a slow webhook, or a workflow that does not fire on `labeled`. A re-run refuses again until a new Actions run appears or the state reads `CLEAN` |
| the check wait ended with checks unfinished or unreadable, state not CLEAN | wait a minute, then re-run: the last read of the wait failed, or the runs finished after the wait gave up |
| merge state BEHIND | update the branch (`gh pr update-branch <n>`, or merge the base in the worktree and push). After `gh pr update-branch`, pull the update into the worktree (`git -C <worktree> pull --ff-only`) before re-running `land`, or the push is refused (`PUSH REFUSED`) because origin is ahead of the local tip. The update commit is newer than the label (GitHub dates its own update commit at push time), so the sync re-adds the label |
| changes requested | address the review, then re-run |
| not mergeable (CONFLICTING or UNKNOWN) | `UNKNOWN`: re-run later. `CONFLICTING`: resolve in the worktree, or run `wrap merge --apply --pr <n>`, whose union re-merge and squash fallback handle the log-file case. Autoland hands this case to that path itself |
| head moved during the check wait / the PR head never showed the pushed head | someone else pushed, or GitHub had not caught up: inspect the PR, then re-run `land` |
| could not re-read the PR / could not read the repo labels / could not read the label events / could not build the check snapshot | a transient gh failure: re-run |
| could not resolve the repo of #n from its url | the PR lives on a host other than github.com. Remove the `ci` label by hand, then re-run: the sync takes the absent-label branch |
| a `land` re-run after a hand `git push`, or after a `land` whose push landed but stopped before the label re-add (`moved` reads 0, and the head commit predates the label) | the sync dates the label and may end its wait on a check the push started. Remove the label by hand (`gh pr edit <n> --remove-label ci`), then re-run: the sync takes the absent-label branch, snapshots the rollup and starts a fresh `ci` run |

## Design

### Diagram

The flow and the caller map are drawn once, under `## Picture`.

### Interfaces

| Surface | Before | After |
|---|---|---|
| `_ci_regate <url> <pr> <def> <pinned-oid>` | none | new. Stdout is the refusal reason with rc 1 (rc 3 for CONFLICTING); empty stdout with rc 0 is OK. Reads `${CI_WAIT_END:-}`, `${CI_PRELABEL_KEYS:-[]}` and `${CI_NEW_SCOPE:-}` (the scope picks the `NONEW` reason text) |
| `_ci_label_sync <url> <pr> [<pinned-oid> [<moved>]]` | two args, returns 0/1/2; a failed probe returns 1 | optional pinned oid and moved flag; clears `CI_PRELABEL_KEYS` to `[]` and `CI_NEW_SCOPE` to empty on entry; returns 3 when the pinned head never shows; a failing probe, or a probe output that is neither empty or whitespace-only nor an array, returns 2, and an empty or whitespace-only probe output returns 1; dates or re-adds a label that is already on; sets `CI_NEW_SCOPE` on every label-on path |
| `_ci_label_date <slug> <pr> <detail> <moved>` | none | new. Prints `READD<TAB><reason>` or `DATED<TAB><T>`, rc 0; a failed events read prints its stderr line, rc 2 |
| `CI_NEW_SCOPE` | none | new out-param of the sync, cleared by every sync call on entry, read by `_ci_checks_wait` and `_ci_regate`: empty means any new entry counts, else the `<owner>/<name>` whose Actions runs count |
| `_ci_checks_wait` / `CI_JQ_DEFS` | NEW is any entry outside the snapshot | NEW is filtered by `CI_NEW_SCOPE` through `def actions($s)`; nothing else changes |
| `cmd_merge` sync call | `_ci_label_sync url n` | passes an empty pin and `moved` (1 after its own union re-merge) |
| `cmd_land` refusals | `MERGE FAILED #<n>: the ci label could not be set` | adds `MERGE FAILED #<n>: <reason>; left open` and the head-never-showed line |
| `_autoland_carry` lines | `SKIP land ...` set | adds `SKIP land <branch>: PR #<n>: <reason>; left open`; the old unlabeled line becomes `SKIP land <branch>: PR #<n>: the ci label could not be set or read; left open` and covers every sync rc other than 0 and 1 |
| sync stderr | `could not read the labels and checks`, `could not add`, `could not re-add` | adds `could not read the repo labels for #<n>` (the PR number, never the remote url), `PR #<n> never showed the pushed head <short>`, `could not resolve the repo of #<n> from its url`, `could not read the label events of #<n>`, `could not build the check snapshot of #<n>`; stdout adds `re-labeled #<n> ci (<reason>)` for the three RE-ADD reasons |
| gh and git calls | `gh label list`, `gh pr view --json labels,statusCheckRollup`, `gh pr edit` in the sync | the sync read adds `headRefOid,url,commits`; one paginated `gh api --hostname github.com repos/<o>/<r>/issues/<n>/events` read, only when the label is on over a non-empty rollup and `moved` is not 1; `land` adds `git ls-remote origin refs/heads/<branch>` before its push |
| test stub, labels | `gh label list` prints `[]` when `GH_STUB_LABELS` is unset | prints `$GH_STUB_LABELS` verbatim and nothing when it is unset, as real gh does on no match. `GH_STUB_LABELS='[]'` prints an empty array. `GH_STUB_LABEL_RC` is unchanged |
| test stub, events | `gh api` answers the login | a `gh api` call whose argument matches `repos/*/issues/<n>/events*` prints `GH_STUB_EVENTS_<n>` (default `[]` when unset; a set but empty value prints nothing), then exits `GH_STUB_EVENTS_RC` (default 0); every other `gh api` call is unchanged. The call is logged like every other |

### Approaches considered

For `land`:

1. **One helper shared with `cmd_merge` (chosen).** The post-wait block is an enforcement rule, and two copies of it would drift. With the carry as its third caller, the kit's three-use rule is met anyway. The helper is the block moved as-is, so `cmd_merge`'s tests pin it before `land` uses it.
2. Route `land` through `cmd_merge --apply --pr` (rejected). `cmd_merge` needs the PR to be the operator's own and eligible on its first gate, runs the union re-merge and the squash fallback, and pins the head from its own read, while `land` pins the tip it pushed.
3. Gate `land` on every repo, not only label-gated ones (rejected here). Without the label `land` never waited, so there is no wait to re-gate after, and the change would reach every repo. Named under Out of scope.

For autoland:

1. **The carry re-gates itself with its own snapshot (chosen; DEC-A).** The carry holds the real snapshot and `CI_WAIT_END` at the moment the wait ends, so it applies the rule with no state crossing into a subshell. The inner merge keeps its own re-gate as a second check. A `CONFLICTING` verdict passes through to the inner merge (DEC-G, DEC-Y).
2. An env handoff: `CI_CARRY_OID` and `CI_CARRY_KEYS` set in the merge subshell, the inner merge adopting the snapshot with a grace of 0 (rejected in round 1). The adopt condition could fire after the inner sync re-added the label on a moved head. The handoff also needed a grace override, a load-time reset and a head bind no stub case could test.
3. Hand off `CI_WAIT_END` and skip the inner wait (rejected). The carried state is stale by one subshell start, and skipping drops today's second pending hold.

For a label that is already on over a non-empty rollup:

1. **Date the label from the issue events API; re-add when the head is newer than the label or nothing dates it (chosen; DEC-B, DEC-E, DEC-F).** Both times in the cut are GitHub's own clock. SPEC-360 rejected a local-clock cut for skew, and this cut avoids it. The head-age test uses the committer's clock, which is the one residual (Failure modes). The cost is one paginated read, made only on this branch, plus a new `ci` run when the sync re-adds.
2. Keep `[]` (today, rejected by round 1). Every recovery pass skips the CLEAN rule, which undoes the fix on the second try.
3. Remove and re-add the label on every pass (rejected). It fires a new `labeled` event and a new CI run on every pass, even for a head the `ci` workflow already tested. The chosen approach re-adds only when the head is newer than the label, or nothing dates the label.
4. Snapshot the whole rollup with no date (rejected in round 2). A pass after the label's own runs completed would count those runs as pre-label, hold the grace window, and refuse an `UNSTABLE` PR whose `ci` runs are green. On a moved head it hides nothing either: every entry reads as old, so the CLEAN rule alone would decide whether a head the `ci` workflow never ran on merges.
5. Date the last push from the repository activity API, `repos/<o>/<r>/activity?ref=refs/heads/<branch>&activity_type=push`, which returns each push's `timestamp` and `after` oid (Grounding) (rejected for now; future hardening). It would close the residual of a head pushed after the label by something other than wrap. It costs a second paginated read on every dated pass, one more fail-closed read path, and a match between the activity `after` oid and `headRefOid`. `moved` already covers wrap's own pushes, so this round keeps the committer-date test and names the residual.

For what may end a label-on wait (round 3, DEC-S):

1. **Scope NEW to this repo's Actions runs inside the wait (chosen).** The snapshot is a set of keys taken at one instant, so a check that registers after it is always outside it. Only a filter applied at wait time can keep a late DCO or lint status from ending the wait.
2. Put the Actions test into the snapshot only (rejected, round 2's shape). It covers the entries that exist at snapshot time and nothing that registers later, which is the case round 3's five reviewers found.
3. Scope to the `ci` workflow by name (rejected). The sync cannot know what the repo's label-triggered workflow is called, and a rename would silently disable the gate.

For a failed label or events read:

1. **Refuse with rc 2 (chosen; DEC-F).** Nothing merges on a read the sync could not trust. A probe that exits 0 with empty or whitespace-only output is not a failed read: it is gh's answer for "no label matches" (DEC-R).
2. Snapshot every key with a real start and print a stderr line (rejected in round 2, the fail-open half of a reviewer conflict). It leaves the CLEAN rule as the only check, and a `CLEAN` state merges a head whose `ci` status nobody read.
3. Fall back to `[]` (round 1, rejected). The wait ends on the first read and the CLEAN rule is off.
4. Treat an empty or whitespace-only probe output as a failed read (round 2's shape, rejected by round 3). Every repo without a `ci` label would refuse `land` and `merge --apply`.

### Boundaries

- The label date keys on the latest `ci` labeled event. An `unlabeled` event is not read: the sync reaches this branch only while the label is on, so the latest `labeled` event is the one that put it there.
- An entry with no real start goes in the dated snapshot. It never counts as NEW. While it is pending the pending count holds the wait, and once it completes the wait holds to the grace bound and the CLEAN rule applies.
- The start of an entry is `startedAt`, then `createdAt`. `completedAt` is not a fallback (DEC-I).
- Whenever the label was already on (empty rollup, RE-ADD, DATED), only an Actions run of this repo can count as NEW: a non-empty `workflowName` and a url under `https://github.com/<slug>/actions/`. The absent-label path keeps SPEC-360's rule, where any entry outside the snapshot counts (DEC-J, DEC-S).
- The cut is `<= T`: an entry that started in the same second as the label joins the snapshot.
- The label-on rules assume the CI the `ci` label starts is a GitHub Actions workflow of this repo. Label-started CI of any other kind (Prow, Jenkins, Netlify, a CircleCI StatusContext) never counts as NEW on a label-on pass (Failure modes, Out of scope).
- A scoped wait that ends `NONEW` with an empty snapshot (the empty-rollup arm, or a DATED snapshot where no entry started by `T`) skips the CLEAN clause, which needs a snapshot other than `[]`. `_pr_gate` alone decides then, the same verdict SPEC-360 gives its empty-rollup path, so the scope makes it no worse (T18's row under Failure modes).
- gh emits `statusCheckRollup[].workflowName` from v2.14.0 on (Grounding). An older gh omits it, so every entry reads as non-Actions (Failure modes).

## Failure modes

| Failure | Caller | Behavior |
|---|---|---|
| The label-started run completes red | `land`, carry | the re-gate picks the red run as latest for its name and refuses; PR open |
| The run is still queued at the carry bound | `land`, carry | the pending entry sorts last and trips the checks clause; refuses |
| The head moved during the wait | `land`, carry | refuses with `head moved to <short>` |
| GitHub has not shown the pushed head yet when `land` syncs | `land` | the sync re-reads up to `KIT_WRAP_SETTLE_SECS`; the head never shows -> `MERGE FAILED`, left open, nothing labeled |
| The re-gate read fails or is empty | all three | `_pr_detail_settled` ends on it at once (unchanged) -> `could not re-read`; refuses |
| The wait's last read is unreadable | all three | the CLEAN rule applies (C10); a non-CLEAN state refuses with the unfinished-or-unreadable text |
| No new entry, state not CLEAN | all three, every pass | refuses with the non-CLEAN line |
| The label probe exits non-zero, or prints output that is neither empty or whitespace-only nor a JSON array | all three, every repo | refuses (C7); the operator re-runs |
| The label probe exits 0 with empty or whitespace-only output (gh's no-match answer) | all three | no `ci` label: ungated, as today (C7) |
| The events read fails, prints unparseable text, or the PR url is not a github.com PR url | every sync with the label on | refuses (C8) |
| The events read exits 0 and prints nothing | every sync with the label on over a non-empty rollup | an empty history: `T` is empty, so RE-ADD (DEC-X) |
| The snapshot jq yields no output | every label-on sync that dates or re-adds | refuses with `could not build the check snapshot`, before any label edit; never a `[]` fallback (DEC-V) |
| No `ci` labeled event (a label added before the events retention window) | same | RE-ADD: a new `ci` run on the current head, the whole rollup in the snapshot |
| `land` pushed a new head onto a PR whose label is on | `land` | RE-ADD before any events read. The snapshot holds the push-started checks that registered before the sync's read, and only those. Only an Actions run outside the snapshot ends the wait, so a fast non-Actions status cannot. A push-started Actions run that registers after the sync's read (a fast `synchronize` workflow) and completes before the `ci` run registers does end it, on a rollup without the `ci` run (residual, Out of scope; no settle is added). `_pr_gate` still reads every check |
| `cmd_merge`'s union re-merge pushed a new head onto a PR whose label is on | `wrap merge`, carry (inner merge) | RE-ADD (`moved` = 1), same as `land`'s push |
| The label is on over an empty rollup at the pushed tip, and a fast non-Actions status (DCO, a lint app) registers before the label's `ci` run | all three | the status is not an Actions run, so the wait keeps holding until the `ci` run appears or the grace bound ends (T18). When the grace bound ends `NONEW` with only non-Actions entries, the snapshot is `[]`, so the CLEAN clause is skipped and `_pr_gate` decides: no worse than SPEC-360's empty-rollup path |
| A first `land` or a first carry sync (label absent), where a check that registers and completes before the `ci` run (a DCO status) arrives after the snapshot | `land`, carry | residual, kept from SPEC-360: the unscoped wait counts that check as NEW and ends on it, and `_pr_gate` reads a rollup without the `ci` run. The scope does not apply on the absent-label path (its T12). The carry's inner merge then finds the label on and re-checks scoped; `land` has no second check |
| The `ci` label starts only non-Actions CI (Prow, Jenkins, Netlify, CircleCI StatusContexts) | every label-on pass: `wrap merge`, the carry's inner merge, `land` re-runs, later autoland passes | the scoped wait never counts that CI as NEW. It holds while any entry is pending, then to the grace bound, and ends `NONEW`. With a snapshot other than `[]` the CLEAN rule then refuses any state but `CLEAN`, even when that CI is green; with `[]`, `_pr_gate` decides. Cost: up to `KIT_WRAP_CI_GRACE_SECS` per pass, and a refusal on `UNSTABLE`. On the pass that first labels a carry PR, that refusal comes from the inner merge, which sets `FAILURES`, so `apply` exits 2; a later pass refuses at the carry's own re-gate with `SKIP land`. The first, label-absent sync is unscoped and unaffected |
| gh older than v2.14.0, which omits `workflowName` | every label-on pass | every entry reads as non-Actions, the same as the row above for all CI: a grace hold, then the CLEAN rule. Fails closed on a non-`CLEAN` state |
| A head commit whose committer date predates `T`, pushed after `T` by something other than wrap (a hand `git push`, then `wrap merge --apply --pr` or a `land` re-run), a `land` re-run after a push that stopped before the re-add, or a committer clock behind GitHub's | `wrap merge`, carry, `land` re-run | residual: `moved` reads 0 and the sync takes the DATED path, so a push-started Actions run can count as NEW and end the wait on a head the `ci` workflow never ran on. `_pr_gate` still reads every check. A first `land` on a head it pushed itself does not have this gap. The recovery row names the manual step |
| A committer clock ahead of GitHub's, or a PR over 100 commits (`commits` holds only the first 100, so the head is missing) | `wrap merge`, carry, `land` | the head-age test fails: RE-ADD on this and every later pass, one extra `ci` run each. Fails safe |
| A check started in the same second as the `ci` labeled event | every dated sync | it joins the snapshot; the wait holds to the grace bound and the CLEAN rule applies (fail closed) |
| The carry PR reads `CONFLICTING` at the carry re-gate | carry | `_ci_regate` returns 3: handed to `cmd_merge --apply --pr`: the union re-merge, then its own sync, wait and re-gate on the new head |
| `mergeable` stays `UNKNOWN` past `KIT_WRAP_SETTLE_SECS` | all three | `_pr_gate` refuses (`not mergeable (UNKNOWN)`) |
| The repo has no `ci` label | `land`, carry | unchanged apart from `land`'s `ls-remote`: no head wait and no re-gate in `land`; the carry's plain pending wait, then `cmd_merge`'s own gates |
| The carry's sync returns 2 (probe, read, events or label edit failed) | carry | `SKIP land <branch>: PR #<n>: the ci label could not be set or read; left open`; `apply` exits 0 |

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
- AC10: `wrap land` whose label probe prints text that is not a JSON array refuses with `MERGE FAILED #<n>: the ci label could not be set` and makes no `pr merge` call.
- AC11: `wrap land` on a repo without the `ci` label makes no `_pr_detail` read (`--json number,title,body`) and no events read, and merges as before.
- AC12: The existing land ci cases (ci-gated, T6, ci-armed, ci-stale, ci-noset) pass with `headRefOid` at the tip on the sync read and full detail on the re-gate read. ci-gated shows exactly 4 counted reads of #42. T6's merge follows the 5th rollup-bearing read, which is the `_pr_detail` read.
- AC13: Autoland on a label-gated repo whose carry PR holds only pre-label checks, with no new entry and `UNSTABLE`: `apply` exits 0, the output holds `SKIP land <branch>: PR #42: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`, and no `pr merge 42` call is made.
- AC14: A second autoland pass, where the carry PR already carries the label and a `ci` labeled event dates it, refuses the same way, with the scoped reason: `SKIP land <branch>: PR #42: no Actions run of this repo reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`.
- AC15: T13 passes with exactly 26 reads of #42 (two grace holds per carry, C6). T13d, the same fixture at a 40s grace, passes with exactly 34, which pins four holds.
- AC16: Autoland whose carry PR reads `CONFLICTING` at the carry re-gate hands the PR to `cmd_merge`: the output holds `retry #42: one re-merge of main into` and no carry `SKIP land` line naming `not mergeable (CONFLICTING)`.
- AC17: `wrap merge --apply` on a PR with the label on applies the CLEAN rule from the dated snapshot. It keys on the latest of two `ci` labeled events and keeps in the snapshot an entry started exactly at `T` and an entry with no start. It never counts as NEW a StatusContext whose target url sits under this repo's `actions/` prefix, or an Actions run of another repo.
- AC18: `wrap merge --apply` ignores a later labeled event for another label, and ends the wait on an Actions run that started after `T`.
- AC19: `wrap merge --apply` refuses with `the ci label could not be set` when the events read exits non-zero, when it prints text that is not JSON, and when the PR url is not a github.com PR url or names a repo made only of dots, with no `pr edit` and no `pr merge` call.
- AC20: `wrap merge --apply` on a PR whose head commit is newer than the label re-adds the label, holds the grace window, and refuses `UNSTABLE` with the non-CLEAN line.
- AC21: `wrap merge --apply` on a PR with the label on and no `ci` labeled event re-adds the label and merges on `CLEAN` after the grace hold (T4, rewritten).
- AC22: `wrap merge --apply` whose re-gate read is unreadable refuses with `could not re-read #<n> after the check wait; left open`.
- AC23: `wrap merge --apply` whose label probe exits non-zero refuses with `the ci label could not be set` after one read of the PR.
- AC24: `wrap merge --apply` whose wait ended on an unreadable read refuses `UNSTABLE` with `the check wait ended with checks unfinished or unreadable, and merge state UNSTABLE is not CLEAN; left open`.
- AC25: `cmd_merge`'s other ci-wait cases (T1 to T3, T3b, T5, T8 to T12) and the settle cases pass unchanged.
- AC26: `bash tests/test-wrap.sh` and `bash tests/test-meta.sh` pass.
- AC27: Each negative control below turns red exactly the traced `chk` lines, read from the failing `chk` names, not only the exit code. NC18 is the one exception in shape: its trace names T17 and L11 and also expects every existing case that leaves `GH_STUB_LABELS` unset and reaches the sync to go red, and the record lists them from the run.
- AC28: `wrap merge --apply` and `wrap land` whose label probe exits 0 with empty or whitespace-only output merge with no gate: exit 0, merged, no `pr edit`, no events call. `GH_STUB_LABELS='[]'` does the same (T17, T17b, L11).
- AC29: `wrap merge --apply` on a PR whose label is on over an empty rollup at the tip, where the wait's first reads show only a non-Actions status, does not end the wait on it. It ends on the Actions run that appears later (T18).
- AC30: `wrap merge --apply` whose union re-merge pushed the head, with the label on and a `ci` labeled event newer than the head commit, removes and re-adds the label and reads no events (RM1).
- AC31: `wrap merge --apply` refuses with `the ci label could not be set`, `could not build the check snapshot of #<n>` on stderr, no `pr edit` and no `pr merge`, when the snapshot jq yields nothing, on the RE-ADD path (E6) and on the DATED path (E6b).
- AC32: `wrap merge --apply` whose events read exits 0 with zero bytes re-adds the label with reason `no ci labeled event dates the label` and merges on `CLEAN` after the grace hold (E7).
- AC33: Autoland whose label probe exits non-zero prints `SKIP land <branch>: PR #42: the ci label could not be set or read; left open`, exits 0, makes no `pr edit` and no `pr merge`, and reads #42 zero times (T19).
- AC34: Autoland with two carries, the first on a PR whose label is on and the second on a PR whose label is absent, runs the second carry's wait unscoped: a non-Actions check outside its snapshot ends that wait on its first read. `apply` exits 0, both carries merge, and #42 is read exactly 24 times (T20).

## Test plan

Every case goes in `tests/test-wrap.sh`, beside the "land: the ci label gate", "merge --apply: the ci label gate" and autoland ci sections. The existing `gh` stub serves read k of `pr view <n>` from `GH_STUB_PR_<n>_<j>` for the highest set j <= k (j >= 2), else from `GH_STUB_PR_<n>`. A `--json state,mergeCommit` read neither counts nor steps. The count lands in `$GH_STUB_CALLS.view-<n>` (`cw_views <n>` reads it), and a `gh api` call does not count. The stub gains the events branch and the empty-output label default named under Interfaces. A failed later page of real `--paginate` behaves the way `GH_STUB_EVENTS_RC` models it: earlier pages print, then gh exits non-zero. `$TMPD/nosleep` stubs `sleep`, and the harness exports `KIT_WRAP_SETTLE_SECS=0`, so the sync's head wait and the re-gate are one read each unless a case sets the knob. In a merge case the reads are: 1 the eligibility read, 2 the sync, then the wait reads, then the re-gate. In a `--pr` merge the draft check adds one read before eligibility. "The non-CLEAN line" is the `NONEW` refusal in the variant the scope picks (Change 1): `no check reported after the ci label went on, ...` when the sync took the absent-label path (L4, T13b, T3b), and `no Actions run of this repo reported after the ci label went on, ...` when the label was already on (L6, T13c, E1, E4).

Fixtures reuse SPEC-360's rollups: `CW_OLD` (`test` SKIPPED on `https://gh/job/1`, `preview` SUCCESS on `https://gh/job/2`, both started and completed 2026-09-28T02:44:01Z), `CW_RUN`, `CW_QUEUED` (zero `completedAt`, empty `conclusion`, real `startedAt` 2026-09-29T10:21:58Z, `https://gh/job/3`), `CW_GREEN`, `CW_RED`. These carry no `workflowName`, so on a label-on path (scoped wait) none of their entries can count as NEW. Cases that need a NEW entry on a label-on path use the Actions-shaped fixtures below. New fixtures, with the task that owns each:

- D0: `EV_CI`: `[{"event":"labeled","label":{"name":"ci"},"created_at":"2026-09-29T10:21:52Z"}]`.
- D2: `EV_CI2`: `EV_CI` plus a `ci` labeled event at 2026-09-20T00:00:00Z. `EV_CI_DOCS`: `EV_CI` plus a `docs` labeled event at 2026-09-29T11:00:00Z.
- D0: `CA_OLD`: `CW_OLD` with `workflowName` `ci` and `detailsUrl` `https://github.com/o/r/actions/runs/1/job/1` and `.../job/2`. The T13 family, L6, T4, E3, E5 and E7 use it, so the scoped wait treats their entries as candidates for NEW and the snapshot decides.
- D1: `CA_GREEN`: `CA_OLD` plus `test` SUCCESS started 2026-09-29T10:21:58Z with `workflowName` `ci` on `https://github.com/o/r/actions/runs/2/job/3`. RM1 (D1) and E2 (D2) use it.
- D2: `CA_E1`: `CA_OLD` plus four entries, each aimed at one arm: `build`, an Actions run (`workflowName` `ci`) SUCCESS started and completed at exactly 2026-09-29T10:21:52Z on `.../actions/runs/2/job/5` (the `<= T` cut); `legacy`, an Actions run (`workflowName` `ci`) SUCCESS with no `startedAt` or `createdAt` on `https://github.com/o/r/actions/runs/3` (the empty-start arm); `forged`, a StatusContext SUCCESS with `createdAt` 2026-09-29T11:00:00Z and `targetUrl` `https://github.com/o/r/actions/runs/4`, no `workflowName` (the workflowName arm); `xrepo`, SUCCESS started 2026-09-29T11:00:00Z with `workflowName` `ci` on `https://github.com/x/y/actions/runs/1/job/1` (the url-prefix arm).
- D1: `CW_PUSH`: `CW_OLD` plus `lint` SUCCESS started 2026-09-29T11:00:00Z with `workflowName` `lint` on `https://github.com/o/r/actions/runs/9/job/9` (a push-started workflow). `CW_PUSH_CI`: `CW_PUSH` plus `test` SUCCESS started 2026-09-29T11:05:00Z with `workflowName` `ci` on `.../actions/runs/10/job/10` (the re-added label's run).
- D0: `CW_DCO`: one entry, `DCO` SUCCESS started 2026-09-29T11:00:00Z, no `workflowName`, `detailsUrl` `https://github.com/o/r/pull/107/checks` (a fast app status). `CW_DCO_CI`: `CW_DCO` plus `test` SUCCESS started 2026-09-29T11:05:00Z with `workflowName` `ci` on `https://github.com/o/r/actions/runs/10/job/10`.
- D0: `cw_dated <n> <mergeStateStatus> <rollup> [<committedDate>]`: `cw_full`'s record plus `url` `https://github.com/o/r/pull/<n>` and `commits` `[{"oid":PR50_OID,"committedDate":<date>}]`, default date 2026-09-28T02:40:00Z.
- B2: "Full detail at tip" (land): the whole `_pr_detail` record with `headRefOid` = the land tip, `baseRefName: main`, `mergeable: MERGEABLE`, the named `mergeStateStatus`, `reviewDecision: APPROVED`, labels `[ci]`, `isDraft: false`, the named rollup, `url` `https://github.com/o/r/pull/42`, and `commits` at the tip dated 2026-09-28T02:40:00Z. The helper `ld_full` (owned by B2) builds it. "Sync at tip" is `{labels, statusCheckRollup, headRefOid: tip}`.
- `CW_PUSH` and `CW_PUSH_CI` (D1) and `CA_E1` (D2) get no users beyond the cases named above. The E-cases use PR numbers no other fixture uses (the build greps for a clash).

Land cases use PR 42 and a fresh `build_land` fixture each, and set `GH_STUB_LAND_REPO`, `GH_STUB_LAND_REMOTE`, `GH_STUB_LAND_BRANCH=feat/land` and `GH_STUB_LAND_DEF=main`, so a merge that should not happen lands for real and the worktree checks can go red. They create the PR (`GH_STUB_CREATE_NUM=42`) unless the row says adopted: an adopted case sets `GH_STUB_OPEN_HEAD_feat_land='[{"number":42,"baseRefName":"main","author":{"login":"me"},"isDraft":false}]'`. Merge cases use PR numbers no other fixture uses; the new ones take 101 to 108.

| Case | Setup (reads served) | Assert |
|---|---|---|
| L1 AC1 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 wait: `CW_OLD`. 3 wait: `CW_RUN`. 4 onward: full detail at tip, UNSTABLE, `CW_RED` | exit 2; the refusal line; no `pr merge 42`; no `pr close`; worktree dir and branch `feat/land` exist; `view-42` count is 5 |
| L2 AC2 | `KIT_WRAP_CARRY_CHECKS_SECS=10`. 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, CLEAN, `CW_QUEUED` | exit 2; the refusal line; no `pr merge 42`; `view-42` count is 4 |
| L3 AC3 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail, CLEAN, `CW_GREEN`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: head moved to 3333333 during the check wait; left open`; no `pr merge 42` |
| L4 AC4 | `KIT_WRAP_CI_GRACE_SECS=20`. 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, UNSTABLE, `CW_OLD` | exit 2; the non-CLEAN line; no `pr merge 42`; `view-42` count is 5 |
| L5 AC5 | 1 sync at tip: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, BEHIND, `CW_GREEN` | exit 2; the BEHIND line; no `pr merge 42` |
| L6 AC6 | adopted; `feat/land` pushed to the bare remote at the tip before the run (so `moved` is 0); `KIT_WRAP_CI_GRACE_SECS=20`, `GH_STUB_EVENTS_42="$EV_CI"`. Every read: full detail at tip, UNSTABLE, `CA_OLD` | exit 2; `adopted PR #42`; no `pr create`; the non-CLEAN line; no `pr edit 42`; no `pr merge 42`; `view-42` count is 5 |
| L7 AC7 | `KIT_WRAP_SETTLE_SECS=4`. Every read: labels `[]`, `CW_OLD`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: the PR head never showed the pushed <tip short>; left open`; no `pr edit 42`; no `pr merge 42`; `view-42` count is 3 (reads at 0s, 2s and 4s) |
| L8 AC8 | `KIT_WRAP_SETTLE_SECS=4`. 1: labels `[]`, `CW_OLD`, `headRefOid` `3333333333333333333333333333333333333333`. 2 sync at tip: labels `[]`, `CW_OLD`. 3 onward: full detail at tip, CLEAN, `CW_GREEN` | exit 0; merged; `view-42` count is 4 (2 sync reads, 1 wait read that sees `test@job/3` as NEW, 1 re-gate read); the `--add-label ci` edit comes after the second `pr view 42` line of the call log |
| L9 AC9 | adopted; the tip's parent pushed to the bare remote as `feat/land` before the run (so `moved` is 1); `GH_STUB_EVENTS_42="$EV_CI"`. 1 and 2: full detail at tip, CLEAN, `CW_PUSH`. 3 onward: full detail at tip, CLEAN, `CW_PUSH_CI` | exit 0; `re-labeled #42 ci (the push moved the head)`; the remove precedes the add precedes the merge; no `/events` call; `view-42` count is 4 |
| L10 AC10 | `GH_STUB_LABELS='not json'` | exit 2; `MERGE FAILED #42: the ci label could not be set`; `could not read the repo labels for #42`; no `pr merge 42` |
| L11 AC28 | `GH_STUB_LABELS` unset (empty output, exit 0); PR 42 created; a fresh `build_land` fixture; no PR reads served, as in ci-fuzzy: on sync rc 1 `cmd_land` runs no wait and no re-gate and goes straight to `_gh_merge_retry` | exit 0; merged; no `pr edit 42`; no `/events` call; no `--json number,title,body` call; `view-42` count is 0 |
| ci-fuzzy AC11 | unchanged fixture | add: no `--json number,title,body` call and no `/events` call for #42 |
| ci-gated AC12 | read 1 gains `headRefOid` at tip; read 3 becomes full detail at tip, CLEAN, `pr-check` SUCCESS | the "waited out" check becomes `cw_views 42` equal to 4. Today's `grep -c '^pr view 42 '` also counts the post-merge `state,mergeCommit` read, so its `-ge 3` (and round 1's `-ge 4`) holds with no re-gate. The other asserts pass unchanged |
| T6 AC12 | read 1 gains `headRefOid` at tip; reads 3 and 4 become full detail at tip, CLEAN, with `CW_RUN` and `CW_GREEN`; the case comment names the 5th read as the re-gate | the merge follows the 5th rollup-bearing read; the 5th read is the `_pr_detail` field list; merged |
| ci-armed AC12 | the single fixture becomes full detail at tip, CLEAN, with `pr-check` SUCCESS started 2026-09-29T10:22:00Z with `workflowName` `ci` on `https://github.com/o/r/actions/runs/1/job/9`; `GH_STUB_EVENTS_42="$EV_CI"` | unchanged asserts pass (no `pr edit`, merged) |
| ci-stale, ci-noset AC12 | the sync read gains `headRefOid` at tip. ci-stale's sync read also gains `url` `https://github.com/o/r/pull/42` (the label-on branch now resolves the slug before the empty-rollup arm), and its read 2 becomes full detail at tip, CLEAN, with `pr-check` SUCCESS carrying `workflowName` `ci` on `https://github.com/o/r/actions/runs/1/job/9` (a scoped wait counts only an Actions run) | unchanged asserts pass |
| autoland ci-gated | `AL_PR_CI_2` gains `url` `https://github.com/o/r/pull/42`, `commits` `[{"oid":"%CARRY_TIP%","committedDate":"2026-09-28T02:40:00Z"}]`, and a `pr-check` started 2026-09-29T10:22:00Z with `workflowName` `ci` on `.../actions/runs/1/job/9`; `GH_STUB_EVENTS_42="$EV_CI"` | unchanged asserts pass |
| T13b AC13 | as T13 below, with `mergeStateStatus: UNSTABLE` on both fixtures | apply exits 0; the `SKIP land` line with the non-CLEAN reason for #42; no `pr merge 42`; `view-42` count is 6 |
| T13c AC14 | as T13b, but read 1 already carries labels `[ci]`, `url` and `commits` (the reads-2-onward fixture serves every read) | apply exits 0; the `SKIP land` line with the scoped non-CLEAN reason (AC14); no `pr edit 42`; no `pr merge 42`; `view-42` count is 6 |
| T13 AC15 | renamed "autoland on a ci-gated repo: the carry and the merge each hold the grace window (T13)". `KIT_WRAP_CI_GRACE_SECS=20`, the carry PR on `CA_OLD`, labels `[ci]` from read 2. Reads 2 onward gain `url` and `commits` as in autoland ci-gated; `GH_STUB_EVENTS_42="$EV_CI"` | apply exits 0; tree verified; `view-42` count is 26 |
| T13d AC15 | T13 at `KIT_WRAP_CI_GRACE_SECS=40` | apply exits 0; `view-42` count is 34 (each of the four holds reads 2 more times) |
| T13e AC16 | as T13, with `mergeable: CONFLICTING` and `mergeStateStatus: DIRTY` from read 2 | the output holds `retry #42: one re-merge of main into`; no `SKIP land` line containing `not mergeable (CONFLICTING)`. The re-merge's outcome is not asserted: the union re-merge cases own it |
| T19 AC33 | as autoland ci-gated (carry PR created as 42), with `GH_STUB_LABEL_RC=1` | apply exits 0; the output holds `SKIP land <branch>: PR #42: the ci label could not be set or read; left open`; no `pr edit 42`; no `pr merge 42`; `view-42` count is 0 (the probe fails before any PR read) |
| E1 AC17 | `wrap merge --apply`, PR 73, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_dated 73 UNSTABLE "$CA_E1" 2026-09-19T00:00:00Z`, `GH_STUB_EVENTS_73="$EV_CI2"` | exit 2; `FAILED merge #73: no Actions run of this repo reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`; no `pr edit 73`; no `pr merge 73`; `view-73` count is 6 |
| E2 AC18 | PR 74, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_dated 74 UNSTABLE "$CA_GREEN"`, `GH_STUB_EVENTS_74="$EV_CI_DOCS"` | exit 0; merged; `view-74` count is 4 (one wait read: `test@.../job/3`, an Actions run started after `T`) |
| E3 AC19 | PR 76, every read `cw_dated 76 UNSTABLE "$CA_OLD"`, `GH_STUB_EVENTS_76="$EV_CI"`, `GH_STUB_EVENTS_RC=1` | exit 2; `FAILED merge #76: the ci label could not be set`; `could not read the label events of #76`; no `pr edit 76`; no `pr merge 76`; `view-76` count is 2 |
| E3b AC19 | PR 77, as E3 with `GH_STUB_EVENTS_77='not json'` and rc 0 | the same four asserts for #77; `view-77` count is 2 |
| E5 AC19 | PR 79, every read `cw_dated 79 UNSTABLE "$CA_OLD"` with `url` `https://ghe.example.com/o/r/pull/79` | exit 2; `could not resolve the repo of #79 from its url`; no `/events` call; no `pr merge 79` |
| E5b AC19 | PR 101, every read `cw_dated 101 UNSTABLE "$CA_OLD"` with `url` `https://github.com/o/../pull/101`, `GH_STUB_EVENTS_101="$EV_CI"` | exit 2; `could not resolve the repo of #101 from its url`; no `/events` call; no `pr edit 101`; no `pr merge 101`; `view-101` count is 2 |
| E4 AC20 | PR 78, `KIT_WRAP_CI_GRACE_SECS=20`, every read `cw_dated 78 UNSTABLE "$CW_PUSH" 2026-09-29T11:00:00Z`, `GH_STUB_EVENTS_78="$EV_CI"` | exit 2; `re-labeled #78 ci (the head commit is not older than the label)`; the non-CLEAN line; no `pr merge 78`; `view-78` count is 6 |
| E6 AC31 | PR 102, `GH_STUB_EVENTS_102='[]'`. 1: `cw_dated 102 CLEAN "$CA_OLD"`. 2: the same record with `statusCheckRollup` set to the JSON string `"x"` (the jq cannot iterate it). 3 onward: `cw_dated 102 CLEAN "$CA_OLD"` | exit 2; `FAILED merge #102: the ci label could not be set`; `could not build the check snapshot of #102`; no `pr edit 102`; no `pr merge 102`; `view-102` count is 2 |
| E6b AC31 | PR 103, as E6 with `GH_STUB_EVENTS_103="$EV_CI"` and the commit date 2026-09-28T02:40:00Z (the DATED path) | the same asserts for #103; `view-103` count is 2 |
| E7 AC32 | PR 104, as T4's shape: `KIT_WRAP_CI_GRACE_SECS=20`, `GH_STUB_EVENTS_104=""` (set, empty), every read `cw_dated 104 CLEAN "$CA_OLD"` | exit 0; `re-labeled #104 ci (no ci labeled event dates the label)`; the remove precedes the add; merged; `view-104` count is 6 |
| T4 AC21 | renamed "the label is already on and no ci labeled event dates it: remove and re-add". `KIT_WRAP_CI_GRACE_SECS=20`; the three fixtures use `CA_OLD`; `GH_STUB_PR_63_2` gains `url` `https://github.com/o/r/pull/63`; events default `[]` | exit 0; `re-labeled #63 ci (no ci labeled event dates the label)`; the remove precedes the add; `view-63` count is 6; merged. Today's "a label already on is not edited" assert is replaced |
| T14 AC22 | PR 81: 1 `cw_full 81 CLEAN "$CW_OLD"`; 2 labels `[]`, `CW_OLD`; 3 `cw_full 81 CLEAN "$CW_GREEN"`; 4 `not json` | exit 2; `FAILED merge #81: could not re-read #81 after the check wait; left open`; no `pr merge 81` |
| T15 AC23 | PR 83, `GH_STUB_LABEL_RC=1`, every read `cw_full 83 CLEAN "$CW_GREEN"` | exit 2; `FAILED merge #83: the ci label could not be set`; `could not read the repo labels for #83`; no `pr edit 83`; no `pr merge 83`; `view-83` count is 1 |
| T16 AC24 | PR 85, `KIT_WRAP_CARRY_CHECKS_SECS=10`: 1 `cw_full 85 UNSTABLE "$CW_OLD"`; 2 labels `[]`, `CW_OLD`; 3 `not json`; 5 `cw_full 85 UNSTABLE "$CW_OLD"` | exit 2; `FAILED merge #85: the check wait ended with checks unfinished or unreadable, and merge state UNSTABLE is not CLEAN; left open`; no `pr merge 85`; `view-85` count is 5 |
| T17 AC28 | PR 105, `GH_STUB_LABELS` unset (empty output, exit 0), every read `cw_full 105 CLEAN "$CW_GREEN"` | exit 0; merged; no `pr edit 105`; no `/events` call; `view-105` count is 1 |
| T17b AC28 | PR 106, as T17 with `GH_STUB_LABELS='[]'` | the same asserts for #106; `view-106` count is 1 |
| T18 AC29 | PR 107, `KIT_WRAP_CI_GRACE_SECS=20`, label probe `[ci]`. 1 and 2: `cw_dated 107 CLEAN "[]"` (eligibility, then the sync's empty rollup). 3 and 4: `cw_dated 107 CLEAN "$CW_DCO"`. 5 onward: `cw_dated 107 CLEAN "$CW_DCO_CI"` | exit 0; `re-labeled #107 ci (the label predates the head)`; no `/events` call; merged; `view-107` count is 6 (3 wait reads at 0s, 10s and 20s, the third seeing `test` as NEW, then 1 re-gate read) |
| RM1 AC30 | PR 108 in a `build_remerge` fixture like the re-merge `--apply` case (PR 12): `GH_STUB_LABELS='[{"name":"ci"}]'`, `GH_STUB_EVENTS_108="$EV_CI"`, `KIT_WRAP_CI_GRACE_SECS=20`. 1 `conflict_json`. 2 and 3: the post-re-merge record (head `%REMERGE_TIP%`, MERGEABLE, CLEAN, labels `[ci]`, rollup `CA_OLD`, `url`, `commits` at `%REMERGE_TIP%` dated 2026-09-28T02:40:00Z). 4 onward: the same with `CA_GREEN`. The stub's `GH_STUB_LAND_*` variables land the tip as in the PR 12 case | exit 0; `re-labeled #108 ci (the push moved the head)`; the remove precedes the add precedes the merge; no `/events` call; merged; `view-108` count is 5 (conflict read, settle read, sync read, one wait read that sees `test` as NEW, re-gate read) |
| T20 AC34 | as T13 (`KIT_WRAP_CI_GRACE_SECS=20`, `GH_STUB_EVENTS_42="$EV_CI"`), with three fixtures. `GH_STUB_PR_42` through `AL_PR_OVERRIDE` (reads 1 to 13): the T13c record (labels `[ci]`, `url`, `commits` at `%CARRY_TIP%` dated 2026-09-28T02:40:00Z, CLEAN, `CA_OLD`). `GH_STUB_PR_42_14`: the same record with labels `[]` and rollup `CW_OLD`. `GH_STUB_PR_42_15` onward: labels `[]`, rollup `CW_GREEN`, CLEAN | apply exits 0; two `pr merge 42` lines; `view-42` count is 24. Carry 1 (label on, dated) reads 13, as T13's carry 2. Carry 2: the sync at read 14 takes the absent-label path with scope cleared; wait read 15 sees `test@https://gh/job/3` (no `workflowName`) as NEW and ends; head read 16; carry re-gate 17; the inner merge reads draft 18, eligibility 19, sync 20 (label absent again, `job/3` now in the snapshot), a `NONEW` hold of 21 to 23, re-gate 24 |

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

A running CheckRun carries the zero `completedAt`, an empty `conclusion` and a real `startedAt`, the shape of `CW_RUN`. An Actions run's `detailsUrl` sits under `https://github.com/<owner>/<name>/actions/`. The QUEUED shape (`CW_QUEUED`) was not sampled today: no listed PR had a queued check. It rests on SPEC-360's round-3 sample of four public PRs. The PR record `_pr_detail` reads, sampled with `gh pr view 163486 -R rust-lang/rust --json headRefOid,baseRefName,mergeable,mergeStateStatus,reviewDecision,isDraft,labels`, returns `{"headRefOid":"d8ff9a0c6611…","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","isDraft":false,"labels":[…]}`. The full-detail fixtures use those field names and value spellings. A live `BEHIND` sample was not taken, because the one list call that could have found one returned HTTP 504.

**Live label probe shape (round 3 critical).** Read-only, today, `gh` 2.101.0. The command is the probe's own, aimed at a public repo:

```
gh label list --repo rust-lang/rust --search zzqqnomatch --limit 200 --json name
  exit 0, stdout 0 bytes, stderr 0 bytes                      (no label matches)
gh label list --repo rust-lang/rust --search rollup --limit 200 --json name
  exit 0, stdout [{"name":"rollup"}]                           (one match)
```

A search with no match prints nothing, not `[]`. A probe that refused on "not a JSON array" would refuse every repo that has no `ci`-like label. The rule in Change 5 reads exit 0 with empty or whitespace-only output as "no `ci` label". The stub's default answer now matches this sample.

**Live workflowName shape (round 3 warning 1).** Read-only, today:

```
gh pr view 163486 -R rust-lang/rust --json statusCheckRollup --jq '[.statusCheckRollup[] | {name, workflowName, __typename, detailsUrl}][0:2]'
  {"name":"Calculate job matrix","workflowName":"CI","__typename":"CheckRun",
   "detailsUrl":"https://github.com/rust-lang/rust/actions/runs/36575034118/job/109428342551"}
gh pr list -R microsoft/vscode --limit 10 --json number,statusCheckRollup   (entries with an empty workflowName)
  {"name":"CodeQL","workflowName":"","detailsUrl":"https://github.com/microsoft/vscode/runs/109472346347"}
  {"name":"Dependencies Check","workflowName":"",
   "detailsUrl":"https://github.com/microsoft/vscode-engineering/actions/runs/36575..."}
gh pr list -R rust-lang/rust --limit 20 --json number,statusCheckRollup
  {"name":"Bors auto build","workflowName":"","detailsUrl":"https://bors.rust-lang.org"}
```

An Actions CheckRun carries a non-empty `workflowName` (`CI`) and a url under its repo's `actions/`. App checks carry an empty `workflowName`: CodeQL and Bors, and `Dependencies Check`, whose url sits under another repo's `actions/`. The url prefix alone admits a check that only points there, and `workflowName` alone admits an Actions run of a different repo. The wait keys on both.

**Live StatusContext shape (round 4).** Read-only, today, a Prow-gated repo:

```
gh pr view 142529 -R kubernetes/kubernetes --json statusCheckRollup \
  --jq '[.statusCheckRollup[] | select(.__typename=="StatusContext")][0]'
{"__typename":"StatusContext","context":"pull-kubernetes-node-kubelet-serial-containerd",
 "startedAt":"2026-09-29T14:40:04Z","state":"PENDING",
 "targetUrl":"https://prow.k8s.io/view/gs/kubernetes-ci-logs/pr-logs/pull/142529/..."}
```

A StatusContext carries `context`, `state`, `targetUrl` and a `startedAt`, and no `detailsUrl` and no `workflowName` key at all. `def actions` reads the missing `workflowName` as `""`, so this entry is never NEW on a label-on pass. That is the non-Actions cost row under Failure modes. `ckey` keys it on `targetUrl`, the start on `startedAt`.

**gh version for `workflowName`.** cli/cli PR 5919 (merged 2022-07-12, merge commit `dea1af1`) added `workflowName` for checks and `startedAt` for statuses to `gh pr view --json statusCheckRollup`. `gh api repos/cli/cli/compare/dea1af1...v2.13.0` reads `behind` and `...v2.14.0` reads `ahead`, so v2.14.0 is the first release that emits it. The sample above ran on gh 2.101.0.

**Live push activity shape (round 4).** Read-only, today:

```
gh api 'repos/cli/cli/activity?ref=refs/heads/trunk&activity_type=push&per_page=2' \
  --jq '[.[] | {activity_type, ref, timestamp, after: .after[0:10]}]'
[{"activity_type":"push","after":"441beb9de3","ref":"refs/heads/trunk","timestamp":"2023-12-14T16:42:38Z"}, ...]
```

GitHub does date a push: the activity API returns each push's `timestamp` and `after` oid. This spec does not adopt it (Approaches considered, alternative 5).

**Live url and commits shape.** Read-only, today:

```
gh pr view 163486 -R rust-lang/rust --json url,headRefOid,commits \
  --jq '{url, headRefOid, n: (.commits|length), last: (.commits[-1] | {oid, committedDate})}'
{"headRefOid":"d8ff9a0c6611d4b22f1ee3e58a96e805c12aa8d5",
 "last":{"committedDate":"2026-09-29T13:25:46Z","oid":"d8ff9a0c6611d4b22f1ee3e58a96e805c12aa8d5"},
 "n":12,"url":"https://github.com/rust-lang/rust/pull/163486"}
```

`url` has the `https://github.com/<owner>/<name>/pull/<n>` form the slug check expects. Each commit carries `oid` and a `committedDate` in the same `Z` format as `created_at`, so the head-age test is a string compare. On this PR the head commit (13:25:46) predates its first labeled events (13:25:51), the normal order the DATED path relies on. GitHub's `commits` field holds at most the first 100 commits of a PR, so the head of a longer PR is not in it.

**Live events shape.** Read-only, today:

```
gh api 'repos/rust-lang/rust/issues/163486/events?per_page=100' \
  | jq -c '[.[] | select(.event=="labeled" or .event=="unlabeled") | {event, label, created_at}][0:2]'
[{"event":"labeled","label":{"name":"rollup","color":"f1ffa5"},"created_at":"2026-09-29T13:25:51Z"},
 {"event":"labeled","label":{"name":"S-waiting-on-review","color":"d3dddd"},"created_at":"2026-09-29T13:25:54Z"}]
```

The endpoint serves PR events by issue number. Each labeled event carries `event`, `label.name` and a `created_at` in the same `Z` format as `startedAt`, so a string compare orders them. The PR had 11 events and no `Link` header, so one page held them all. `--paginate` plus `jq -s` covers longer histories. `jq -s` reads empty input as `[]`, which is why an exit 0 with no output is an empty history. `EV_CI` uses this shape, less the fields the filter never reads.

**Read paths, from the code.** `_autoland_carry` calls `_ci_label_sync` (wrap.sh:1376) and `_ci_checks_wait` (1378), reads `headRefOid`, then runs the subshell merge (1398); its `case` has arms for 0 and 2 only. `cmd_merge` calls `_ci_label_sync` (2260) and `_ci_checks_wait` (2263), and its `case` refuses every rc other than 0 and 1. The sync resets `CI_PRELABEL_KEYS` (1262). Its probe (1263 to 1264) pipes `gh label list` into `jq -e`, so a failed gh, an empty answer and a non-array answer all return 1, and with the label on over a non-empty rollup it takes neither edit branch and returns 0. `_union_remerge` pushes through `_remerge_push` (1941 to 1959) and sets `REMERGE_OID`, which `cmd_merge` turns into `head_oid` (2213 to 2223) before it calls the sync. `_pr_detail_settled` (1824) without a pushed oid breaks on the first read whose `mergeable` is not `UNKNOWN`, which includes an empty read, so an unreadable re-gate read reaches `_ci_regate` at once as an empty head.

**T13's count.** Grace 20 makes each `NONEW` hold 3 wait reads. Carry 1 (the orphan): 1 sync (label absent), 3 hold reads, 1 head read, 1 carry re-gate read, then the inner merge: draft check, eligibility, sync (label on, dated on `EV_CI`, `CA_OLD` in the snapshot), 3 hold reads, re-gate. That is 13. Carry 2 (the remainder) finds the label on: 1 sync (dated), 3 hold reads, 1 head read, 1 carry re-gate read, and the same inner 7. That is 13 more, 26 in all. The events read is `gh api`, which the counter skips. At grace 40 each hold is 5 reads, so T13d reads 26 + 4 x 2 = 34. T13b and T13c refuse at carry 1's re-gate, read 6. The scoped wait changes none of these counts, because no `CA_OLD` entry is outside the dated snapshot and none is pending.

**T20's count.** Carry 1 finds the label on from read 1, so it takes T13's carry-2 shape: 13 reads. Carry 2: sync 14 (label absent, snapshot `test@…/job/1`, `preview@…/job/2`, scope cleared), one wait read 15 (`test@https://gh/job/3` is NEW), head read 16, carry re-gate 17 (`CI_WAIT_END` 0, so no CLEAN clause), then the inner merge: draft 18, eligibility 19, sync 20 (label absent, all three keys in the snapshot), a `NONEW` hold 21 to 23, re-gate 24 on `CLEAN`. 24 in all. The sync's clear is what makes read 15 end the wait: carry 1's sync ran in the same shell and set the scope to `o/r`.

**Dry traces of the negative controls.** Each mutation is applied after the feature commit and restored before the next.

NC1: the `cmd_land` call to `_ci_regate` replaced by `:`.
- L1: read 1 snapshots `[test@…/job/1, preview@…/job/2]` at tip. Read 2 (`CW_OLD`) is `NONEW`, read 3 (`CW_RUN`) is pending, read 4 (`CW_RED`) has pending 0 and NEW job/3, so the wait ends. `_gh_merge_retry` runs, the stub lands `feat/land`, the tree verifies, and land removes the worktree and deletes the branch. Red: "L1 exits 2", "L1 refusal line", "L1 no pr merge", "L1 worktree exists", "L1 branch exists", "L1 5 reads" (4).
- L2: read 2 is pending, and read 3 is pending with waited=10, which ends the wait. The merge runs. Red: exit, refusal line, no pr merge, 4 reads (3).
- L3: read 2 has pending 0 and NEW job/3; the merge runs, because the stub ignores `--match-head-commit`. Red: exit, refusal line, no pr merge.
- L4: reads 2 to 4 are `NONEW` until grace 20 runs out; the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- L5: read 2 has pending 0 and NEW job/3; the merge runs. Red: exit, refusal line, no pr merge.
- L6: the dated snapshot holds both old keys; reads 2 to 4 are `NONEW`; the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- T6: the merge follows the 4th rollup read. Red: "the merge follows the 5th read", "the 5th read is `_pr_detail`". ci-gated: 3 counted reads. Red: "ci-gated 4 reads". L7 to L11, ci-armed and ci-stale stay green.

NC2: the `_autoland_carry` call to `_ci_regate` replaced by `:`.
- T13b: the carry's hold ends `NONEW` and its head read passes. In the subshell, `cmd_merge`'s sync dates the label on `EV_CI`, holds its own grace, and its re-gate refuses `UNSTABLE`. `cmd_merge` returns 2, so the carry sets `FAILURES` and `apply` exits 2. Red: "T13b exits 0", "T13b SKIP land line", "T13b 6 reads" (12: the 13 of the passing run less the carry's own re-gate read). "T13b no pr merge 42" stays green: the inner re-gate is the second check doing its job.
- T13c: the same path. Red: "T13c exits 0", "T13c SKIP land line", "T13c 6 reads".
- T13: 24 reads instead of 26. Red: "T13 26 reads". T13d: 32 instead of 34. Red: "T13d 34 reads". T13e stays green: with no carry re-gate the carry reaches `cmd_merge` anyway.

NC3: the DATED assignment in `_ci_label_sync` replaced by `CI_PRELABEL_KEYS='[]'`. The scope stays set, and `CA_OLD` entries are Actions runs, so each reads as NEW against an empty snapshot.
- L6: read 2 ends the wait with state `0`. The re-gate passes `UNSTABLE`, because the CLEAN rule needs a snapshot, and the merge runs. Red: exit, refusal line, no pr merge, 5 reads (3).
- T13c: the carry's wait ends on state `0`, the carry re-gate passes, and the inner merge, also on `[]`, merges. Red: "T13c SKIP land line", "T13c no pr merge 42", "T13c 6 reads".
- T13: carry 2 and both inner merges end their waits on one read: 20 reads. Red: "T13 26 reads", "T13d 34 reads".
- E1: `build` is an Actions run outside the empty snapshot; one wait read gives state `0`, the re-gate passes, and the PR merges. Red: exit, refusal line, no pr merge, 6 reads (4).
- E2 stays green (its one NEW entry ends the wait either way). T4, E4, E7 and L9 take RE-ADD before the DATED line and stay green.

NC4: the `.label.name == "ci"` filter dropped.
- E2: `T` becomes 2026-09-29T11:00:00Z (the `docs` event). The head (2026-09-28T02:40:00Z) is still older, so the path stays DATED, and job/3 (started 10:21:58) joins the snapshot. The wait holds 3 `NONEW` reads, and the CLEAN rule refuses `UNSTABLE`. Red: "E2 exits 0", "E2 merged", "E2 4 reads".

NC5: `max` replaced by `min`.
- E1: `T` becomes 2026-09-20T00:00:00Z. The head (2026-09-19) is older, so the path stays DATED. `preview@…/job/2` (started 2026-09-28, an Actions run) is outside the snapshot, one wait read gives state `0`, and the PR merges. Red: exit, refusal line, no pr merge, 6 reads.

NC6: the pinned-head re-read in `_ci_label_sync` dropped (the sync ignores the pinned oid).
- L7: the sync adds the label on the wrong head. The wait runs on `CW_OLD` (`NONEW`, default grace 90, 10 reads). The re-gate then reads head 3333333 and refuses with `head moved`. Red: "L7 head-never-showed line", "L7 no pr edit 42", "L7 3 reads". "L7 exits 2" and "L7 no pr merge" stay green.
- L8: the sync labels after read 1. Read 2 holds `NONEW`, read 3 ends the wait, read 4 re-gates, and the merge runs. Red: "L8 edit after the second read". The exit, the merge and the count (4) stay green.

NC7: the events read's exit code ignored (the sync parses whatever gh printed).
- E3: `EV_CI`, printed before the non-zero exit, dates the label, so the snapshot holds both old keys. The wait holds for the default grace (10 reads), and the CLEAN rule refuses `UNSTABLE` with the non-CLEAN line. Red: "E3 refusal line", "E3 events line", "E3 2 reads". The exit, no pr edit and no pr merge stay green.

NC8: the carry's `CONFLICTING` pass-through dropped (every `_ci_regate` refusal, rc 3 included, prints `SKIP land`).
- T13e: the carry prints `SKIP land …: not mergeable (CONFLICTING) once the ci label's checks ran; left open` and never calls `cmd_merge`. Red: "T13e retry line", "T13e no CONFLICTING SKIP line".

NC9: the `moved` arm dropped.
- L9: the path goes DATED on `EV_CI` (the fixture's head date, 2026-09-28T02:40:00Z, is older than `T`). `lint@…/runs/9/job/9`, an Actions run started after `T`, is outside the dated snapshot, so read 2 ends the wait with state `0`, the re-gate passes, and the merge runs on a head the label's run never reached. Red: "L9 re-label line", "L9 remove, add, merge order", "L9 no events call", "L9 4 reads" (3). The exit and the merge stay green: this is the round-2 critical, and the proof that the fix is live is the order and the count.

NC10: the head-age arm dropped.
- E4: the path goes DATED; `lint` (an Actions run) is NEW, read 3 ends the wait with state `0`, and the re-gate passes `UNSTABLE`. Red: exit, re-label line, non-CLEAN line, no pr merge, 6 reads (4).

NC11: the empty-`T` arm returns 0 with the `[]` snapshot instead of RE-ADD (round 1's behavior). Dropping the arm outright is not a control: the head-age arm would then RE-ADD on the empty `T` anyway.
- T4: `CA_OLD`'s `preview` is an Actions run outside the empty snapshot, so one wait read ends on it. Red: "T4 re-label line", "T4 remove precedes add", "T4 6 reads" (4). Exit and merged stay green.

NC12: the DATED cut `<= T` replaced by `< T`.
- E1: `build@…/job/5` (started exactly at `T`) is NEW; the wait ends on read 3 and the PR merges. Red: exit, refusal line, no pr merge, 6 reads.

NC13: the empty-start arm of the DATED cut dropped.
- E1: `legacy@…/runs/3` (an Actions run, no times) is NEW; the PR merges. Red: the same four lines.

NC14: the url-prefix half of `def actions` dropped (the wait tests `workflowName` only).
- E1: `xrepo` (an Actions run of `x/y`, started 11:00) is NEW; the PR merges. Red: the same four lines. T18 stays green: `DCO` has no `workflowName`.

NC15: the probe's failure arm returns 1 (today's behavior).
- T15: no gate; the eligibility read passed on `CLEAN`, so the PR merges. Red: exit, refusal line, labels line, no pr merge. L10: land merges ungated. Red: exit, refusal line, labels line, no pr merge.

NC16: the CLEAN clause keyed back on `CI_WAIT_END == NONEW`.
- T16: the wait ends on state `""`; the clause does not fire and the PR merges on `UNSTABLE`. Red: exit, non-CLEAN line, no pr merge.

NC17: a failed `jq -s` parse of the events ignored (only gh's exit code checked).
- E3b: `T` comes back empty, so the sync takes RE-ADD, holds the default grace, and refuses `UNSTABLE` with the non-CLEAN line. Red: "E3b refusal line", "E3b events line", "E3b no pr edit", "E3b 2 reads".

NC18: the probe treats exit 0 with empty or whitespace-only output as a failed read (round 2's shape: any output that is not an array returns 2).
- T17: the probe returns 2, so the merge refuses. Red: "T17 exits 0", "T17 merged". L11: the same. Red: "L11 exits 0", "L11 merged". T17b stays green (`[]` is an array). Every existing case that leaves `GH_STUB_LABELS` unset and reaches the sync goes red as well, because the stub now answers as gh does. The record lists them from the run. This is intended: they prove the stub and the rule agree.

NC19: the `CI_NEW_SCOPE` assignment dropped (the wait counts any entry).
- T18: `DCO` is NEW on the first wait read, the wait ends with state `0`, the re-gate passes, and the PR merges. Red: "T18 6 reads" (4). The exit and the merge stay green.
- E1: `forged` and `xrepo` are outside the dated snapshot and now count as NEW. Red: exit, refusal line, no pr merge, 6 reads (4).
- L6, E4 and T13c: with the scope never set, their `NONEW` refusal prints the unscoped text. Nothing else moves (same exits, no merge, same counts). Red: "L6 refusal line", "E4 non-CLEAN line", "T13c SKIP land line".

NC20: the `workflowName` half of `def actions` dropped (the wait tests the url prefix only).
- E1: `forged` (a StatusContext whose target url sits under this repo's `actions/`, created 11:00) is NEW; the PR merges. Red: the same four lines. T18 stays green: `DCO`'s url is under `pull/107/checks`.

NC21: the guard on an empty snapshot removed (an empty jq result falls back to `[]` and the edit runs).
- E6: the sync sets `[]`, removes and re-adds the label, and reads 3 onward serve a valid `CA_OLD`. `preview` is an Actions run outside the empty snapshot, so one wait read ends the wait and the PR merges. Red: "E6 exits 2", "E6 refusal line", "E6 snapshot line", "E6 no pr edit", "E6 no pr merge", "E6 2 reads" (4). E6b: the same on the DATED path. Red: the same six lines for #103.

NC22: an events read that exits 0 with zero bytes treated as a failed read.
- E7: the sync returns 2. Red: "E7 exits 0", "E7 re-label line", "E7 merged", "E7 6 reads" (2). T4 (events `[]`) stays green.

NC23: the carry's catch-all sync arm dropped (only rc 0 and rc 1 have arms).
- T19: rc 2 falls through to the head read and `cmd_merge`, whose own sync refuses, so `apply` exits 2. Red: "T19 exits 0", "T19 SKIP line", "T19 0 reads" (at least 1).

NC24: `cmd_merge`'s `moved` argument dropped (the sync call passes 0).
- RM1: the path goes DATED on `EV_CI` (the commit at `%REMERGE_TIP%` is dated 2026-09-28, older than `T`). The events read runs, and `test@…/job/3` in `CA_GREEN` is an Actions run outside the snapshot, so the count stays 5. Red: "RM1 re-label line", "RM1 remove, add, merge order", "RM1 no events call". The exit, the merge and the count stay green.

NC25: the dots-only guard on the repo name dropped.
- E5b: the slug `o/..` passes and the events read runs on `repos/o/../issues/101/events`. `EV_CI` dates the label and the head predates it, so the sync goes DATED, the wait holds the default grace (10 reads), and the CLEAN rule refuses `UNSTABLE`. The exit stays 2. Red: "E5b resolve line" (absent), "E5b no events call", "E5b 2 reads" (13). "E5b no pr edit" and "E5b no pr merge" stay green. The stub's events branch matches `repos/*/issues/<n>/events*`, so it answers.

NC26: the `CI_NEW_SCOPE=""` clear on sync entry dropped.
- T20: carry 2's label-absent sync keeps carry 1's scope `o/r`. Its wait reads `test@https://gh/job/3` (no `workflowName`) as not NEW, holds 3 `NONEW` reads (15 to 17), then head 18 and re-gate 19 pass on `CLEAN`. The inner merge's subshell inherits the scope, so its label-absent sync holds too: draft 20, eligibility 21, sync 22, hold 23 to 25, re-gate 26. Red: "T20 24 reads" (26). The exit and both merges stay green. Every other case runs one sync per shell, or a label-on sync last, and stays green.

## Negative control

After the feature commit, one run per control through `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`, each restored before the next: NC1 to NC26 as traced under `## Grounding`. The record quotes the failing `chk` names from each run and checks them against the traced lists. A suite exit code alone does not pass a control. The exact `sed` patterns are set at build time against the final lines. NC18 is the one control whose traced list is open at one end (every unlabeled case), so its record lists the full set and confirms T17 and L11 are in it.

## Out of scope

- `land` on a repo without the `ci` label still merges with no gate. It never waits there, and a gate there would change `land` on every repo.
- A PR on a host other than github.com (GHES) with the `ci` label already on. The slug check refuses it every pass, on the empty-rollup and moved arms too. The recovery row names the manual step. Supporting it needs the events read and the scope prefix to target the PR's own host. The events read passes `--hostname github.com`, so an exported `GH_HOST` cannot point it at another host.
- The Actions scope on the absent-label path. There a third-party check that registers after the label still counts as NEW and can end the wait early, as in SPEC-360 (its T12 depends on it). A first `land` and a first carry sync keep that race (Failure modes).
- Another Actions workflow of this repo registering after the snapshot on a label-on path, for example a workflow on `synchronize` that registers after the sync's read and completes before the `ci` run registers. It counts as NEW and ends the wait before the `ci` run. The scope removes app statuses, not workflows. `_pr_gate` still reads every check. A settle before the wait could narrow this; this round adds none.
- Label-started CI that is not a GitHub Actions workflow of this repo (Prow, Jenkins, Netlify, CircleCI StatusContexts). The label-on rules assume Actions. Such a repo pays the grace hold and the CLEAN rule on every label-on pass (Failure modes). Supporting it needs a per-repo list of the label's check names or contexts.
- A head commit dated before the label but pushed after it by something other than wrap (a hand push, a `land` re-run after a push that stopped early), and committer clock skew behind GitHub's (Failure modes). The PR record carries no push time, so the sync uses the committer date. The repository activity API does date pushes (Grounding); dating the head's push from it is the future hardening, rejected for now (Approaches considered, alternative 5).
- The autoland exit-code asymmetry inside `cmd_merge`. A post-wait refusal in the inner merge returns 2 and sets `FAILURES`, while the carry's own re-gate refusal now returns 1 with `apply` exit 0. The inner merge refuses when the state changed between the two checks. It also refuses when its scoped wait cannot see the CI the label started while the carry's unscoped first wait could: on a repo whose label starts only non-Actions CI, the carry passes and the inner merge refuses a state other than `CLEAN`, so `apply` exits 2 with the PR open (Failure modes).
- The residual races SPEC-360 names: two workflows on one event, the read-to-edit window, `needs:` chains, StatusContext key shifts, delayed webhooks.

## Verification

Iterate with `bin/test-affected`. At the end, run `bash tests/test-wrap.sh` in full once, with L1 to L11, T13 to T13e, T17, T17b, T18, T19, T20, E1 to E7 (including E3b, E5b, E6b), T4, T14 to T16, RM1 and the updated land and autoland cases present, plus `bash tests/test-meta.sh`, then the negative controls above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap land regate after wait"` names it.

## Tasks

- [ ] Task A: extract `_ci_regate` from `cmd_merge`, with the `could not re-read` line, the CLEAN clause on `CI_WAIT_END != 0` with its three reason texts, and rc 3 for a CONFLICTING verdict (`lib/wrap/wrap.sh`); cases T14 and T16 (`tests/test-wrap.sh`). The scoped `NONEW` text keys on `${CI_NEW_SCOPE:-}`, which nothing sets before D0; its first case is E4 (D1). Check: the existing merge ci-wait and settle cases pass unchanged.
- [ ] Task B1 (depends on Task A): in `_ci_label_sync`, the fail-closed probe with the empty-or-whitespace rule and the `could not read the repo labels for #<n>` line, the wider PR read and the pinned-head wait with return 3; in `cmd_land`, the `ls-remote` before the push, the new sync arguments and the return-3 arm (`lib/wrap/wrap.sh`). The stub's empty-output label default (`tests/test-wrap.sh`). Cases L7, L10, L11, T15, T17 and T17b; `headRefOid` at tip on the sync reads of ci-gated, T6, ci-armed, ci-stale and ci-noset. Check: every land ci case passes. The sync accepts `moved` here and ignores it until D1.
- [ ] Task B2 (depends on Task B1): the `cmd_land` re-gate (`lib/wrap/wrap.sh`); the `ld_full` helper; cases L1 to L5 and L8 (L8's count of 4 includes the re-gate read); the full-detail re-gate fixtures of ci-gated, T6, ci-armed and ci-stale; ci-gated's count on `cw_views`; the ci-fuzzy asserts (`tests/test-wrap.sh`).
- [ ] Task C (depends on Task A): the carry re-gate, the rc 3 pass-through and the catch-all `case` arm with its new line in `_autoland_carry` (`lib/wrap/wrap.sh`); cases T13b, T13e and T19; T13's count becomes 20 for this task (18 plus one carry re-gate read per carry) (`tests/test-wrap.sh`).
- [ ] Task D0 (depends on Tasks B2 and C): the wait scope. In `lib/wrap/wrap.sh`, four sites: `def actions` in `CI_JQ_DEFS`; the `--arg scope` filter in `_ci_checks_wait`; `CI_NEW_SCOPE=""` beside the `CI_PRELABEL_KEYS` reset on sync entry; at the top of the sync's label-on branch, the slug check and `CI_NEW_SCOPE` set from it, so the empty-rollup arm and today's `[]` fallthrough for a non-empty rollup both run scoped. In `tests/test-wrap.sh`: fixtures `EV_CI`, `CA_OLD`, `CW_DCO`, `CW_DCO_CI` and `cw_dated`; cases T18, E5 and E5b. Fixture moves, so every existing label-on case keeps its asserts under the scope: `url` and an Actions-shaped `pr-check` on ci-stale (its sync read and read 2), an Actions-shaped `pr-check` on ci-armed, `url` and an Actions-shaped `pr-check` on `AL_PR_CI_2` (autoland ci-gated), `CA_OLD` and `url` on T4's three fixtures (asserts unchanged: 4 reads, no edit), and `CA_OLD` plus `url` on reads 2 onward of T13, T13b and T13e (T13 stays at 20 reads). Check: every case passes. T20, the case for the entry clear, lands in D2, where carry 1's count is final.
- [ ] Task D1 (depends on Task D0): the RE-ADD plumbing. In `lib/wrap/wrap.sh`: `_ci_label_date` (the `moved` arm, the `--hostname github.com` events read, the empty-`T` and head-age arms); in the sync's non-empty label-on arm, the call to it and the RE-ADD action with its empty-snapshot guard, while `DATED` falls through to `[]`; in `cmd_merge`, `moved` after the union re-merge. In `tests/test-wrap.sh`: the stub's events branch; fixtures `CA_GREEN`, `CW_PUSH` and `CW_PUSH_CI`; cases L9, E3, E3b, E4, E6, E7, T4 rewritten and RM1; `GH_STUB_EVENTS_42="$EV_CI"` on ci-armed, and `EV_CI` plus `commits` on autoland ci-gated and on T13, T13b and T13e (T13 stays at 20 reads). Check: every D1 case and every earlier case passes.
- [ ] Task D2 (depends on Task D1): the DATED cut (`lib/wrap/wrap.sh`): the `DATED` arm of the sync in place of the `[]` fallthrough, and the empty-snapshot guard on it. In `tests/test-wrap.sh`: fixtures `EV_CI2`, `EV_CI_DOCS` and `CA_E1`; cases L6, E1, E2, E6b and T20; T13 renamed with 26 reads, T13c and T13d. Check: every case passes, T13 reads 26 and T20 reads 24.
- [ ] Task E: the comments named in Change 7; `commands/wrap.md` lines 104 and 323; regenerate `docs/FEATURES.md` if `feature-registry.sh check` reports drift.

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
- DEC-E: Round-2 critical R1(a), a merge on a head the `ci` workflow never ran on. After a fix push the label stays on, push-started checks start after `T`, and the DATED cut read them as NEW. Fix: RE-ADD instead of dating when `land`'s push moved the head (`ls-remote` before the push, a failed read counting as moved), or when the head commit is not older than `T`. Tests: L9, E4; controls NC9, NC10. The head-age arm uses the committer's clock; its gap is named under Failure modes and Out of scope. Round 3 extends the same rule to `cmd_merge`'s own union re-merge push (DEC-T).
- DEC-F: Round-2 critical R1(b), fail-open reads, with R2's conflicting fallback. One fail-closed rule: a label probe or events read that exits non-zero or prints unparseable text returns 2 and refuses; a PR url that is not a github.com PR url returns 2 as well. When the events read works and holds no `ci` labeled event, the sync RE-ADDs. Rejected: R2's "snapshot every key with a real start, plus a stderr line", because it leaves the CLEAN rule as the only check on a `CLEAN` PR whose `ci` status nobody read. Tests: T15, L10, E3, E3b, E5, T4; controls NC7, NC11, NC15, NC17. Round 3 narrows the probe half: DEC-R.
- DEC-G: Round-2 critical R3, the carry re-gate refusing a `CONFLICTING` carry PR and so blocking the inner union re-merge. Fix: the carry passes a CONFLICTING carry PR through to `cmd_merge --apply --pr`, whose union re-merge, sync, wait and re-gate then run on the re-merged head. Round 3 changed the signal from reason text to `_ci_regate` rc 3 (DEC-Y). Test: T13e; control NC8.
- DEC-H: Round 1's Change 6 (`_pr_detail_settled` re-reading an empty read and an `UNKNOWN` merge state) and round 1's contract row C7 are cut (R4 and R5: untested settle retries; cut preferred over new cases). Round 1's Change 7 (the `CI_WAIT_END` load reset) is cut too (R4): every `_ci_regate` call runs right after `_ci_checks_wait`, which assigns `CI_WAIT_END` unconditionally, and the clause now fires on any value other than `0`, so an unset or stale value fails closed. With Change 6 cut, an empty re-gate read ends the settle at once and refuses as `could not re-read` (T14).
- DEC-I: R2's "start time falls back to `completedAt`" is cut, in favor of R1's "no-real-start entries go in the snapshot". With R1's rule, the fallback could only move an entry from the snapshot to NEW (an entry with no start that completed after `T`), which is the fail-open direction. R1's rule already covers the case R2 raised.
- DEC-J: R1's "only `github.com/<slug>/actions/` URLs count as NEW" applied to the DATED cut only, not inside `_ci_checks_wait` (round-2 call). Rationale: putting the rule in the wait would change SPEC-360's fresh-label path, whose T12 ends the wait on new third-party checks. Round 3 amends it (DEC-S): the rule moves into the wait behind `CI_NEW_SCOPE`, set only on the label-on paths, so the absent-label path and T12 stay as they are.
- DEC-K: R2's "add an rc 3 arm to the carry" is folded as a catch-all arm: every sync rc other than 0 and 1 prints one `SKIP land` line. The carry passes no pinned oid (its own post-wait head check and the re-gate's head check cover a moved head), so rc 3 cannot occur there today, and the catch-all keeps any later code fail-closed. Round 3 rewords the line (DEC-Y).
- DEC-L: R1's "apply CLEAN when `CI_WAIT_END != 0`" is folded with the existing message text for `NONEW`, so T3b's assert stands. The new reach is the unreadable-last-read end (T16, NC16); round 3 gives that end its own reason text (DEC-W).
- DEC-M: R1's slug validation and R2's "owner/name from the PR's own url" fold together: the slug comes from the PR's `url` field, never from the origin remote (which can be an ssh host alias), and must match the github.com PR url pattern. Anything else refuses (fail closed); a GHES repo with the label on is Out of scope.
- DEC-N: R1's `<=` cut is folded: an entry that started in the same second as `T` joins the snapshot. Control: NC12. R1's "no-real-start entries go in the snapshot" is folded (Boundaries). Control: NC13.
- DEC-O: R2's "test the settle defaults" is read as the head wait's bound under a non-zero `KIT_WRAP_SETTLE_SECS`, which the harness default of 0 never exercises: L7 and L8 run at 4s and assert the read counts (3 and 4). Change 6 of round 1 is cut (DEC-H), so no other settle default changes.
- DEC-P: R4's test fixes fold: the could-not-re-read refusal gets T14; the head appearing on a later read gets L8; ci-gated's count moves to the stub's `cw_views` counter, because `grep -c '^pr view 42 '` also counts the post-merge `state,mergeCommit` read and passes with no re-gate; L6 adopts the operator's open PR with the branch already at the tip, the real re-run shape; Task B splits into B1 (the sync and land's call site) and B2 (the land re-gate).
- DEC-Q: R5's T13 fix folds: T13 serves `EV_CI`, is renamed for what it now shows, and asserts 26 reads. The whole-rollup snapshot becomes rejected alternative 4.
- DEC-R: Round-3 critical (R3, reproduced by the lead on this repo): `gh label list --search <no match> --json name` exits 0 and prints zero bytes, not `[]`. Round 2's probe returned 2 on "not a JSON array", so every repo without a `ci` label would have refused `land` and `merge --apply`. Fix: the probe captures gh's output and exit code. A non-zero exit, or non-empty output that is not an array, returns 2. Exit 0 with empty output means "no `ci` label" and returns 1, ungated, as today. The stub's no-match default now prints nothing, matching real gh, and `GH_STUB_LABELS='[]'` keeps the empty-array mode. Tests: T17 (zero bytes), T17b (`[]`), L11; control NC18, whose red set includes every existing unlabeled case. Grounding holds the live sample. The Problem section lists the fail-open probe as gap 4, now narrowed to the two real failure shapes.
- DEC-S: Round-3 warning 1 (five reviewers): the wait could end on a fast non-ci check (DCO, a lint app) that registers after the snapshot and before the label's `ci` run, on the RE-ADD path, the empty-rollup path and the DATED path. A snapshot cannot stop this, because the check is not in it yet. Fix: `_ci_label_sync` sets `CI_NEW_SCOPE` to the PR's slug on every label-on path, and `_ci_checks_wait` counts as NEW only an entry with a non-empty `workflowName` and a url under `https://github.com/<slug>/actions/`. Both halves are needed: the live sample shows app checks with an empty `workflowName` and an Actions url of another repo with an empty `workflowName` (Grounding). The dated snapshot loses its url-prefix arm, since the wait carries the Actions test for every label-on path. The absent-label path keeps SPEC-360's rule (its T12). This changes `_ci_checks_wait` and `CI_JQ_DEFS` by one filter and one def. Tests: T18, E1 (`forged`, `xrepo`); controls NC14, NC19, NC20. The fixtures in the T13 family, L6, T4, E3, E5 and E7 move to the Actions-shaped `CA_OLD`, because a `CW_OLD` entry can never be NEW under a scope. The Failure modes row that overclaimed ("the push-started checks are in the snapshot, so only the new ci run ends the wait") is corrected: another Actions workflow that registers late can still end the wait (Out of scope).
- DEC-T: Round-3 warning 2 (R1 W1): `cmd_merge`'s union re-merge pushes a head wrap made itself, so the DATED path could read the push-started checks as the label's. Same rule as DEC-E: `cmd_merge` passes `moved` = 1 to the sync when its re-merge set `head_oid` from `REMERGE_OID`, with an empty pinned oid (the settle before it already waited for the pushed head). The squash fallback opens a new PR with no label, so it does not set `moved`. Test: RM1; control NC24.
- DEC-U: Round-3 warnings 3 and 5 (R1 W2, R3 W2, R2 W2): the residual row and the recovery table now name `land`, and name the two shapes where `moved` reads 0 (a hand push, and a `land` re-run after a push that stopped before the re-add). The recovery for both is to remove the label by hand and re-run. The BEHIND recovery adds `git pull --ff-only` in the worktree after `gh pr update-branch`, so the next `land` does not hit `PUSH REFUSED`. No behavior change.
- DEC-V: Round-3 warning 4 (R1 W4): a DATED or RE-ADD jq that yields no output stops the sync with rc 2 and `could not build the check snapshot of #<n>` before any label edit. It never falls back to `[]`. The label-absent branch keeps SPEC-360's fallback. Tests: E6 (RE-ADD), E6b (DATED); control NC21.
- DEC-W: Round-3 warning 6 (R2 W3, R3 W4): the CLEAN clause gives a separate reason when the wait did not end `NONEW`, because "no check reported after the ci label went on" is false for an unreadable last read or a pending-bound end. `NONEW` keeps its text, so T3b stands. Change 1's claim that the pending case "refuses one clause earlier" is corrected: it holds only while the run is still pending at the re-gate read. T16 and AC24 take the new text.
- DEC-X: Round-3 warning 7 (R2 W4, R3 W4): one behavior for an events read that exits 0 with zero bytes. It is an empty history: `jq -s` reads empty input as `[]`, `T` comes back empty, and the sync RE-ADDs. Failures (non-zero exit, unparseable text) refuse. Stated once in the Picture, the Change, C8 and the Failure modes. Test: E7; control NC22.
- DEC-Y: Round-3 warning 8 (R6 W2, R5 W3, R2 W5): the carry's catch-all sync arm prints its own line, `the ci label could not be set or read`, because "unlabeled on a ci-gated repo" is wrong for a failed probe or read. `_ci_regate` returns 3 for a CONFLICTING verdict, keyed on `_pr_gate`'s own output `SKIP not mergeable (CONFLICTING)`, so the carry passes through on the return code and never matches composed reason text. DEC-G, T13e and NC8 follow. Test: T19; control NC23.
- DEC-Z: Round-3 warning 9 (R4 W1, W2): Task D splits. D1 holds the fail-closed plumbing and the RE-ADD arms, with DATED left on today's fallthrough (so T13 stays at 20 reads until D2). D2 holds the DATED cut and the cases that need it (L6, E1, E2, E6b, T13c, T13 at 26, T13d). Helper ownership: `ld_full` in B2; `cw_dated`, `EV_CI`, `CA_OLD`, `CW_PUSH`, `CW_PUSH_CI`, `CW_DCO`, `CW_DCO_CI` in D1; `EV_CI2`, `EV_CI_DOCS`, `CA_GREEN`, `CA_E1` in D2. L8 moves to B2, because its count of 4 includes the re-gate read that B2 adds. The D-task split and fixture ownership are superseded by DEC-AK.
- DEC-AA: Round-3 warning 10 (R5 W2): the label-on decision is extracted into `_ci_label_date <slug> <pr> <detail> <moved>`, returning `READD <reason>` or `DATED <T>`. Adopted, because it adds no case: every test already reaches it through the sync, and the negative controls mutate lines inside it. It leaves the sync with the probe, the read, the head wait and the actions, and gives the four RE-ADD conditions one home.
- DEC-AB: Round-3 warnings 11 and 12 (R3 W5, W6, R2 W5, R1 W5): NC2's T13b trace counts 12 reads, not 13. A committer clock ahead of GitHub's re-adds on later passes, one extra `ci` run, and fails safe. `commits` is capped at 100, so a longer PR re-adds every pass, also safe. The slug check rejects a repo name made only of dots (E5b, NC25).
- DEC-AC: Round-4 warning 1 (R1, R3, R4): the sync clears `CI_NEW_SCOPE` on entry, stated in Change 5, the Picture and the Interfaces table. The carry calls the sync once per branch in one shell, so a label-absent carry after a label-on carry would inherit a stale scope. Test: T20 (AC34), two carries with the second label-absent, asserting the unscoped wait through the read count (24). Control: NC26 (26 reads). T20 lives in D2, because carry 1's 13 reads need the DATED cut.
- DEC-AD: Round-4 warning 2 (R2 to R5): the label-on rules assume the label-started CI is a GitHub Actions workflow of this repo. The assumption is stated in Change 6, C12, Boundaries and Out of scope. A Failure modes row names the cost for Prow, Jenkins, Netlify and CircleCI StatusContexts: a grace hold, then the CLEAN rule, on every label-on pass. The Out-of-scope claim that the inner merge refuses only on a changed state is corrected: R3 traced an autoland `apply` that exits 2 on a non-Actions repo. The optional StatusContext case on the DATED path is skipped: E1's `forged` entry already is one (a StatusContext with a `targetUrl`, no `workflowName`, dated after `T`), and NC20 pins it.
- DEC-AE: Round-4 warnings 3 and 5 (R1 to R4): the claim that push-started checks are in the snapshot is narrowed in Problem gap 3, C1, C9, the Failure modes row for `land`'s push and Recovery row 1. It holds only for runs that registered before the sync's read; a fast `synchronize` workflow that completes before the `ci` run registers is the named residual. C1 and a new Failure modes row also state that a first, label-absent land keeps SPEC-360's early-end race. No settle is added (no redesign).
- DEC-AF: Round-4 warning 4 (R2, R5, R6): a scoped wait that ends `NONEW` with only non-Actions entries and an empty snapshot skips the CLEAN clause, and `_pr_gate` decides, as on SPEC-360's empty-rollup path. Named in Boundaries and the T18 Failure modes row. The scoped `NONEW` refusal now reads `no Actions run of this repo reported after the ci label went on, ...`; `_ci_regate` picks it from `${CI_NEW_SCOPE:-}`. Verified against the tests: T3b's sync reads labels `[]`, so it takes the absent-label path with the scope empty and keeps today's text, as do L4 and T13b (AC13). E1, AC14 (T13c), L6 and E4 take the scoped text, and NC19's trace gains their three text asserts.
- DEC-AG: Round-4 warning 6 (R1): "No GitHub field dates a push" was false. The activity API (`repos/<o>/<r>/activity?ref=refs/heads/<branch>&activity_type=push`) returns push timestamps with the `after` oid (Grounding, sampled live). It is listed as rejected alternative 5 for the dated path, as future hardening. The Out-of-scope rationale now says the PR record carries no push time.
- DEC-AH: Round-4 warning 7 (R1): the probe's stderr line is `could not read the repo labels for #<n>`. It names the PR number, never `$url`, because `_origin_url` returns the raw remote url and that can carry userinfo. L10 and T15 assert the new text.
- DEC-AI: Round-4 warning 8 (R3): the events read passes `--hostname github.com`, matching the slug check. Verified on gh 2.101.0: the flag wins over an exported `GH_HOST`. The minimum gh that emits `statusCheckRollup[].workflowName` is v2.14.0 (cli/cli PR 5919, compare API: v2.13.0 behind, v2.14.0 ahead). Boundaries names it, and a Failure modes row covers an older gh (every entry non-Actions: grace hold, then the CLEAN rule).
- DEC-AJ: Round-4 warning 9 (R2): Recovery row "checks pending past the carry bound" now says to re-run after the runs complete, since a `ci` run still queued with the zero `startedAt` joins the dated snapshot and never counts as NEW. L11 no longer says "the plain pending wait": on sync rc 1 `cmd_land` runs no wait and no re-gate, so L11 serves no PR read and asserts `view-42` count 0.
- DEC-AK: Round-4 warning 10 (R4, R6): Task D splits three ways, each within one worker. D0 is the wait scope (four code sites: `def actions`, the wait filter, the entry clear, the slug check with the scope at the top of the label-on branch), with T18, E5, E5b and the Actions-shaped fixture moves that keep every existing label-on case green under the scope. D1 is the RE-ADD plumbing, with `DATED` falling through to `[]`. D2 is the DATED cut, with L6, E1, E2, E6b, T13 at 26, T13c, T13d and T20. Fixture ownership: `EV_CI`, `CA_OLD`, `CW_DCO`, `CW_DCO_CI`, `cw_dated` in D0; `CA_GREEN` (RM1 needs it), `CW_PUSH`, `CW_PUSH_CI` in D1; `EV_CI2`, `EV_CI_DOCS`, `CA_E1` in D2. The stray `D2:` tag on the `CW_PUSH` usage note is dropped.
- DEC-AL: Round-4 warning 11 (R4, R6): the probe's no-match rule reads "empty or whitespace-only output" in every place the rule is stated (Problem, Picture, Change 5, C7, Interfaces, Approaches, Failure modes, AC28, the test plan). The Grounding sample keeps "stdout 0 bytes", because that is the observed fact. Grounding gains the live StatusContext sample from a Prow-gated repo: no `detailsUrl`, no `workflowName`.
