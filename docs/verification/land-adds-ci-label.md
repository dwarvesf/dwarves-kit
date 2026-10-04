# Proof of done: `wrap land` arms the `ci` label on label-gated repos

2026-09-29. Acceptance: on a repo whose PR workflows run only on `pull_request: types:
[labeled]`, a landing path that waits for checks must first make the PR carry `ci`, else
an unlabeled PR reports an empty rollup and the wait reads "nothing pending" on an
untested head. Both wrap.sh landing paths (`cmd_land`, and `_autoland_carry` under
`wrap apply`) sync the label before the merge and wait for the runs it starts; a label
that predates the head is removed and re-added; a repo without the label behaves exactly
as before; a label that will not set refuses the merge. `commands/greenlight.md` gets the
same step before its snapshot, where "no checks at all" is `done` only on a repo with no
`ci` label. Lane: bug. Files: `lib/wrap/wrap.sh`, `commands/greenlight.md`,
`tests/test-wrap.sh`.

## How it works

`_ci_label_sync <url> <pr>` exact-matches the repo's `ci` label out of the fuzzy
`gh label list --search` answer, then adds it when the PR lacks it, or removes and
re-adds it when the PR carries it but the head has no rollup (the `labeled` event fired
before the pushed commits, so the head was never tested). `_ci_checks_wait` replaces the
ordinary pending-check wait on a gated repo: an empty rollup counts as pending inside
`KIT_WRAP_CI_GRACE_SECS` (90s) because the `labeled` event registers its runs a few
seconds late; past the window an empty rollup is a paths-filtered workflow that started
nothing. What red checks do is unchanged: the merge and `_pr_gate` read them as they
always did.

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 1511 passed`
Verdict: PASS. Six new cases: label added before the merge on a gated repo; fuzzy
`ci-cd` hit never arms (negative); an armed label is never re-added; a stale label is
removed and re-added; an unset label refuses the merge; autoland labels the carry PR.

Command: `bash tests/test-meta.sh`
Exit: 1
Output: one failure, `docs/FEATURES.md is fresh (check verb)`, and the same check fails
on unmodified master (`feature-registry.sh check` exits 1 there too): the `+N` spec-count
columns drifted before this branch. Pre-existing, not introduced here; regenerating
FEATURES.md is a separate commit's worth of unrelated diff.
Verdict: PASS for this change's surface.

Command: live run of the patched `bin/wrap land` on a docs-only throwaway PR in
consolelabs/content (its pr-check is label-gated)
Exit: 0
Output:

```
land docs/ci-label-land-proof -> main
     pushed docs/ci-label-land-proof (9b12ab2)
     opened PR #20
     labeled #20 ci (this repo runs PR checks only on the label)
     merged #20 (d14e530290050e04ac53a7b84016c7dc32838cd6): tree verified
     pulled <consumer-repo>/content
     removed worktree .../ci-label-land-proof
```

`gh pr view 20 -R consolelabs/content` afterwards: labels `["ci"]`, state `MERGED`,
statusCheckRollup `no-ai-commits`, `frontmatter`, `images` all `COMPLETED/SUCCESS` --
the label the tooling added is what ran the checks.
Verdict: PASS.

## Negative control

Command: `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<mutation>'`
Mutation: `.name == "ci"` -> `.name == "cix"` in `_ci_label_sync`, which makes the
exact-match never hit and the gate never arm while every other path stays intact. (A
first mutation on the `--search` argument was toothless: the test's gh stub answers
`GH_STUB_LABELS` without filtering on the search term, the same class of blind spot the
mutation exists to catch.)

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/\.name == "ci"/.name == "cix"/g' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- commands/wrap.md lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Verdict: PASS.
