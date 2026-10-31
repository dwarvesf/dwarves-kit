# Verification -- wrap apply --own scopes the origin sweep

`wrap apply --own <wt>...` now sweeps only the origin branches the named worktrees held; plain `apply` and `--worktrees` stay repo-wide.

## Green run
```
Command: perl -e '$SIG{TERM}=q(DEFAULT);$SIG{INT}=q(DEFAULT);$SIG{HUP}=q(DEFAULT);exec @ARGV' bash tests/test-wrap-apply.sh
Exit: 0
Output:
  --- pinned refs: injected GIT_CONFIG_COUNT config reaches wrap's git calls
    PASS pinned config: the fetch through the mapping succeeds
    PASS pinned config: agent2 is proven merged after that fetch
    PASS pinned config: agent2 is gone

  test-wrap-apply: all 321 passed
Verdict: PASS
```
Cases added: (a) `--own` deletes the named worktree's merged origin branch (`origin --own deleted the named worktree's branch`); (b) `--own` keeps merged branches no named worktree held (`origin --own kept gone2, held by no named worktree`, `kept gone3`); (c) without `--own` both go (`origin repo-wide deleted the worktree's branch`, `also deleted gone2`). `tests/test-wrap-cli.sh` ends `test-wrap-cli: all 22 passed`.

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "<the green command above>" "grep -vF 'select($own == null' lib/wrap/wrap-apply.sh >| mut.sh && command cp -f mut.sh lib/wrap/wrap-apply.sh"
Exit: 1 (under mutation, RED expected)
Output:
  FAIL origin --own counts only the named branch
  FAIL origin --own kept gone2, held by no named worktree
  FAIL origin --own kept gone3, held by no named worktree
  FAIL origin --own dry run does not name gone2
  FAIL origin --own, no worktree kept gone
  FAIL origin --no-pull --own kept gone2
  test-wrap-apply: 313 passed, 8 FAILED of 321
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The mutation deletes the one jq line that filters origin candidates to the named worktrees' branches. Restored from HEAD; the final run is green.

## Not proven
- Only a fixture bare origin behind a github.com URL and a gh stub ran; no real GitHub remote was swept.
- A `--own` path already removed before `apply` (ExitWorktree) adds no origin candidate; the rule is documented, not exercised against a real session.
- negctl's restore step ignores INT/TERM/HUP, and children inherit that; the suite's busy-holder cases kill `sleep` by TERM and fail under a bare negctl, so the commands above reset the signals through perl first. The suite itself is unchanged.
