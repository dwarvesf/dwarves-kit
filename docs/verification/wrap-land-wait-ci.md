# Verification -- wrap-land-wait-ci

`wrap land --with-ci` and `wrap merge --with-ci` merged while a PR's checks were pending (share#55, #60). On a repo with no `ci` label the label sync returned early and nothing waited; `_land_pr_checks_gate` skipped its own wait under `--with-ci` on the assumption the label path had run it. The gate then read the empty rollup of a head seconds old and merged.

## Rule

- A repo with no `pull_request` workflow has no CI: `land` merges at once, as before.
- Otherwise `--with-ci` holds while GitHub registers the runs (`KIT_WRAP_LAND_REGISTER_SECS`, 300, for a workflow that runs on every PR; `KIT_WRAP_LAND_GRACE_SECS`, 30, for a filtered one), then until no check is pending (`KIT_WRAP_CARRY_CHECKS_SECS`), then merges only when none failed or was cancelled.
- A failed, cancelled or timed-out check exits 2 and merges nothing. So does an empty rollup where a workflow runs on every PR.
- `merge --with-ci` does the same through `_merge_register_gate`; by slug there is no checkout to read workflows from, so it takes the short grace and an empty rollup passes.

## Green run

```
Command: bash tests/test-wrap-ci.sh
Exit: 0
Output:
  test-wrap-ci: all 177 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
  test-wrap-land: 18 sections, 18 ran, 0 cached (0 checks credited)
  test-wrap-land: all 871 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-ship.sh
Exit: 0
Output:
  test-wrap-ship: all 120 passed
Verdict: PASS
```

The new cases: land PW1 (empty list never fills: refused, no merge), PW2 (pending until pass: merges after 5 reads), PW3 and PW3b (failed, cancelled, timed out: exit 2, no `pr merge` call), PW4 (all pass: merges), PW5 (no pull_request workflow: merges at once); merge `--with-ci` with no label (empty then pending then green merges; never registers refuses; red refuses).

## Negative control

The previous revision of `lib/wrap/wrap-land.sh` and `lib/wrap/wrap-merge.sh` put back through `lib/gate/negctl.sh`; the new cases go RED and the restore is green.

### land section
Command: LAND_CACHE=0 LAND_SECTION=sec_prgate bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Output:
  --- PW4: --with-ci, all checks pass: merges
  --- PW5: --with-ci on a repo with no pull_request workflow (no CI at all) merges at once
  land-section-result: 74 0 74

Mutation: git show 212f814f35bbf217654011d9d9337394e6be74b7:lib/wrap/wrap-land.sh > lib/wrap/wrap-land.sh; git show 212f814f35bbf217654011d9d9337394e6be74b7:lib/wrap/wrap-merge.sh > lib/wrap/wrap-merge.sh
Changed: lib/wrap/wrap-land.sh, lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
  --- PW4: --with-ci, all checks pass: merges
  --- PW5: --with-ci on a repo with no pull_request workflow (no CI at all) merges at once
  land-section-result: 65 9 74

Restore: git checkout HEAD -- lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS

### merge and ci suite
Command: bash tests/test-wrap-ci.sh
Exit: 0 (green before mutation)
Output:
    PASS the worktree was removed
    PASS the branch was deleted
  === the gate verdict is a code: callers do not depend on the reason wording ===
    PASS code gate: a reworded conflict reason still prints on the SKIP line
    PASS code gate: a reworded conflict reason still starts the conflict recovery
    PASS code gate: a reworded pending reason still exits 0
    PASS code gate: a reworded pending reason still reaches the ci label sync
    PASS code gate: the reworded pending case still merges once green
  
  test-wrap-ci: all 177 passed

Mutation: git show 212f814f35bbf217654011d9d9337394e6be74b7:lib/wrap/wrap-land.sh > lib/wrap/wrap-land.sh; git show 212f814f35bbf217654011d9d9337394e6be74b7:lib/wrap/wrap-merge.sh > lib/wrap/wrap-merge.sh
Changed: lib/wrap/wrap-land.sh, lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS the worktree was removed
    PASS the branch was deleted
  === the gate verdict is a code: callers do not depend on the reason wording ===
    PASS code gate: a reworded conflict reason still prints on the SKIP line
    PASS code gate: a reworded conflict reason still starts the conflict recovery
    PASS code gate: a reworded pending reason still exits 0
    PASS code gate: a reworded pending reason still reaches the ci label sync
    PASS code gate: the reworded pending case still merges once green
  
  test-wrap-ci: 171 passed, 6 FAILED of 177

Restore: git checkout HEAD -- lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
