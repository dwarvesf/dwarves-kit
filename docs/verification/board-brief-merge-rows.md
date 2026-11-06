# Verification -- board-brief-merge-rows

`board brief run` now drops a decision row from the incidents block, merges a board's count and triage warning into one line with card titles, collapses a healthy sync and bots pair into one line, names the details field `ℹ️ Details`, and treats a `👉` hook line as a daily decision.

## Green run

```
Command: bash tests/test-board-brief.sh
Exit: 0
Output:
  case no duplicate rows (a decision row is not an incident row):
    ok   the incident head counts only rows not asked about
  case boards (count line and triage warning are one line, with card titles):
    ok   a warning folds into the status mix, titles trail
  case sync and bots (one healthy line; any error keeps two; Details):
    ok   the healthy pair is one line
  case hook lines (a pointing-hand line is a decision, other lines stay in Boards):
    ok   a day with hidden boards: the line is a decision in the main message
  board-brief: 153 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-board-health.sh && bash tests/test-board-sweep.sh && bash tests/test-board-digest.sh
Exit: 0
Output:
  board-health: 97 passed, 0 failed
  PASS=55 FAIL=0
  PASS=63 FAIL=0
Verdict: PASS
```

## Negative control

Run after the commit, one per behavior change.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-brief.sh" "<dedup filter disabled in lib/sync/sweep/board-brief>"
Exit: 0
Output:
  board-brief: 140 passed, 0 failed   (before)
  board-brief: 132 passed, 8 failed   (under mutation, RED)
  Restore: git checkout HEAD -- lib/sync/sweep/board-brief
  Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-brief.sh" "<hand-marker match disabled in lib/sync/sweep/board-brief>"
Exit: 0
Output:
  board-brief: 153 passed, 0 failed   (before)
  board-brief: 145 passed, 8 failed   (under mutation, RED)
  Restore: git checkout HEAD -- lib/sync/sweep/board-brief
  Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert the squash commit. The payload shape is unchanged, so the poster needs no change.
