# Verification: wrap merge proofs name full refs

Change: `lib/wrap/wrap.sh`.

- Every proof and tip read in `scan`, `_merge_proof`, `_apply_worktrees`, and `_apply_branches` names `refs/heads/<b>` and `refs/remotes/origin/<def>`, or a sha already read. `_absorbed` is unchanged.
- Branches enumerate with `%(refname:lstrip=2)`, so scan output and the tip snapshot never carry a `heads/` prefix.
- `_apply_archive_unmerged` enumerates the same way. It skips a symbolic ref under `refs/heads/`. It runs `git cherry refs/remotes/origin/<def> refs/heads/<b>` and pushes `refs/heads/<b>:refs/heads/<archive ref>`. When `ls-remote` shows origin's archive ref at the tip it read, it re-checks `git symbolic-ref -q HEAD` and the worktree list for `branch refs/heads/<b>`. A hit keeps the branch and reports it kept. Otherwise it deletes with `git update-ref --no-deref -d refs/heads/<b> <tip>` and removes `branch.<b>` config.
- The script unsets the repo-location variables: git's `--local-env-vars` list minus `GIT_CONFIG*`, plus `GIT_NAMESPACE`, or a fixed copy of that list when git prints nothing. `GIT_CONFIG_PARAMETERS` and the `GIT_CONFIG_COUNT`/`KEY_*`/`VALUE_*` pairs stay. `mini-run` and `checkout-sync` pass credential and `insteadOf` config through them.

| Check | Command | Result |
|---|---|---|
| Suite, fix | `bash tests/test-wrap.sh` | `test-wrap: all 1486 passed` (1436 before, plus 50 new) |
| Suite, master's `wrap.sh` | `git show origin/master:lib/wrap/wrap.sh` swapped in, suite run, file restored and confirmed with `cmp` | `test-wrap: 1453 passed, 33 FAILED of 1486`; every failure is in the new section |
| New cases, previous head `e842ab1a` | isolated run of the new section against that revision | `43 passed, 7 FAILED of 50`: the symref, recheck, and injected-config cases |
| New cases, delete swapped back to `branch -D` | one-off `sed` on a scratch copy | `47 passed, 3 FAILED of 50`: the three local lease checks |
| Negative controls | `bash lib/gate/negctl.sh <clone> "bash tests/test-wrap.sh" "bash <mutation>"`, six mutations, below | each green, RED under mutation (exit 1), green after restore, `Verdict: PASS` |
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
| Leaked `GIT_COMMON_DIR` | `GIT_COMMON_DIR=<other clone>/.git`, `agent` merged in the other clone | reads the other clone's refs, deletes the target's unlanded `agent` and `agent2`, removes the other clone's worktree directory | acts on the target only, everything kept |
| Archive with a same-named tag | tag `agent2` at a different unmerged commit, `branch.agent2.*` config set | `src refspec agent2 matches more than one`: FAILED, nothing archived | origin `archive/agent2-<date>` holds `agent2`'s own tip, the local branch and its config go, the tag stays |
| Symbolic ref | `refs/heads/zalias` a symref to the worktree-held, unmerged `agent` | `branch -D` removes only the symref; no skip line | `SKIP zalias: a symbolic ref`; at `e842ab1a` the delete followed the symref and removed `agent` |
| Checked out during the push | a `pre-push` hook adds a worktree on `agent2` | `branch -D` refuses; no kept line | archived, `agent2` kept, "kept agent2: archived to ..., but it was checked out during the push"; at `e842ab1a` `agent2` was deleted |
| Local lease | a `pre-push` hook moves `agent2` to newer work | `branch -D` deletes the moved branch | the leased delete refuses, FAILED, exit 2, `agent2` keeps the new work |
| Remote lease | a `post-receive` hook on the bare remote moves the archive ref | `branch -D` deletes the branch | FAILED "origin ... holds ...", exit 2, `agent2` kept |
| Injected config | origin set to `fake://ic/remote`, `GIT_CONFIG_COUNT=1` maps it to the bare remote with `insteadOf` | green: master unsets nothing | fetch succeeds and the merged `agent2` is deleted; at `e842ab1a` the mapping was stripped, fetch failed, and every delete was skipped |

In one early master run, the `GIT_COMMON_DIR` fixture deleted nothing and only its report check went red. Every later run deleted as the table says. The report check was red in every run.

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
  FAIL pinned archive: the branch.agent2 config goes with it
  FAIL pinned symref: the alias is skipped by name
  FAIL pinned recheck: reports the branch kept
  FAIL pinned lease: a moved branch exits 2
  FAIL pinned lease: the refused delete is FAILED
  FAIL pinned lease: agent2 survives with its new work
  FAIL pinned remote lease: exits 2
  FAIL pinned remote lease: FAILED names the mismatch
  FAIL pinned remote lease: agent2 survives
test-wrap: 1453 passed, 33 FAILED of 1486
```

Seventeen new checks stay green on master. Master never reaches those refs, or never strips the config it would need. Every fixture except injected config has at least one check red on master. Injected config is red on `e842ab1a`, the revision that stripped the config.

## Red on the previous head (`e842ab1a`)

```
  FAIL pinned symref: the alias is skipped by name
  FAIL pinned symref: the held agent keeps its tip
  FAIL pinned recheck: reports the branch kept
  FAIL pinned recheck: agent2 survives
  FAIL pinned config: the fetch through the mapping succeeds
  FAIL pinned config: agent2 is proven merged after that fetch
  FAIL pinned config: agent2 is gone
test-wrap: 43 passed, 7 FAILED of 50
```

## Delete swapped back to `branch -D`

```
  FAIL pinned lease: a moved branch exits 2
  FAIL pinned lease: the refused delete is FAILED
  FAIL pinned lease: agent2 survives with its new work
test-wrap: 47 passed, 3 FAILED of 50
```

## Green with the fix

```
test-wrap: all 1486 passed
```

## Negative controls

Each ran in a scratch clone of the committed branch (`b3ceec96`), in parallel, with the full suite as the test command.

| Behavior | Mutation | Under mutation | Verdict |
|---|---|---|---|
| Proof pin | `_merge_proof` back to bare `origin/${def}` | Exit 1 | PASS |
| Symref skip | `symbolic-ref -q "refs/heads/${b}"` checks a ref that never exists | Exit 1 | PASS |
| Pre-delete recheck | the worktree grep matches nothing | Exit 1 | PASS |
| Local lease | `update-ref --no-deref -d ... "$tip"` back to `branch -D "$b"` | Exit 1 | PASS |
| Remote lease | the `pushed != tip` condition removed | Exit 1 | PASS |
| Injected config kept | `GIT_CONFIG_COUNT` added to the unset | Exit 1 | PASS |

Each run printed `Exit: 0 (green before mutation)`, `Changed: lib/wrap/wrap.sh`, `Exit: 1 (under mutation, RED expected)`, `Exit: 0 (green after restore)`, `Verdict: PASS`.
