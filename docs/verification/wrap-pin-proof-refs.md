# Verification: wrap merge proofs name full refs

Change: `lib/wrap/wrap.sh`. Every proof and tip read in `scan`, `_merge_proof`, `_apply_worktrees`, and `_apply_branches` names `refs/heads/<b>` and `refs/remotes/origin/<def>`, or a sha already read. Branches enumerate with `%(refname:lstrip=2)`, so scan output and the tip snapshot never carry a `heads/` prefix. The script unsets `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_CONFIG_PARAMETERS`, and `GIT_CONFIG_COUNT`/`KEY_*`/`VALUE_*` once at the top. `_absorbed` is unchanged.

| Check | Command | Result |
|---|---|---|
| Suite, fix | `bash tests/test-wrap.sh` | `test-wrap: all 1457 passed` (1436 before, plus 21 new) |
| Suite, master's `wrap.sh` | `git show origin/master:lib/wrap/wrap.sh` swapped in, suite run, file restored | `test-wrap: 1440 passed, 17 FAILED of 1457`; every failure is in the new section |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" '<sed: _merge_proof back to bare origin/${def}>'` | green, RED under mutation (exit 1), green after restore, `Verdict: PASS` |
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
test-wrap: 1440 passed, 17 FAILED of 1457
```

Four new checks stay green on master: the local `origin/main` branch itself survives, and the target's worktree, `agent`, and `agent2` survive the leaked `GIT_DIR` run. Master never reaches those refs, because it acts on the other clone. Every fixture still has at least one check that goes red.

## Green with the fix

```
test-wrap: all 1457 passed
```

## Negative control

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
