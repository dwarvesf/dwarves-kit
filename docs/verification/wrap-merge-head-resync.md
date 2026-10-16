# Proof of done: `wrap merge` resyncs a stale PR head with one close and reopen

2026-10-16. Spec: `docs/specs/SPEC-405-wrap-merge-head-resync.md`. Lane: full. Files: `lib/wrap/wrap-merge.sh`, `tests/test-wrap-merge.sh`, `tests/lib/wrap-stub.sh`, `commands/wrap.md`, `lib/config/module-registry.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), `docs/implementation-notes/SPEC-405-wrap-merge-head-resync.md`, and this file.

Acceptance: after wrap's own re-merge push, if the settle wait ends with GitHub still on the pre-push head and origin holds exactly the pushed commit, `wrap merge --apply` closes and reopens its own PR once. It then settles and gates again, and merges only the pushed head. It never closes a draft, a fork PR, a PR that is not OPEN, a PR with auto-merge armed, or a PR with open dependents. It also never closes when origin's tip is anything else. A failed reopen, or a failed close whose state cannot be read, exits 2 and prints the exact `gh pr reopen` command. An interrupt inside the close window reopens the PR and exits 130.

## Guards

| Guard | Refuses when | Case |
|---|---|---|
| Fresh read, every field present | `state` is not exactly OPEN, `isDraft` or `isCrossRepository` is not exactly false, `autoMergeRequest` is missing or set, or the head is not the pre-push one | `#92`, `#93`, `#102`, `#105`, `#106`, `#107`, `#118`, `#119`, `#121` |
| Origin is wrap's push | the exact `refs/heads/<branch>` line is missing, ambiguous, or not the pushed oid | `#91`, `#103`, `#122` |
| No churn under dependents | an open PR is based on the branch | `#98` |
| Failed close judged by state | OPEN gives no reopen; CLOSED gives a reopen; three unreadable reads give exit 2 and no blind reopen | `#100`, `#108`, `#101` |
| Reopen | one retry after 2s, then exit 2 with the command | `#95`, `#94` |
| Interrupts | before the close nothing changes; after it, a reopen only on exactly CLOSED, and one more read when the handler saw OPEN | `#110`, `#104`, `#109`, `#111`, `#112`, `#113`, `#115`, `#117` |
| One pair per run | still stale after a resync gives a SKIP that names the next steps, never a second close | `#97` |
| Merge pin | always | `#90`, `#95`, `#96`, `#103`, `#108`, `#114`, `#116` assert `--match-head-commit <pushed>` |

## Green run

```
Command: bash tests/test-wrap-merge.sh
Exit: 0
Output: test-wrap-merge: all 410 passed
Verdict: PASS
```

The same suite was also run as a background job, the way run-all launches it, where SIGINT is ignored on entry:

```
Command: bash -c 'bash tests/test-wrap-merge.sh > log 2>&1 & wait $!'; tail -1 log
Exit: 0
Output: test-wrap-merge: all 410 passed
Verdict: PASS
```

```
Command: RUN_ALL_TIMEOUT_SECS=900 bash tests/run-all.sh --changed --time
Exit: 0
Output: run-all: --changed against 5a1a0f4c: 12 changed files -> 40 suites (36 named, the rest always-on)
        test-wrap-merge                                ok (192s)
        run-all: all 40 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

The suite has 410 assertions: 246 existed before this change and 164 are new. The new ones are the resync section's 160 and four zero-close assertions on the existing settle cases. The longer runner ceiling is there because the default 300s run timed out six suites, wrap-merge among them, while the negative controls loaded the machine. The run above is on an idle machine at `ee783e4f`.

## Negative controls

Run: `bash lib/gate/negctl.sh --parallel 5 "$PWD" "bash docs/verification/wrap-merge-head-resync/negctl-test.sh" "python3 docs/verification/wrap-merge-head-resync/negctl-mutations.py AC-1" ... "... AC-32"` at `32eace33`. negctl exit 0: 29 of 29 controls PASS. Each was green before, red under its mutation, and green after the restore, with the tree unchanged.

| Control | Mutation | Red case, from the run's output tail (failures) | Verdict |
|---|---|---|---|
| AC-1 | delete the `_pr_head_resync` call | `#116: one close` (74 red) | PASS |
| AC-2 | drop the origin oid comparison | `#91: no pr close` (3 red) | PASS |
| AC-3 | drop the `isDraft` test | `#92: a draft is named` (6 red) | PASS |
| AC-4 | drop the `state` test | `#93: a closed PR is named` (6 red) | PASS |
| AC-5 | read a missing `state` as OPEN | `#105: no pr close` (3 red) | PASS |
| AC-6 | ignore the reopen exit code | `#94: one comment saying the reopen failed` (8 red) | PASS |
| AC-7 | remove the reopen retry | `#95: exits 0` (5 red) | PASS |
| AC-8 | drop the still-stale flag | `#97: names the wait` (2 red) | PASS |
| AC-9 | add `--delete-branch` to the close | `#90: the close carries no --comment, -d or --delete-branch` (1 red) | PASS |
| AC-10 | drop the dependents check | `#98: no pr close` (3 red) | PASS |
| AC-11 | treat a failed close as success | `#100`/`#101`/`#108` (8 red) | PASS |
| AC-15 | rc 1 on a caught-up head | `#96: merged, tree verified` (3 red) | PASS |
| AC-16 | drop the `autoMergeRequest` test | `#102: armed auto-merge is named` (6 red) | PASS |
| AC-17 | take the first `ls-remote` line | `#103: merged, tree verified` (3 red) | PASS |
| AC-18 | remove the trap arm | `#104`, `#109`, `#110`, `#111`, `#112`, `#113`, `#115`, `#117` (23 red) | PASS |
| AC-19 | rc 1 on an unreadable failed close | `#101: exits 2` (2 red) | PASS |
| AC-20 | read `isDraft` with `// false` | `#106: no pr close` (3 red) | PASS |
| AC-21 | drop `has("autoMergeRequest")` | `#107: no pr close` (3 red) | PASS |
| AC-22 | drop the flag check right after the close | `#109: the handler's read is the last one (6 reads)` (1 red) | PASS |
| AC-23 | one state read after a failed close | `#101: three state reads, no more` (5 red) | PASS |
| AC-24 | remove the three pre-close flag checks | `#110: no pr close` (1 red) | PASS |
| AC-25 | remove the wrapper's late read | `#113`/`#117` (3 red) | PASS |
| AC-26 | drop the `isCrossRepository` test | `#121: no pr close` (3 red) | PASS |
| AC-27 | drop the moved-head test | `#118: no pr close` (3 red) | PASS |
| AC-28 | reopen on an OPEN read in the handler | `#111: an open PR is left alone` (2 red) | PASS |
| AC-29 | `_url_public` returns the raw URL | `unit: userinfo is stripped` (1 red) | PASS |
| AC-30 | drop the flag reset at entry | `#121: exits 0` and every refusal case (97 red: `set -u` meets an unset flag) | PASS |
| AC-31 | drop the TERM handler restore | `unit: the caller's TERM trap is back` (2 red) | PASS |
| AC-32 | drop the comment-failure line | `#114: names the failed comment` (1 red) | PASS |

`negctl-test.sh` resets INT, TERM and HUP to their defaults through `perl` before it runs the suite. negctl's `restore()` sets `trap '' INT TERM HUP` for its whole process and never undoes it. bash cannot trap a signal that was ignored on entry, so without the reset every TERM-based case fails the post-restore run. That includes the pre-existing `merge-cycle: TERM inside a scratch-worktree cycle` case. A first batch without the reset showed exactly that: all 29 controls were red under the mutation but `test not green after restore`. This is a negctl defect, outside this change.

Two of the blocks, with scratch paths masked and the unrelated `PASS` lines cut from each `Output:` tail:

```
## Negative control (negctl)
Command: bash <scratch>/nc-test.sh
Exit: 0 (green before mutation)
Output:
  test-wrap-merge: all 410 passed

Mutation: python3 <scratch>/mut.py AC-22
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL resync #109: the handler's read is the last one (6 reads)
  test-wrap-merge: 409 passed, 1 FAILED of 410

Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
## Negative control (negctl)
Command: bash <scratch>/nc-test.sh
Exit: 0 (green before mutation)
Output:
  test-wrap-merge: all 410 passed

Mutation: python3 <scratch>/mut.py AC-24
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL resync #110: no pr close
  test-wrap-merge: 409 passed, 1 FAILED of 410

Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

`<scratch>/nc-test.sh` and `<scratch>/mut.py` are byte-for-byte the committed `negctl-test.sh` and `negctl-mutations.py`, apart from the docstring line.

## Primary flow

The real flow cannot be produced on demand. GitHub serving a stale head after a push is the observed anomaly, and nothing triggers it. The closest end-to-end run is the one the suite performs:

- the real `bin/wrap merge --apply` against a real bare remote;
- a real union re-merge and push;
- a gh stub that serves the stale head until a `pr reopen` is logged.

`#90` is that run. It covers the re-merge, the push, the stale settle, the close, the reopen, the second settle, the gate, the pinned merge and the tree verify.

## Not proven

- That a close and a reopen make GitHub re-read a stale head. This is the spec's one unsampled premise, and the operator's two hand recoveries are the only evidence for it.
- A live close and reopen canary on a scratch PR: [UNAVAILABLE: this worker runs under a never-push, never-merge brief, so creating a scratch repo and PR on GitHub is out of bounds; the lead can run it on a throwaway PR].
- A signal landing between the last pre-close flag check and the `gh pr close` spawn. That window cannot be hit deterministically. `#117` covers its effect: the handler reads OPEN, then the late read finds CLOSED and reopens.
- The handler's `gh` calls have no timeout. A hung `gh` inside the handler yields only to SIGKILL.
