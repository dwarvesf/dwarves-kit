# Verification -- archive-held-worktrees

`wrap apply --archive-worktrees` (SPEC-415) archives stale worktrees no other verb removes: a branch-held one whose branch is unmerged, a detached one with a commit origin lacks, or a dirty one. Uncommitted files go into a temp-index snapshot commit, the tip goes to origin `archive/<slug>-<date>` under a create-only lease, is read back, and only then is the worktree removed and its branch deleted.

| Check | Command | Result |
|---|---|---|
| Real flow, scratch fixture | `bin/wrap apply [--apply] --archive-worktrees <scratch clone>` | 3 archived, 1 fresh kept, rc 0 |
| New section | `APPLY_ONLY=archive-wt bash tests/test-wrap-apply.sh` | all 147 passed |
| Apply suite | `bash tests/test-wrap-apply.sh` | all 468 passed |
| Land suite | `bash tests/test-wrap-land.sh` | all 750 passed |
| CLI suite | `bash tests/test-wrap-cli.sh` | all 22 passed |
| Config registry | `bash tests/test-config-registry.sh` | 60/60 passed |
| Changed suites | `bash tests/run-all.sh --changed` | all 50 suites passed |
| Negative controls | `lib/gate/negctl.sh` x6 | Verdict: PASS x6 |

## Green run

The real primary flow: `bin/wrap` against a scratch bare origin plus clone (never a real repo), with three aged worktrees (branch-held unmerged, detached with a unique commit, dirty with a staged-then-edited file) and one fresh one.

```
Command: bash <scratch>/smoke.sh   (bin/wrap apply --archive-worktrees, then --apply, on <S>/c)
Exit: 0
Output:
=== DRY
-- archive worktrees:
     WOULD archive worktree <S>/c/.claude/worktrees/det [detached, 1 unique commits, 0 uncommitted paths, idle 7296h] -> origin archive/det-20261101, then remove it
     WOULD archive worktree <S>/c/.claude/worktrees/dirty [feat/dirty, 0 unique commits, 3 uncommitted paths, idle 7296h] -> origin archive/feat-dirty-20261101, then remove it
     SKIP <S>/c/.claude/worktrees/fresh: fresh, idle 0h < 72h (wrap.archive_worktree_min_age_hours)
     WOULD archive worktree <S>/c/.claude/worktrees/held [feat/held, 1 unique commits, 0 uncommitted paths, idle 7296h] -> origin archive/feat-held-20261101, then remove it
-- origin branches:
=== APPLY
-- archive worktrees:
     archived worktree <S>/c/.claude/worktrees/det -> archive/det-20261101 (f6a60a4); removed
     archived worktree <S>/c/.claude/worktrees/dirty -> archive/feat-dirty-20261101 (6dcb460); removed, feat/dirty deleted
     SKIP <S>/c/.claude/worktrees/fresh: fresh, idle 0h < 72h (wrap.archive_worktree_min_age_hours)
     archived worktree <S>/c/.claude/worktrees/held -> archive/feat-held-20261101 (b51a33f); removed, feat/held deleted
-- origin branches:
rc=0
=== origin
refs/heads/archive/det-20261101 f6a60a4
refs/heads/archive/feat-dirty-20261101 6dcb460
refs/heads/archive/feat-held-20261101 b51a33f
=== dirty ref content
a.txt: base mod 
w.txt: w 
s.txt: disk 
staged parent s.txt: staged
=== worktrees left
<S>/c                         8ed0679 [main]
<S>/c/.claude/worktrees/fresh 4f7155a [feat/fresh]
=== branches left
+ feat/fresh
* main
S=<S>
Verdict: PASS
```

The suites:

```
Command: bash tests/test-wrap-apply.sh
Exit: 0
Output:
test-wrap-apply: all 468 passed

Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
test-wrap-land: 16 sections, 16 ran, 0 cached (0 checks credited)
test-wrap-land: all 750 passed

Command: bash tests/test-wrap-cli.sh
Exit: 0
Output:
test-wrap-cli: all 22 passed

Command: bash tests/test-config-registry.sh
Exit: 0
Output:
=== 60/60 passed ===

Command: bash tests/run-all.sh --changed
Exit: 0
Output:

run-all: all 50 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Each control ran after the feature commit, through `lib/gate/negctl.sh`, on one case (`APPLY_ONLY=archive-wt AW_CASE=<case>`). Every mutation turned its case red and `git checkout HEAD --` restored it green.

### AC-2: a dry run writes no object (snapshot moved before the APPLY check)
```
Command: APPLY_ONLY=archive-wt AW_CASE=archive_wt_dry_run_no_objects bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-2 a dry run on a dirty worktree writes no object
    PASS AC-2 dry run previews the dirty worktree
    PASS AC-2 the object store is unchanged
  
  test-wrap-apply: all 2 passed

Mutation: perl -0pi -e 's/(  if \[ "\$APPLY" != 1 \]; then\n    echo "     WOULD archive worktree)/  _wt_trees "\$wt" "\$gd" >\/dev\/null\n$1/' lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-2 a dry run on a dirty worktree writes no object
    PASS AC-2 dry run previews the dirty worktree
    FAIL AC-2 the object store is unchanged
  
  test-wrap-apply: 1 passed, 1 FAILED of 2

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### AC-16b: the read-back compare (deleted)
```
Command: APPLY_ONLY=archive-wt AW_CASE=archive_wt_readback_mismatch bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-16b origin holding another commit after the push keeps the worktree
    PASS AC-16b exits 2
    PASS AC-16b FAILED names both commits
    PASS AC-16b the worktree stays
    PASS AC-16b the branch stays
  
  test-wrap-apply: all 4 passed

Mutation: perl -0pi -e 's/if \[ -z "\$pushed" \] \|\| \[ "\$pushed" != "\$tip" \]; then/if false; then/' lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-16b origin holding another commit after the push keeps the worktree
    FAIL AC-16b exits 2
    FAIL AC-16b FAILED names both commits
    FAIL AC-16b the worktree stays
    FAIL AC-16b the branch stays
  
  test-wrap-apply: 0 passed, 4 FAILED of 4

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### AC-30b: the embedded-repo guard reads `--untracked-files=all` (mutated to `normal`)
```
Command: APPLY_ONLY=archive-wt AW_CASE=archive_wt_embedded_repo_deep bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-30b a nested clone below an untracked directory blocks
    PASS AC-30b dry run names outer/inner
    PASS AC-30b dry run prints no WOULD
    PASS AC-30b apply names outer/inner
    PASS AC-30b outer/inner/.git stays
    PASS AC-30b nothing pushed
  
  test-wrap-apply: all 5 passed

Mutation: perl -0pi -e 's/status --porcelain=v1 -z --untracked-files=all \\\n/status --porcelain=v1 -z --untracked-files=normal \\\n/' lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-30b a nested clone below an untracked directory blocks
    FAIL AC-30b dry run names outer/inner
    FAIL AC-30b dry run prints no WOULD
    PASS AC-30b apply names outer/inner
    PASS AC-30b outer/inner/.git stays
    PASS AC-30b nothing pushed
  
  test-wrap-apply: 3 passed, 2 FAILED of 5

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### AC-31: a staged-added ignored `.env` (both diff-tree checks dropped, status check limited to untracked)
```
Command: APPLY_ONLY=archive-wt AW_CASE=archive_wt_secret_staged bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-31 a staged-added .env, ignored on disk, is never pushed
    PASS AC-31 SKIP names .env
    PASS AC-31 nothing pushed
  
  test-wrap-apply: all 2 passed

Mutation: bash <scratch>/mut-ac31.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-31 a staged-added .env, ignored on disk, is never pushed
    FAIL AC-31 SKIP names .env
    FAIL AC-31 nothing pushed
  
  test-wrap-apply: 0 passed, 2 FAILED of 2

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### AC-37: the `.claude/` synced-copy class (widened to any `.claude/` path)
```
Command: APPLY_ONLY=archive-wt AW_CASE=archive_wt_claude_synced bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-37 a .claude/ copy identical to the main checkout is regenerable; a differing one blocks
    PASS AC-37a the identical copy archives
    PASS AC-37b the differing copy blocks
    PASS AC-37b the differing file stays
    PASS AC-37b nothing pushed for it
    PASS AC-37c a file with no twin in the main checkout blocks
    PASS AC-37c the extra file stays
  
  test-wrap-apply: all 6 passed

Mutation: bash <scratch>/mut-ac37.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
  --- AC-37 a .claude/ copy identical to the main checkout is regenerable; a differing one blocks
    PASS AC-37a the identical copy archives
    FAIL AC-37b the differing copy blocks
  grep: <TMPD>/awclone-syn/.claude/worktrees/diff/.claude/rules/x.md: No such file or directory
    FAIL AC-37b the differing file stays
    FAIL AC-37b nothing pushed for it
    FAIL AC-37c a file with no twin in the main checkout blocks
    FAIL AC-37c the extra file stays
  
  test-wrap-apply: 1 passed, 5 FAILED of 6

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### AC-38: the gitlink tree guard alone (forced to "none")
```
Command: APPLY_ONLY=archive-wt AW_CASE=archive_wt_tree_guards bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-38 the tree guards, called alone on built trees
    PASS AC-38 a new gitlink is found
    PASS AC-38 HEAD's own tree has no new gitlink
    PASS AC-38 an added .env is found by name
    PASS AC-38 HEAD's own tree adds no secret
    PASS AC-38 an edited tracked token.go stays pushable
    PASS AC-38 an edited tracked .env.sample is a secret
  
  test-wrap-apply: all 6 passed

Mutation: perl -0pi -e 's/(_wt_new_gitlink\(\) \{\n)/$1  return 1\n/' lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
  === apply --archive-worktrees: stale unmerged and detached worktrees ===
  --- AC-38 the tree guards, called alone on built trees
    FAIL AC-38 a new gitlink is found
    PASS AC-38 HEAD's own tree has no new gitlink
    PASS AC-38 an added .env is found by name
    PASS AC-38 HEAD's own tree adds no secret
    PASS AC-38 an edited tracked token.go stays pushable
    PASS AC-38 an edited tracked .env.sample is a secret
  
  test-wrap-apply: 5 passed, 1 FAILED of 6

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven
- No run against a real repository with `--apply`: by design, the sweep ran only on scratch fixtures.
- No run under Linux GNU coreutils; the stat, touch and find calls follow the existing `_mtime` dual form, and the suite ran on macOS (git 2.56, bash 5).
- The gitlink tree guard has no end-to-end case that reaches it with the status guard intact (spec Depth: blind-spot); AC-38 calls it alone on a built tree instead.
- A worker whose lock pid belongs to another user can be read as dead (`kill -0` EPERM); the Failure modes row in the spec stands.
- Validate and ship gates are left to the lead.
