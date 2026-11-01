# Verification -- wrap apply archives to hidden refs/archive, not branches

`wrap apply --archive-unmerged` and `--archive-worktrees` now push to `refs/archive/<slug>-<date>`; origin gains no `refs/heads/archive/*` branch.

## Green run
```
Command: perl -e '$SIG{TERM}=q(DEFAULT);$SIG{INT}=q(DEFAULT);$SIG{HUP}=q(DEFAULT);exec @ARGV' bash tests/test-wrap-apply.sh
Exit: 0
Output:
    PASS archive apply gained no refs/heads/archive/* branch on origin
    PASS AC-3 origin gained no refs/heads/archive/* branch
    PASS AC-43 kept after a lock during the push
    PASS AC-27 the never-remove exception

  test-wrap-apply: all 470 passed
Verdict: PASS
```
Cases: every archive-ref assertion in `tests/test-wrap-apply.sh` moved to `refs/archive/...` (names, create-only lease string, the "already exists" refusal, the read-back mismatch hook, the pinned-ref cases). Two new assertions, one per path: `archive apply gained no refs/heads/archive/* branch on origin` (`--archive-unmerged`) and `AC-3 origin gained no refs/heads/archive/* branch` (`--archive-worktrees`). Regression: `bash tests/run-all.sh --changed --time` ended `run-all: all 39 suites passed, 0 skipped for missing tooling`; the full `--all` glob was not run (AGENTS.md: about 25 minutes, nightly job owns it).

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "<the green command above>" "perl -pi -e 's|ref=\"refs/archive/|ref=\"refs/heads/archive/|' lib/wrap/wrap-apply.sh"
Exit: 1 (under mutation, RED expected)
Output:
    FAIL archive apply gained no refs/heads/archive/* branch on origin
    FAIL AC-3 origin gained no refs/heads/archive/* branch
  test-wrap-apply: 427 passed, 43 FAILED of 470
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The mutation points both archive paths back at `refs/heads/archive/`. The two FAIL lines above come from a second, plain run of the same mutation (negctl keeps only the output tail); negctl's own block recorded `43 FAILED of 470`. Restored from HEAD.

## Not proven
- Only fixture bare origins ran; no real GitHub remote received a `refs/archive/*` push in this run (the operator confirmed GitHub stores such a ref).
- Archives already pushed as `archive/*` branches are not migrated.
