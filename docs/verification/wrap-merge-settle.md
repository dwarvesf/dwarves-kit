# Proof of done: `wrap merge` waits for GitHub to settle on the head it pushed

2026-09-23. Spec: `docs/specs/SPEC-306-wrap-merge-settle.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`, `lib/config/module-registry.md`, `commands/wrap.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: after its own re-merge push, `wrap merge --apply` polls the PR until the head is the pushed one and `mergeable` has left UNKNOWN/CONFLICTING, bounded by `KIT_WRAP_SETTLE_SECS` (default 60). It then gates, and merges only the pushed head (`--match-head-commit`). A head it did not push is refused. A first read of UNKNOWN is re-read before any SKIP. A branch no local checkout holds re-merges in a scratch detached worktree.

## Guards

| Guard | Refuses when | Why |
|---|---|---|
| Pushed head only | the settled head is not the oid wrap pushed | a foreign push, or a push GitHub never registered, was not gated |
| Early stop | a head that is neither the prior nor the pushed oid appears | no point waiting on a head wrap will refuse anyway |
| Bounded | `KIT_WRAP_SETTLE_SECS` elapses | a verdict that never settles still fails closed, then reaches the existing fallback |
| Merge pin | always | `--match-head-commit` stays the pushed head |
| Scratch worktree | fetched tip differs from the PR head, or the worktree add fails | the same tip-identity rule the checkout path applies |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 802 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: --changed against 25d4940: 7 changed files -> 15 suites (11 named, the rest always-on)
        run-all: all 15 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: git checkout origin/master -- lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Under the pre-change `wrap.sh` the suite reports `test-wrap: 786 passed, 16 FAILED of 802`:

```
  FAIL settle: the PR is eligible once GitHub settles
  FAIL settle: the PR merges, tree verified
  FAIL settle: polled past UNKNOWN and the stale CONFLICTING (4 detail reads)
  FAIL settle: pinned the merge to the pushed head
  FAIL settle: the wait is bounded (initial read plus 4 reads over 6s)
  FAIL settle: a moved head exits 0 without merging
  FAIL settle: a moved head is named
  FAIL settle: a moved head is never merged
  FAIL settle: an unregistered push names the stale head
  FAIL settle: a first UNKNOWN read settles to eligible
  FAIL settle: a first UNKNOWN read is not skipped
  FAIL no-checkout: names the scratch worktree
  FAIL no-checkout: re-merged and pushed
  FAIL no-checkout: merged, tree verified
  FAIL no-checkout: the pushed head carries the old origin/main
  FAIL no-checkout: pinned the merge to the pushed head
```

The old code merged the foreign `4444444` head in the moved-head case, which is the safety half of this change.

## Existing cases adjusted

| Case | Change | Why |
|---|---|---|
| Re-gate refuses after the push (#17) | head `cc` became `%REMERGE_TIP%` | `cc` was a placeholder; the new head check would refuse it before the review gate this case binds |
| Base not carried (#55) | the checkout is dirtied instead of the local branch deleted | a deleted branch now re-merges in a scratch worktree; a dirty checkout still blocks the re-merge, so the fallback refusal keeps its coverage |
| Every case | `KIT_WRAP_SETTLE_SECS=0` at the top of the file | one read per settle, so cases that do not test the wait do not pay for it |

## Variant 2 (branch lacks the base)

The carried-base fallback's refusal is deliberate: commit-tree reproduces a squash only when the head already holds `origin/<default>`. The observed failure came from the step before it. The union re-merge, the designed recovery for a head that lacks the base, required a local checkout, and the branch had none. The scratch worktree gives it one. The fallback is unchanged.

## Review

One read-only review at Opus found no blocking findings: no path merges a head other than the one wrap pushed or gated. Four were fixed in the follow-up commit. `_remerge_push` now stops before the push when the kanban dedupe commit fails. A failed `mktemp` refuses by name. The bare `git worktree prune` is gone, because it also cleared records this run never created. An empty head from a failed read keeps the wait going instead of ending it. The CI caveat went into the spec. Not taken: a signal trap around the scratch worktree (an interrupted run leaves one scratch worktree record, which `git worktree prune` clears later).

## Not covered

[UNAVAILABLE: a live GitHub run needs a throwaway conflicting PR merged on a real repo, and this change ships as a draft PR that is not merged.] The primary flow runs end to end against real git (a bare origin, real merges, union attributes, pushes and the scratch worktree), with only `gh` stubbed to replay the observed read sequences. The wait ends on mergeability, not on CI, so a repo whose checks restart on the pushed head still needs a second `wrap merge` call once they go green.

## Rollback

No schema, deploy or data surface. `git revert` the commit; the settle loop returns to five UNKNOWN-only reads and a branch with no checkout returns to the fallback refusal.

## Reproduce

```
bash tests/test-wrap.sh
bash tests/run-all.sh --changed
bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' 'git checkout origin/master -- lib/wrap/wrap.sh'
```
