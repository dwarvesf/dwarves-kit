# Verification -- board-brief-your-call

`board brief run` now renders what the reader must do: one `Your call (N)` block (drift, incident decision rows with `action`, hook 👉 lines, a triage action per board past its threshold), one `🤖 Handled` line (hook 🤖 fragments, open incidents, sync and bots state), `Details` on Mondays in Vietnam time or for error lines only, and `severity` warn only for Your call or an error.

## Green run

```
Command: bash tests/test-board-brief.sh && bash tests/test-board-hermes.sh && bash tests/test-board-health.sh && bash tests/test-board-sweep.sh && bash tests/test-board-digest.sh
Exit: 0
Output:
  board-brief: 202 passed, 0 failed
  board-hermes: 79 passed, 0 failed
  board-health: 97 passed, 0 failed
  PASS=55 FAIL=0
  PASS=63 FAIL=0
Verdict: PASS
```

The new suite was red first: against the previous renderer it reports `117 passed, 85 failed`.

## Negative control

Run after the commit, one per behavior change.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-brief.sh" "git show HEAD~1:lib/sync/sweep/board-brief > lib/sync/sweep/board-brief"
Exit: 0
Output:
  board-brief: 117 passed, 85 failed   (under mutation, RED)
  Restore: git checkout HEAD -- lib/sync/sweep/board-brief
  Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-brief.sh" "<Monday gate forced true in lib/sync/sweep/board-brief>"
Exit: 0
Output:
  board-brief: 190 passed, 12 failed   (under mutation, RED)
  Restore: git checkout HEAD -- lib/sync/sweep/board-brief
  Exit: 0 (green after restore)
Verdict: PASS
```

A third mutation (the `action` branch of the decision row disabled) went RED with `194 passed, 8 failed` and restored green; its ledger block read FAIL only because this file was created while it ran, so it is not claimed as a control.

## Rollback

Revert the squash commit. The poster reads `footer_tail` only when it chooses to; no other consumer changes.
