# Verification -- land-no-pull

`wrap land <worktree> --no-pull` makes the same promise `merge --no-pull` and `apply --no-pull` make: the main checkout is never written. The closing fast-forward prints `SKIP pull: --no-pull`; the merge, tree verify, origin branch delete, worktree removal and local branch delete still run. The flag reuses the shared `NO_PULL` global and the `SKIP pull` wording from `apply`; the only new code is the flag parse and one branch in `_land_tidy`.

## Green run

Real git, stubbed `gh`; the main checkout carries an untracked file from "another session", and its HEAD, index hash and status are compared before and after.

```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
test-wrap-land: 14 sections, 13 ran, 1 cached (32 checks credited)
test-wrap-land: all 615 passed
Verdict: PASS
```

Other affected suites: `test-wrap-merge-nopull` 17 passed, `test-wrap-cli` 22 passed, `test-wrap-adopt` 207 passed, `test-meta` 902 passed.

## Negative control

Mutation: the `--no-pull` branch in `_land_tidy` replaced by `if false`, so the fast-forward runs again.

```
Command: bash lib/gate/negctl.sh "$PWD" "LAND_ONLY='land: one hand-made' LAND_CACHE=0 bash tests/test-wrap-land.sh" "<python replace of the NO_PULL branch with if false>"
Exit: 1 (under mutation, RED expected)
Output:
test-wrap-land: 28 passed, 4 FAILED of 32
Verdict: PASS (green before, RED under mutation, green after restore)
```

The mutated file was restored with `git checkout HEAD -- lib/wrap/wrap-land.sh`; negctl's final run was green.

## Not proven

- The adopt path (`cmd_land` called from `wrap adopt`) never passes `--no-pull`; adopt still pulls.
- The already-landed early path shares `_land_tidy`, so it skips the pull the same way, but no case exercises it under `--no-pull`.
- No live GitHub run: `gh` is stubbed.
