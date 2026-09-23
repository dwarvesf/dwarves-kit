# Verification -- wrap-origin-branch-sweep

`wrap apply` now deletes origin branches whose same-repo PR merged at their
exact origin tip, never the default branch and never a head or base of an
open PR, under the root-only knob `wrap.delete_merged_remote_branches`
(default `true`). Each delete is leased to the tip it read.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS -- all 844 passed, including the origin-sweep block: the dry
  run counts and names the three eligible branches and deletes nothing;
  --apply deletes them and keeps the tip-moved, open-PR base, open-PR head,
  fork-head and default branches; a second --apply finds nothing left; a
  failed PR read skips the sweep and deletes nothing; the operator knob false
  prints the report line and deletes nothing; a project .kit.toml setting the
  knob false is ignored; a push refused by receive.denyDeletes is FAILED with
  exit 2 and the pull still runs; a branch pushed to after the read (modelled
  with pushInsteadOf to a second bare) is refused by the lease while the
  other two delete; WRAP_ORIGIN_DELETE_CHUNK=2 splits three names into two
  pushes and deletes all three; a non-GitHub origin prints its SKIP line.

Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS -- 854/854 (docs/FEATURES.md regenerated).

Command: bash tests/test-config-registry.sh; test-config.sh;
  test-config-seams.sh; test-config-stamp.sh; test-reserved-config-guard.sh
Exit: 0 each
Verdict: PASS -- 50/50, selftest PASS, 53/53, 17/17, 9/9. The registry
  test failed first (root-only call site not declared) until the key was
  added to lib/config/module-registry.md.
```

## Real primary flow (dry run, read-only on origin)
```
Command: KIT_CONFIG_ROOT=<worktree> bin/wrap apply <repo>   # no --apply
Exit: 0 for each repo
Verdict: PASS
  foundation-workers: WOULD delete 176 of 181 origin heads.
  foundation-ops:     WOULD delete 113 of 114.
  foundation-apps:    WOULD delete 26 of 30.
  An earlier run of the same code the same day read 173 of 178 on
  foundation-workers, the count the operator reported; the gap is PRs merged
  since. Kept there: main, chore/preview-on-workers-builds (open PR at the
  tip), docs/pat-finding, fix/client-invoice-render, fix/preview-cron-guard
  (origin tip differs from the merged PR head, checked by gh pr list --head).
```
The first cut read tips from `refs/remotes/origin/` and found 2 on
foundation-workers, because that checkout's fetch refspec is
`+refs/heads/main:refs/remotes/origin/main`. The tip source moved to
`git ls-remote --heads origin`.

## Negative control
```
Command: one mutation per rsync'd copy of the worktree, bash tests/test-wrap.sh in each
Exit: 1 under every mutation (RED expected); 0 on the unmutated worktree
Verdict: PASS
  tip check dropped            -> RED, 8 checks ("kept moved, its tip is past the PR head")
  open-PR filter dropped       -> RED, 9 checks ("kept stack-base, an open PR targets it")
  cross-repo filter dropped    -> RED, 8 checks ("kept fork-head, its PR came from a fork")
  default-branch rule dropped  -> RED, 10 checks ("--apply exits 0", counts)
  knob read via kit_config_get -> RED, 2 checks (project .kit.toml honoured)
  push failure swallowed       -> RED, 4 checks ("refused push exits 2", "is FAILED")
  only the first chunk pushed  -> RED, 2 checks ("removed all three")
  lease dropped                -> RED, 3 checks ("lease kept the branch that moved")
```
The first negctl pass caught a fixture gap: the open-head PR targeted `main`,
so the open-PR rule masked a dropped default-branch rule. The fixture now
gives every kept branch exactly one guard.

## Review
Two lenses ran on the diff (security on Opus, architecture + test coverage on
Sonnet). Applied: the per-name lease and the fully qualified refspec, a sweep
skip on a full open-PR page, tests for a failed PR read and a second apply,
and the chunk seam named in the file header. Declined: requiring the PR base
to be the default branch (see the implementation notes).

## Not proven
- No `--apply` against a real GitHub origin. The deletes run against a local
  bare repo behind a github.com URL (`url.<bare>.insteadOf`). GitHub branch
  protection was modelled with `receive.denyDeletes`.
- The chunk loop is proven at a chunk of 2 through the test seam, not at the
  shipped 100. The first real `--apply` on foundation-workers runs two pushes.
- The full-open-page skip and the failed re-read after the delete have no
  test; both are one-line guards.

## Revision: the sweep runs under `--own`

| Check | Command | Result |
|---|---|---|
| Suite with the fix | `bash tests/test-wrap.sh` | `test-wrap: all 848 passed` |
| Negative control | `lib/wrap/wrap.sh` reverted to origin/master, same suite | `test-wrap: 846 passed, 2 FAILED of 848` (the two `origin --own` delete checks) |
| Structure | `bash tests/test-meta.sh` | `Passed: 854 / 854` |
| Real repos | `wrap apply --apply foundation-workers foundation-apps` after `--own` runs left merged heads | `deleted 4 of 4` and `deleted 1 of 1` merged branches on origin |
