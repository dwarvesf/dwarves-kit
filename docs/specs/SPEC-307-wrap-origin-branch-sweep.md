# SPEC-307: wrap apply deletes merged branches on origin

**Status:** VALIDATED (the change lands in the same PR)
Lane: normal
**Proof:** `tests/test-wrap.sh`, the origin-sweep block; `docs/verification/wrap-origin-branch-sweep.md`.

## Problem

`wrap merge` squash-merges with `gh pr merge --squash` and never passes
`--delete-branch`, because a worktree may still hold the local branch.
`wrap apply` then deletes the LOCAL branch and worktree only. Nothing deletes
the branch on origin, and `delete_branch_on_merge` is off on the operator's
repos. Measured: dwarvesf/foundation-workers holds 173 origin branches whose
PR already merged, foundation-ops 109, foundation-apps 25.

## Contract

- `wrap apply` sweeps origin after the local branch sweep, per repo, when the
  raw `remote.origin.url` names github.com and gh is authenticated. Either one
  missing prints one `SKIP origin sweep:` line.
- Origin tips come from `git ls-remote --heads origin`, never from
  `refs/remotes/origin/`: a checkout whose fetch refspec names only the
  default branch tracks a handful of origin's branches (foundation-workers
  tracks 13 of 178).
- Two reads: `gh pr list --state merged --json headRefName,headRefOid,isCrossRepository`
  and `gh pr list --state open --json headRefName,baseRefName`, each capped at
  1000. A failed read (either list or `ls-remote`) skips the sweep by name.
- An origin branch is ELIGIBLE only when ALL hold: a merged same-repo PR
  (`isCrossRepository` false) has the branch's current origin tip as its
  `headRefOid`; it is not the default branch; no open PR uses it as head or
  base. Every other branch is kept without a line.
- Dry run: `WOULD delete N merged branches on origin:` plus one indented name
  per line. `--apply`: one `git push origin --delete` per 100 names, then
  `deleted K of N merged branches on origin`, where K is counted from a second
  `ls-remote` (a multi-ref push is not atomic). A failed re-read is `FAILED`.
- A refused push prints `FAILED delete <k> origin branches: exit <rc> ...`,
  sets exit 2, and the rest of `apply` (the pull) still runs.
- Knob `wrap.delete_merged_remote_branches`, default `true`, resolved with
  `kit_config_get_root` only. `false` prints
  `N merged branches left on origin (wrap.delete_merged_remote_branches=false)`
  and deletes nothing.
- Scope matches the local branch sweep: it runs on every `apply` call,
  `--worktrees` or not, and `--own` skips it.

## Design record

The sweep sits beside `_apply_branches` rather than under `--worktrees`,
because that flag gates worktree removal, and branch deletion already runs on
every `apply`. `--own` skips both branch sweeps for the same reason: another
live session's merged branch is out of the named scope.

The tip-equals-PR-head rule is the origin twin of the local squash proof: a
branch that gained a commit after merge carries unmerged work, so it stays.
The open-PR base rule exists because GitHub closes a PR whose base branch is
deleted. The GitHub test reads the raw config URL, so an `insteadOf` rewrite
still counts as GitHub, which is also how the tests point a github.com URL at
a local bare repo.

No `--force-with-lease` on the delete: the window between the fetch and the
push is seconds, and the file promises never to force a push.

## Test plan

| Case | Expected |
|---|---|
| merged same-repo PR at the origin tip, `--apply` | deleted, `deleted 1 of 1` |
| dry run | `WOULD delete 1 ...` plus the name, origin unchanged |
| origin tip past the PR head | kept |
| base of an open PR | kept |
| head of an open PR | kept |
| cross-repo (fork) PR head | kept |
| default branch with a merged-PR record | kept |
| operator `kit.toml` knob false | report line, origin unchanged |
| project `.kit.toml` knob false | ignored, branch deleted |
| push refused (`receive.denyDeletes`) | `FAILED`, exit 2, pull still runs |
| non-GitHub origin | `SKIP origin sweep: origin is not a GitHub remote` |
