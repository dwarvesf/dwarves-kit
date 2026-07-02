# Proof of done cc-hyg-04: Stop-hook + override tax reduction

VERDICT: PASS

## Acceptance criteria

Both new behaviors covered by green tests AND the full kit suite passes:
1. slop-cleaner reports a flagged file once/session, silent until content changes.
2. session-state-save debounces on an unchanged Stop.
3. proof-gate override rejects a source-file remainder (deploy-inert still passes).

## Implementation

- `hooks/slop-cleaner.sh`: per-session seen-state (`slop-seen-<session_id>.tsv`, `path<TAB>hash`), skip already-reported-at-same-hash files, prune >7d.
- `hooks/session-state-save.sh`: change-gated debounce on `branch|dirty|HEAD` fingerprint (dirty via `--untracked-files=all` minus the hook's own `.claude/session-state/`).
- `lib/proof-ledger.sh` `check()`: an override on a source-code file outside `deploy/` is rejected (exit 1); deploy scripts + non-code stay override-able.

## Confirmation run-table (2026-07-02, Air, cc-hyg-04 worktree)

| # | Command | Exit | Output |
|---|---------|------|--------|
| 1 | `bash tests/test-hooks.sh` | 0 | `Passed: 449 / 449` (incl. 4 review-round tests) |
| 2 | `bash tests/test-deployable-done.sh` | 0 | `17/17 passed, 0 failed` |
| 3 | `bash tests/test-proof-visual-evidence.sh` | 0 | (green) |
| 4 | `bash tests/test-ledger-durability.sh` | 0 | `32/32 passed` |
| 5 | `bash tests/test-meta.sh` | 0 | `Passed: 578 / 578` |
| 6 | `bash tests/test-e2e.sh` | 0 | `Passed: 20 / 20` |
| 7 | `bash tests/test-lane-classify.sh` | 0 | `16/16 passed` |
| 8 | `bash tests/test-meta-agent.sh` | 0 | `65/65 passed` |
| 9 | `bash tests/test-orchestrate.sh` | 0 | (green) |
| 10 | `bash tests/test-review-team-plants.sh` | 0 | `Passed: 8 / 8` |
| 11 | `bash tests/test-role-classify.sh` | 0 | `15/15 passed` |

All 11 CI suites: exit 0, 0 total failures.

## NEGATIVE CONTROL

The override-rejection is falsifiable, not a rubber stamp:

- **Source change + override -> REJECTED (exit 1).** A branch changing `lib/a.sh`
  with a logged override:
  ```
  $ proof-ledger.sh check <repo> <base> x   # override 'x' logged
  proof-of-done: override for 'x' REJECTED -- the branch changes source files with no proof of done:
      - lib/a.sh
  Exit: 1
  ```
- **Deploy-path change + override -> PASS (exit 0).** The same shape under `deploy/`:
  ```
  $ proof-ledger.sh check <repo> <base> y   # override 'y' logged, deploy/roll.sh
  proof-of-done: OVERRIDDEN for 'y' (docs/deploy-inert remainder; logged, ...)
  Exit: 0
  ```
  Proves the gate discriminates source (reject) from deploy-inert (pass), not a
  blanket allow/deny.
- **Debounce is falsifiable:** the test asserts the DEBUG "skipping" line is PRESENT
  on an unchanged Stop and ABSENT after a real commit. Before the fingerprint fix
  (which excludes the hook's own untracked output), that test failed , the debounce
  never fired , which is how the untracked-churn bug was caught.

## Reproduce

```
cd <dwarves-kit>/.claude/worktrees/cc-hyg-04   # or the merged master
for t in test-hooks test-deployable-done test-proof-visual-evidence \
         test-ledger-durability test-meta test-e2e test-lane-classify \
         test-meta-agent test-orchestrate test-review-team-plants test-role-classify; do
  bash "tests/$t.sh" >/dev/null 2>&1 && echo "OK $t" || echo "FAIL $t"
done
```
