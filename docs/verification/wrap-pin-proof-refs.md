# Verification: wrap merge proofs name full refs

Change: `lib/wrap/wrap.sh`.

- Every proof and tip read in `scan`, `_merge_proof`, `_apply_worktrees`, and `_apply_branches` names `refs/heads/<b>` and `refs/remotes/origin/<def>`, or a sha already read. `_absorbed` is unchanged.
- Branches enumerate with `%(refname:lstrip=2)`, so scan output and the tip snapshot never carry a `heads/` prefix.
- `_apply_archive_unmerged` enumerates the same way and runs `git cherry refs/remotes/origin/<def> refs/heads/<b>`. It pushes `refs/heads/<b>:refs/heads/<archive ref>`. It deletes the local branch only when `ls-remote` shows origin's archive ref at the tip it read, with `git update-ref -d refs/heads/<b> <tip>`.
- The script unsets `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`, and every `GIT_CONFIG_KEY_*`/`VALUE_*`. It then unsets `$(git rev-parse --local-env-vars)`, git's own list of repo-local variables (`GIT_DIR`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_INDEX_FILE`, and the rest).

| Check | Command | Result |
|---|---|---|
| Suite, fix | `bash tests/test-wrap.sh` | `test-wrap: all 1470 passed` (1436 before, plus 34 new) |
| Suite, master's `wrap.sh` | `git show origin/master:lib/wrap/wrap.sh` swapped in, suite run, file restored and confirmed with `cmp` | `test-wrap: 1446 passed, 24 FAILED of 1470`; every failure is in the new section |
| New cases, first revision's hand-listed unset (`b647d8e2`) | same swap, new section only | 7 FAILED of 34: the `GIT_COMMON_DIR` and archive cases |
| Negative control 1 | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" '<sed: _merge_proof back to bare origin/${def}>'` | green, RED under mutation (exit 1), green after restore, `Verdict: PASS` |
| Negative control 2 | same, `'<sed: archive push source back to bare ${b}>'` | green, RED under mutation (exit 1), green after restore, `Verdict: PASS` |
| Meta suite | `bash tests/test-meta.sh` | `Passed: 879 / 879` |
| Feature registry | `bash lib/registry/feature-registry.sh check` | `docs/FEATURES.md is fresh` |

## Fixtures

Each fixture is a clone whose `agent` branch (with a worktree) and `agent2` branch (no worktree) carry one commit `origin/main` lacks.

| Fixture | Shape | Master | Fix |
|---|---|---|---|
| Tag `origin/main` | `git tag origin/main agent` | worktree removed, `agent` and `agent2` deleted "(ancestor of origin/main)" | all kept |
| Local branch `origin/main` | `git branch origin/main agent` | scan prints `heads/origin/main` and SAFE-d `agent`, `agent2`, and itself; worktree removed, `agent` and `agent2` deleted | all kept, scan prints `origin/main` |
| Tag at merged PR head | tag `agent` at the first commit, gh reports that commit merged, the branch has one more | scan prints `heads/agent`, and the snapshot misses the tip-moved guard; worktree removed and `agent` deleted "squash-merged per gh" | kept, scan prints `agent [NOT merged / unknown: LEAVE]` |
| Leaked `GIT_DIR` | `GIT_DIR=<other clone>/.git wrap apply --apply --worktrees <target>` | acts on the other clone and deletes its merged `agent2` | acts on the target, leaves its unlanded worktree, other clone untouched |
| Leaked `GIT_COMMON_DIR` | `GIT_COMMON_DIR=<other clone>/.git wrap apply --apply --worktrees <target>`, `agent` merged in the other clone | reads the other clone's refs, deletes the target's unlanded `agent` and `agent2`, removes the other clone's worktree directory | acts on the target only, everything kept |
| Archive with a same-named tag | tag `agent2` at a different unmerged commit, `apply --apply --archive-unmerged` | `src refspec agent2 matches more than one`: FAILED, nothing archived | origin `archive/agent2-<date>` holds `agent2`'s own tip, the local branch is deleted, the tag stays |

`GIT_COMMON_DIR` is outside the first revision's hand-listed unset, and the case fails against that revision too. In one early master run the `GIT_COMMON_DIR` fixture deleted nothing and only its report check went red. Every later run deleted as the table says. The report check was red in every run.

## Red on master

```
  FAIL pinned tag: no ancestor proof from the tag
  FAIL pinned tag: the worktree survives apply
  FAIL pinned tag: agent survives apply
  FAIL pinned tag: agent2 survives apply
  FAIL pinned branch: scan names the branch in full, never heads/
  FAIL pinned branch: scan does not SAFE-d agent off the local branch
  FAIL pinned branch: no ancestor proof from the local branch
  FAIL pinned branch: the worktree survives apply
  FAIL pinned branch: agent survives apply
  FAIL pinned branch: agent2 survives apply
  FAIL pinned squash: scan leaves agent
  FAIL pinned squash: scan never names the branch heads/agent
  FAIL pinned squash: no squash proof from the tag
  FAIL pinned squash: the worktree survives apply
  FAIL pinned squash: agent survives apply
  FAIL pinned GIT_DIR: apply reads the target's worktree
  FAIL pinned GIT_DIR: the other repo's merged agent2 survives
  FAIL pinned GIT_COMMON_DIR: apply reads the target's worktree
  FAIL pinned GIT_COMMON_DIR: agent survives apply
  FAIL pinned GIT_COMMON_DIR: agent2 survives apply
  FAIL pinned GIT_COMMON_DIR: the other repo's merged worktree survives
  FAIL pinned archive: reports the archive
  FAIL pinned archive: origin holds the branch's own tip
  FAIL pinned archive: the local branch goes once archived
test-wrap: 1446 passed, 24 FAILED of 1470
```

Ten new checks stay green on master, because master never touches those refs or never reaches that state. Examples: the target's worktree under a leaked `GIT_DIR`, the local `origin/main` branch itself, and the archive tag. Every fixture has at least one check that goes red.

## Green with the fix

```
test-wrap: all 1470 passed
```

## Negative controls

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak "/^_merge_proof() {/,/^}/ s|\"refs/remotes/origin/\${def}\"|\"origin/\${def}\"|" lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak "s|\"refs/heads/\${b}:refs/heads/\${ref}\"|\"\${b}:refs/heads/\${ref}\"|" lib/wrap/wrap.sh && rm -f lib/wrap/wrap.sh.bak
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```
