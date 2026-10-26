# wrap

The landing step after ship. One pass over every repo a session touched: report state, merge green PRs, tidy worktrees and branches, and write the activity log. It removes the hand-rolled git cleanup at session close.

**Entry points**
- `lib/wrap/wrap.sh <verb>`: the dispatcher. `bin/wrap` forwards to it, and consumers call `bin/wrap`.
- `scan`: report only, never writes.
- `apply`: gated writes, dry run unless `--apply`. Covers the pull, merged-branch sweep, `--worktrees`, `--own`, and `--archive-unmerged`.
- `merge`: merge one own green PR.
- `land`: land one hand-made worktree.
- `start`: open a worktree on a fresh branch, with `--pick` and `--carry`.
- `rebase`: a worktree branch onto `origin/<default>`, safe conflicts only.
- `adopt`: adopt repos into the kit contract and land them.
- `log`, `stage`, `knowledge-root`: the activity line, a staged candidate, and the fenced knowledge dir.
- `default-branch`, `follow-mode`, `deploy-wait`, `flick-7b`: small report verbs.
- `lib/wrap/report-lint.sh`: lints the `Needs you` section of a wrap report.

**Layout**
- `wrap-<verb>.sh`: one file per verb (`wrap-scan.sh`, `wrap-apply.sh`, `wrap-merge.sh`, and so on).
- `wrap-common.sh`, `wrap-carry.sh`, `wrap-pull.sh`, `wrap-ci.sh`: shared helpers that own no verb.

**Tests**: one suite per module in `tests/test-wrap*.sh`. Run `bash tests/run-all.sh --only test-wrap`.

**Spec and docs**: `docs/reference/wrap.md` holds the verb-by-situation table. The playbook that calls the verbs is `commands/wrap.md`.
