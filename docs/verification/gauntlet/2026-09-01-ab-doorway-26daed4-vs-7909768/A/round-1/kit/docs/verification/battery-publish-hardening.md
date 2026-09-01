# Proof of done: battery hardening for publish + sync collision hold

Fixes from the 2026-09-01 verification battery on the board-publish batch (infra CRITICAL: autostash-conflict could commit conflict markers or wedge the checkout; security M3-M6: unpinned push, logical-path fence, glob pathspec, swallowed rebase; review H1/M4/M8: same conflict class, interactive-prompt hang, refused-adoption duplicate loop).

Changes: `cmd_publish` is commit-first (a rebase conflict can never stage markers into the board file); push pinned to `origin HEAD:refs/heads/<branch>` with detached-HEAD refusal; `:(literal)` pathspecs; physical-path worktree fence; non-interactive git (`GIT_TERMINAL_PROMPT=0`, `core.askPass=true`, BatchMode ssh); rc 3 = committed-but-not-on-remote (monitoring signal); `rebase --abort` guarantees a clean checkout. `plan_sync` holds `src_create` for a bid whose existing spoke item title-mismatches, so a refused adoption cannot mint duplicates forever.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-board-publish.sh` | 0 | PASS 19/19 (new AC5 diverged+rebase, AC6 real same-line conflict -> no markers + clean index + rc 3, AC7 detached HEAD) |
| 2 | `uv run --with pytest pytest lib/sync/tests/` | 0 | PASS 249/249 (new collision-hold test) |
| 3 | `bash -n lib/board/board.sh` | 0 | PASS |

## Negative control

Fault injected: the `rebase --abort` recovery replaced with a no-op. Result: `FAIL CONFLICT MARKERS in the working board file` + `FAIL unmerged index left behind` (17/19). This is the exact bug the AC6 fixture caught during development (`rebase --abort --quiet` is not a valid flag combination, so the original abort never ran). Restored; 19/19 (run #1).

## Reproduce

```bash
bash tests/test-board-publish.sh
uv run --with pytest pytest lib/sync/tests/
```
