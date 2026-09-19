# Proof of done: `wrap merge` lands a carried-base conflict via a squash-equivalent PR

2026-09-20. Acceptance: when `bin/wrap merge --apply` finds one own, otherwise-green PR stuck on
`CONFLICTING` whose pushed head already contains `origin/<default>` (the union re-merge from
`wrap-union-remerge` already ran, or nothing was left to re-merge), wrap builds the commit GitHub's
squash would have computed: `git merge-tree --write-tree` for the merged tree, one `git commit-tree`
parented on `origin/<default>`, pushed to a `<branch>-squash` branch, and a replacement PR opened
under the original title and body. The replacement gates and merges through the same `_pr_gate` +
squash + tree-verify path, and the report names the superseded PR for a manual close. The working
tree is never touched. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`,
`commands/wrap.md`, `docs/CHANGELOG.md`, `_meta/BACKLOG.md`, `docs/FEATURES.md` (regenerated).

## Why this is safe to automate

GitHub's squash merge ignores `.gitattributes`, so a union-marked log both sides appended to reports
`CONFLICTING` on the PR even after the operator's local `git merge` resolved it cleanly and the push
carried the result. At that point the PR head's tree IS the tree a squash merge would produce: the
squash parent is the base tip, the squash tree is the merge result, and both are already on disk. The
fallback constructs that exact commit shape with `commit-tree` and lets the normal merge path (gate,
`gh pr merge --squash`, tree-verify) land it as a fresh PR.

The ancestor check is the classifier. `git merge-base --is-ancestor origin/<default> <head>` is true
exactly when the base is already carried, which is the only state in which commit-tree reproduces the
merge instead of inventing one. Every other conflicting state (real divergence, a red check, a moved
tip) still refuses by name before any write.

## The failure this replaces

The union re-merge leg (#608, `docs/verification/wrap-union-remerge.md`) covers a conflict GitHub
invented when the branch has not yet absorbed the base. Once that push lands, GitHub still reports
`CONFLICTING` (its merge never re-reads the attribute), so the re-merge path reports "already
contains the base" and stops. The remaining recovery was by hand: a scratch branch, a commit-tree or
reset, a replacement PR, a second trip through the gates. That is the leg this change automates.

## Guards, all fail-closed

| Guard | Refuses when | Why |
|---|---|---|
| Green except conflict | the PR fails any gate besides mergeability | a red check or dismissed review is a human call |
| Carried base | `origin/<default>` is not an ancestor of the head | commit-tree would not reproduce the merge; the divergence is real |
| Tip identity | the PR head moved between gate and build | the squash commit must pin the head the gate read |
| Clean merge-tree | `git merge-tree` reports a conflict | belt over the ancestor check; a conflicted tree refuses |
| Replacement gate | the replacement PR's detail read fails any gate | the same `_pr_gate` the first merge owed |
| Tree verify | the default branch lacks the replacement's head | `TREE MISMATCH`, exit 3, unchanged |
| Bounded | always | one fallback per call; the replacement merges or the branch is left for a human |

## Green run

Command: `bash -n lib/wrap/wrap.sh`
Exit: 0
Verdict: PASS.

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 763 passed`
Verdict: PASS. 724 assertions before the change, 763 after; the 39 new ones cover the dry-run note,
the carried-base fallback, and three refusal paths plus the re-merge-then-fallback chain. The
pre-existing tree-mismatch assertion still binds exit 3.

Command: `bash tests/test-meta.sh`
Exit: 0
Verdict: PASS. One FAIL on first run (`docs/FEATURES.md is fresh`) traced to registry drift already
on the base plus this diff's `commands/wrap.md` edit; `feature-registry.sh check --fix` regenerated
the file and the re-run is clean.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output: `Passed: 498 / 498`
Verdict: PASS.

## Cases the tests bind

Each case builds a real bare origin plus a clone with `.gitattributes merge=union` on an appended
log, so `git merge-tree` and `git commit-tree` run for real; `gh` stays stubbed, with a `%SQUASH_TIP%`
marker resolving the commit wrap creates mid-run so the stub can gate the replacement PR on the head
it will actually carry.

| Case | Setup | Asserted |
|---|---|---|
| Dry run | one conflicting PR, no `--apply` | the note names the `<branch>-squash` fallback |
| Happy path | union log merged locally and pushed, head carries `origin/main` | exit 0, reason reported, `-squash` branch pushed, replacement created under the original title and body, replacement gated + merged + tree-verified, superseded PR named, `pr merge` called on #51 never #50 |
| Commit shape | same | the commit's tree equals the stuck head's tree, its parent is the fetched `origin/main` tip, the remote got the `-squash` branch, the stuck branch is untouched, the checkout stayed clean |
| Red PR | conflicting AND a failing check | refusal names the reason, no `-squash` ref written, no push, no `pr create`, no `pr merge` |
| Base not carried | conflicting, head lacks `origin/main`, nothing to re-merge | refusal names the missing ancestor, no `pr create`, no push |
| Gated replacement | replacement PR reports `BEHIND` | named, no `pr merge`, the `-squash` branch stays on origin for a human |
| Chain | re-merge pushes, PR still `CONFLICTING` | the re-merge push is reported, the re-gate refusal is reported, the fallback opens and merges the replacement, the superseded PR is named, one `pr merge` on the replacement only |
| Tree mismatch | stub lands a wrong tree (pre-existing case) | exit 3, unchanged |

## Negative control

Command: `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<mutation>'`
Mutation: swap the ancestor check's operands, so "base carried by head" reads as "head carried by
base" and the fallback refuses on every path.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/merge-base --is-ancestor "origin\/\$\{def\}" "\$head_oid"/merge-base --is-ancestor "\$head_oid" "origin\/\$\{def\}"/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Eighteen assertions go RED under that mutation, `test-wrap: 745 passed, 18 FAILED of 763`:

```
  FAIL squash fallback reports the pushed scratch branch
  FAIL squash fallback reports the replacement PR
  FAIL squash fallback gates the replacement
  FAIL squash fallback merges the replacement, tree verified
  FAIL squash fallback names the superseded PR
  FAIL squash fallback created the PR on the -squash branch
  FAIL squash fallback carried the original title
  FAIL squash fallback carried the original body
  FAIL squash fallback merged #51, never #50
  FAIL squash fallback pinned the squash commit it built
  FAIL the squash commit's tree is the stuck head's tree
  FAIL the squash commit's parent is the origin/main tip it fetched
  FAIL a gated replacement names the merge state
  FAIL a gated replacement leaves the -squash branch on origin for a human
  FAIL chain: the fallback opens the replacement
  FAIL chain: the replacement merges
  FAIL chain: the superseded PR is named
  FAIL chain: one pr merge call, on #59 never #58
```

The refusal assertions stay green under the mutation, and they should: each asserts that nothing
happened, which holds both when a guard refuses and when the fallback is unreachable. They bind the
safety property; the eighteen above bind the feature.

## Not covered

The superseded original PR is reported, not closed; wrap never closes PRs and the close stays a
human step named in the report. A pre-emptive warn at PR-open time (the third option on board row
ID-653) remains unimplemented. The fallback assumes a clean `merge-tree` result; a carried-base head
that still conflicts in `merge-tree` refuses rather than guessing.

## Rollback

No schema/deploy/data surface touched (shell logic plus tests and generated docs). To revert:
`git revert` this commit, or `git checkout HEAD~1 -- lib/wrap/wrap.sh tests/test-wrap.sh
commands/wrap.md docs/CHANGELOG.md _meta/BACKLOG.md docs/FEATURES.md`; the fallback disappears and
the union re-merge leg keeps working. Any `<branch>-squash` branch a live run already pushed is
ordinary remote state, deleted with `git push origin :<branch>-squash` once its replacement PR is
closed or merged.

## Reproduce

```
git -C <repo> switch feat/wrap-merge-squash-fallback
bash -n lib/wrap/wrap.sh
bash tests/test-wrap.sh          # the feature, 763 assertions
bash tests/test-meta.sh && bash tests/test-hooks.sh
bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' \
  'perl -i -pe '\''s/merge-base --is-ancestor "origin\/\$\{def\}" "\$head_oid"/merge-base --is-ancestor "\$head_oid" "origin\/\$\{def\}"/'\'' lib/wrap/wrap.sh'
```
