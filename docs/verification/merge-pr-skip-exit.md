# Verification -- wrap merge --apply --pr exits 4 when the PR was not merged

`wrap merge --apply --pr <n>` printed `SKIP #<n> ...` or `nothing eligible to merge.` and exited 0, so `wrap merge --apply --pr 439 <repo> && gh workflow run deploy` deployed the old code. It now exits 4 whenever the named PR was not merged and nothing failed. The bare form (no `--pr`) and every dry run keep exit 0.

Callers checked: the only in-kit caller of `cmd_merge` is `_autoland_carry` in `lib/wrap/wrap-carry.sh`, which counted any non-zero as a failure and set `FAILURES`; it now reads 4 as "PR left open" (its documented, exit-unchanged behavior). `commands/wrap.md` steps 3 and 10 and `lib/wrap/wrap-adopt.sh` only read the printed text. `wrap land`, `stack-merge` and `mega-merge` do not call `cmd_merge`. Exit 4 was free: `cmd_merge` uses 0, 1, 2, 3 (merged, tree mismatch), 64, 130.

## Green run
```
Command: bash tests/test-wrap-merge.sh && bash tests/test-wrap-merge-nopull.sh && bash tests/test-wrap-carry.sh
Exit: 0
Output:
    PASS autoland commits: nothing failed
    PASS autoland commits blocked dry-run: no landing named
    PASS autoland commits blocked: the reason prints
    PASS autoland commits blocked: no PR opened

  test-wrap-carry: all 145 passed
Verdict: PASS
```
Cases added: `merge --apply --pr on a pending-checks PR exits 4` (plus its SKIP line and no `pr merge` call), `merge --apply without --pr, nothing eligible: exits 0`, `merge --pr 43 dry run on a pending-checks PR exits 0`, and `merge --no-pull --pr: a PR held by main exits 4, not merged`. `tests/test-wrap-merge-stacked.sh` had encoded the old behavior (`conflict: exits 0 without merging`, a refused stacked rebase under `--apply --pr`); it now expects 4. Regression: `bash tests/run-all.sh --changed --time` ended `run-all: all 43 suites passed, 0 skipped for missing tooling`; the full `--all` glob was not run (AGENTS.md: nightly job owns it).

## Negative control
```
Command: bash lib/gate/negctl.sh --parallel 2 "$PWD" "bash tests/test-wrap-merge.sh && bash tests/test-wrap-merge-nopull.sh && bash tests/test-wrap-carry.sh" "<revert the exit code: WRAP_MERGE_NOT_MERGED_RC=4 -> 0 in lib/wrap/wrap-merge.sh>" "<drop the autoland carry's tolerance of 4 in lib/wrap/wrap-carry.sh>"
Exit: 1 (under mutation, RED expected)
Output:
    FAIL merge --apply --pr on a pending-checks PR exits 4
  test-wrap-merge: 279 passed, 1 FAILED of 280
    FAIL merge --no-pull --pr: a PR held by main exits 4, not merged
  test-wrap-merge-nopull: 50 passed, 1 FAILED of 51
    FAIL autoland gate refusal: apply exits 0
    FAIL autoland gate refusal: the PR is left open
  test-wrap-carry: 143 passed, 2 FAILED of 145
Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh lib/wrap/wrap-carry.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Both controls came back `Verdict: PASS` from negctl (RED under the mutation, green after the restore). The FAIL lines above come from a plain run of each mutation, since negctl keeps only the output tail. Control 1 reverts the exit change; control 2 keeps exit 4 but removes the carry adaptation, which makes `wrap apply` exit 2 on a gate refusal. Each mutated file was restored from HEAD.

## Not proven
- No real GitHub PR was merged or skipped; the `gh` stub from `tests/lib/wrap-stub.sh` served every PR.
- External callers outside this repo that chain on `wrap merge` exit codes are not enumerated; the one that motivated this change now stops on 4.
