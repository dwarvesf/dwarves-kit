# Verification -- compact-reinject-event

Run id: `compact-reinject-event`. Lane: bug.

`hooks/post-compact-reinject.sh` was wired as `PostToolUse` matcher `compact`. No tool is named
`compact`, so it never fired. It now runs on `SessionStart` matcher `compact` and emits
`hookSpecificOutput.additionalContext`.

## Green run

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS
```

| Check | Result |
|---|---|
| output parses as JSON, `hookEventName` is `SessionStart` | PASS |
| `additionalContext` carries the `SPEC:` line | PASS |
| `additionalContext` carries `INTENT:` from `## Problem`, quotes and a backslash intact | PASS |
| intent stops at the first paragraph | PASS |
| spec with no Problem section: valid JSON, SPEC line, no `INTENT:` line | PASS |
| `settings.json` and `hooks/hooks.json` wire the script under SessionStart `compact` | PASS (2) |
| neither table wires it under PostToolUse | PASS (2) |

Totals: `Passed: 719 / 719`. Also green: `tests/test-install-modules.sh` (42 passed, 0 failed),
`tests/test-meta.sh` (879 / 879), `tests/test-codex-hooks.sh` (94 passed), `tests/test-hook-anchor.sh` (8 passed).

## Negative control

```
Command: bash tests/test-hooks.sh
Mutation: git checkout HEAD~1 -- settings.json hooks/hooks.json   (old PostToolUse wiring)
Exit: 1 (RED expected)   Passed: 715 / 719, Failed: 4
Restore: git checkout HEAD -- settings.json hooks/hooks.json
Exit: 0 (green after restore)   Passed: 719 / 719
Verdict: PASS
```

The four red lines are the wiring assertions: both tables lose "wires under SessionStart compact"
and both fail "does not wire under PostToolUse".

## Not proven

- No live Claude Code compaction was observed injecting the context. The event choice rests on
  the docs (SessionStart matchers include `compact`; SessionStart stdout is added as context).
  The fetched docs page did not quote the `hookSpecificOutput.additionalContext` shape for
  SessionStart in the SessionStart section itself; it is the documented general shape.
- `tests/run-all.sh` (the full suite) was not run; only the five suites above.
