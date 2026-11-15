# Verification -- orch-retry-no-claim

## What it did before

In `lib/queue/orchestrate.sh` a sub-goal session that exits 0 without flipping its ROADMAP box ends the loop (`blocked`, `box not flipped (no self-claim)`, return 1) until a human re-runs it. One measured run sat blocked 74 minutes that way. The wave path has the same halt (`wave: box not flipped`, then `a wave sub-goal did not complete ... halting`).

## What it does now

| Case | Behavior |
|---|---|
| Serial path, session rc 0, box unflipped, no PR on origin | Re-dispatch the SAME sub-goal in a fresh session, up to `NOCLAIM_RETRIES` (default 1, `[mega].noclaim_retries`) per sub-goal per run. The retry prompt is the normal prompt (goal file, previous HANDOFF) plus a RETRY block. Then halt exactly as before. |
| Box checked on origin with a real `PR #<n>` | Unchanged: the merged-PR reconcile accepts it, no retry. |
| Box checked on origin with NO `PR #<n>` (a bare claim) | Never retried; the loop halts as before. The reconcile fast-forward can already show that box checked locally, so a retry would have read it as a flip. |
| Session exits nonzero | Unchanged: halts, not retried. |
| `NOCLAIM_RETRIES=0` | Old behavior, one session then halt. |
| Wave path (`_wave_run`) | Unchanged, still halts. See "Not proven". |

No-self-claim is untouched: the driver never writes a box itself on this path. A retry advances the loop only when a session's own flip lands, or the merged-PR reconcile finds the box on origin with a PR number. The failed session's tokens are recorded and its transcript is kept as `.orchestrate/<id>.noclaim<n>.stream.jsonl` before the retry reuses the path.

## Recorded run

```
Command: bash tests/test-orchestrate.sh
Exit: 0
Output:
  PASS no-claim retry: unflipped first session -> one fresh retry flips the box, run completes (2 sessions)
  PASS no-claim retry: only the second prompt carries the RETRY block
  PASS no-claim retry: the retry prompt still carries the previous HANDOFF
  PASS no-claim retry: the loop says it is retrying
  PASS no-claim retry NC: never flipping -> exactly 2 sessions, then halt, box still unchecked (no self-claim)
  PASS no-claim retry: NOCLAIM_RETRIES=0 halts after one session (old behavior)
  PASS no-claim retry: a nonzero session exit is not retried
  PASS no-claim retry: NOCLAIM_RETRIES=2 -> two retries, third session flips
  ALL PASS
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0
Output:
  test-orchestrate                               ok (63s)
  test-orchestrate-gate-dispatch                 ok (21s)
  test-turn-cap                                  ok (15s)
  test-wave-rid-check                            ok (37s)
  run-all: all 43 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

The first `--changed` run was red on `test-orchestrate-gate-dispatch` case A2 (a bare remote box with no `PR #<n>` must still halt): the retry accepted it. That is the bare-claim row above, fixed in the second commit and now pinned by A2.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate.sh" "git show origin/master:lib/queue/orchestrate.sh >| lib/queue/orchestrate.sh"
Exit: 1 under the mutation (RED expected), 0 after restore
Output:
  FAIL no-claim retry: NOCLAIM_RETRIES=2 wrong (rc=1 sessions=1)
  [orchestrate] [guardrail] SG-01 did not check its ROADMAP box; halting (no self-claim, no advance on a dead/incomplete session).
  6 FAILED
Verdict: PASS
```

The mutation is the pre-change driver. Six of the new cases go red (retry flips, RETRY block, HANDOFF in the retry prompt, retry message, never-flips takes 2 sessions, `NOCLAIM_RETRIES=2`); the `=0` and nonzero-exit cases stay green because the old driver already behaved that way.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate-gate-dispatch.sh" "perl -pi -e 's/ && \[ \"\$bare_remote\" = 0 \]//' lib/queue/orchestrate.sh"
Exit: 1 under the mutation (RED expected), 0 after restore
Output:
  1 FAILED
Verdict: PASS
```

The mutation drops the bare-claim guard; case A2 goes red.

## Not proven
- No live mega-goal run and no real `claude -p` session: every session is a mock `CLAUDE_CMD`.
- The wave path still halts on an unflipped box. A retry there must also converge the siblings that already landed in the same failed wave (`_wave_converge` is skipped when `_wave_run` fails today), which is a design call, not a one-line change.
- Default is 1 (on). `[mega].noclaim_retries = 0` in a project `.kit.toml` restores the halt. `kit.toml` itself is a hard path under `[lanes] extra_hard_paths`, so the key is documented in `docs/reference/architecture.md` and the driver header, not in `kit.toml`.
- The retry prompt points at the branch, worktree and PR for earlier work; it does not regenerate a handoff from the failed session's transcript (the turn-cap path does). The previous HANDOFF.md, including anything the failed session wrote there, is what the retry reads.

## Rollback
Revert the commits, or set `NOCLAIM_RETRIES=0` per run, or `[mega].noclaim_retries = 0` in a project `.kit.toml`. The driver writes no new state beyond the renamed transcript file under the mega-goal's `.orchestrate/`.
