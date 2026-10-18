# Verification -- dead-parts

Wires the intake sweep at SessionStart, removes the unread `session-state-save` hook, makes `/kit:spec` flip a cited board row to `validated`, and makes the feature registry read hook commands that carry arguments.

## Green run

| # | Command | Exit | Output |
|---|---------|------|--------|
| 1 | `bash tests/test-meta-plugin-hooks.sh` | 0 | `Passed: 54 / 54` (5 new rows: both registries carry `backlog-stage --surface` on SessionStart, neither carries `session-state-save`, the hook file is gone) |
| 2 | `bash tests/test-meta.sh` | 0 | `Passed: 907 / 907` |
| 3 | `bash tests/test-meta-docs-registry.sh` | 0 | `Passed: 120 / 120` (README hook rows equal hook files; `docs/FEATURES.md` fresh) |
| 4 | `bash tests/test-hooks.sh` | 0 | `Passed: 813 / 813` |
| 5 | `bash tests/test-install-modules.sh` | 0 | `42 passed, 0 failed` |
| 6 | `bash tests/test-kit-contract.sh` | 0 | `25 passed, 0 failed` |
| 7 | `bash tests/test-hook-anchor.sh` | 0 | `8 passed, 0 failed` |
| 8 | `bash tests/test-adopt.sh` | 0 | `PASS=55 FAIL=0` |
| 9 | `bash tests/test-redteam-gate.sh` | 0 | `40/40 passed` |
| 10 | `bash tests/test-intake-sweep.sh`, `test-backlog-stage-parity.sh`, `test-board-promote.sh`, `test-no-scattered-ids.sh`, `test-registry-freshness-guard.sh` | 0 | all green |

Real flow, run end to end in a scratch repo through `anchor-root.sh` the way the hook table calls it:

| # | Step | Result |
|---|------|--------|
| 11 | `backlog-stage.sh --surface` without `BACKLOG_STAGE_AUTO`, config present | exit 0, no staging file written |
| 12 | same with `BACKLOG_STAGE_AUTO=1`, one `jsonl` source | prints `intake-sweep: staged 1 candidate(s)`, writes `_meta/backlog-staging.md` with a `[staged]` block |
| 13 | `backlog.sh set <ID> validated` on a `speccing` row | row reads `validated` |

## Negative control

Run after the commit. `hooks/hooks.json` was reset to its pre-change blob, so the SessionStart entry vanished and `session-state-save` came back.

```
Command: bash tests/test-meta-plugin-hooks.sh   (hooks/hooks.json from HEAD~1)
Exit: 1
Output:
  FAIL hook count parity (settings.json == hooks.json) (expected '27', got '28')
  FAIL same event types in both files (... got '...SessionStart,Stop,SubagentStop,UserPromptSubmit')
  FAIL hooks.json: backlog-stage --surface registered on SessionStart
  FAIL hooks.json: session-state-save not registered
  Passed: 50 / 54
Verdict: RED, as required
```

Restored with `git checkout -- hooks/hooks.json`; the suite is `Passed: 54 / 54` again.

## Not proven

- `tests/test-kit-foldin-hooks.sh` rows 3e and 4i fail here and on an untouched master checkout: they look for a detached process that has already exited, and this host ran at load 150 or more. Unrelated to this change.
- `/kit:spec` is prose a model follows. The `Board:` header and the `validated` flip are asserted by the instruction text, not by an automated run of the command.
- `lib/adopt.sh` still lists `session-state-save.sh` in its copy of the module hook list. It is outside this slice.
