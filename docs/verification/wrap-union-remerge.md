# Proof of done: `wrap merge` recovers once from a conflict GitHub invented

2026-09-12. Acceptance: when `bin/wrap merge --apply` finds nothing eligible and exactly one open PR
reports `CONFLICTING`, it merges `origin/<default>` into the branch inside the checkout that holds it,
pushes, and re-gates the PR once. A merge that stops on a conflict aborts and changes nothing. A dry
run announces the retry instead of running it. Lane: full. Files: `lib/wrap/wrap.sh`,
`tests/test-wrap.sh`.

## Why this is safe to automate

GitHub resolves a squash merge on its own side, and that resolution never reads `.gitattributes`. A
log both branches appended to therefore conflicts on the PR while a local `git merge` resolves it by
keeping every line, because the repo declared the file `merge=union`. The local merge is the repo's
own stated semantics for that file, not a judgment.

That asymmetry is also the classifier. Git applies the union attribute during the merge this code
runs, so anything git cannot resolve is a real conflict a human owns. The abort on a conflicted merge
is what keeps the automation inside the declared-safe case; no separate guess about which files are
union-marked is needed or made.

## The failure this replaces

The conflict fired twice in one long session, each time on a branch whose only divergence was an
append-only log. Each recovery cost a manual merge of the default branch, a re-push, and a second
trip through the merge gates. Two memory notes describe the recovery; neither prevents the cost.

## Guards, all fail-closed

| Guard | Refuses when | Why |
|---|---|---|
| Unambiguous target | more than one PR is `CONFLICTING`, or anything else is eligible | the branch to recover would be a guess |
| Tip identity | the local branch tip is not the head the gates read | otherwise the push ships commits no gate saw |
| Clean checkout | the worktree holding the branch is dirty | a merge would sweep uncommitted work into the branch |
| Foreign writer | an `index.lock` older than the stale window is held | another writer owns the checkout |
| Already current | the branch already contains `origin/<default>` | a re-merge cannot clear that conflict, so the cause is elsewhere |
| Real conflict | `git merge` stops | proves the divergence is not the union case; aborts, branch untouched |
| Re-gate | the post-push read fails any gate | a dismissed approval, a broken check or an open dependent refuses here |
| Bounded | always | one retry, never a loop |

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 348 passed`
Verdict: PASS. 326 assertions before the change, 348 after; the 22 new ones cover six cases against
real git repos built on disk.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 852 / 852`
Verdict: PASS.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output: `Passed: 498 / 498`
Verdict: PASS.

Command: `bash tests/run-all.sh`
Exit: 0
Output: `run-all: FAILED -> test-config-registry` / `run-all: 138 suites run, 1 skipped for missing tooling`
Verdict: PASS, no regression. `test-config-registry` fails the same two `wrap.drain_staged`
assertions on `master` before the change, so the counts match on both sides.

| Suite run | Suites | Skipped | Failing suites |
|---|---|---|---|
| Before, `master` c7f4d78 | 138 | 1 | test-config-registry (2 assertions, `48/50 passed`) |
| After, `feat/wrap-union-remerge` | 138 | 1 | test-config-registry (2 assertions, `48/50 passed`) |

## Cases the tests bind

Each case builds its own bare origin plus a clone carrying a real `.gitattributes`, a log both sides
appended to, and a real divergent commit. Nothing stubs `git`: what git does to a union-marked file
during a merge is the whole subject. `gh` stays stubbed, and the stub can serve a second detail read,
which is how a PR whose mergeability changes after the push is modelled.

| Case | Setup | Asserted |
|---|---|---|
| Dry run | one conflicting PR, no `--apply` | the retry is announced, the branch tip is unchanged, no `pr merge` |
| Happy path | union log diverged both sides | the push is reported, the re-gate passes, one `pr merge`, the remote branch advanced, both log lines present, the merge pinned the head the re-gate read rather than the stale one |
| Real conflict | `a.txt` also diverged, outside the union declaration | the abort is reported, the tip is unchanged, no half-merged tree, no `pr merge` |
| Tip moved | PR head is not the local tip | the mismatch is named, no `pr merge` |
| Two conflicts | two conflicting PRs | nothing is retried, the tip is unchanged |
| Re-gate refuses | the post-push read reports `CHANGES_REQUESTED` | the reason is named, no `pr merge` |

`pinned the head the re-gate read, not the stale one` is the load-bearing one. A retry that merged
against the pre-push OID would ship a `--match-head-commit` that can never match, or worse, match a
head no gate saw.

## Negative control

Command: `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<mutation>'`
Mutation: change the retry's arity guard from `1` to `99`, which makes the retry unreachable while
every other path stays intact.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/\[ "\$conflict_count" = 1 \]/[ "\$conflict_count" = 99 ]/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Eleven assertions go RED under that mutation, `test-wrap: 337 passed, 11 FAILED of 348`:

```
  FAIL re-merge dry run names the branch it would re-merge
  FAIL re-merge --apply reports the push
  FAIL re-merge --apply re-gates the PR
  FAIL re-merge --apply merges the recovered PR
  FAIL re-merge --apply called pr merge exactly once
  FAIL re-merge --apply pinned the head the re-gate read, not the stale one
  FAIL re-merge --apply advanced the remote branch
  FAIL re-merge --apply kept both log lines
  FAIL re-merge with a real conflict says it aborted
  FAIL re-merge refuses a branch whose tip is not the PR head
  FAIL a re-gate that refuses after the push names the reason
```

The other eleven new assertions stay green under the mutation, and they should: each one asserts that
nothing happened. A tip left alone, a `pr merge` never called, an exit of 0 with no merge, all hold
both when a guard refuses and when the retry is unreachable. They bind the safety property. The
eleven above bind the feature, and they are what this control proves.

## Not covered

This is the recovery leg only. A pre-emptive warn at PR-open time, when a union-marked file has
diverged since the branch point, stays an open option on the board row; nothing here implements it.

## Reproduce

```
git -C <repo> switch feat/wrap-union-remerge
bash tests/test-wrap.sh          # the feature, 348 assertions
bash tests/run-all.sh            # no regression across 138 suites
bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' \
  'perl -i -pe '\''s/\[ "\$conflict_count" = 1 \]/[ "\$conflict_count" = 99 ]/'\'' lib/wrap/wrap.sh'
```
