# Proof of done: `board publish` (the git leg of intake -> publish -> relay)

`board sync` mutates the board file in place; the estate's hourly sweeper had no publish leg, so every Mini checkout stayed permanently dirty: spoke writes invisible off-host and every ff-pull blocked (ops-toolkit ID-638; bit two deploys on 2026-09-01). `cmd_publish` stages only the board file, pulls rebase-first with autostash, commits `chore(board): publish spoke updates`, and pushes; a failed push keeps the commit local with an honest warn. Worktree checkouts are refused, the same fence as sync.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-board-publish.sh` | 0 | PASS 11/11 (commit+push; other dirt untouched; clean no-op; worktree refusal; push-failure keeps commit + warns) |
| 2 | `bash -n lib/board/board.sh` | 0 | PASS |

## Negative control

Fault injected: commit subject changed away from `chore(board): publish spoke updates`. Result: 3/11 FAIL (`no publish commit`, `remote missing the publish commit`, `no local commit after push failure`). Restored from the commit; suite green (run #1).

## Reproduce

```bash
bash tests/test-board-publish.sh
```

## Consumer wiring (separate PR, ops-toolkit)

`_meta/board-sync-all` calls `board publish --backlog-file <path>` per repo after its sync leg; push auth under launchd rides the sweeper's existing env (GH_TOKEN / askpass), with the warn path covering hosts that lack it.
