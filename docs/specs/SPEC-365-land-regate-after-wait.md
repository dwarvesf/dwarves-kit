# Spec: land re-gates after the ci wait, and the carry hands its snapshot to the merge

Generated: 2026-09-29
Status: DRAFT
Lane: full (lib/ enforcement surface: the merge gate of `wrap land` and of the carry autoland; changes what `wrap land` promises on a label-gated repo)
Type: bug
File: `docs/specs/SPEC-365-land-regate-after-wait.md`
References: `docs/specs/SPEC-360-wrap-ci-label-wait.md` (the two gaps its Out of scope and Failure modes name); `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, `_pr_detail_settled`, `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the "merge --apply: the ci label gate", "land: the ci label gate" and autoland ci sections); `commands/wrap.md` (the `land` paragraph and step 10's "Never `wrap land` here" line); `docs/implementation-notes/land-regate-after-wait.md` (deltas)

## Problem

SPEC-360 made `wrap` wait for the runs a fresh `ci` label starts. It left two gaps, both named in its Out of scope and Failure modes.

1. `cmd_land` syncs the label and waits, then calls `gh pr merge` with no gate. A label-started run that completes red still lands. A run still queued when `KIT_WRAP_CARRY_CHECKS_SECS` runs out also lands. `--match-head-commit` pins the head, and nothing reads the checks.
2. The CLEAN rule does not reach autoland. The rule says: after a wait that ended `NONEW` with a non-empty pre-label snapshot, `cmd_merge` merges only on `mergeStateStatus == CLEAN`. `_autoland_carry` runs the sync and the wait itself, then lands through `cmd_merge --apply --pr` in a subshell. That inner merge runs its own sync. The label is on by then and the rollup is not empty, so the sync records `CI_PRELABEL_KEYS='[]'`. With an empty snapshot every non-SKIPPED pre-label entry reads as NEW, the inner wait ends on its first read with state `0`, and the CLEAN rule stays off. A carry PR whose label started nothing merges on an `UNSTABLE` state on checks that predate the label.

## Picture

```
cmd_land                                   _autoland_carry
  push, open or adopt PR #n                  open or adopt PR #n
  _ci_label_sync  -> CI_PRELABEL_KEYS        _ci_label_sync  -> CI_PRELABEL_KEYS (snapshot S)
  _ci_checks_wait -> CI_WAIT_END             _ci_checks_wait -> holds grace once
        |                                    head check (want)
        v                                          |
  NEW: _ci_regate url n def tip                    v   subshell: CI_CARRY_OID=want, CI_CARRY_KEYS=S
    head != tip        -> refuse             cmd_merge --apply --pr n
    _pr_gate != OK     -> refuse               eligibility gate, head_oid
    NONEW + S + !CLEAN -> refuse               _ci_label_sync -> CI_PRELABEL_KEYS = []  (label on)
        |                                      NEW: head_oid == CI_CARRY_OID and own keys [] and S != []
        v                                           -> CI_PRELABEL_KEYS = S, grace 0
  gh pr merge --match-head-commit tip          _ci_checks_wait (grace 0: one NONEW read ends it)
                                               _ci_regate url n def head_oid   (same helper)
                                               gh pr merge
```

A refusal on either side prints one line, merges nothing, and leaves the PR open.

## Change

1. **`_ci_regate <url> <pr> <def> <pinned-oid>`**, a new helper that holds `cmd_merge`'s post-wait block unchanged. It reads the PR once through `_pr_detail_settled "$url" "$pr"`, then checks in this order. The head must equal `<pinned-oid>`, else `head moved to <short> during the check wait`. `_pr_gate` must return `OK`, else `<verdict without SKIP> once the ci label's checks ran`. When `CI_WAIT_END` is `NONEW` and `CI_PRELABEL_KEYS` is not `[]`, `mergeStateStatus` must be `CLEAN`, else `no check reported after the ci label went on, and merge state <S> is not CLEAN`. On a refusal it prints the reason on stdout and returns 1. On OK it prints nothing and returns 0.
2. **`cmd_merge`** replaces its inline post-wait block with `_ci_regate`. Its three refusal lines stay byte-identical: `FAILED merge #<n>: <reason>; left open`, exit 2.
3. **`cmd_land`**, in the sync's return-0 branch only, calls `_ci_regate "$url" "$n" "$def" "$tip"` after `_ci_checks_wait`. On a refusal it prints `     MERGE FAILED #<n>: <reason>; left open` on stderr and returns 2 before `_gh_merge_retry`. Nothing is merged, deleted or removed. The PR, the pushed branch, the worktree and the local branch all stay. The return-1 branch (no `ci` label) and the return-2 branch (the label could not be set) do not change.
4. **`_ci_checks_wait <url> <pr> [<grace-secs>]`** takes an optional third argument for the grace bound. The default is `KIT_WRAP_CI_GRACE_SECS`. The three existing calls pass nothing.
5. **The carry handoff.** `_autoland_carry` runs its merge as `(CI_CARRY_OID="$want"; CI_CARRY_KEYS="$CI_PRELABEL_KEYS"; cmd_merge --apply --pr "$n" "$repo")`. The assignments sit inside the subshell, so they never outlive the call. In the sync's return-0 branch, after its own `_ci_label_sync`, `cmd_merge` adopts the handoff when all three hold: `CI_CARRY_OID` is non-empty and equals `head_oid`; its own sync left `CI_PRELABEL_KEYS` at `[]`; and `CI_CARRY_KEYS` is not `[]`. Adopting means two separate lines: `CI_PRELABEL_KEYS="$CI_CARRY_KEYS"`, then a grace of 0 passed to `_ci_checks_wait`. The carry already held the grace window on this head, so the inner wait makes one read. A `NONEW` read ends it at once with `CI_WAIT_END=NONEW` and the snapshot in place, and `_ci_regate` applies the CLEAN rule. A pending read still waits on the carry bound, as today. A new entry ends the wait with state `0`, as today.
6. **Top-level reset.** Beside the other ci globals, `wrap.sh` sets `CI_CARRY_OID=''` and `CI_CARRY_KEYS='[]'` at load. An exported variable in the operator's shell therefore never reaches a plain `wrap merge`.
7. **Comments and docs.** The comment above `cmd_land` names the re-gate. The comment above `_autoland_carry` names the handoff. The comment above `_ci_checks_wait` names the third argument. T13's comment in `tests/test-wrap.sh` credits the grace-0 handoff with the single hold; the sync's reset no longer carries that. `commands/wrap.md` line 104 (the `land` paragraph) gains the re-gate. Line 323 changes "because `land` merges right after it opens a PR and never reads the checks" to "because `land` reads the checks only on a repo that gates on the `ci` label".

Nothing else changes. The env knobs keep their names and defaults. `_pr_gate`, `_ci_label_sync` and `CI_JQ_DEFS` stay as they are.

## Contract changes

These are changes to what `wrap land` and the carry autoland promise. The operator must accept each one before the build starts.

| # | Surface | Before | After |
|---|---|---|---|
| C1 | `wrap land`, repo gates on `ci` (sync returned 0) | merges once the wait ends, whatever the checks read | merges only when `_ci_regate` returns OK. Otherwise it prints `MERGE FAILED #<n>: <reason>; left open` and exits 2, and the PR, the pushed branch, the worktree and the local branch stay |
| C2 | same | a PR GitHub would merge in state `BEHIND`, `UNKNOWN` or `UNSTABLE`-with-red-checks, with `CHANGES_REQUESTED`, or with `mergeable` still `UNKNOWN` merges | `_pr_gate` refuses each of them, as `wrap merge --apply` already does. `BEHIND` is the one that bites in practice: `land` no longer merges a PR that is behind its base on a label-gated repo, even where branch protection allows it |
| C3 | same | no read after the wait | one `_pr_detail_settled` read, up to `KIT_WRAP_SETTLE_SECS` (default 60s) while `mergeable` reads `UNKNOWN` |
| C4 | autoland, label-gated repo, the carry's wait ended `NONEW` with a non-empty snapshot | merges on any state `_pr_gate` allows (`CLEAN`, `HAS_HOOKS`, `UNSTABLE`) | merges only on `CLEAN`. Otherwise the inner merge refuses with the existing non-CLEAN line and returns 2, and the carry reports it as a failure (`FAILURES=1`, `apply` exits 2), the path every SPEC-360 re-gate refusal in autoland already takes |

Recovery after a C1 refusal: once the checks are green, run `wrap land <worktree>` again. The push is a no-op, the PR is adopted, the label is on with a non-empty rollup, so the sync records no snapshot, the wait makes one read, and the re-gate decides. `wrap merge --apply --pr <n>` also merges it, but it leaves the worktree for a later wrap.

## Design

### Interfaces

| Surface | Before | After |
|---|---|---|
| `_ci_regate <url> <pr> <def> <pinned-oid>` | none | new. Stdout is the refusal reason, rc 1. Empty stdout and rc 0 mean OK. It reads `CI_WAIT_END` and `CI_PRELABEL_KEYS` |
| `_ci_checks_wait <url> <pr> [<grace>]` | two args | an optional third: the grace bound, default `KIT_WRAP_CI_GRACE_SECS` |
| `CI_CARRY_OID`, `CI_CARRY_KEYS` | none | new globals, reset at load; set only inside the carry's merge subshell, read only by `cmd_merge` |
| `cmd_merge` refusal lines | three post-wait lines | same text, now built from `_ci_regate`'s reason |
| `cmd_land` refusal lines | `MERGE FAILED #<n>: the ci label could not be set` | adds `MERGE FAILED #<n>: <reason>; left open` with the three `_ci_regate` reasons |
| exit codes | `land` 2 on a merge failure | same 2 on a re-gate refusal |

### Approaches considered

For `land`:

1. **One helper shared with `cmd_merge` (chosen).** The post-wait block is an enforcement rule, and two copies of it would drift. The kit's "three uses before an abstraction" rule yields to that. The helper is the block moved as-is, so `cmd_merge`'s tests pin it before `land` uses it.
2. Route `land` through `cmd_merge --apply --pr` (rejected). `cmd_merge` needs the PR to be the operator's own and eligible on its first gate. It runs the union re-merge and the squash fallback, and it pins the head from its own read, while `land` pins the tip it pushed. That changes far more than the gap.
3. Gate `land` on every repo, not only label-gated ones (rejected here). Without the label, `land` never waited, so "re-gate after the wait" has no wait to follow. It would change `land`'s promise on every repo. Named under Out of scope.

For the carry handoff:

1. **Snapshot plus grace 0 inside the subshell (chosen).** The inner wait recomputes its state from a fresh read against the real snapshot, so a check that registered late still counts. The single-hold property of T13 holds, because the grace the carry already spent is not spent again.
2. Hand off `CI_WAIT_END` and skip the inner wait (rejected). The carried state is up to one subshell start old, and a skipped wait drops today's second pending hold on the carry bound, a behavior change nobody asked for.
3. Hand off the snapshot alone (rejected). The inner wait holds the grace window a second time on a `NONEW` PR, which is the double hold T13 exists to forbid.
4. Stop `_ci_label_sync` from resetting `CI_PRELABEL_KEYS` when the label is already on (rejected). The reset is what keeps a plain `wrap merge` on a pre-armed PR from inheriting a stale snapshot. The snapshot would also leak between the carry's PRs.

### Boundaries

- The handoff is bound to one head. `CI_CARRY_OID` must equal the head `cmd_merge` pinned, so a push between the carry's head check and the inner eligibility read, or a squash-fallback replacement PR, gets no snapshot and no grace-0 wait. Without that bind, a head re-labeled because it moved would skip its grace hold with an empty rollup and merge on `CLEAN`.
- An empty carried snapshot (`[]`) is never adopted. That covers a carry that found the label already on, and a carry that re-added it. The inner merge behaves exactly as today.

## Failure modes

| Failure | Caller | Behavior |
|---|---|---|
| The label-started run completes red | `land` | the re-gate picks the red run as latest for its name and refuses; PR open, worktree kept, exit 2 |
| The run is still queued at the carry bound | `land` | the pending entry sorts last and trips the checks clause; refuses |
| The head moved during the wait | `land` | refuses with `head moved to <short>`; `--match-head-commit` would have refused later anyway, and now the line names it |
| GitHub still serves the pre-push head on the re-gate read (an adopted PR, a wait that ended on its first read) | `land` | fail-closed: refuses as head moved; re-running `land` recovers. `_pr_detail_settled` has no prior oid to wait past, because `land` never reads the adopted PR's old head |
| No new entry, state not CLEAN | `land` | refuses with the non-CLEAN line |
| No new entry, state not CLEAN | autoland | the inner merge refuses with the non-CLEAN line; the carry records a failure |
| `mergeable` stays `UNKNOWN` past `KIT_WRAP_SETTLE_SECS` | `land` | `SKIP not mergeable (UNKNOWN)`; refuses |
| The re-gate read fails (not JSON) | `land` | `_pr_gate` prints nothing, so the verdict is not OK; refuses. The head reads empty, so the reason is `head moved to ` with an empty short sha, the same text `cmd_merge` prints today |
| A push lands between the carry's check and the inner read | autoland | no handoff (head bind); the inner merge runs today's path on the new head |
| The repo has no `ci` label | `land`, autoland | unchanged: no re-gate in `land`; the carry's plain pending wait, then `cmd_merge`'s own gates |

## Acceptance criteria

- AC1: `wrap land` on a label-gated repo whose label-started run completes red refuses with `MERGE FAILED #<n>: checks are pending or failing once the ci label's checks ran; left open`, exits 2, and makes no `pr merge` call. The worktree directory and the local branch still exist, and no `pr close` call is made.
- AC2: `wrap land` on a label-gated repo whose label-started run is still queued at `KIT_WRAP_CARRY_CHECKS_SECS` (live shape: zero `completedAt`, empty `conclusion`, real `startedAt`) refuses the same way.
- AC3: `wrap land` refuses with `head moved to <short> during the check wait; left open` when the re-gate read shows a head other than the pushed tip.
- AC4: `wrap land` after a `NONEW` grace expiry with a non-empty snapshot on `UNSTABLE` refuses with the non-CLEAN line.
- AC5: `wrap land` on a label-gated repo with green new checks and `mergeStateStatus: BEHIND` refuses with `merge state BEHIND (an unresolved thread or a blocked merge) once the ci label's checks ran; left open` (contract change C2).
- AC6: `wrap land` on a repo without the `ci` label makes no `_pr_detail` read (`--json number,title,body,...`) and merges as before.
- AC7: The existing land ci cases (ci-gated, T6, ci-armed, ci-stale) pass with full-detail fixtures on the re-gate read. T6 shows exactly 4 rollup reads from the sync and the wait before the re-gate read, and the merge follows the 5th.
- AC8: Autoland on a label-gated repo whose carry PR holds only pre-label checks, with no new entry and state `UNSTABLE`, makes no `pr merge 42` call and prints `FAILED merge #42: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN`. `apply` exits 2.
- AC9: T13 still passes with exactly 18 reads of #42: the handoff keeps the single grace hold.
- AC10: `cmd_merge`'s existing ci-wait cases (T1 to T5, T3b, T8 to T12) pass unchanged, so its refusal text and read counts did not move.
- AC11: `bash tests/test-wrap.sh` and `bash tests/test-meta.sh` pass.
- AC12: Each negative control below turns red exactly the named `chk` lines, read from the failing `chk` names in the output, not only the exit code.

## Test plan

Every case goes in `tests/test-wrap.sh`, beside the "land: the ci label gate" section and T13. The existing `gh` stub serves read k of `pr view <n>` from `GH_STUB_PR_<n>_<j>` for the highest set j <= k (j >= 2), else from `GH_STUB_PR_<n>`. A `--json state,mergeCommit` read neither counts nor steps. The count lands in `$GH_STUB_CALLS.view-<n>`. `$TMPD/nosleep` stubs `sleep`, and the harness exports `KIT_WRAP_SETTLE_SECS=0`, so the re-gate is exactly one read. Land cases use PR 42 (`GH_STUB_CREATE_NUM=42`) and a fresh `build_land` fixture each.

Fixtures reuse SPEC-360's live-shaped rollups: `CW_OLD` (`test` SKIPPED on `.../job/1`, `preview` SUCCESS on `.../job/2`, both completed 2026-09-28), `CW_RUN`, `CW_QUEUED` (zero `completedAt`, empty `conclusion`, real `startedAt`, `.../job/3`), `CW_GREEN`, `CW_RED`. "Full detail at tip" means the whole record `_pr_detail` reads: `headRefOid` = the land tip, `baseRefName: main`, `mergeable: MERGEABLE`, the named `mergeStateStatus`, `reviewDecision: APPROVED`, labels `[ci]`, `isDraft: false`, and the named rollup. A new helper builds it, as `cw_full` does with `PR50_OID`.

| Case | Setup (reads served) | Assert |
|---|---|---|
| L1 AC1 | 1 sync: labels `[]`, `CW_OLD`. 2 wait: labels `[ci]`, `CW_OLD`. 3 wait: `CW_RUN`. 4 onward: full detail at tip, UNSTABLE, `CW_RED` | exit 2; the refusal line; no `pr merge 42`; no `pr close`; worktree dir and branch `feat/land` exist; `view-42` count is 5 |
| L2 AC2 | `KIT_WRAP_CARRY_CHECKS_SECS=10`. 1 sync: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, CLEAN, `CW_QUEUED` | exit 2; the refusal line; no `pr merge 42`; `view-42` count is 4 |
| L3 AC3 | 1 sync: labels `[]`, `CW_OLD`. 2 onward: full detail, CLEAN, `CW_GREEN`, `headRefOid` `3333333333333333333333333333333333333333` | exit 2; `MERGE FAILED #42: head moved to 3333333 during the check wait; left open`; no `pr merge 42` |
| L4 AC4 | `KIT_WRAP_CI_GRACE_SECS=20`. 1 sync: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, UNSTABLE, `CW_OLD` | exit 2; `MERGE FAILED #42: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN; left open`; no `pr merge 42`; `view-42` count is 5 |
| L5 AC5 | 1 sync: labels `[]`, `CW_OLD`. 2 onward: full detail at tip, BEHIND, `CW_GREEN` | exit 2; the BEHIND refusal line; no `pr merge 42` |
| ci-fuzzy AC6 | unchanged fixture | add: no `--json number,title,body` call for #42 |
| ci-gated AC7 | read 3 becomes full detail at tip, CLEAN, `pr-check` SUCCESS | unchanged asserts pass |
| T6 AC7 | reads 3 and 4 become full detail at tip, CLEAN, with `CW_RUN` and `CW_GREEN` | the merge follows the 5th rollup-bearing read; the 5th read is the `_pr_detail` field list; merged |
| ci-armed, ci-stale AC7 | the read after the sync becomes full detail at tip, CLEAN, `pr-check` SUCCESS | unchanged asserts pass |
| T13b AC8 | as T13 (`KIT_WRAP_CI_GRACE_SECS=20`, the carry PR on `CW_OLD`, labels `[ci]` from read 2), with `mergeStateStatus: UNSTABLE` on both fixtures | apply exits 2; the non-CLEAN refusal line for #42; no `pr merge 42` |
| T13 AC9 | unchanged | 18 reads of #42 |

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

Pending CheckRuns carry the zero `completedAt`, an empty `conclusion` and a real `startedAt`, the shape of `CW_RUN` and `CW_QUEUED`. The PR record `_pr_detail` reads, sampled the same way (`gh pr view 163486 -R rust-lang/rust --json headRefOid,baseRefName,mergeable,mergeStateStatus,reviewDecision,isDraft,labels`), returns `{"headRefOid":"d8ff9a0c6611…","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","isDraft":false,"labels":[…]}`. Those are the fields and value spellings the full-detail fixtures use. A live `BEHIND` sample was not taken: the one list call that could have found one returned HTTP 504. `BEHIND` is a documented `mergeStateStatus` value, and `_pr_gate` already names it by exclusion.

**Autoland read path, from the code.** `_autoland_carry` calls `_ci_label_sync` (wrap.sh:1376), then `_ci_checks_wait` (1378), then the subshell merge (1398). `cmd_merge` calls `_ci_label_sync` again (2260). That sync resets `CI_PRELABEL_KEYS='[]'` (1262), takes neither edit branch with the label on and a non-empty rollup, and returns 0. `_ci_checks_wait` (2263) then computes NEW against `[]`.

**Dry traces of the negative controls** (each mutation is applied after the feature commit and restored before the next):

NC1: the `cmd_land` call to `_ci_regate` replaced by `:` (no re-gate).
- L1: the sync is read 1 and snapshots `[test@…/job/1, preview@…/job/2]`. Wait read 2 (`CW_OLD`) is `NONEW`, read 3 (`CW_RUN`) is pending, read 4 (`CW_RED`) has pending 0 and NEW `test@…/job/3`, so the wait ends. With no re-gate, `_gh_merge_retry` runs and the stub merges. Red: "L1: exits 2", "L1: no pr merge", "L1: 5 reads" (4 reads).
- L2: read 2 is pending, read 3 is pending with waited=10 and ends the wait, then the merge runs. Red: exit, no pr merge, 4 reads (3).
- L3: read 2 has pending 0 and NEW job/3, then the merge runs, because the stub ignores `--match-head-commit`. Red: exit, refusal line, no pr merge.
- L4: reads 2, 3 and 4 are `NONEW` and the grace runs out at 20, then the merge runs. Red: exit, refusal line, no pr merge, 5 reads (4).
- L5: read 2 has pending 0 and NEW job/3, then the merge runs. Red: exit, refusal line, no pr merge.
- T6: the merge follows the 4th rollup read. Red: "the merge follows the 5th read". ci-gated, ci-armed and ci-stale stay green, because a missing re-gate only means one read fewer.

NC2: `cmd_merge`'s `CI_PRELABEL_KEYS="$CI_CARRY_KEYS"` line deleted (grace 0 kept).
- T13b: the carry's sync snapshots `CW_OLD`'s keys, and its wait holds reads 2 to 4 (`NONEW`, grace 20). In the subshell, `cmd_merge`'s sync sees labels `[ci]` and a non-empty rollup, so it records `[]`. With the handoff line gone, the inner wait's one read computes NEW against `[]`, `preview@…/job/2` SUCCESS counts, and the state is `0`. `_ci_regate` passes on `UNSTABLE`, because the CLEAN rule needs a non-empty snapshot, and the merge runs. Red: "T13b: exits 2", "T13b: refusal line", "T13b: no pr merge 42". T13 stays green: its inner wait is one read either way.

NC3: the grace-0 argument dropped (the adopted snapshot kept).
- T13: the inner wait reads `NONEW` against the adopted snapshot and holds the default grace (20 in the case) for 3 reads instead of 1 in each carry merge. Red: "T13: 18 reads". T13b stays green: after the longer hold, the CLEAN rule still refuses.

NC4: the head bind dropped (`CI_CARRY_OID` compare removed). Every stub case keeps `head_oid == want`, so no case can turn red. This control is not run. The bind is covered by review, and the implementation note records why.

## Negative control

After the feature commit, one run per control through `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`, each restored before the next: NC1, NC2 and NC3 as traced under `## Grounding`. The record quotes the failing `chk` names from each run and checks them against the traced lists. A suite exit code alone does not pass a control. The exact `sed` patterns are set at build time against the final lines. The handoff's two adopt lines stay separate so NC2 and NC3 can each remove one.

## Out of scope

- `land` on a repo without the `ci` label still merges with no gate (sync returned 1). It never waits there, so there is no wait to re-gate after, and a gate there would change `land` on every repo.
- The autoland exit-code asymmetry. A first-pass eligibility refusal in the inner merge leaves the PR open with `apply` exit 0. A post-wait re-gate refusal, including the new C4 one, returns 2 and sets `FAILURES`. That predates this change, and this spec keeps it.
- The residual races SPEC-360 names: two workflows on one event, the read-to-edit window, `needs:` chains, StatusContext key shifts, delayed webhooks.
- A stale-head read on `land`'s re-gate, handled fail-closed as listed under Failure modes.

## Verification

Iterate with `bin/test-affected`. At the end, run `bash tests/test-wrap.sh` in full once, with L1 to L5, T13b and the updated land cases present, plus `bash tests/test-meta.sh`, then the negative controls above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap land regate after wait"` names it.

## Tasks

- [ ] Task A: extract `_ci_regate` from `cmd_merge` with no behavior change, and add the optional grace argument to `_ci_checks_wait` (`lib/wrap/wrap.sh`). Check: the existing merge ci-wait cases pass unchanged.
- [ ] Task B: the `cmd_land` re-gate (`lib/wrap/wrap.sh`); cases L1 to L5; full-detail fixtures for ci-gated, T6, ci-armed and ci-stale; the AC6 assert on ci-fuzzy (`tests/test-wrap.sh`).
- [ ] Task C: the carry handoff, meaning the subshell assignments in `_autoland_carry`, the adopt condition in `cmd_merge`, and the top-level reset (`lib/wrap/wrap.sh`); case T13b and T13's comment (`tests/test-wrap.sh`).
- [ ] Task D: the comments above `cmd_land`, `_autoland_carry` and `_ci_checks_wait`; `commands/wrap.md` lines 104 and 323; regenerate `docs/FEATURES.md` if `feature-registry.sh check` reports drift.
