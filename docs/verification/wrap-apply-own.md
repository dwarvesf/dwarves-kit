# Verification -- wrap-apply-own

`wrap apply --own <path>` scopes the worktree tidy to the paths the operator
names, so a session ending on a repo shared with other live sessions removes
only its own worktrees and their branches. `--worktrees` still sweeps the
whole repo; `--own` is the session-scoped form, and every refusal the sweep
applies (dirty, detached, protected, unproven, tip-moved, live-pid lock,
index.lock) applies unchanged to a named worktree.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS -- all 678 passed, including the 22 SPEC-302 cases: the named
  proven worktree is the only candidate (dry-run WOULD, apply removes it and
  deletes its branch), the unnamed dirty and detached worktrees get no line
  at all, the all-branches sweep prints its scope-off SKIP and leaves
  merged-ancestor in place, a named dirty worktree still refuses as dirty,
  a named non-worktree path reports `not a registered worktree`, a
  trailing-slash path canonicalises to the same entry, --own composes with
  --worktrees under the own set, and a bare `--own` exits 64.

Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS -- 853/853 after regenerating docs/FEATURES.md
  (`bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md`);
  the only failure before the regen was the expected freshness pin.
```

## Negative control
```
Command: bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' \
  'bash /tmp/mutate-own.sh .'   # sed: every `if [ -n "$OWN_SET" ]; then`
                                # in wrap.sh -> `if false; then`
Exit: 1 under mutation (RED expected), 0 before and after restore
Verdict: PASS -- with the own-scope gates neutralised the named-worktree
  checks went red (unnamed worktrees re-entered the candidate set and the
  branch sweep ran again), and the restore returned the suite to green.
```
The mutation reproduces the reported bug precisely: without the scope check,
`--own` degenerates into the repo-wide sweep the row calls unsafe on a
shared repo.

## Not proven
- Two live sessions running `wrap apply --own` concurrently on one repo was
  not exercised; the fixture proves the candidate-set restriction and every
  inherited refusal in isolation, not the race window itself.
- `--own` names paths explicitly; the row's alternative (reading a
  session-maintained worktree list) was not implemented -- no such list
  exists in the kit today, and inventing session state for one flag would
  be a second feature.
