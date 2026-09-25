# Proof of done: wrap apply --archive-unmerged

Profile: feature   Proof class: behavioral

## What this proves

`bin/wrap apply --archive-unmerged` (opt-in, never default-on, never under `--own`): for
every local branch that is not the current or default branch and is not held by a
worktree, and carries at least one commit `git cherry origin/<default> <branch>` marks
unique (a `+` line), the dry run previews `WOULD archive <branch> -> origin
archive/<branch-slug>-<YYYYMMDD> (<n> unique commits)`; `--apply` pushes it there with no
force and, only once that push lands, deletes the local branch, printing `archived
<branch> -> <ref>`. An existing archive ref, or any push refusal (a pre-push hook,
branch protection, auth), keeps the branch local and reports `FAILED archive <branch>:
<first error line>`. A branch with zero unique commits is left for the existing
merged-branch sweep.

## R1 GREEN

Command: `bash tests/test-wrap.sh`
Exit: 0
Output (excerpt):
```
--- dry run: previews the eligible branch, writes nothing
  PASS archive dry run exits 0
  PASS archive dry run previews unique-work
  PASS archive dry run leaves the ancestor for the merged sweep
  PASS archive dry run kept unique-work locally
  PASS archive dry run pushed no archive ref
--- --apply: the branch lands on origin and disappears locally; the ancestor is untouched
  PASS archive apply exits 0
  PASS archive apply reports the landed ref
  PASS archive apply pushed the ref to origin
  PASS archive apply deleted the local branch
  PASS archive apply left nothing-unique for the existing ancestor sweep, not archive-unmerged
  PASS archive apply never archived nothing-unique
--- a worktree-held branch is skipped, never archived and never deleted
  PASS archive wt-held is skipped by name
  PASS archive wt-held kept the branch locally
  PASS archive wt-held pushed no archive ref for it
--- a push a pre-push hook refuses is FAILED, exit 2, the branch stays local
  PASS archive hook refusal exits 2
  PASS archive hook refusal is FAILED with the hook's own line
  PASS archive hook refusal kept the branch locally
  PASS archive hook refusal pushed no archive ref
  PASS archive hook refusal still ran the rest of apply
--- an existing archive ref refuses the push without force, without deleting the branch
  PASS archive dupe-ref exits 2
  PASS archive dupe-ref is FAILED naming the existing ref
  PASS archive dupe-ref kept the branch locally
--- never under --own: the whole sweep is scoped away, not just narrowed
  PASS archive --own exits 0
  PASS archive --own is skipped by name
  PASS archive --own never previews a branch
--- the flag off: apply's report carries no archive-unmerged section at all
  PASS archive-unmerged section is absent without the flag

test-wrap: all 1085 passed
```
Verdict: PASS
Note: covers every acceptance case named for the feature: archived branch lands on
origin and disappears locally; a worktree-held branch is skipped; a branch with no
unique patch is not deleted; a push refused by a pre-push hook keeps the local branch
and reports FAILED; an existing archive ref refuses the push the same way; the dry run
writes nothing; the flag is opt-in (absent report section when off) and never runs
under `--own`.

Also run: `bash tests/test-meta.sh` -- 854/854 passed, including the feature-registry
freshness pin (this change edits `commands/wrap.md`, a projection input) and the
doc-projection check (`bash lib/gate/doc-projection-check.sh <root>` exits 0).

## R2 NEGATIVE CONTROL

Command: `bash lib/gate/negctl.sh <root> "bash tests/test-wrap.sh" "sed -i.bak 's/--archive-unmerged) ARCHIVE_UNMERGED=1 ;;/--archive-unmerged) ARCHIVE_UNMERGED=0 ;;/' lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak"`

Output:
```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/--archive-unmerged) ARCHIVE_UNMERGED=1 ;;/--archive-unmerged) ARCHIVE_UNMERGED=0 ;;/' lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Verdict: PASS
Note: the mutation neuters the `--archive-unmerged` flag (it silently no-ops instead of
enabling the sweep), which turns every new archive-unmerged assertion red without
touching any other test in the suite. `negctl` staged the mutation, ran it, confirmed
RED, then restored `lib/wrap/wrap.sh` to `HEAD` via `git checkout HEAD --` and confirmed
GREEN again; `git status --short` was clean before and after.

## Reproduce

```
bash tests/test-wrap.sh
bash tests/test-meta.sh
bash lib/gate/negctl.sh "$(pwd)" "bash tests/test-wrap.sh" \
  "sed -i.bak 's/--archive-unmerged) ARCHIVE_UNMERGED=1 ;;/--archive-unmerged) ARCHIVE_UNMERGED=0 ;;/' lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak"
```
