# Spec: wrap merge resyncs a stale PR head with one close and reopen
Generated: 2026-10-16
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a close whose reopen fails leaves the operator's own PR closed, and no later wrap run lists a closed PR, so it drops off every board silently)
References: `lib/wrap/wrap-merge.sh:516-548` (the post-push re-gate in `cmd_merge`; the resync slots in between its settle read and its head check); `lib/wrap/wrap-merge.sh:70-87` (`_pr_detail_settled`; reuse as is for the re-read after the reopen); `lib/wrap/wrap-merge.sh:421-442` (the `--pr` draft path; imitate its one-shot `gh pr ready` call and its `FAILED merge #N: ... return 2` shape for the reopen failure); `tests/test-wrap-merge.sh:721-805` (the settle cases; imitate their fixture shape, the `nosleep` PATH and the `views` counter).

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

1. **One close and reopen, gated on proof that wrap's own push is the only difference.** When the settle wait ends on the pre-push head, and origin's branch tip is exactly the commit wrap pushed, close and reopen the PR once, then settle again. Tradeoff: a visible close and reopen pair lands in the PR timeline, and a failed reopen leaves the PR closed.
2. **A longer settle bound.** Raise `KIT_WRAP_SETTLE_SECS` or add a second wait. Tradeoff: the observed stale head outlived 90 seconds and cleared only on a close and reopen, so a longer wait just refuses later.
3. **Push an empty commit to nudge GitHub.** Tradeoff: it adds a commit to the branch, the next head is again one GitHub may not register, and a pushed commit is harder to take back than a reopen.

### Chosen approach + why

Approach 1. It is the recovery the operator ran by hand, and it worked on the first try both times. Approach 2 does not fix the observed case. Approach 3 writes to the branch, and the branch is the thing a merge must not change behind the gates.

The resync never stands in for the gates. After the reopen, the same `_pr_detail_settled` read runs, and the existing head check and `_pr_gate` decide. The merge stays pinned to the pushed head with `--match-head-commit`.

### Extensibility & boundaries

- The load-bearing dimension is how many places wrap pushes and then waits on GitHub. Today two do: this re-merge path and `land`'s merge retry (`lib/wrap/wrap-land.sh:739-742`). The helper takes a PR number, a branch, a prior head and a pushed head, so `land` could call it later without change. This spec wires only `merge`.
- One unit: `_pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid>`. It checks the preconditions, closes, and reopens. It never reads the merge verdict and never merges. It returns 0 (resynced, or GitHub caught up on its own, so re-read), 1 (preconditions not met, nothing changed) or 2 (closed and the reopen failed).

### Architecture

See `## Design` below.

## Picture

```
  cmd_merge, the single-conflict retry path (--apply only)
  ---------------------------------------------------------
  _union_remerge ---push---> origin/<branch> = PUSHED
        |
        v
  _pr_detail_settled(want=PUSHED, prior=OLD)          [existing, unchanged]
        |
        +-- head == PUSHED -------------------------------> existing gate path
        +-- head == other (foreign push) -----------------> existing SKIP, no resync
        +-- head == OLD (stale)
                |
                v
        _pr_head_resync  [NEW]
          1. dependents open on <branch>?  yes -> rc 1
          2. git ls-remote origin <branch> == PUSHED?  no -> rc 1
          3. gh pr view N --json state,isDraft,headRefOid
               head PUSHED already?  yes -> rc 0, no close
               state OPEN, isDraft false, head OLD?  no -> rc 1
          4. gh pr close N --comment "<why>"     (never --delete-branch)
               fails and PR still OPEN -> rc 1
          5. gh pr reopen N   (one retry after 2s)
               fails twice -> rc 2  ---------------------> FAILED, exit 2
                |
             rc 0
                v
        _pr_detail_settled(want=PUSHED, prior=OLD)    [second and last read window]
                |
                v
        existing head check + _pr_gate + dependents gate
          head still OLD -> SKIP "... still stale after a close and reopen"
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds one tradeoff: the precondition read (step 3) costs one extra `gh pr view` per resync. It buys a fresh `state` check right before the close, so a PR a human closed during the settle window is never reopened by wrap.

### Diagram

The flowchart in `## Picture` is the design diagram. `docs/SYSTEM-DESIGN.md` does not exist in this repo, and the change adds no container or external system; it is L3 detail inside `lib/wrap/wrap-merge.sh`.

### ADR link(s)

None. The close and reopen is reversible by the same verb, and the decisions are recorded in `## Decision Log`.

### Boundaries & failure modes

The design touches an external integration (GitHub PR state). Out of bounds: any PR not in this run's own-PR set, any draft, any PR not OPEN, any branch whose origin tip is not wrap's pushed commit. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes:
  - The settled detail JSON from `_pr_detail_settled <url> <n> <pushed> <prior>`: `headRefOid` decides whether the resync runs.
  - `git -C <repo> ls-remote origin refs/heads/<branch>`: one line, `<oid>\t<ref>`. The first field is compared to the pushed oid. Empty output or a non-zero exit means no resync.
  - `gh pr view <n> --repo <url> --json state,isDraft,headRefOid`: `state` must be exactly `OPEN`, `isDraft` exactly `false`, `headRefOid` exactly the prior oid. A missing or unreadable field means no resync.
  - The dependents cache `${jsondir}/index` that `cmd_merge` already builds (`number\thead\tbase` rows).
- Outputs / produces:
  - `gh pr close <n> --repo <url> --comment "<text>"`. The comment names wrap, the stale head and the pushed head. Never `-d` or `--delete-branch`.
  - `gh pr reopen <n> --repo <url>`, retried once after 2s on a non-zero exit.
  - Stdout lines, indented five spaces like the other re-merge notes:
    - `     #N still shows head <old> after the push of <new>; closing and reopening #N to resync`
    - `     resynced #N: closed and reopened`
    - `     #N caught up on its own; no resync needed`
    - `     no resync for #N: <reason>` (one reason: dependents open, origin tip is <x>, not the pushed <new>, state <s>, a draft, head moved to <x>, close failed)
  - A stale head after the resync keeps the existing SKIP prefix and appends: `SKIP #N after the re-merge: head is <old>, not the pushed <new>, still stale after a close and reopen`.
  - A failed reopen prints to stderr: `FAILED merge #N: closed #N to resync its head, and the reopen failed; reopen it: gh pr reopen N --repo <url>`, and `cmd_merge` returns 2.
- Invariants:
  - At most one close and one reopen pair per `wrap merge` run. The retry path itself runs once per run (`lib/wrap/wrap-merge.sh:497`).
  - No close unless `state` read `OPEN` in the read right before it.
  - The merge stays pinned to the pushed head (`--match-head-commit`), and only after the existing head check and `_pr_gate` pass on a read taken after the reopen.
  - A PR outside the run's own-PR set never reaches this path: `numbers` is the own-PR set (`lib/wrap/wrap-merge.sh:410-426`), and the conflict retry draws `conflict_n` only from it.

### Data model changes

None.

### API changes (endpoints, request/response shapes)

None to wrap's CLI. Two new outbound `gh` calls (`pr close`, `pr reopen`) and one extra read (`pr view --json state,isDraft,headRefOid`), all on the retry path only.

### UI changes (screens, components, interactions)

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Test stub

- [ ] TASK-A: Extend the gh stub in `tests/lib/wrap-stub.sh`. Add `pr close` and `pr reopen` verbs. Each records its call like every other verb. `GH_STUB_CLOSE_RC` and `GH_STUB_REOPEN_RC` set their exits (default 0). `GH_STUB_REOPEN_FAILS=N` fails the first N reopens, then exits 0. A successful `pr reopen <n>` writes a marker `${GH_STUB_CALLS}.reopened-<n>`. Once the marker exists, every later `pr view <n>` serves `GH_STUB_PR_<n>_REOPENED` when set, with the same `%REMERGE_TIP%` substitution, ahead of the indexed `_<j>` answers. Acceptance: every existing section of `tests/test-wrap-merge.sh` and `tests/test-wrap-land.sh` stays green with the stub change alone.

### Phase 2: The resync

- [ ] TASK-B: Add `_pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid> <cache>` to `lib/wrap/wrap-merge.sh`, beside `_pr_detail_settled`, with a header comment in the file's style. It runs the five steps in `## Picture` in that order and returns 0, 1 or 2 per `### Extensibility & boundaries`. On a close that exits non-zero, it reads `state` once: `OPEN` returns 1 with `close failed`; anything else goes on to the reopen, because wrap may have closed it. Acceptance: AC-1 to AC-10 and AC-15.
- [ ] TASK-C: Wire it into `cmd_merge` right after the post-push `_pr_detail_settled` read (`lib/wrap/wrap-merge.sh:519`). It runs only when that read's `headRefOid` equals `c_oid`. On 0, re-read with `_pr_detail_settled "$url" "$conflict_n" "$REMERGE_OID" "$c_oid"` and set a flag that appends `, still stale after a close and reopen` to the stale-head SKIP. On 2, `rm -rf "$jsondir"` and return 2. On 1, the existing path runs unchanged. Acceptance: AC-1, AC-6, AC-11.

### Phase 3: Tests and docs

- [ ] TASK-D: Add a section `merge: a stale head after wrap's own push resyncs with one close and reopen` to `tests/test-wrap-merge.sh` holding every case in the AC table. Assert in the existing `moved`, `stuck` and `settle` cases that no `pr close` was called. Acceptance: the section runs green, and each negative control in the AC table turns its case red.
- [ ] TASK-E: Docs. Add one sentence to the `merge` bullet in `commands/wrap.md` (line 127) naming the one close and reopen, its preconditions, and the exit 2 on a failed reopen. Add one clause to the `KIT_WRAP_SETTLE_SECS` row in `lib/config/module-registry.md`: the wait can run a second time after a resync. Write the proof at `docs/verification/wrap-merge-head-resync.md`, table-first. Acceptance: `grep -c 'reopen' commands/wrap.md` is at least 1; the proof file holds the captured test output.

## After state

- [ ] A PR whose head GitHub never re-reads after wrap's own re-merge push merges in one `wrap merge --apply` call, checkable by the `resync_stale_head_merges` case. (Today: the call SKIPs with `head is <old>, not the pushed <new>`, and the next call refuses with `left alone`.)
- [ ] wrap never closes a PR that is a draft, not OPEN, not the operator's own, or whose origin tip is not wrap's pushed commit, checkable by `grep -c '^pr close' <stub log>` equal to 0 in each refusal case.
- [ ] A failed reopen exits 2 and prints the exact `gh pr reopen` command, checkable by the `resync_reopen_fails` case. (Today: no path closes a PR.)
- [ ] `commands/wrap.md` names the close and reopen, checkable by `grep -n 'reopen' commands/wrap.md`.

Not covered: a reopen re-fires the repo's `pull_request` `reopened` event, so a repo whose checks run on it sees them restart. That call then SKIPs with `checks are pending or failing`, and the next `wrap merge` call merges once they pass. This matches the SPEC-306 "Not covered" note.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] The AC table below is green, and each negative control turns its case red
- [ ] No regressions in `tests/test-wrap-merge.sh` and `tests/test-wrap-land.sh`

### AC table

Fixture shape for every case: `build_remerge <name>`, `PATH="$TMPD/nosleep:$PATH"`, `KIT_WRAP_SETTLE_SECS=4`, `GH_STUB_PR_<n>` a conflict fixture on the old tip with `"state":"OPEN","isDraft":false` added, and `GH_STUB_PR_<n>_2` the same stale head reading CONFLICTING. Reads 2 to 4 are the settle window; read 5 is the precondition read.

| AC | Criterion | Test case | Negative control (mutation, expected red) |
|---|---|---|---|
| AC-1 | stale head, origin tip is the pushed commit, OPEN, not a draft: one `pr close`, then one `pr reopen`, then eligible and `merged #N (<sha>): tree verified`, merge pinned with `--match-head-commit <pushed>` | `resync_stale_head_merges` (`GH_STUB_PR_90_REOPENED` on `%REMERGE_TIP%` MERGEABLE CLEAN, `GH_STUB_LAND_REPO` set) | delete the `_pr_head_resync` call in `cmd_merge`: the run SKIPs `head is <old>, not the pushed`, no merge, case red |
| AC-2 | origin tip is not the pushed commit (a foreign commit landed after wrap's push): no `pr close`, the existing SKIP, `no resync for #N: origin tip is` | `resync_refused_origin_moved` (PR 91; a `post-receive` hook in the bare remote commits on top of wrap's push) | drop the ls-remote comparison: `pr close` is called, case red |
| AC-3 | precondition read shows `isDraft: true`: no `pr close`, `no resync for #N: a draft` | `resync_refused_draft` (`GH_STUB_PR_92_5` stale with `isDraft: true`) | drop the `isDraft` check: `pr close` is called, case red |
| AC-4 | precondition read shows `state: CLOSED`: no `pr close`, no `pr reopen`, `no resync for #N: state CLOSED` | `resync_refused_closed` (`GH_STUB_PR_93_5` with `state: CLOSED`) | drop the `state` check: `pr close` and `pr reopen` are called, case red |
| AC-5 | precondition read has no `state` field: no `pr close` (fail closed) | the existing `lost` case, plus a new `grep -c '^pr close 86'` equal to 0 assertion | treat a missing `state` as OPEN: `pr close 86` is called, case red |
| AC-6 | reopen fails twice: exit 2, stderr names `gh pr reopen 94 --repo`, exactly two `pr reopen 94` calls, no `pr merge` | `resync_reopen_fails` (`GH_STUB_REOPEN_RC=1`) | ignore the reopen exit code: the run continues to a stale SKIP and exits 0, case red |
| AC-7 | reopen fails once, then succeeds: merged and tree verified, two `pr reopen` calls | `resync_reopen_retry` (`GH_STUB_REOPEN_FAILS=1`) | remove the retry: exit 2, case red |
| AC-8 | still stale after the reopen: exactly one `pr close` and one `pr reopen`, SKIP ends `still stale after a close and reopen`, no `pr merge`, exit 0 | `resync_still_stale` (no `_REOPENED` answer) | drop the flag that appends the suffix: `chk_has` on the suffix fails, case red |
| AC-9 | the close argv carries `--comment` and never `-d` or `--delete-branch`; the remote branch still exists after the run | asserted inside `resync_stale_head_merges` | add `--delete-branch` to the close call: argv check and remote-ref check fail, case red |
| AC-10 | dependents open on the branch: no `pr close`, `no resync for #N: dependents open` | `resync_refused_dependents` (a second own PR based on `feat/union`) | drop the dependents check: `pr close` is called, case red |
| AC-11 | close fails and the PR still reads OPEN: no `pr reopen`, `no resync for #N: close failed`, the existing SKIP | `resync_close_fails_open` (`GH_STUB_CLOSE_RC=1`, the state read after it serves OPEN) | treat a failed close as success: `pr reopen` is called, case red |
| AC-12 | a foreign-authored stale PR is never closed | `resync_foreign_pr_untouched` (`GH_STUB_OPEN_PRS` entry with `author.login` other) | n/a, structural: the PR never enters `numbers`; pinned by the existing `a PR someone else authored is never listed` section |
| AC-13 | the existing `moved`, `stuck` and `settle` cases call no `pr close` | new `grep -c '^pr close'` equal to 0 assertions in each | n/a, pins that the resync runs only on a stale head |
| AC-14 | every control above is red against its mutant | the control run in `## Verification` | n/a |
| AC-15 | precondition read already shows the pushed head: no `pr close`, `caught up on its own`, then merged and tree verified | `resync_caught_up` (`GH_STUB_PR_96_5` on `%REMERGE_TIP%` MERGEABLE CLEAN, OPEN) | return 1 on a pushed head at step 3: the caller gates the stale settle read and SKIPs, case red |

## Verification

The exact commands:

```
bash tests/test-wrap-merge.sh
bash tests/run-all.sh --changed origin/master
```

Each negative control runs on a mutated copy of `lib/wrap/wrap-merge.sh` in a scratch worktree (`lib/gate/negctl.sh`), after the branch is committed, and the named case must go red.

## Edge Cases

1. GitHub catches up between the settle read and the precondition read: step 3 sees `headRefOid` equal to the pushed oid. The helper returns 0 without a close and prints `#N caught up on its own; no resync needed`. The caller re-reads and gates as after a resync. AC-15 pins it.
2. Someone pushes to the branch between the ls-remote check and the close: the reopen still runs, the re-read shows a head that is neither old nor pushed, and the existing `head is <x>, not the pushed` SKIP refuses it. Nothing merges.
3. A human closes the PR between the precondition read and the close: `gh pr close` on a closed PR is a no-op, and wrap then reopens a PR a human closed. The window is one `gh` round trip. Accepted and named in `## Failure modes`.
4. `ls-remote` fails (network): empty output, so no resync, and the existing SKIP stands.
5. The dry run (no `--apply`) never reaches the re-merge, so it never reaches the resync.
6. `--no-pull` with the branch in the main checkout: the PR SKIPs before the retry path (`lib/wrap/wrap-merge.sh:471-474`), so no resync.
7. Guarantee inversion, "at most one pair per run": the retry path sits behind `conflict_count = 1` and runs once; the helper has no loop. AC-8 pins it.
8. Guarantee inversion, "never a foreign PR": AC-12 and the `numbers` invariant pin it.
9. Guarantee inversion, "the merge waits for a read after the reopen": AC-1's mutant without the resync never merges; a mutant that skips the second settle read would gate the stale detail and SKIP, so AC-1 stays red there too.
10. The ci-label gate (`--with-ci`): it runs after the retry path on `first_eligible`, unchanged; it re-reads and re-gates the same pushed head.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Reopen fails after the close | `FAILED merge #N: closed #N to resync its head, and the reopen failed` on stderr, exit 2 | One retry after 2s first. Then the line names `gh pr reopen N --repo <url>`; the close comment on the PR explains the state to anyone who opens it. |
| GitHub refuses the reopen because the head was force-pushed while closed | same FAILED line | The close-to-reopen window is one round trip; the operator reopens by hand or recreates the PR. |
| Reopen re-fires CI | the re-gate SKIPs `checks are pending or failing` | The next `wrap merge` merges once green (`## After state`, Not covered). |
| A human closed the PR during the one-call window | the PR reopens with wrap's close comment above it | Accepted (Edge 3); the comment names wrap, so the trail is visible. |
| GitHub still stale after the reopen | `still stale after a close and reopen` SKIP | No second pair. The operator waits, or checks GitHub status. |
| The close comment fails to post but the close succeeds | the close exits 0, so nothing to detect | Harmless; the stdout line still records the resync. |

## Out of Scope

- The cross-run case: a later `wrap merge` call that finds a stale head and a local tip ahead of it (`left alone` at `lib/wrap/wrap-merge.sh:195-196` and `:204-205`). That run did not push, so it cannot prove the origin tip is its own. With this spec the first call resyncs, so the second call no longer arises from this path.
- `land`'s merge retry stale-head refusal (`lib/wrap/wrap-land.sh:739-742`). The helper is shaped so a later spec can call it there.
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
- DEC-B: the resync requires origin's tip to equal the oid wrap pushed in this run, read by `git ls-remote`, not the local tip. A local tip proves only what this checkout holds; GitHub reads origin. Rejected: compare the local worktree tip (misses a foreign push).
- DEC-C: one fresh `state,isDraft,headRefOid` read right before the close. The settled detail has no `state` field, and a PR closed by a human during the settle window must never be reopened by wrap. Rejected: add `state` to `_pr_detail` (widens every read for one path).
- DEC-D: the close carries a `--comment` naming wrap and the two heads. A close and reopen pair with no reason reads as an accident in the timeline, and if the reopen fails the comment is what a human sees. Rejected: comment on the reopen (absent exactly when it matters).
- DEC-E: a failed reopen retries once after 2s, then exits 2. A closed own PR drops out of `_open_own_prs`, so silence would hide it from every later run. Rejected: no retry (one transient 502 strands the PR), unbounded retry (spins against a real refusal).
- DEC-F: no resync when dependents are open. The dependents gate would refuse the merge anyway, so a resync there is visible churn with no merge behind it.
- DEC-G: no own-PR re-check inside the helper. `conflict_n` comes only from the own-PR set, so a re-check would be unreachable code. AC-12 pins the end-to-end property.

## Grounding

External shapes the spec asserts, each sampled read-only on this machine:

- `gh pr view --json headRefOid` shape. Sample: `gh pr view 4496 --repo tieubao/ops-toolkit --json number,headRefName,headRefOid,isDraft,state,mergeable,mergeStateStatus,author` printed `{"author":{...,"login":"tieubao",...},"headRefName":"docs/vps-mon-deploy-pointer","headRefOid":"16eddb8f3943bde62e5caab79fae86874ea85b33","isDraft":false,"mergeStateStatus":"UNKNOWN","mergeable":"UNKNOWN","number":4496,"state":"MERGED"}`. `headRefOid` is a full 40-hex oid; `state` is an upper-case word (`MERGED` here; `OPEN` and `CLOSED` are its other values); `isDraft` is a JSON boolean.
- An open PR and a draft side by side. Sample: `gh pr list --repo tieubao/ops-toolkit --state open --limit 3 --json number,headRefName,headRefOid,isDraft` printed `[{"headRefName":"feat/jev-first-workflow","headRefOid":"95022ed1...","isDraft":false,"number":4401},{"headRefName":"feat/teardown-clean-route","headRefOid":"5f6c89b0...","isDraft":true,"number":4376}]` (oids trimmed here).
- `git ls-remote` shape. Sample, from the ops-toolkit checkout: `git ls-remote origin refs/heads/feat/jev-first-workflow` printed `95022ed1798b42dd4bc66223f2e9dc47427bd2ce\trefs/heads/feat/jev-first-workflow`. It matches the `headRefOid` above, which is the in-sync case. The first tab-separated field is the oid.
- The REST pulls endpoint agrees with `gh pr view` in the in-sync case. Sample: `gh api repos/tieubao/ops-toolkit/pulls/4401 --jq '{head_sha: .head.sha, head_ref: .head.ref, state, draft, mergeable_state}'` printed `{"draft":false,"head_ref":"feat/jev-first-workflow","head_sha":"95022ed1798b42dd4bc66223f2e9dc47427bd2ce","mergeable_state":"unknown","state":"open"}`.
- `gh pr close` and `gh pr reopen` flags. `gh pr close --help` lists `-c, --comment string   Leave a closing comment` and `-d, --delete-branch    Delete the local and remote branch after close`; the branch is deleted only with `-d`. `gh pr reopen --help` lists `-c, --comment string   Add a reopening comment`. Version: `gh version 2.101.0 (2026-09-15)`. Neither verb was run live.
- The stale-head state itself (GitHub reporting the old head for over 90 seconds while `ls-remote` shows the new tip) cannot be sampled on demand. The evidence is the operator's two observations in the item; the stub models it as a stale `headRefOid` served until a `pr reopen` call.
- The test stub today answers no `pr close` or `pr reopen`: an unknown `pr` verb falls to `exit 1` (`tests/lib/wrap-stub.sh:226`). Its `pr view` serves `GH_STUB_PR_<n>_<j>` by read count (`tests/lib/wrap-stub.sh:134-150`). TASK-A adds the two verbs and the `_REOPENED` answer.

Dry traces, one per negative control (read from `lib/wrap/wrap-merge.sh` at the cited lines; nothing mutated here):

- NC for AC-1 (delete the `_pr_head_resync` call). Fixture: `GH_STUB_PR_90` is the conflict fixture on the old tip; `GH_STUB_PR_90_2` serves the old head CONFLICTING for every later read; `GH_STUB_PR_90_REOPENED` would serve `%REMERGE_TIP%` MERGEABLE CLEAN but is never reached, because no `pr reopen` is logged. Path: read 1 in the cache loop (`:453`) gates SKIP CONFLICTING, so `conflict_count` is 1 (`:484-485`). `_union_remerge` pushes (`:506`). `_pr_detail_settled` (`:519`) polls reads 2 to 4 on the old head and stops at the 4s bound (`:83`). `r_head` is the old oid, so `:522-523` sets `SKIP head is <old>, not the pushed <new>`. Nothing is eligible, `:560` prints `nothing eligible to merge.`, exit 0, no `pr merge` logged. `resync_stale_head_merges` asserts `merged #90 (...): tree verified` and a `pr reopen 90` line. Red.
- NC for AC-2 (drop the ls-remote comparison). Fixture: the bare remote's `post-receive` hook moves `feat/union` to a commit on top of wrap's push. Mutant path: the helper skips step 2, and the precondition read (read 5) serves OPEN, not a draft, old head, so `pr close 91` is logged. The case asserts zero `^pr close` lines. Red.
- NC for AC-3 (drop the `isDraft` check). Read 5 serves `isDraft: true`; the mutant closes. Zero-close assertion fails. Red.
- NC for AC-4 (drop the `state` check). Read 5 serves `state: CLOSED`; the mutant closes and reopens a closed PR. Zero-close and zero-reopen assertions fail. Red.
- NC for AC-5 (missing `state` read as OPEN). The existing `lost` case at `tests/test-wrap-merge.sh:785-794` uses `conflict_json` with no `state` field. The mutant closes `#86`. The new zero-close assertion fails. Red.
- NC for AC-6 (ignore the reopen exit). `GH_STUB_REOPEN_RC=1`; the mutant returns 0, the caller re-reads, the head is still old, and the run SKIPs with exit 0. The case asserts exit 2 and the `gh pr reopen 94 --repo` text. Red.
- NC for AC-7 (remove the retry). `GH_STUB_REOPEN_FAILS=1`; the mutant returns 2 on the first failure. The case asserts exit 0, `merged #95`, and two `pr reopen 95` lines. Red.
- NC for AC-8 (drop the suffix flag). No `_REOPENED` answer, so the re-read stays old; the mutant prints the SKIP without `still stale after a close and reopen`. `chk_has` on the suffix fails. Red.
- NC for AC-9 (add `--delete-branch`). The stub logs the flag in the `pr close` argv; the argv assertion fails. Red.
- NC for AC-10 (drop the dependents check). The second own PR's base is `feat/union`, so the cache has a dependent row; the mutant closes. Zero-close assertion fails. Red.
- NC for AC-11 (treat a failed close as success). `GH_STUB_CLOSE_RC=1` and the state read serves OPEN; the mutant calls `pr reopen`. Zero-reopen assertion fails. Red.
- NC for AC-15 (rc 1 on a pushed head at step 3). Read 5 serves the pushed head; the mutant returns 1, so the caller keeps the stale settle read from reads 2 to 4 and `:522-523` SKIPs. The case asserts `merged #96`. Red.

## Open questions

(none)
