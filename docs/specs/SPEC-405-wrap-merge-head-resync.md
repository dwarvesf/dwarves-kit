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
- One unit: `_pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid>`, six arguments. It owns only the GitHub-side proof and the close and reopen. It never reads the merge verdict, never reads the dependents cache, and never merges. Its return codes are in `### Interfaces`.
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
  _pr_detail_settled(want=PUSHED, prior=OLD)                [existing]
        |
        +-- head == PUSHED --------------------------------+
        +-- head == other (foreign push) ------------------+
        +-- head == OLD (stale)                            |
                |                                          |
        dependents open on <branch>? (bare form only) yes -+
                | no                                       |
                v                                          |
        _pr_head_resync  [NEW]                             |
          1. gh pr view N --json state,isDraft,            |
               headRefOid,autoMergeRequest                 |
               head PUSHED already ---------> rc 3 --+     |
               not OPEN / draft / auto-merge armed /  |    |
               head not OLD / unreadable --> rc 1 ----|----+
          2. git ls-remote origin refs/heads/<branch> |    |
               exactly one exact-ref line == PUSHED?  |    |
               no -------------------------> rc 1 ----|----+
          3. arm INT/TERM/HUP trap                    |    |
          4. gh pr close N        (no --comment,      |    |
                                   never -d)          |    |
               fails: state read exactly CLOSED?      |    |
                 no ----------------------> rc 1 -----|----+
          5. gh pr reopen N   (one retry after 2s)    |    |
               fails twice -> comment ----> rc 2 -> FAILED, exit 2
          6. clear trap, restore caller's traps       |    |
          7. gh pr comment N --body <static>          |    |
               (best effort, after the reopen)        |    |
               signal in 3..6 -> handler: state-guarded reopen,
                                 stderr recovery line, rc 130 -> exit 130
                |                                     |    |
             rc 0                                     |    |
                v                                     v    |
        _pr_detail_settled(want=PUSHED, prior=OLD)  [second and last window]
                |                                          |
                v                                          v
        existing head check + _pr_gate + dependents gate  <+
          head still OLD after rc 0 -> SKIP "... still stale after a close and reopen; ..."
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
  - `gh pr view <n> --repo <url> --json state,isDraft,headRefOid,autoMergeRequest`. Required: `state` exactly `OPEN`, `isDraft` exactly `false`, `autoMergeRequest` exactly `null`, `headRefOid` exactly the prior oid. `headRefOid` exactly the pushed oid returns 3. Any other value, a missing field or a failed read returns 1.
  - `git -C <repo> ls-remote origin refs/heads/<branch>`, run right after the precondition read and right before the trap and the close. Keep only lines whose second tab-separated field is exactly `refs/heads/<branch>`. Exactly one such line, whose first field equals the pushed oid, passes. Zero lines, two or more lines, a different oid, or a non-zero exit returns 1. `ls-remote` patterns match on the tail of a ref name, so a ref such as `refs/heads/x/refs/heads/<branch>` also prints; the exact filter drops it.
- Outputs / produces:
  - `gh pr close <n> --repo <url>`. No `--comment`, never `-d` or `--delete-branch`.
  - `gh pr reopen <n> --repo <url>`, retried once after 2s on a non-zero exit.
  - After the reopen step, one best-effort `gh pr comment <n> --repo <url> --body <text>`. The text is static plus two short oids, nothing read from the PR: on success `wrap merge closed and reopened this PR so GitHub re-reads its head: it still showed <old7> after the push of <new7>.`; on a failed reopen `wrap merge closed this PR so GitHub re-reads its head (<old7> stale, <new7> pushed), and the reopen failed. Reopen it: gh pr reopen <n>.` A failed comment prints `     comment on #N failed; the resync itself is unaffected` and changes no return code.
  - Return codes: 0 resynced (a close and a reopen both ran), 3 caught up (step 1 already saw the pushed head; no close ran), 1 preconditions not met (nothing changed on GitHub), 2 closed and the reopen failed twice, 130 interrupted between the trap arm and the trap clear.
  - Stdout lines, indented five spaces like the other re-merge notes:
    - `     #N still shows head <old> after the push of <new>; closing and reopening #N to resync`
    - `     resynced #N: closed and reopened`
    - `     #N caught up on its own; no resync needed`
    - `     no resync for #N: <reason>`, one reason of: `dependents open`, `state <s>`, `a draft`, `auto-merge armed`, `head moved to <x>`, `unreadable PR state`, `origin tip is <x>, not the pushed <new>`, `origin ref is ambiguous or missing`, `close failed`.
  - Stderr lines:
    - Reopen failed twice: `FAILED merge #N: closed #N to resync its head, and the reopen failed; reopen it: gh pr reopen N --repo <url>`. `cmd_merge` returns 2.
    - Interrupt, printed first thing in the handler, before any network call: `INTERRUPTED inside the resync of #N; if #N is closed, reopen it: gh pr reopen N --repo <url>`. Then one of `reopened #N after the interrupt` or `could not reopen #N after the interrupt; run the command above`. `cmd_merge` returns 130.
  - After rc 0 only, a still-stale re-read sets the SKIP to: `SKIP #N after the re-merge: head is <old>, not the pushed <new>, still stale after a close and reopen; wait until gh pr view N --json headRefOid shows <new7>, then re-run wrap merge --apply --pr N`. After rc 3 the existing SKIP text stands unchanged.
- Invariants:
  - At most one close and one reopen pair per `wrap merge` run. The retry path runs once per run (`lib/wrap/wrap-merge.sh:497`), and the helper has no loop.
  - No close unless the read in step 1 saw `state` exactly `OPEN`, and no reopen after a failed close unless a read saw `state` exactly `CLOSED`.
  - The trap is armed only from just before the close to just after the reopen step, and the caller's INT, TERM and HUP handlers go back on every exit path, the way `_merge_verify_push` restores them.
  - The merge stays pinned to the pushed head (`--match-head-commit`), and only after the existing head check and `_pr_gate` pass on a read taken after the reopen.
  - A PR outside the run's own-PR set never reaches this path: `numbers` is the own-PR set (`lib/wrap/wrap-merge.sh:410-426`), and the conflict retry draws `conflict_n` only from it.

### Data model changes

None.

### API changes (endpoints, request/response shapes)

None to wrap's CLI. New outbound `gh` calls on the retry path only: one `pr view` read, `pr close`, `pr reopen` (up to two), `pr comment` (one), and one `git ls-remote`.

### UI changes (screens, components, interactions)

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Test stub

- [ ] TASK-A: Extend the gh stub in `tests/lib/wrap-stub.sh`. Add `pr close`, `pr reopen` and `pr comment` verbs; each records its call like every other verb. `GH_STUB_CLOSE_RC`, `GH_STUB_REOPEN_RC` and `GH_STUB_COMMENT_RC` set their exits (default 0). `GH_STUB_REOPEN_FAILS=N` fails the first N reopens, then exits 0. `GH_STUB_CLOSE_DELAY=<s>` makes `pr close` write a marker `${GH_STUB_CALLS}.closing-<n>` and then sleep `<s>` seconds through `/bin/sleep` (an absolute path, so the `nosleep` PATH shim does not void it). A successful `pr reopen <n>` writes a marker `${GH_STUB_CALLS}.reopened-<n>`. Once that marker exists, every later `pr view <n>` serves `GH_STUB_PR_<n>_REOPENED` when set, with the same `%REMERGE_TIP%` substitution, ahead of the indexed `_<j>` answers.
  Depends on: none.
  Acceptance: every existing section of `tests/test-wrap-merge.sh` and `tests/test-wrap-land.sh` stays green with the stub change alone.

### Phase 2: The resync

- [ ] TASK-B1: Add `_pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid>` to `lib/wrap/wrap-merge.sh`, beside `_pr_detail_settled`, with a header comment in the file's style. This task writes the precondition half only: step 1 (the read and its rc 3 and rc 1 outcomes) and step 2 (the exact-ref `ls-remote` check), each refusal printing its `no resync for #N: <reason>` line. Stub the close half as `return 1` until TASK-B2.
  Depends on: none.
  Acceptance: AC-2, AC-3, AC-4, AC-5, AC-15, AC-16, AC-17 (refusal half) hold once TASK-C and TASK-D1 exist.
- [ ] TASK-B2: Replace the stub with the close half: steps 3 to 7 of `## Picture`. Arm a trap `_resync_trap` on INT, TERM and HUP just before the close, after saving the caller's handlers with `trap -p`. The handler's first line is `trap '' INT TERM HUP`. It sets a flag, prints the INTERRUPTED stderr line, reads `state` once, runs one `gh pr reopen` only on an exact `CLOSED`, prints its outcome line to stderr, and returns; it never calls `exit`. The helper checks the flag before the close and before each reopen attempt, and returns 130 once it is set. After a non-zero close, read `state` once: exactly `CLOSED` goes on to the reopen; anything else (OPEN, empty, unreadable) returns 1 with `close failed`. A reopen that fails twice returns 2. The comment runs after the reopen step and the trap clear. Every return path restores the caller's handlers.
  Depends on: TASK-B1.
  Acceptance: AC-1, AC-6, AC-7, AC-9, AC-11, AC-12, AC-18.
- [ ] TASK-C: Wire it into `cmd_merge` right after the post-push `_pr_detail_settled` read (`lib/wrap/wrap-merge.sh:519`). Run only when that read's `headRefOid` equals `c_oid`. First run the dependents check on the cache (`awk` as at `:526-527`); a dependent prints `no resync for #N: dependents open` and skips the call. Then map the helper's return: 0 re-reads with `_pr_detail_settled "$url" "$conflict_n" "$REMERGE_OID" "$c_oid"` and sets the flag that switches on the still-stale SKIP text; 3 re-reads the same way without the flag; 1 runs the existing path on the read it holds; 2 runs `rm -rf "$jsondir"` and returns 2; 130 runs `rm -rf "$jsondir"` and returns 130.
  Depends on: TASK-B2.
  Acceptance: AC-1, AC-8, AC-10, AC-15.

### Phase 3: Tests, controls and docs

- [ ] TASK-D1: Add a section `merge: a stale head after wrap's own push resyncs with one close and reopen` to `tests/test-wrap-merge.sh` holding the positive and refusal cases: AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10, AC-13, AC-15, AC-16, AC-17.
  Depends on: TASK-A, TASK-C.
  Acceptance: the cases run green.
- [ ] TASK-D2: Add the reopen, close-failure, stale and interrupt cases to the same section: AC-6, AC-7, AC-8, AC-11, AC-12, AC-18.
  Depends on: TASK-A, TASK-C.
  Acceptance: the cases run green.
- [ ] TASK-D3: Commit the branch, then run every negative control in the AC table on a mutated copy of `lib/wrap/wrap-merge.sh` in a scratch worktree (`lib/gate/negctl.sh`), and capture each red result.
  Depends on: TASK-D1, TASK-D2.
  Acceptance: AC-14; every listed control goes red, and the captured output is ready for the proof.
- [ ] TASK-E: Docs and proof. Add one sentence to the `merge` bullet in `commands/wrap.md` (line 127) naming the one close and reopen, its preconditions, exit 2 on a failed reopen and exit 130 on an interrupt. Add one clause to the `KIT_WRAP_SETTLE_SECS` row in `lib/config/module-registry.md`: the wait can run a second time after a resync, so the worst case is about twice the bound. Write the proof at `docs/verification/wrap-merge-head-resync.md`, table-first, with the green run and the TASK-D3 control output. Optional canary: one live `gh pr close` then `gh pr reopen` on a scratch PR in a scratch repo under the operator's account, recording that the head, the labels and the review state survive; record `[UNAVAILABLE: <reason>]` when no scratch repo is at hand.
  Depends on: TASK-D3.
  Acceptance: `grep -c 'reopen' commands/wrap.md` is at least 1; the proof file holds the captured test and control output.

## After state

- [ ] A PR whose head GitHub never re-reads after wrap's own re-merge push merges in one `wrap merge --apply` call, checkable by the `resync_stale_head_merges` case. (Today: the call SKIPs with `head is <old>, not the pushed <new>`, and the next call refuses with `left alone`.)
- [ ] wrap never closes a PR that is a draft, not OPEN, has auto-merge armed, is not the operator's own, or whose origin tip is not wrap's pushed commit, checkable by `grep -c '^pr close' <stub log>` equal to 0 in each refusal case.
- [ ] A failed reopen exits 2 and prints the exact `gh pr reopen` command, checkable by the `resync_reopen_fails` case. (Today: no path closes a PR.)
- [ ] An interrupt between the close and the reopen reopens the PR and exits 130, checkable by the `resync_interrupted_reopens` case.
- [ ] `commands/wrap.md` names the close and reopen, checkable by `grep -n 'reopen' commands/wrap.md`.

Worst-case wall time of the retry path: the first settle window (`KIT_WRAP_SETTLE_SECS`, default 60) plus the precondition read, the `ls-remote`, the close, up to two reopens 2s apart, the comment, and the second settle window. That is about twice the bound plus 10s, about 130s at the default.

Not covered:
- A reopen re-fires the repo's `pull_request` `reopened` event, so a repo whose checks run on it sees them restart. That call then SKIPs with `checks are pending or failing`, and the next `wrap merge` call merges once they pass. This matches the SPEC-306 "Not covered" note.
- The close fires `pull_request` `closed` for every workflow and webhook that listens to it. Such a workflow sees `merged == false`, the same event a human close sends. wrap cannot see or undo what those listeners do.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] The AC table below is green, and each negative control turns its case red
- [ ] No regressions in `tests/test-wrap-merge.sh` and `tests/test-wrap-land.sh`

### AC table

Fixture shape for every case: `build_remerge <name>`, `PATH="$TMPD/nosleep:$PATH"`, `KIT_WRAP_SETTLE_SECS=4`, `GH_STUB_PR_<n>` a conflict fixture on the old tip with `"state":"OPEN","isDraft":false,"autoMergeRequest":null` added, and `GH_STUB_PR_<n>_2` the same stale head reading CONFLICTING. Reads 2 to 4 are the settle window; read 5 is the precondition read.

| AC | Criterion | Test case | Negative control (mutation, expected red) |
|---|---|---|---|
| AC-1 | stale head, origin tip is the pushed commit, OPEN, not a draft, no auto-merge: one `pr close`, one `pr reopen`, one `pr comment`, then eligible and `merged #N (<sha>): tree verified`, merge pinned with `--match-head-commit <pushed>` | `resync_stale_head_merges` (PR 90; `GH_STUB_PR_90_REOPENED` on `%REMERGE_TIP%` MERGEABLE CLEAN; `GH_STUB_LAND_REPO` set) | delete the `_pr_head_resync` call in `cmd_merge`: the run SKIPs `head is <old>, not the pushed`, no merge, case red |
| AC-2 | origin tip is not the pushed commit (a foreign commit landed after wrap's push): no `pr close`, the existing SKIP, `no resync for #N: origin tip is` | `resync_refused_origin_moved` (PR 91; a `post-receive` hook in the bare remote commits on top of wrap's push) | drop the oid comparison in step 2: `pr close` is called, case red |
| AC-3 | precondition read shows `isDraft: true`: no `pr close`, `no resync for #N: a draft` | `resync_refused_draft` (PR 92; `GH_STUB_PR_92_5` stale with `isDraft: true`) | drop the `isDraft` check: `pr close` is called, case red |
| AC-4 | precondition read shows `state: CLOSED`: no `pr close`, no `pr reopen`, `no resync for #N: state CLOSED` | `resync_refused_closed` (PR 93; `GH_STUB_PR_93_5` with `state: CLOSED`) | drop the `state` check: `pr close` and `pr reopen` are called, case red |
| AC-5 | precondition read has no `state` field: no `pr close` (fail closed) | the existing `lost` case (PR 86), plus a new zero `^pr close 86` assertion | treat a missing `state` as OPEN: `pr close 86` is called, case red |
| AC-6 | reopen fails twice: exit 2, stderr names `gh pr reopen 94 --repo`, exactly two `pr reopen 94` calls, one `pr comment 94` holding `the reopen failed`, no `pr merge` | `resync_reopen_fails` (PR 94; `GH_STUB_REOPEN_RC=1`) | ignore the reopen exit code: the run continues to a stale SKIP and exits 0, case red |
| AC-7 | reopen fails once, then succeeds: merged and tree verified, two `pr reopen` calls | `resync_reopen_retry` (PR 95; `GH_STUB_REOPEN_FAILS=1`) | remove the retry: exit 2, case red |
| AC-8 | still stale after a resync: exactly one `pr close` and one `pr reopen`, SKIP ends with `still stale after a close and reopen; wait until gh pr view 97 --json headRefOid shows`, no `pr merge`, exit 0 | `resync_still_stale` (PR 97; no `_REOPENED` answer) | drop the flag that switches on the suffix: `chk_has` on the suffix fails, case red |
| AC-9 | the close argv carries neither `--comment` nor `-d` nor `--delete-branch` | asserted inside `resync_stale_head_merges` on the `pr close 90` log line | add `--delete-branch` to the close call: the argv check fails, case red |
| AC-10 | bare form, dependents open on the branch: no `pr close`, `no resync for #N: dependents open` | `resync_refused_dependents` (PR 98 plus an own PR 99 based on `feat/union`, run without `--pr`) | drop the dependents check in `cmd_merge`: `pr close` is called, case red |
| AC-11 | close fails and the state read shows OPEN: no `pr reopen`, `no resync for #N: close failed`, the existing SKIP | `resync_close_fails_open` (PR 100; `GH_STUB_CLOSE_RC=1`, the read after the close serves `state: OPEN`) | treat a failed close as success: `pr reopen` is called, case red |
| AC-12 | close fails and the state read is empty: no `pr reopen`, `no resync for #N: close failed` | `resync_close_fails_unreadable` (PR 101; `GH_STUB_CLOSE_RC=1`, the read after the close serves `{}`) | reopen on anything but OPEN: `pr reopen` is called, case red |
| AC-13 | the existing `moved`, `stuck` and `settle` cases call no `pr close` | new zero `^pr close` assertions in each | n/a, pins that the resync runs only on a stale head |
| AC-14 | every control in this table is red against its mutant | the TASK-D3 run | n/a |
| AC-15 | precondition read already shows the pushed head: no `pr close`, `caught up on its own`, then merged and tree verified, and no `still stale` text anywhere | `resync_caught_up` (PR 96; `GH_STUB_PR_96_5` on `%REMERGE_TIP%` MERGEABLE CLEAN, OPEN) | return 1 on a pushed head in step 1: the caller gates the stale settle read and SKIPs, case red |
| AC-16 | precondition read shows `autoMergeRequest` non-null: no `pr close`, `no resync for #N: auto-merge armed` | `resync_refused_automerge` (PR 102; `GH_STUB_PR_102_5` with `autoMergeRequest: {"mergeMethod":"SQUASH"}`) | drop the `autoMergeRequest` check: `pr close` is called, case red |
| AC-17 | a decoy ref `refs/heads/a/refs/heads/feat/union` on the bare remote at the old tip, sorting before the real ref: the exact filter still finds the pushed oid, so the resync runs and the PR merges | `resync_exact_ref_match` (PR 103) | take the first `ls-remote` line instead of the exact-ref line: the decoy's old oid fails the comparison, no resync, no merge, case red |
| AC-18 | TERM sent to the wrap process while `pr close` runs: exit 130, stderr holds `INTERRUPTED inside the resync of #104` and `gh pr reopen 104 --repo`, one `pr reopen 104` logged, no `pr merge` | `resync_interrupted_reopens` (PR 104; `GH_STUB_CLOSE_DELAY=2`; the case runs wrap in the background, waits for the `.closing-104` marker, sends TERM, then waits; the read after the close serves `state: CLOSED`) | remove the trap arm: TERM ends wrap with no reopen, so the zero-to-one `pr reopen 104` assertion and the exit-130 check fail, case red |

AC-12 of round 1 (a foreign-authored stale PR is never closed) is dropped as a test case. It had no negative control that could go red: the own-PR filter keeps such a PR out of `numbers`, and the existing `a PR someone else authored is never listed` section already pins that filter. The invariant stays in `### Interfaces`.

## Verification

The exact commands:

```
bash tests/test-wrap-merge.sh
bash tests/run-all.sh --changed origin/master
```

Each negative control runs on a mutated copy of `lib/wrap/wrap-merge.sh` in a scratch worktree (`lib/gate/negctl.sh`), after the branch is committed (TASK-D3), and the named case must go red.

## Edge Cases

1. GitHub catches up between the settle read and the precondition read: step 1 sees `headRefOid` equal to the pushed oid and returns 3 without a close. The caller re-reads and gates. AC-15 pins it, including that no `still stale` text prints.
2. Someone pushes to the branch between the `ls-remote` check and the close: the reopen still runs, the re-read shows a head that is neither old nor pushed, and the existing `head is <x>, not the pushed` SKIP refuses it. Nothing merges. The window is one `gh` round trip because step 2 runs right before the close.
3. A human closes the PR between the precondition read and the close: `gh pr close` on a closed PR does nothing, and wrap then reopens a PR a human closed. The window is one `ls-remote` plus one round trip. Accepted and named in `## Failure modes`.
4. `ls-remote` fails (network): non-zero exit or no exact line, so no resync, and the existing SKIP stands.
5. The dry run (no `--apply`) never reaches the re-merge, so it never reaches the resync.
6. `--no-pull` with the branch in the main checkout: the PR SKIPs before the retry path (`lib/wrap/wrap-merge.sh:471-474`), so no resync.
7. Under `--pr N` the dependents check cannot fire, because the cache holds only N's row. The bare form is the only form where it guards anything (AC-10 runs the bare form).
8. A signal arrives after the trap is armed but before the close runs: the handler reads `state` OPEN and does not reopen; the helper sees the flag before the close, skips it, and returns 130. Nothing changed on GitHub.
9. A signal arrives while the stub or real `gh pr close` runs: bash defers the handler until that child returns, so the handler's `state` read sees the result of the close.
10. Guarantee inversion, "at most one pair per run": the retry path sits behind `conflict_count = 1` and runs once; the helper has no loop. AC-8 pins it.
11. Guarantee inversion, "never a foreign PR": the `numbers` invariant and the existing own-PR filter section pin it.
12. Guarantee inversion, "the merge waits for a read after the reopen": AC-1's mutant without the resync never merges; a mutant that skips the second settle read would gate the stale detail and SKIP, so AC-1 stays red there too.
13. The ci-label gate (`--with-ci`): it runs after the retry path on `first_eligible`, unchanged; it re-reads and re-gates the same pushed head.
14. The autoland carry path runs `cmd_merge` in a subshell with `2>&1` captured into a variable (`lib/wrap/wrap-carry.sh:148`) and prints it at `:149` once the subshell returns. The handler returns 130 rather than dying by the signal, so the subshell exits normally and the parent prints the captured INTERRUPTED and outcome lines. The recovery line goes to stderr from inside the handler before any network call, so it never waits on a later stdout write.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Reopen fails after the close | `FAILED merge #N: closed #N to resync its head, and the reopen failed` on stderr, exit 2 | One retry after 2s first. Then the line names `gh pr reopen N --repo <url>`, and the best-effort comment on the PR says the same to anyone who opens it. |
| INT, TERM or HUP between the close and the reopen | `INTERRUPTED inside the resync of #N` on stderr, exit 130 | The handler reads `state` and reopens once on an exact `CLOSED`, then prints whether it worked; on failure the recovery command is already printed. AC-18 pins it. |
| SIGKILL or a host crash between the close and the reopen | the PR is closed with no wrap comment, and the next `wrap merge` does not list it | Untrappable. The window is two `gh` round trips. Recovery: `gh pr list --repo <url> --author @me --state closed` finds it; `gh pr reopen N` restores it. A durable marker file is rejected for now (DEC-I). |
| TERM sent to the carry parent alone | the carry run's captured output never prints | The `cmd_merge` subshell never got the signal, so it finishes the resync and reopens; only the log is lost. |
| GitHub refuses the reopen because the head was force-pushed while closed | the FAILED line above | The close-to-reopen window is one round trip; the operator reopens by hand or recreates the PR. |
| Reopen re-fires CI | the re-gate SKIPs `checks are pending or failing` | The next `wrap merge` merges once green (`## After state`, Not covered). |
| The close fires `pull_request` `closed` listeners | none inside wrap | Named under Not covered. A repo whose close listeners act on unmerged closes should not run unattended wrap merges. |
| A human closed the PR during the one-round-trip window | the PR reopens with wrap's comment below it | Accepted (Edge 3); the comment names wrap. |
| GitHub still stale after the reopen | the `still stale after a close and reopen` SKIP, naming the wait-then-re-run step | No second pair. |
| The comment fails to post | `comment on #N failed; the resync itself is unaffected` | Harmless; the stdout lines still record the resync. The comment is posted after the reopen step, so a comment failure can never stop or precede a close. |

## Out of Scope

- The cross-run case: a later `wrap merge` call that finds a stale head and a local tip ahead of it still refuses with `left alone` (`lib/wrap/wrap-merge.sh:195-196` and `:204-205`). That run did not push, so it cannot prove the origin tip is its own. This spec narrows how often that path is reached, because the first call now resyncs; it does not remove it. A run that resynced and still found a stale head names the next step in its SKIP: wait until `gh pr view` shows the pushed head, then re-run.
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
- DEC-C: one fresh `state,isDraft,headRefOid,autoMergeRequest` read right before the close. The settled detail has no `state` field, and a PR closed by a human during the settle window must never be reopened by wrap. Rejected: add the fields to `_pr_detail` (widens every read for one path).
- DEC-D: the comment is a separate `gh pr comment` after the reopen step, never `gh pr close --comment`. Whether `gh pr close --comment` posts before or after the close, and whether it closes when the comment fails, is not sampled here; a separate call after the reopen makes that question moot and keeps the closed window to the close and the reopen. The text is static plus short oids, so nothing read from the PR reaches the comment. Rejected: `--comment` on the close (unsampled ordering), no comment (a closed PR after a failed reopen carries no reason).
- DEC-E: a failed reopen retries once after 2s, then exits 2. A closed own PR drops out of `_open_own_prs`, so silence would hide it from every later run. Rejected: no retry (one transient 502 strands the PR), unbounded retry (spins against a real refusal).
- DEC-F: the dependents check lives in `cmd_merge`, before the call, not in the helper. It reads the cache only `cmd_merge` owns, and keeping it out keeps the helper at six arguments and GitHub-side only. It guards only the bare form; under `--pr N` it cannot fire.
- DEC-G: no own-PR re-check inside the helper. `conflict_n` comes only from the own-PR set, so a re-check would be unreachable code.
- DEC-H: no resync while auto-merge is armed. A close disarms it and a reopen does not re-arm it, so the resync would silently drop an operator's armed merge. Rejected: re-arm after the reopen (wrap never arms auto-merge; see `lib/wrap/wrap-merge.sh:599-600`).
- DEC-I: an INT/TERM/HUP trap covers the close-to-reopen window, mirroring `_mvp_trap`. A durable marker file that a later run reads to reopen a stranded PR would also cover SIGKILL, but it adds persisted state for a two-round-trip window. Rejected for now; `## Failure modes` names the manual recovery.
- DEC-J: rc 3 for caught up, separate from rc 0 for resynced, so the still-stale SKIP suffix prints only when a close ran.

## Grounding

External shapes the spec asserts, each sampled read-only on this machine:

- `gh pr view --json headRefOid` shape. Sample: `gh pr view 4496 --repo tieubao/ops-toolkit --json number,headRefName,headRefOid,isDraft,state,mergeable,mergeStateStatus,author` printed `{"author":{...,"login":"tieubao",...},"headRefName":"docs/vps-mon-deploy-pointer","headRefOid":"16eddb8f3943bde62e5caab79fae86874ea85b33","isDraft":false,"mergeStateStatus":"UNKNOWN","mergeable":"UNKNOWN","number":4496,"state":"MERGED"}`. `headRefOid` is a full 40-hex oid; `state` is an upper-case word (`MERGED` here; `OPEN` and `CLOSED` are its other values); `isDraft` is a JSON boolean.
- The precondition read's exact field set. Sample: `gh pr view 4401 --repo tieubao/ops-toolkit --json number,state,isDraft,headRefOid,autoMergeRequest` printed `{"autoMergeRequest":null,"headRefOid":"95022ed1798b42dd4bc66223f2e9dc47427bd2ce","isDraft":false,"number":4401,"state":"OPEN"}`. `autoMergeRequest` is `null` when nothing is armed; `gh pr view --help` lists the field. The armed shape (an object) is not sampled live; the AC-16 fixture uses an object, and the check is `!= null`, so any object refuses.
- An open PR and a draft side by side. Sample: `gh pr list --repo tieubao/ops-toolkit --state open --limit 3 --json number,headRefName,headRefOid,isDraft` printed `[{"headRefName":"feat/jev-first-workflow","headRefOid":"95022ed1...","isDraft":false,"number":4401},{"headRefName":"feat/teardown-clean-route","headRefOid":"5f6c89b0...","isDraft":true,"number":4376}]` (oids trimmed here).
- `git ls-remote` shape. Sample, from the ops-toolkit checkout: `git ls-remote origin refs/heads/feat/jev-first-workflow` printed `95022ed1798b42dd4bc66223f2e9dc47427bd2ce\trefs/heads/feat/jev-first-workflow`, the oid then a tab then the full ref. `git ls-remote origin feat/jev-first-workflow` (a bare tail pattern) printed the same line, which shows patterns match on the ref tail; the exact second-field filter is what rules out a tail-matching decoy.
- The REST pulls endpoint agrees with `gh pr view` in the in-sync case. Sample: `gh api repos/tieubao/ops-toolkit/pulls/4401 --jq '{head_sha: .head.sha, head_ref: .head.ref, state, draft, mergeable_state}'` printed `{"draft":false,"head_ref":"feat/jev-first-workflow","head_sha":"95022ed1798b42dd4bc66223f2e9dc47427bd2ce","mergeable_state":"unknown","state":"open"}`.
- `gh pr close`, `gh pr reopen` and `gh pr comment` flags. `gh pr close --help` lists `-c, --comment string   Leave a closing comment` and `-d, --delete-branch    Delete the local and remote branch after close`; the branch is deleted only with `-d`. `gh pr reopen --help` lists `-c, --comment string   Add a reopening comment`. `gh pr comment --help` lists `-b, --body text        The comment body text`. Version: `gh version 2.101.0 (2026-09-15)`. None of the three verbs was run live. The order in which `gh pr close --comment` posts and closes was not sampled (no gh source on this machine); DEC-D avoids depending on it.
- The stale-head state itself (GitHub reporting the old head for over 90 seconds while `ls-remote` shows the new tip) cannot be sampled on demand. The evidence is the operator's two observations in the item; the stub models it as a stale `headRefOid` served until a `pr reopen` call. TASK-E's optional canary samples the close and reopen side effects on a scratch PR.
- The trap pattern. `_mvp_trap` (`lib/wrap/wrap-common.sh:501-536`) blocks re-entry with `trap '' INT TERM HUP`, sets a flag, judges cleanup by state, and never calls `exit`; `_merge_verify_push` (`:545-570`) saves the caller's handlers with `trap -p` and restores them with `eval` or `trap -`.
- The carry capture. `lib/wrap/wrap-carry.sh:148` runs `out="$( (cmd_merge --apply --pr "$n" "$repo") 2>&1)"` and `:149` prints `$out` after the subshell returns.
- The test stub today answers no `pr close`, `pr reopen` or `pr comment`: an unknown `pr` verb falls to `exit 1` (`tests/lib/wrap-stub.sh:226`). Its `pr view` serves `GH_STUB_PR_<n>_<j>` by read count (`tests/lib/wrap-stub.sh:134-150`). The `nosleep` shim (`tests/lib/wrap-stub.sh:249`) replaces `sleep` on PATH, which is why `GH_STUB_CLOSE_DELAY` must call `/bin/sleep`.

Dry traces, one per negative control (read from `lib/wrap/wrap-merge.sh` at the cited lines; nothing mutated here):

- NC for AC-1 (delete the `_pr_head_resync` call). Fixture: `GH_STUB_PR_90` is the conflict fixture on the old tip; `GH_STUB_PR_90_2` serves the old head CONFLICTING for every later read; `GH_STUB_PR_90_REOPENED` would serve `%REMERGE_TIP%` MERGEABLE CLEAN but is never reached, because no `pr reopen` is logged. Path: read 1 in the cache loop (`:453`) gates SKIP CONFLICTING, so `conflict_count` is 1 (`:484-485`). `_union_remerge` pushes (`:506`). `_pr_detail_settled` (`:519`) polls reads 2 to 4 on the old head and stops at the 4s bound (`:83`). `r_head` is the old oid, so `:522-523` sets `SKIP head is <old>, not the pushed <new>`. Nothing is eligible, `:560` prints `nothing eligible to merge.`, exit 0, no `pr merge` logged. `resync_stale_head_merges` asserts `merged #90 (...): tree verified` and a `pr reopen 90` line. Red.
- NC for AC-2 (drop the oid comparison). Fixture: the bare remote's `post-receive` hook moves `feat/union` to a commit on top of wrap's push. Mutant path: step 1 (read 5) serves OPEN, not a draft, no auto-merge, old head; step 2 finds one exact line but no longer compares its oid, so `pr close 91` is logged. The case asserts zero `^pr close` lines. Red.
- NC for AC-3 (drop the `isDraft` check). Read 5 serves `isDraft: true`; the mutant closes. Zero-close assertion fails. Red.
- NC for AC-4 (drop the `state` check). Read 5 serves `state: CLOSED`; the mutant closes and reopens a closed PR. Zero-close and zero-reopen assertions fail. Red.
- NC for AC-5 (missing `state` read as OPEN). The existing `lost` case at `tests/test-wrap-merge.sh:785-794` uses `conflict_json` with no `state` field. The mutant closes `#86`. The new zero-close assertion fails. Red.
- NC for AC-6 (ignore the reopen exit). `GH_STUB_REOPEN_RC=1`; the mutant returns 0, the caller re-reads, the head is still old, and the run SKIPs with exit 0. The case asserts exit 2 and the `gh pr reopen 94 --repo` text. Red.
- NC for AC-7 (remove the retry). `GH_STUB_REOPEN_FAILS=1`; the mutant returns 2 on the first failure. The case asserts exit 0, `merged #95`, and two `pr reopen 95` lines. Red.
- NC for AC-8 (drop the suffix flag). No `_REOPENED` answer, so the re-read stays old; the mutant prints the SKIP without `still stale after a close and reopen`. `chk_has` on the suffix fails. Red.
- NC for AC-9 (add `--delete-branch`). The stub logs the flag in the `pr close 90` line; the argv assertion fails. Red. (Round 1 also claimed a remote-ref check here; the stub never deletes a branch on close, so that check could not go red and is dropped.)
- NC for AC-10 (drop the dependents check). Run in the bare form, the cache has PR 99's row with base `feat/union`; the mutant calls the helper, which closes `#98`. Zero-close assertion fails. Red.
- NC for AC-11 (failed close treated as success). `GH_STUB_CLOSE_RC=1` and the state read serves OPEN; the mutant calls `pr reopen`. Zero-reopen assertion fails. Red.
- NC for AC-12 (reopen on anything but OPEN). `GH_STUB_CLOSE_RC=1` and the state read serves `{}`, so `state` is empty; the mutant reopens. Zero-reopen assertion fails. Red.
- NC for AC-15 (rc 1 on a pushed head in step 1). Read 5 serves the pushed head; the mutant returns 1, so the caller keeps the stale settle read from reads 2 to 4 and `:522-523` SKIPs. The case asserts `merged #96`. Red.
- NC for AC-16 (drop the `autoMergeRequest` check). Read 5 serves an object; the mutant closes. Zero-close assertion fails. Red.
- NC for AC-17 (first `ls-remote` line). The decoy `refs/heads/a/refs/heads/feat/union` sorts before `refs/heads/feat/union` and holds the old oid; `ls-remote origin refs/heads/feat/union` prints both. The mutant reads the decoy's oid, which is not the pushed oid, so it returns 1 and the run SKIPs. The case asserts `merged #103`. Red.
- NC for AC-18 (remove the trap arm). The case waits for the `.closing-104` marker and sends TERM to the wrap process while the stub sleeps 2s in `/bin/sleep`. With no trap, the shell takes the default TERM action and ends without a `pr reopen`; the exit code is 143, not 130. The case asserts exit 130 and one `pr reopen 104` line. Red.

## Open questions

(none)
