# Verification -- wrap-skip-live-lock

`wrap apply --worktrees` no longer removes a worktree whose lock names a pid
that is still alive, closing the case where a subagent's own worktree, locked
seconds after creation with a fresh branch trivially ancestor-of-main, was
about to be force-removed by a concurrent `--apply`.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS -- all 587 passed, including the 6 new live-pid cases (dry-run
  SKIP for the live pid, dry-run WOULD-remove for the dead pid, apply removes
  the dead-pid worktree and its branch, apply keeps the live-pid worktree and
  its branch).

Command: bash tests/run-all.sh --changed
Exit: 0
Verdict: PASS -- 9 changed-scope suites (test-bin-forwarders,
  test-boundary-lint, test-config-registry, test-gitattributes-union,
  test-kit-contract, test-meta, test-no-personal-paths, test-no-scattered-ids,
  test-wrap), all ok, 0 skipped for missing tooling.
```

## Negative control
```
Command: revert the `_wt_lock_live` skip block in lib/wrap/wrap.sh's
  _apply_worktrees loop only (leave the helpers _wt_lock_pid/_wt_lock_live in
  place, unused), then bash tests/test-wrap.sh
Exit: 1
Verdict: NEGATIVE CONTROL RED -- exactly 3 of the 6 new cases failed:
  "livepid dry-run: the live-pid worktree is skipped, not removed",
  "livepid apply kept the live-pid worktree",
  "livepid apply kept the live-pid worktree's branch"
  (584 passed, 3 FAILED of 587; every other case, old and new, still passed).
  Restored via `git checkout -- lib/wrap/wrap.sh`; re-ran bash tests/test-wrap.sh,
  exit 0, all 587 passed again.
```
The revert reproduces the reported bug precisely: without the live-pid check,
a locked worktree on an ancestor-of-main branch is removed regardless of
whether its lock's pid is still running.

## Not proven
- Real concurrent-agent timing (two live Claude Code sessions racing
  `wrap apply --worktrees --apply` against each other) was not exercised; the
  fixture proves the pid-liveness gate in isolation, not the original
  race window itself.
- Windows/non-POSIX `kill -0` semantics are out of scope; the kit targets
  macOS/Linux bash per its stated stack.
