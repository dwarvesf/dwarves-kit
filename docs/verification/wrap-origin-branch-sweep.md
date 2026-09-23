# Verification -- wrap-origin-branch-sweep

`wrap apply` now deletes origin branches whose same-repo PR merged at their
exact origin tip, never the default branch and never a head or base of an
open PR, under the root-only knob `wrap.delete_merged_remote_branches`
(default `true`).

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS -- all 836 passed, including the origin-sweep block: dry run
  counts and names the three eligible branches and deletes nothing; --apply
  deletes them and keeps the tip-moved, open-PR base, open-PR head, fork-head
  and default branches; the operator knob false prints the report line and
  deletes nothing; a project .kit.toml setting the knob false is ignored;
  a push refused by receive.denyDeletes is FAILED with exit 2 and the pull
  still runs; WRAP_ORIGIN_DELETE_CHUNK=2 splits three names into two pushes
  and deletes all three; a non-GitHub origin prints its SKIP line.

Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS -- 854/854 after regenerating docs/FEATURES.md.

Command: bash tests/test-config-registry.sh; test-config.sh;
  test-config-seams.sh; test-config-stamp.sh; test-reserved-config-guard.sh
Exit: 0 each
Verdict: PASS -- 50/50, selftest PASS, 53/53, 17/17, 9/9. The registry
  test first failed (root-only call site not declared) until the key was
  added to lib/config/module-registry.md.
```

## Real primary flow (dry run, read-only on origin)
```
Command: KIT_CONFIG_ROOT=<worktree> bin/wrap apply <repo>   # no --apply
Exit: 0 for each repo
Verdict: PASS
  foundation-workers: WOULD delete 173 of 178 origin heads. Kept: main,
    chore/preview-on-workers-builds (open PR at the tip),
    docs/pat-finding, fix/client-invoice-render, fix/preview-cron-guard
    (origin tip differs from the merged PR head, checked by gh pr list --head).
  foundation-ops: WOULD delete 110 of 112. Kept: main, feat/dispatch-contract.
  foundation-apps: WOULD delete 26 of 30. Kept: main, docs/roadmap-sg02,
    fix/ci-op-env-read-d5, fix/deploy-verify-backoff.
```
The first cut read tips from `refs/remotes/origin/` and found 2 on
foundation-workers, because that checkout's fetch refspec is
`+refs/heads/main:refs/remotes/origin/main`. The tip source moved to
`git ls-remote --heads origin`, and the count matched the reported 173.

## Negative control
```
Command: one mutation per rsync'd copy of the worktree, bash tests/test-wrap.sh in each
Exit: 1 under every mutation (RED expected); 0 on the unmutated worktree
Verdict: PASS
  tip check dropped         -> RED, 6 checks ("kept moved, its tip is past the PR head")
  open-PR filter dropped    -> RED, 7 checks ("kept stack-base, an open PR targets it")
  cross-repo filter dropped -> RED, 6 checks ("kept fork-head, its PR came from a fork")
  default-branch rule dropped -> RED, 6 checks ("--apply exits 0", counts)
  knob read via project-aware kit_config_get -> RED, 2 checks (project .kit.toml honoured)
  push failure swallowed    -> RED, 2 checks ("refused push exits 2", "is FAILED")
  chunk loop stops after the first push -> RED, 2 checks ("removed all three")
```
The first negctl pass caught a fixture gap: the open-head PR targeted `main`,
so the open-PR rule masked a dropped default-branch rule. The fixture now
gives every kept branch exactly one guard.

## Not proven
- No `--apply` against a real GitHub origin. The delete runs against a
  local bare repo behind a github.com URL (`url.<bare>.insteadOf`). Branch
  protection on GitHub was modelled with `receive.denyDeletes`.
- The chunk loop is proven at a chunk of 2 through the test seam, not at
  the shipped 100. The first real `--apply` on foundation-workers (173
  names) runs two pushes.
- A repo with more than 1000 open PRs could hide a base branch past the
  list cap. No operator repo is near that.
