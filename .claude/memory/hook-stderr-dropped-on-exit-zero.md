---
name: hook-stderr-dropped-on-exit-zero
description: A Claude Code hook's stderr on exit 0 reaches neither the user nor the model; a notice on an allowed action must be exit-0 JSON (systemMessage plus hookSpecificOutput.additionalContext).
metadata:
  type: project
---

On exit 0, Claude Code sends a hook's stderr to the debug log only. Only exit-2 stderr feeds back to the model. A hook that "warns" on stderr and then allows the action shows its warning to no one. The visible channel is one JSON object on stdout: `systemMessage` for the user, `hookSpecificOutput.additionalContext` (with `hookEventName`) for the model. `hooks/ship-gate.sh` emits it from one spot after `_floor_check`; `hooks/batch-debt-warn.sh` is the PreToolUse precedent. A test that captures the hook's stderr goes green whether or not anyone sees the line, so assert the stdout JSON with `jq`. The Codex adapter drops exit-0 output entirely, so under Codex the log is the only record.

**Why:** the hard-path exemption rework claimed "visible on every push" for a security mitigation, and two validate reviewers found the advisory lines would reach nobody; the tests had captured stderr directly.

**How to apply:** any new hook advisory on an allowed path goes through the JSON emitter, and its test reads stdout. Related: [[gate-ledger-keys-by-spec-slug]].
