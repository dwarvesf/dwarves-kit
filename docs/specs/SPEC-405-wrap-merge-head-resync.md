# Spec: wrap merge resyncs a stale PR head with one close and reopen
Generated: 2026-10-16
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a close whose reopen fails leaves the operator's own PR closed, and no later wrap run lists a closed PR, so it drops off every board silently)
References: `lib/wrap/wrap-merge.sh:516-548` (the post-push re-gate in `cmd_merge`; the resync slots in between its settle read and its head check); `lib/wrap/wrap-merge.sh:70-87` (`_pr_detail_settled`; reuse as is for the re-read after the reopen); `lib/wrap/wrap-common.sh:501-570` (`_mvp_trap` and its arming in `_merge_verify_push`; imitate the re-entry block, the state-judged cleanup, the flag-and-return-130 contract and the save-and-restore of the caller's traps); `lib/wrap/wrap-merge.sh:421-442` (the `--pr` draft path; imitate its one-shot `gh` call and its `FAILED merge #N: ... return 2` shape); `tests/test-wrap-merge.sh:721-805` (the settle cases; imitate their fixture shape, the `nosleep` PATH and the `views` counter).

## Problem

`wrap merge --apply --pr N <repo>` refused twice in one session on tieubao/ops-toolkit. Each time the PR conflicted only on a union-marked log. wrap re-merged `origin/main` into the branch and pushed. Then the settle wait ran out with GitHub still on the pre-push head:

1. The first call printed `SKIP #N after the re-merge: head is <old>, not the pushed <new>` (`lib/wrap/wrap-merge.sh:522-523`).
2. A second call read the stale head again, judged it CONFLICTING, and tried the re-merge again. `_union_remerge` then refused with `feat/... tip <new> is not the PR head <old>, left alone` (`lib/wrap/wrap-merge.sh:195-196`), because the local tip had moved past the head GitHub reported.

For over 90 seconds, `gh pr view --json headRefOid` and the REST pulls endpoint both reported the old head. `git ls-remote` showed the new tip. A manual `gh pr close N` then `gh pr reopen N` made GitHub resync at once: the head updated and mergeable read clean. The next `wrap merge --apply --pr N` merged and verified the tree.

The settle wait cannot fix this. GitHub did not lag on mergeability. It never re-read the head ref. Waiting longer only fails later.

## Terms

none

## Solution

### Approaches considered

1. **One close and reopen, gated on proof that wrap's own push is the only difference.** When the settle wait ends on the pre-push head, and origin's branch tip is exactly the commit wrap pushed, close and reopen the PR once, then settle again. Tradeoff: a visible close and reopen pair lands in the PR timeline, and a reopen that never happens leaves the PR closed.
2. **A longer settle bound.** Raise `KIT_WRAP_SETTLE_SECS` or add a second wait. Tradeoff: the observed stale head outlived 90 seconds and cleared only on a close and reopen, so a longer wait just refuses later.
3. **Push an empty commit to nudge GitHub.** Tradeoff: it adds a commit to the branch, the next head is again one GitHub may not register, and a pushed commit is harder to take back than a reopen.

### Chosen approach + why

Approach 1. It is the recovery the operator ran by hand, and it worked on the first try both times. Approach 2 does not fix the observed case. Approach 3 writes to the branch, and the branch is the thing a merge must not change behind the gates.

The resync never stands in for the gates. After the reopen, the same `_pr_detail_settled` read runs, and the existing head check and `_pr_gate` decide. The merge stays pinned to the pushed head with `--match-head-commit`.

### Extensibility & boundaries

- The load-bearing dimension is how many places wrap pushes and then waits on GitHub. Today two do: this re-merge path and `land`'s merge retry (`lib/wrap/wrap-land.sh:739-742`). The helper takes only a repo, a URL, a PR number, a branch and two oids, so `land` could call it later without change. This spec wires only `merge`.
- One unit: `_pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid>`, six arguments. It owns only the GitHub-side proof, the close and reopen, and every line it prints. It never reads the merge verdict, never reads the dependents cache, and never merges. Its return codes are in `### Interfaces`.
- The helper runs in the current shell, never inside `$(...)` or a pipeline. A subshell would hold its own copy of the trap and the interrupt flag, so the caller could not see either.
- The dependents check stays in `cmd_merge`, before the call. It reads the cache `cmd_merge` already builds.

### Architecture

See `## Design` below.

## Picture

```
  cmd_merge, the single-conflict retry path (--apply only)
  ---------------------------------------------------------
  _union_remerge ---push---> origin/<branch> = PUSHED
        |
        v
  _pr_detail_settled(want=PUSHED, prior=OLD)                  [existing]
        |
        +-- head == PUSHED -----------------------------------------+
        +-- head == other (foreign push) ---------------------------+
        +-- head == OLD (stale)                                     |
                |                                                   |
        dependents open on <branch>? (bare form only)  yes ---------+
                | no                                                |
                v                                                   |
        _pr_head_resync  [NEW]                                      |
          1. gh pr view N --json state,isDraft,headRefOid,          |
                                 autoMergeRequest                   |
               head == PUSHED -------------------> rc 3 ----+       |
               not exactly OPEN / isDraft not exactly       |       |
               false / autoMergeRequest missing or set /    |       |
               head not OLD / unreadable -------> rc 1 -----|-------+
          2. git ls-remote origin refs/heads/<branch>       |       |
               not exactly one exact-ref line == PUSHED     |       |
                                       ---------> rc 1 -----|-------+
          3. save caller traps; arm INT/TERM/HUP trap       |       |
          4. gh pr close N  (no --comment, never -d)        |       |
               flag set? (checked before rc) --> 130 path   |       |
               ok ----------------------------------> 5     |       |
               failed: read state, up to 3 reads 2s apart   |       |
                 exactly OPEN ------> 6, then rc 1 ---------|-------+
                 exactly CLOSED ----------------------> 5   |       |
                 unreadable x3 ------> 6, then rc 2 -> FAILED, exit 2
          5. gh pr reopen N   (flag checked before each try;|
                               one retry after 2s)          |
               ok ------------------> 6, 7, then rc 0       |
               fails twice ---------> 6, 7, then rc 2 -> FAILED, exit 2
          6. flag set? -> 130 path; else clear trap,        |
             restore caller traps                           |
          7. gh pr comment N --body <static>  (best effort; |
             after 5 only)                                  |
                |                                           |
             rc 0                                           |
                v                                           v
        _pr_detail_settled(want=PUSHED, prior=OLD)    [second and last window]
                |                                                   |
                v                                                   v
        existing head check + _pr_gate + dependents gate  <---------+
          head still OLD after rc 0 -> SKIP "... still stale after a close and reopen; ..."

  130 path: the handler already ran (stderr recovery line, one state read,
            reopen only on exactly CLOSED); restore caller traps; rc 130 -> exit 130
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds two tradeoffs. The precondition read (step 1) costs one extra `gh pr view` per resync; it buys a fresh `state` and `autoMergeRequest` check right before the close. The trap (steps 3 to 6) adds a handler like `_mvp_trap`; it buys a reopen attempt when the run is interrupted between the close and the reopen.

### Diagram

The flowchart in `## Picture` is the design diagram. `docs/SYSTEM-DESIGN.md` does not exist in this repo, and the change adds no container or external system; it is L3 detail inside `lib/wrap/wrap-merge.sh`.

### ADR link(s)

None. The close and reopen is reversible by the same verb, and the decisions are recorded in `## Decision Log`.

### Boundaries & failure modes

The design touches an external integration (GitHub PR state). Out of bounds: any PR not in this run's own-PR set, any draft, any PR not OPEN, any PR with auto-merge armed, any branch whose origin tip is not wrap's pushed commit. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes:
  - The settled detail JSON from `_pr_detail_settled <url> <n> <pushed> <prior>`: `headRefOid` equal to the prior oid is the only trigger.
  - The dependents cache `${jsondir}/index` (`number\thead\tbase` rows), read in `cmd_merge` before the call. Under `--pr N` the cache holds only N's row (`lib/wrap/wrap-merge.sh:426`), so the check can never fire there, the same as the existing dependents gate at `:526-528`. It is live only in the bare `wrap merge --apply <repo>` form.
  - Step 1: `gh pr view <n> --repo <url> --json state,isDraft,headRefOid,autoMergeRequest`. Pass needs all four: `.state == "OPEN"`, `.isDraft == false`, `has("autoMergeRequest") and .autoMergeRequest == null`, `.headRefOid` equal to the prior oid. A missing field fails its test (never `// false` or `// null`, which would read a missing field as a pass). `.headRefOid` equal to the pushed oid returns 3 before the other tests. Anything else, or a failed read, returns 1.
  - Step 2: `git -C <repo> ls-remote origin refs/heads/<branch>`, run right after step 1 and right before the trap and the close. Keep only lines whose second tab-separated field is exactly `refs/heads/<branch>`. Exactly one such line, whose first field equals the pushed oid, passes. Zero lines, two or more lines, a different oid, or a non-zero exit returns 1. `ls-remote` patterns match on the tail of a ref name, so a ref such as `refs/heads/x/refs/heads/<branch>` also prints; the exact filter drops it.
  - After a failed close: `gh pr view <n> --repo <url> --json state`, up to three reads 2s apart. Exactly `OPEN` or exactly `CLOSED` ends the reads. Any other value, an empty value or a failed read counts as unreadable.
- Outputs / produces:
  - `gh pr close <n> --repo <url>`. No `--comment`, never `-d` or `--delete-branch`.
  - `gh pr reopen <n> --repo <url>`, retried once after 2s on a non-zero exit.
  - After the reopen step only, one best-effort `gh pr comment <n> --repo <url> --body <text>`. The text is static plus two short oids, nothing read from the PR. On success: `wrap merge closed and reopened this PR so GitHub re-reads its head: it still showed <old7> after the push of <new7>.` After two failed reopens: `wrap merge closed this PR so GitHub re-reads its head (<old7> stale, <new7> pushed), and the reopen failed. Reopen it: gh pr reopen <n>. If the branch is gone on origin, push <branch> at <new7> first.` No other path posts a comment.
  - Return codes:
    - 0: resynced; a close and a reopen both succeeded.
    - 3: caught up; step 1 already saw the pushed head, and no close ran.
    - 1: no resync; step 1 or step 2 refused, or the close failed and a later read saw exactly `OPEN`. In every rc 1 case the last read wrap took shows the PR open and unchanged.
    - 2: needs a human; two reopens failed, or the close failed and three reads could not tell whether it landed.
    - 130: interrupted between the trap arm and the trap clear.
  - Line ownership: the helper prints every line below exactly once. `cmd_merge` prints nothing of its own on rc 2 or rc 130; it cleans up and returns the same code. `cmd_merge` owns only the still-stale SKIP, because it builds the verdict.
  - Stdout lines (helper), indented five spaces like the other re-merge notes:
    - `     #N still shows head <old> after the push of <new>; closing and reopening #N to resync`
    - `     resynced #N: closed and reopened`
    - `     #N caught up on its own; no resync needed`
    - `     no resync for #N: <reason>`, one reason of: `dependents open` (printed by `cmd_merge`, which owns that check), `state <s>`, `isDraft is not false`, `auto-merge armed or unreadable`, `head moved to <x>`, `unreadable PR state`, `origin tip is <x>, not the pushed <new>`, `origin ref is ambiguous or missing`, `close failed and #N is still open`.
    - `     comment on #N failed; the resync itself is unaffected`
  - Stderr lines (helper):
    - Two reopens failed: `FAILED merge #N: closed #N to resync its head, and the reopen failed; reopen it: gh pr reopen N --repo <url> (if origin lost <branch>, push it at <new7> first)`.
    - Close errored and state unreadable: `FAILED merge #N: close #N errored and its state is unreadable; if it is closed: gh pr reopen N --repo <url>`.
    - Interrupt, printed first thing in the handler, before any network call: `INTERRUPTED inside the resync of #N; if #N is closed, reopen it: gh pr reopen N --repo <url>`. Then exactly one of: `reopened #N after the interrupt`; `could not reopen #N after the interrupt; run the command above`; `#N is still open after the interrupt; nothing to undo`; `#N state reads '<s>' after the interrupt, so no reopen was tried; check it: gh pr view N --repo <url>`.
  - Still-stale SKIP (`cmd_merge`, after rc 0 only): `SKIP #N after the re-merge: head is <old>, not the pushed <new>, still stale after a close and reopen; wait until gh pr view N --json headRefOid shows <new7>, then re-run wrap merge --apply --pr N (a re-run before that ends at left alone), or close and reopen it by hand: gh pr close N && gh pr reopen N`. After rc 3 or rc 1 the existing SKIP text stands unchanged.
- Invariants:
  - At most one close per `wrap merge` run, and at most two reopen calls plus one handler reopen. The retry path runs once per run (`lib/wrap/wrap-merge.sh:497`), and the helper has no loop.
  - No close unless step 1 saw `state` exactly `OPEN`. No reopen unless the close succeeded or a read saw `state` exactly `CLOSED`.
  - The interrupt flag is checked before the close, right after the close returns and before its exit code is read, before each reopen try, and at the trap clear. A set flag returns 130 at the first check that sees it.
  - The trap is armed only from step 3 to step 6, and the caller's INT, TERM and HUP handlers go back on every exit path, the way `_merge_verify_push` restores them.
  - The merge stays pinned to the pushed head (`--match-head-commit`), and only after the existing head check and `_pr_gate` pass on a read taken after the reopen.
  - A PR outside the run's own-PR set never reaches this path: `numbers` is the own-PR set (`lib/wrap/wrap-merge.sh:410-426`), and the conflict retry draws `conflict_n` only from it.

### Data model changes

None.

### API changes (endpoints, request/response shapes)

None to wrap's CLI. New outbound calls on the retry path only: one `pr view` read, up to three `pr view --json state` reads after a failed close, `pr close`, up to two `pr reopen`, one `pr comment`, and one `git ls-remote`.

### UI changes (screens, components, interactions)

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Test stub

- [ ] TASK-A1: Add `pr close`, `pr reopen` and `pr comment` verbs to the gh stub in `tests/lib/wrap-stub.sh`, each logged like every other verb, with `GH_STUB_CLOSE_RC`, `GH_STUB_REOPEN_RC` and `GH_STUB_COMMENT_RC` exits (default 0) and `GH_STUB_REOPEN_FAILS=N` failing the first N reopens. A successful `pr reopen <n>` writes `${GH_STUB_CALLS}.reopened-<n>`, after which every `pr view <n>` serves `GH_STUB_PR_<n>_REOPENED` when set, with `%REMERGE_TIP%` substituted, ahead of the indexed `_<j>` answers.
  Depends on: none.
  Acceptance: every existing section of `tests/test-wrap-merge.sh` and `tests/test-wrap-land.sh` stays green.
- [ ] TASK-A2: Add `GH_STUB_CLOSE_DELAY=<s>`: `pr close` writes `${GH_STUB_CALLS}.closing-<n>`, then sleeps `<s>` seconds through `/bin/sleep`, so the `nosleep` PATH shim cannot void the delay.
  Depends on: TASK-A1.
  Acceptance: the same suites stay green.

### Phase 2: The resync

- [ ] TASK-B1: Add `_pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid>` beside `_pr_detail_settled` in `lib/wrap/wrap-merge.sh`, with steps 1 and 2 of `## Picture` and their `no resync for #N` lines; the close half is a bare `return 1` for now. It runs in the current shell, so no caller may wrap it in `$(...)` or a pipeline.
  Depends on: none.
  Acceptance: `bash -n lib/wrap/wrap-merge.sh` exits 0; `bash -c 'source lib/wrap/wrap-merge.sh; declare -F _pr_head_resync'` prints the name; `grep -c 'no resync for #' lib/wrap/wrap-merge.sh` is at least 1, and each step 1 and step 2 reason string in `### Interfaces` appears in the file.
- [ ] TASK-B2a: Add the trap: save the caller's handlers with `trap -p`, arm `_resync_trap` on INT, TERM and HUP at step 3, and restore the handlers on every return. The handler starts with `trap '' INT TERM HUP`, sets the flag, prints the INTERRUPTED stderr line, reads `state` once, reopens only on exactly `CLOSED`, prints one of its four outcome lines, and returns without `exit`. The 130 path returns 130 once any flag check sees the flag.
  Depends on: TASK-B1.
  Acceptance: AC-18.
- [ ] TASK-B2b: Add the close at step 4 with the flag check right after it returns, and the failed-close rule: up to three `state` reads 2s apart, `OPEN` returns 1, `CLOSED` goes to the reopen, unreadable returns 2 with its FAILED line.
  Depends on: TASK-B2a.
  Acceptance: AC-11, AC-19, AC-22, AC-23.
- [ ] TASK-B2c: Add the reopen at step 5 with one retry after 2s and a flag check before each try, the rc 2 FAILED line, the trap clear at step 6, and the best-effort comment at step 7.
  Depends on: TASK-B2b.
  Acceptance: AC-1, AC-6, AC-7, AC-9.
- [ ] TASK-C: Wire it into `cmd_merge` right after the post-push `_pr_detail_settled` read (`lib/wrap/wrap-merge.sh:519`), only when that read's `headRefOid` equals `c_oid`, with the dependents check first. Map the helper's return: 0 re-reads with `_pr_detail_settled "$url" "$conflict_n" "$REMERGE_OID" "$c_oid"` and switches on the still-stale SKIP text; 3 re-reads without it; 1 keeps the read it holds; 2 and 130 run `rm -rf "$jsondir"` and return the same code with no line of their own.
  Depends on: TASK-B2c.
  Acceptance: AC-8, AC-10, AC-15.

### Phase 3: Tests, controls and docs

All new cases go in one new section of `tests/test-wrap-merge.sh`, `merge: a stale head after wrap's own push resyncs with one close and reopen`.

- [ ] TASK-D1a: The positive, caught-up and existing-case assertions.
  Depends on: TASK-A1, TASK-C.
  Acceptance: AC-1, AC-5, AC-9, AC-13, AC-15 run green.
- [ ] TASK-D1b: The one-field refusals.
  Depends on: TASK-A1, TASK-C.
  Acceptance: AC-3, AC-4, AC-16, AC-20, AC-21 run green.
- [ ] TASK-D1c: The heavy-fixture refusals and the exact-ref case (a bare-remote `post-receive` hook, a second own PR, a decoy ref).
  Depends on: TASK-A1, TASK-C.
  Acceptance: AC-2, AC-10, AC-17 run green.
- [ ] TASK-D2a: The reopen and close-failure cases.
  Depends on: TASK-A1, TASK-C.
  Acceptance: AC-6, AC-7, AC-11, AC-19, AC-23 run green.
- [ ] TASK-D2b: The still-stale and interrupt cases.
  Depends on: TASK-A2, TASK-C.
  Acceptance: AC-8, AC-18, AC-22 run green.
- [ ] TASK-D3: Commit the branch, then run every negative control in the AC table on a mutated copy of `lib/wrap/wrap-merge.sh` in a scratch worktree (`lib/gate/negctl.sh`), and capture each red result.
  Depends on: TASK-D1a, TASK-D1b, TASK-D1c, TASK-D2a, TASK-D2b.
  Acceptance: AC-14.
- [ ] TASK-E1: Add one sentence to the `merge` bullet in `commands/wrap.md` (line 127) naming the one close and reopen, its preconditions, exit 2 and exit 130. Add one clause to the `KIT_WRAP_SETTLE_SECS` row in `lib/config/module-registry.md`: the wait can run a second time after a resync, so the worst case is about twice the bound.
  Depends on: TASK-C.
  Acceptance: `grep -c 'reopen' commands/wrap.md` is at least 1, and `grep -c 'resync' lib/config/module-registry.md` is at least 1.
- [ ] TASK-E2: Write the proof at `docs/verification/wrap-merge-head-resync.md`, table-first, with the green run and the TASK-D3 control output. Optional canary: one live `gh pr close` then `gh pr reopen` on a scratch PR in a scratch repo under the operator's account, recording that the head, the labels and the review state survive; record `[UNAVAILABLE: <reason>]` when no scratch repo is at hand.
  Depends on: TASK-D3, TASK-E1.
  Acceptance: the proof file holds the captured test and control output.

## After state

- [ ] A PR whose head GitHub never re-reads after wrap's own re-merge push merges in one `wrap merge --apply` call, checkable by the `resync_stale_head_merges` case. (Today: the call SKIPs with `head is <old>, not the pushed <new>`, and the next call refuses with `left alone`.)
- [ ] wrap never closes a PR that is a draft, not OPEN, has auto-merge armed, is not the operator's own, or whose origin tip is not wrap's pushed commit, checkable by `grep -c '^pr close' <stub log>` equal to 0 in each refusal case.
- [ ] A close that errors never ends in a silent exit 0 unless a read saw the PR open, checkable by the `resync_close_fails_unreadable` case.
- [ ] A failed reopen exits 2 and prints the exact `gh pr reopen` command, checkable by the `resync_reopen_fails` case. (Today: no path closes a PR.)
- [ ] An interrupt between the close and the reopen reopens the PR and exits 130, checkable by the `resync_interrupted_reopens` case.
- [ ] `commands/wrap.md` names the close and reopen, checkable by `grep -n 'reopen' commands/wrap.md`.

Worst-case wall time of the retry path: the first settle window (`KIT_WRAP_SETTLE_SECS`, default 60), the precondition read, the `ls-remote`, the close, up to three state reads 2s apart or up to two reopens 2s apart, the comment, and the second settle window. That is about twice the bound plus 15s, about 135s at the default.

Not covered:
- A reopen re-fires the repo's `pull_request` `reopened` event, so a repo whose checks run on it sees them restart. That call then SKIPs with `checks are pending or failing`, and the next `wrap merge` call merges once they pass. This matches the SPEC-306 "Not covered" note.
- The close fires `pull_request` `closed` for every workflow and webhook that listens to it. Such a listener sees `merged == false`, the same event a human close sends. wrap cannot see or undo what those listeners do.
- A repo with a merge queue. See DEC-L.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] The AC table below is green, and each negative control turns its case red
- [ ] No regressions in `tests/test-wrap-merge.sh` and `tests/test-wrap-land.sh`

### AC table

Fixture shape for every case unless the row says otherwise:
- The bare form, `wrap merge --apply <repo>`. The `--pr N` form adds `_pr_detail` reads at `lib/wrap/wrap-merge.sh:428` (under `--no-pull`) and `:434`, which shift every read index below.
- `build_remerge <name>`, `PATH="$TMPD/nosleep:$PATH"`, `KIT_WRAP_SETTLE_SECS=4`.
- `GH_STUB_PR_<n>` and `GH_STUB_PR_<n>_2` both carry the old tip, CONFLICTING, and `"state":"OPEN","isDraft":false,"autoMergeRequest":null`.
- Reads 2 to 4 are the settle window; read 5 is the step 1 read; reads 6 to 8 are the state reads after a failed close, or the handler's state read.

| AC | Criterion | Test case | Negative control (mutation, expected red) |
|---|---|---|---|
| AC-1 | stale head, origin tip is the pushed commit, OPEN, not a draft, no auto-merge: one `pr close`, one `pr reopen`, one `pr comment`, then eligible and `merged #N (<sha>): tree verified`, merge pinned with `--match-head-commit <pushed>` | `resync_stale_head_merges` (PR 90; `GH_STUB_PR_90_REOPENED` on `%REMERGE_TIP%` MERGEABLE CLEAN; `GH_STUB_LAND_REPO` set) | delete the `_pr_head_resync` call in `cmd_merge`: the run SKIPs `head is <old>, not the pushed`, no merge, case red |
| AC-2 | origin tip is not the pushed commit (a foreign commit landed after wrap's push): no `pr close`, the existing SKIP, `no resync for #N: origin tip is` | `resync_refused_origin_moved` (PR 91; a `post-receive` hook in the bare remote commits on top of wrap's push) | drop the oid comparison in step 2: `pr close` is called, case red |
| AC-3 | step 1 shows `isDraft: true`: no `pr close`, `no resync for #N: isDraft is not false` | `resync_refused_draft` (PR 92; `GH_STUB_PR_92_5` with `isDraft: true`) | drop the `isDraft` test: `pr close` is called, case red |
| AC-4 | step 1 shows `state: CLOSED`: no `pr close`, no `pr reopen`, `no resync for #N: state CLOSED` | `resync_refused_closed` (PR 93; `GH_STUB_PR_93_5` with `state: CLOSED`) | drop the `state` test: `pr close` and `pr reopen` are called, case red |
| AC-5 | step 1 has no `state` field: no `pr close` | `resync_refused_no_state` (PR 105; `GH_STUB_PR_105_5` with `isDraft:false`, `autoMergeRequest:null`, no `state`) | treat a missing `state` as OPEN: `pr close 105` is called, case red |
| AC-6 | two reopens fail: exit 2, stderr holds `gh pr reopen 94 --repo` and `push it at`, exactly two `pr reopen 94` calls, one `pr comment 94` holding `the reopen failed`, no `pr merge` | `resync_reopen_fails` (PR 94; `GH_STUB_REOPEN_RC=1`) | ignore the reopen exit code: the run continues to a stale SKIP and exits 0, case red |
| AC-7 | one reopen fails, the retry succeeds: merged and tree verified, two `pr reopen` calls | `resync_reopen_retry` (PR 95; `GH_STUB_REOPEN_FAILS=1`) | remove the retry: exit 2, case red |
| AC-8 | still stale after a resync: one `pr close`, one `pr reopen`, the SKIP holds `still stale after a close and reopen; wait until gh pr view 97 --json headRefOid shows` and `gh pr close 97 && gh pr reopen 97`, no `pr merge`, exit 0 | `resync_still_stale` (PR 97; no `_REOPENED` answer) | drop the flag that switches on the suffix: `chk_has` on the suffix fails, case red |
| AC-9 | the `pr close 90` argv carries neither `--comment` nor `-d` nor `--delete-branch` | asserted inside `resync_stale_head_merges` | add `--delete-branch` to the close call: the argv check fails, case red |
| AC-10 | dependents open on the branch: no `pr close`, `no resync for #N: dependents open` | `resync_refused_dependents` (PR 98 plus an own PR 99 based on `feat/union`) | drop the dependents check in `cmd_merge`: `pr close` is called, case red |
| AC-11 | close fails and read 6 shows `state: OPEN`: no `pr reopen`, `no resync for #N: close failed and #N is still open`, the existing SKIP, exit 0 | `resync_close_fails_open` (PR 100; `GH_STUB_CLOSE_RC=1`; `GH_STUB_PR_100_6` OPEN) | treat a failed close as success: `pr reopen` is called, case red |
| AC-13 | the existing `moved`, `stuck`, `settle` and `lost` cases call no `pr close` | new zero `^pr close` assertions in each | n/a, pins that the resync runs only on a proven stale head |
| AC-14 | every control in this table is red against its mutant | the TASK-D3 run | n/a |
| AC-15 | step 1 already shows the pushed head: no `pr close`, `caught up on its own`, merged and tree verified, no `still stale` text | `resync_caught_up` (PR 96; `GH_STUB_PR_96_5` on `%REMERGE_TIP%` MERGEABLE CLEAN, OPEN) | return 1 on a pushed head in step 1: the caller gates the stale settle read and SKIPs, case red |
| AC-16 | step 1 shows `autoMergeRequest` set: no `pr close`, `no resync for #N: auto-merge armed or unreadable` | `resync_refused_automerge` (PR 102; `GH_STUB_PR_102_5` with `autoMergeRequest: {"mergeMethod":"SQUASH"}`) | drop the `autoMergeRequest` test: `pr close` is called, case red |
| AC-17 | a decoy ref `refs/heads/a/refs/heads/feat/union` at the old tip, sorting before the real ref: the exact filter finds the pushed oid, so the resync runs and the PR merges | `resync_exact_ref_match` (PR 103) | take the first `ls-remote` line: the decoy's old oid fails the comparison, no resync, no merge, case red |
| AC-18 | TERM delivered to the wrap process while the stub close sleeps; the close succeeds and read 6 shows CLOSED: exit 130, stderr holds `INTERRUPTED inside the resync of #104`, `gh pr reopen 104 --repo` and `reopened #104 after the interrupt`, exactly one `pr reopen 104`, no `pr merge` | `resync_interrupted_reopens` (PR 104; `GH_STUB_CLOSE_DELAY=2`; the case runs wrap in the background, waits for `.closing-104`, sends TERM, then waits; `GH_STUB_PR_104_6` CLOSED) | remove the trap arm: TERM ends wrap with exit 143 and no reopen, case red |
| AC-19 | close fails and reads 6 to 8 are empty: exit 2, stderr holds `FAILED merge #101: close #101 errored and its state is unreadable; if it is closed: gh pr reopen 101 --repo`, zero `pr reopen`, zero `pr comment`, no `pr merge` | `resync_close_fails_unreadable` (PR 101; `GH_STUB_CLOSE_RC=1`; `GH_STUB_PR_101_6` is `{}`) | return 1 on an unreadable state: exit 0 with no FAILED line, case red |
| AC-20 | step 1 has no `isDraft` field: no `pr close` | `resync_refused_no_isdraft` (PR 106; `GH_STUB_PR_106_5` OPEN, `autoMergeRequest:null`, no `isDraft`) | read `isDraft` with `// false`: `pr close 106` is called, case red |
| AC-21 | step 1 has no `autoMergeRequest` field: no `pr close` | `resync_refused_no_automerge_field` (PR 107; `GH_STUB_PR_107_5` OPEN, `isDraft:false`, no `autoMergeRequest`) | test `.autoMergeRequest == null` without `has(...)`: a missing field reads null, `pr close 107` is called, case red |
| AC-22 | TERM while the stub close sleeps, and the stub close then exits 1; read 6 shows CLOSED: exit 130, `reopened #109 after the interrupt`, exactly one `pr reopen 109`, no failed-close state reads after the handler's | `resync_interrupted_close_errors` (PR 109; `GH_STUB_CLOSE_DELAY=2`, `GH_STUB_CLOSE_RC=1`; `GH_STUB_PR_109_6` CLOSED) | read the close exit code before the flag: the failed-close rule reads CLOSED again and reopens a second time, so two `pr reopen 109` calls and exit 0, case red |
| AC-23 | close fails, read 6 is empty, read 7 shows CLOSED: one `pr reopen`, then merged and tree verified | `resync_close_fails_then_closed` (PR 108; `GH_STUB_CLOSE_RC=1`; `GH_STUB_PR_108_6` `{}`, `GH_STUB_PR_108_7` CLOSED; `GH_STUB_PR_108_REOPENED` on `%REMERGE_TIP%` MERGEABLE CLEAN) | take one state read only: read 6 is unreadable, so exit 2 and no reopen, case red |

## Verification

The exact commands:

```
bash tests/test-wrap-merge.sh
bash tests/run-all.sh --changed origin/master
```

Each negative control runs on a mutated copy of `lib/wrap/wrap-merge.sh` in a scratch worktree (`lib/gate/negctl.sh`), after the branch is committed (TASK-D3), and the named case must go red.

## Edge Cases

1. GitHub catches up between the settle read and step 1: step 1 sees `headRefOid` equal to the pushed oid and returns 3 without a close. The caller re-reads and gates. AC-15 pins it, including that no `still stale` text prints.
2. Someone pushes to the branch between step 2 and the close: the reopen still runs, the re-read shows a head that is neither old nor pushed, and the existing `head is <x>, not the pushed` SKIP refuses it. Nothing merges. The window is one round trip because step 2 runs right before the close.
3. A human closes the PR between step 1 and the close: `gh pr close` on a closed PR is expected to do nothing, and wrap then reopens a PR a human closed. The window is one `ls-remote` plus one round trip. Accepted and named in `## Failure modes`; the no-op behaviour is unsampled (see `## Grounding`).
4. `ls-remote` fails (network): non-zero exit or no exact line, so no resync, and the existing SKIP stands.
5. The dry run (no `--apply`) never reaches the re-merge, so it never reaches the resync.
6. `--no-pull` with the branch in the main checkout: the PR SKIPs before the retry path (`lib/wrap/wrap-merge.sh:471-474`), so no resync.
7. Under `--pr N` the dependents check cannot fire, because the cache holds only N's row. The bare form is the only form where it guards anything, and its purpose there is to avoid churn, not to protect anything (DEC-F).
8. A signal arrives after the trap is armed but before the close: the handler reads `state` OPEN, prints `still open`, and does not reopen; the flag check before the close returns 130. Nothing changed on GitHub.
9. A signal arrives while `gh pr close` runs: bash defers the handler until that child returns, so the handler's `state` read sees the result of the close. The flag check right after the close then returns 130 before the close's exit code is read (AC-22).
10. A signal arrives during the 2s sleep between reopen tries: the handler reads CLOSED and reopens; the flag check before the second try returns 130.
11. A signal arrives while `gh pr reopen` runs: the handler runs after it returns; a successful reopen reads OPEN, so the handler prints `still open` and does not reopen again.
12. Guarantee inversion, "at most one close per run": the retry path sits behind `conflict_count = 1` and runs once; the helper has no loop. AC-8 pins it.
13. Guarantee inversion, "never a foreign PR": the `numbers` invariant and the existing own-PR filter section pin it.
14. Guarantee inversion, "the merge waits for a read after the reopen": AC-1's mutant without the resync never merges; a mutant that skips the second settle read would gate the stale detail and SKIP, so AC-1 stays red there too.
15. The ci-label gate (`--with-ci`): it runs after the retry path on `first_eligible`, unchanged; it re-reads and re-gates the same pushed head.
16. The autoland carry path runs `cmd_merge` in a subshell with `2>&1` captured into a variable (`lib/wrap/wrap-carry.sh:148`) and prints it at `:149` once the subshell returns. The handler returns 130 rather than dying by the signal, so the subshell exits normally and the parent prints the captured INTERRUPTED and outcome lines. The recovery line goes to stderr from inside the handler before any network call, so it never waits on a later stdout write.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Two reopens fail after the close | `FAILED merge #N: closed #N to resync its head, and the reopen failed` on stderr, exit 2 | The line names `gh pr reopen N --repo <url>` and the re-push step for a branch origin lost; the comment on the PR says the same to anyone who opens it. |
| The close errors (timeout, 502) but may have landed, and three state reads stay unreadable | `FAILED merge #N: close #N errored and its state is unreadable` on stderr, exit 2 | No blind reopen. The line names the reopen command for the operator to run once they see the PR closed. AC-19 pins it. |
| INT, TERM or HUP between the trap arm and the trap clear | `INTERRUPTED inside the resync of #N` on stderr, exit 130 | The handler reads `state` and reopens once on exactly `CLOSED`, then prints one of four outcome lines; the recovery command is already printed. AC-18 and AC-22 pin it. |
| SIGKILL or a host crash between the close and the reopen | the PR is closed with no wrap comment, and the next `wrap merge` does not list it | Untrappable. The window is the close plus the reopen. Recovery: `gh pr list --repo <url> --author @me --state closed` finds it; `gh pr reopen N` restores it. A durable marker file is rejected for now (DEC-I). |
| TERM sent to the carry parent alone | the carry run's captured output never prints | The `cmd_merge` subshell never got the signal, so it finishes the resync and reopens; only the log is lost. |
| GitHub refuses the reopen because the branch was force-pushed or deleted while closed | the two-reopens FAILED line | The line names the re-push step; the operator re-pushes and reopens by hand, or recreates the PR. |
| Reopen re-fires CI | the re-gate SKIPs `checks are pending or failing` | The next `wrap merge` merges once green (`## After state`, Not covered). |
| The close fires `pull_request` `closed` listeners | none inside wrap | Named under Not covered. A repo whose close listeners act on unmerged closes should not run unattended wrap merges. |
| A human closed the PR during the one-round-trip window | the PR reopens with wrap's comment below it | Accepted (Edge 3); the comment names wrap. |
| GitHub still stale after the reopen | the `still stale after a close and reopen` SKIP | No second close. The SKIP names the wait-then-re-run step and the manual close and reopen. |
| The comment fails to post | `comment on #N failed; the resync itself is unaffected` | Harmless; the stdout lines still record the resync. The comment runs after the reopen step, so it can never stop or precede a close. |

## Out of Scope

- The cross-run case: a later `wrap merge` call that finds a stale head and a local tip ahead of it still refuses with `left alone` (`lib/wrap/wrap-merge.sh:195-196` and `:204-205`). That run did not push, so it cannot prove the origin tip is its own. This spec narrows how often that path is reached, because the first call now resyncs; it does not remove it. A run that resynced and still found a stale head names the next steps in its SKIP.
- `land`'s stale-head refusals (`lib/wrap/wrap-land.sh:739-742` and `:775`). The `:775` line tells the operator to run `wrap merge --apply --pr N`; on a still-stale head that run takes the same re-merge path and can still end at `left alone`. The helper is shaped so a later spec can call it from `land`.
- The squash-fallback replacement PR's head check (`lib/wrap/wrap-merge.sh:360-365`): wrap opens that PR itself, and no stale head was observed there.
- A knob to turn the resync off. No caller needs one today.

## Touches

- lib/wrap/**
- tests/test-wrap-merge.sh
- tests/lib/wrap-stub.sh
- commands/wrap.md
- lib/config/module-registry.md
- docs/verification/wrap-merge-head-resync.md

## Decision Log

- DEC-A: close and reopen, not a longer wait or an empty commit. The observed stale head outlived 90 seconds and cleared only on a close and reopen; an empty commit writes to the branch the gates read. Rejected: approaches 2 and 3 in `## Solution`.
- DEC-B: the resync requires origin's tip to equal the oid wrap pushed in this run, read by `git ls-remote` with an exact ref match, right before the close. A local tip proves only what this checkout holds; GitHub reads origin. Rejected: compare the local worktree tip (misses a foreign push); take the first `ls-remote` line (a tail-matching ref can come first).
- DEC-C: one fresh `state,isDraft,headRefOid,autoMergeRequest` read right before the close, with every field required present. The settled detail has no `state` field, and a PR closed by a human during the settle window must never be reopened by wrap. Rejected: add the fields to `_pr_detail` (widens every read for one path); `// false` defaults (a missing field would pass).
- DEC-D: the comment is a separate `gh pr comment` after the reopen step, never `gh pr close --comment`. The order in which `gh pr close --comment` posts and closes is unsampled; a separate call after the reopen makes that question moot and keeps the closed window to the close and the reopen. The text is static plus short oids, so nothing read from the PR reaches the comment. Rejected: `--comment` on the close (unsampled ordering), no comment (a closed PR after a failed reopen carries no reason).
- DEC-E: a failed reopen retries once after 2s, then exits 2. A closed own PR drops out of `_open_own_prs`, so silence would hide it from every later run. Rejected: no retry (one transient 502 strands the PR), unbounded retry (spins against a real refusal).
- DEC-F: no resync when dependents are open, and the check lives in `cmd_merge`. The dependents gate would refuse the merge anyway, so a resync there is visible churn with no merge behind it; this is about churn, not safety. Keeping it in `cmd_merge` keeps the helper at six arguments and GitHub-side only. It guards only the bare form; under `--pr N` it cannot fire.
- DEC-G: no own-PR re-check inside the helper. `conflict_n` comes only from the own-PR set, so a re-check would be unreachable code.
- DEC-H: no resync while auto-merge is armed or its field is unreadable. A close is expected to disarm auto-merge and a reopen not to re-arm it (unsampled; see `## Grounding`), so the resync could silently drop an operator's armed merge. Rejected: re-arm after the reopen (wrap never arms auto-merge; see `lib/wrap/wrap-merge.sh:599-600`).
- DEC-I: an INT/TERM/HUP trap covers the close-to-reopen window, mirroring `_mvp_trap`. A durable marker file that a later run reads to reopen a stranded PR would also cover SIGKILL, but it adds persisted state for a short window. Rejected for now; `## Failure modes` names the manual recovery.
- DEC-J: rc 3 for caught up, separate from rc 0 for resynced, so the still-stale SKIP text prints only when a close ran.
- DEC-K: a close that errors is judged by state, fail closed. Exactly `OPEN` means it did not land: rc 1, nothing to undo. Exactly `CLOSED` means it landed: reopen. Anything else after three reads 2s apart is rc 2 with the reopen command printed, never a blind reopen, because a blind reopen on a PR whose state is unknown could reopen one a human closed. Rejected: rc 1 on unreadable (a landed close would strand the PR behind an exit 0); a blind reopen (acts on unknown state).
- DEC-L: no merge-queue guard. `gh pr view` exposes no `isInMergeQueue` field, and the kit's own repos run no merge queue (see `## Grounding`). A consumer repo with a merge queue is not covered by this spec.

## Grounding

External shapes the spec asserts, each sampled read-only on this machine:

- `gh pr view --json headRefOid` shape. Sample: `gh pr view 4496 --repo tieubao/ops-toolkit --json number,headRefName,headRefOid,isDraft,state,mergeable,mergeStateStatus,author` printed `{"author":{...,"login":"tieubao",...},"headRefName":"docs/vps-mon-deploy-pointer","headRefOid":"16eddb8f3943bde62e5caab79fae86874ea85b33","isDraft":false,"mergeStateStatus":"UNKNOWN","mergeable":"UNKNOWN","number":4496,"state":"MERGED"}`. `headRefOid` is a full 40-hex oid; `state` is an upper-case word (`MERGED` here; `OPEN` and `CLOSED` are its other values); `isDraft` is a JSON boolean.
- The step 1 field set. Sample: `gh pr view 4401 --repo tieubao/ops-toolkit --json number,state,isDraft,headRefOid,autoMergeRequest` printed `{"autoMergeRequest":null,"headRefOid":"95022ed1798b42dd4bc66223f2e9dc47427bd2ce","isDraft":false,"number":4401,"state":"OPEN"}`. `autoMergeRequest` is present and `null` when nothing is armed. The armed shape (an object) is not sampled live; the AC-16 fixture uses an object, and the test is `!= null`, so any object refuses.
- Fail-closed field tests. Sample: `printf '%s' '{"state":"OPEN"}' | jq -r '(.isDraft == false), has("autoMergeRequest"), (.isDraft // false)'` printed `false`, `false`, `false`. A missing `isDraft` fails `== false`, and a missing `autoMergeRequest` fails `has(...)`; `.isDraft // false` yields `false`, which a `== false` test would then pass, so the spec forbids that default.
- Merge queue. Sample: `gh pr view 4401 --repo tieubao/ops-toolkit --json isInMergeQueue` exited 1 with `Unknown JSON field: "isInMergeQueue"`, and the printed field list holds no merge-queue field. `gh api repos/dwarvesf/dwarves-kit/rules/branches/master --jq '[.[].type]'` printed `[]`. The same call on tieubao/ops-toolkit returned HTTP 403 `Upgrade to GitHub Pro or make this repository public to enable this feature`, so that private repo has no rulesets and so no merge queue.
- An open PR and a draft side by side. Sample: `gh pr list --repo tieubao/ops-toolkit --state open --limit 3 --json number,headRefName,headRefOid,isDraft` printed `[{"headRefName":"feat/jev-first-workflow","headRefOid":"95022ed1...","isDraft":false,"number":4401},{"headRefName":"feat/teardown-clean-route","headRefOid":"5f6c89b0...","isDraft":true,"number":4376}]` (oids trimmed here).
- `git ls-remote` shape. Sample, from the ops-toolkit checkout: `git ls-remote origin refs/heads/feat/jev-first-workflow` printed `95022ed1798b42dd4bc66223f2e9dc47427bd2ce\trefs/heads/feat/jev-first-workflow`, the oid then a tab then the full ref. `git ls-remote origin feat/jev-first-workflow` (a bare tail pattern) printed the same line, which shows patterns match on the ref tail; the exact second-field filter rules out a tail-matching decoy.
- The REST pulls endpoint agrees with `gh pr view` in the in-sync case. Sample: `gh api repos/tieubao/ops-toolkit/pulls/4401 --jq '{head_sha: .head.sha, head_ref: .head.ref, state, draft, mergeable_state}'` printed `{"draft":false,"head_ref":"feat/jev-first-workflow","head_sha":"95022ed1798b42dd4bc66223f2e9dc47427bd2ce","mergeable_state":"unknown","state":"open"}`.
- `gh pr close`, `gh pr reopen` and `gh pr comment` flags. `gh pr close --help` lists `-c, --comment string   Leave a closing comment` and `-d, --delete-branch    Delete the local and remote branch after close`; the branch is deleted only with `-d`. `gh pr reopen --help` lists `-c, --comment string   Add a reopening comment`. `gh pr comment --help` lists `-b, --body text        The comment body text`. Version: `gh version 2.101.0 (2026-09-15)`. None of the three verbs was run live.
- The trap pattern. `_mvp_trap` (`lib/wrap/wrap-common.sh:501-536`) blocks re-entry with `trap '' INT TERM HUP`, sets a flag, judges cleanup by state, and never calls `exit`; `_merge_verify_push` (`:545-570`) saves the caller's handlers with `trap -p` and restores them with `eval` or `trap -`.
- The carry capture. `lib/wrap/wrap-carry.sh:148` runs `out="$( (cmd_merge --apply --pr "$n" "$repo") 2>&1)"` and `:149` prints `$out` after the subshell returns.
- The test stub today answers no `pr close`, `pr reopen` or `pr comment`: an unknown `pr` verb falls to `exit 1` (`tests/lib/wrap-stub.sh:226`). Its `pr view` serves `GH_STUB_PR_<n>_<j>` by read count (`tests/lib/wrap-stub.sh:134-150`). The `nosleep` shim (`tests/lib/wrap-stub.sh:249`) replaces `sleep` on PATH, which is why `GH_STUB_CLOSE_DELAY` must call `/bin/sleep`.

Unsampled claims, named so a reviewer can weigh them:

- The core premise: a close and a reopen make GitHub re-read a stale head ref. This is the one load-bearing claim with no live sample. The evidence is the operator's two observations in the item. The stale state cannot be produced on demand, so even TASK-E2's optional canary samples only the side effects of a close and reopen, not the re-read.
- DEC-H: a close disarms an armed auto-merge, and a reopen does not re-arm it. The spec refuses the resync whenever auto-merge is armed, so the claim only decides why the refusal exists, not what the code does.
- Edge 3: `gh pr close` on an already-closed PR does nothing. If it errors instead, the failed-close rule reads `CLOSED` and reopens, which is the same outcome Edge 3 already accepts.
- The order in which `gh pr close --comment` posts and closes (no gh source on this machine). DEC-D removes the dependency.

Dry traces, one per negative control (read from `lib/wrap/wrap-merge.sh` at the cited lines; nothing mutated here):

- NC for AC-1 (delete the `_pr_head_resync` call). Fixture: `GH_STUB_PR_90` and `GH_STUB_PR_90_2` serve the old head CONFLICTING; `GH_STUB_PR_90_REOPENED` would serve `%REMERGE_TIP%` MERGEABLE CLEAN but is never reached, because no `pr reopen` is logged. Path: read 1 in the cache loop (`:453`) gates SKIP CONFLICTING, so `conflict_count` is 1 (`:484-485`). `_union_remerge` pushes (`:506`). `_pr_detail_settled` (`:519`) polls reads 2 to 4 on the old head and stops at the 4s bound (`:83`). `r_head` is the old oid, so `:522-523` sets `SKIP head is <old>, not the pushed <new>`. Nothing is eligible, `:560` prints `nothing eligible to merge.`, exit 0, no `pr merge` logged. `resync_stale_head_merges` asserts `merged #90 (...): tree verified` and a `pr reopen 90` line. Red.
- NC for AC-2 (drop the oid comparison). The bare remote's `post-receive` hook moves `feat/union` to a commit on top of wrap's push. Step 1 (read 5) passes; step 2 finds one exact line but no longer compares its oid, so `pr close 91` is logged. The case asserts zero `^pr close` lines. Red.
- NC for AC-3, AC-4, AC-16 (drop the `isDraft`, `state` or `autoMergeRequest` test). Read 5 serves the refusing value; each mutant closes (AC-4's also reopens). The zero-close assertion fails. Red.
- NC for AC-5, AC-20, AC-21 (read a missing field as a pass). Read 5 omits `state`, `isDraft` or `autoMergeRequest`; the mutant treats it as OPEN, as `false` via `// false`, or as `null` without `has(...)`, and closes. The zero-close assertion fails. Red.
- NC for AC-6 (ignore the reopen exit). `GH_STUB_REOPEN_RC=1`; the mutant returns 0, the caller re-reads, the head is still old, and the run SKIPs with exit 0. The case asserts exit 2 and the `gh pr reopen 94 --repo` text. Red.
- NC for AC-7 (remove the retry). `GH_STUB_REOPEN_FAILS=1`; the mutant returns 2 on the first failure. The case asserts exit 0, `merged #95`, and two `pr reopen 95` lines. Red.
- NC for AC-8 (drop the suffix flag). No `_REOPENED` answer, so the re-read stays old; the mutant prints the SKIP without the suffix. `chk_has` on the suffix fails. Red.
- NC for AC-9 (add `--delete-branch`). The stub logs the flag in the `pr close 90` line; the argv assertion fails. Red.
- NC for AC-10 (drop the dependents check). The cache has PR 99's row with base `feat/union`; the mutant calls the helper, which closes `#98`. The zero-close assertion fails. Red.
- NC for AC-11 (failed close treated as success). `GH_STUB_CLOSE_RC=1` and read 6 serves OPEN; the mutant calls `pr reopen`. The zero-reopen assertion fails. Red.
- NC for AC-15 (rc 1 on a pushed head in step 1). Read 5 serves the pushed head; the mutant returns 1, so the caller keeps the stale settle read from reads 2 to 4 and `:522-523` SKIPs. The case asserts `merged #96`. Red.
- NC for AC-17 (first `ls-remote` line). The decoy sorts before `refs/heads/feat/union` and holds the old oid; `ls-remote origin refs/heads/feat/union` prints both. The mutant reads the decoy's oid, returns 1, and the run SKIPs. The case asserts `merged #103`. Red.
- NC for AC-18 (remove the trap arm). The case waits for `.closing-104` and sends TERM while the stub sleeps 2s in `/bin/sleep`. With no trap, the shell takes the default TERM action and ends with exit 143 and no `pr reopen`. The case asserts exit 130 and one `pr reopen 104` line. Red.
- NC for AC-19 (rc 1 on unreadable). Reads 6 to 8 serve `{}`; the mutant returns 1, so the existing SKIP prints and the run exits 0. The case asserts exit 2 and the FAILED line. Red.
- NC for AC-22 (read the close exit code before the flag). The handler runs right after the stub close returns, reads CLOSED (read 6) and reopens once. The mutant then takes the failed-close branch, reads CLOSED again (read 7) and reopens a second time, then continues to the re-read and exits 0. The case asserts exit 130 and exactly one `pr reopen 109`. Red.
- NC for AC-23 (one state read only). Read 6 serves `{}`; the mutant stops there and returns 2. The case asserts one `pr reopen 108` and `merged #108`. Red.

## Open questions

(none)
