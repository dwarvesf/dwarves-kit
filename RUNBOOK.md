# RUNBOOK

Diagnose and recover when the kit misbehaves. For operator usage, see `MANUAL.md`. For why a behavior exists, see `docs/PHILOSOPHY.md` and `docs/decisions/`.

## First step always: turn on debug mode

```
export DWARVES_KIT_DEBUG=1
```

Every hook logs to stderr what it matched and what it decided. Run the failing scenario once with debug on; in 90% of cases the line tells you the bug.

## Where to look

| Symptom | Look at |
|---|---|
| Bash command blocked unexpectedly | `~/.claude/dwarves-kit/logs/safety-gate.log` |
| Stop event keeps firing complaints | `~/.claude/dwarves-kit/logs/anti-rationalization.log` |
| New file warned about unfairly | `~/.claude/dwarves-kit/logs/spec-drift-guard.log` |
| Slop-cleaner nagging on something fine | `~/.claude/dwarves-kit/logs/slop-cleaner.log` |
| Session state lost | `.claude/session-state/last-state.md` and `archive/` |
| Statusline showing defaults | run `bash hooks/statusline.sh < /dev/null` and inspect |
| Hook silently does nothing | `DWARVES_KIT_DEBUG=1` and re-trigger; check stderr |

## Common failure modes

### `safety-gate` blocked a command I want to run

The hook's exit code 2 is final. Override paths in order:
1. Phrase the command differently. `rm` of one file is allowed; `rm -rf` triggers the block.
2. Use the suggested alternative. The block message names one (`trash` instead of `rm`, branch push instead of force).
3. Run the destructive op outside Claude Code. The hook only sees Claude's tool calls.
4. Last resort: comment out the matching pattern in `hooks/safety-gate.sh`, run the op, restore. Do NOT leave the kit in a relaxed state.

### `anti-rationalization` keeps firing on legitimate work

Check `~/.claude/dwarves-kit/logs/anti-rationalization.log` for the pattern. The v1.1 trim narrowed to 5 phrases ("left as an exercise", "follow-up PR", "too many issues to address", "that's a separate concern", "follow-up task"). If a legitimate phrase is hitting, it is in this list. Options:
- Rephrase the completion note (this is the intended behavior; the hook is doing its job).
- If the pattern is genuinely too broad, propose removing it via a PR with sample false-positive logs from your `.log` file as evidence.

### `spec-drift-guard` warns on a file you intentionally added outside the spec

The warning is a nudge, not a block. The file still gets written. The intent is to surface unplanned scope creep so it appears in the chat record. Two responses:
- The new file is genuinely needed. Update `.planning/SPEC.md` to list it; the warning stops on subsequent edits.
- The file is genuinely off-spec. Delete it; tighten the spec or cycle through `/think` again.

### `auto-format` adds 5+ seconds to every edit

The hook was downloading the formatter via `npx --yes` per edit (v1.0 bug). Fixed in v1.1: detection order is project-local > global > npx cache only (`npx --no`). If you still see slowness:
- Confirm the formatter is installed globally: `which prettier`, `which ruff`, etc.
- Confirm the hook is the v1.1+ version: `grep -- '--yes' hooks/auto-format.sh` should return nothing.

### Session state was lost across compaction

Compaction sequence:
1. `pre-compact-backup.sh` writes a snapshot.
2. Claude Code compacts.
3. `post-compact-reinject.sh` re-injects critical rules.
4. `session-state-save.sh` continues to write to `.claude/session-state/last-state.md` on every Stop.

If state is missing, check in order:
- `.claude/session-state/last-state.md` exists and is current.
- `.claude/session-state/archive/` for the last 10 rotated snapshots.
- Bash install only: confirm both PreCompact and PostToolUse(compact) hooks are registered in `settings.json`.
- Plugin install: same checks against `hooks/hooks.json`.

### Statusline shows blank or default values

The script reads model, branch, context %, cost, and thinking mode from Claude Code's StatusLine JSON contract. If Anthropic changes the schema, the script shows defaults.

Diagnose:
```
bash hooks/statusline.sh < /dev/null
```

This runs the hook with no input. Compare what it prints to what a real StatusLine event would give. If a real event's JSON has unexpected fields, propose a hook update with the schema diff.

Plugin install path: statusline is NOT configured (v1 plugin schema gap). Either switch to bash install or wait for the schema to gain `statusLine` (sunset trigger in ADR-0009).

### `task-verifier` blocks on something the spec actually allows

The verifier reads the spec literally. If a task's acceptance criterion is fuzzy ("works well", "is fast enough"), the verifier may FAIL it. Two responses:
- The spec criterion is too fuzzy. Edit `.planning/SPEC.md` to make it concrete, then re-run.
- The criterion is concrete but the verifier is wrong. Inspect the verifier's report. If the verifier is hallucinating a requirement, file an issue with the SPEC excerpt + verifier output.

### `fix-agent` retried twice and the task still fails

The retry cap is by design. After two FAIL:fixable verdicts, the orchestrator halts and asks the human. Read the verifier's final report:
- The task is genuinely harder than the spec assumed. Re-scope in `/think`.
- The fix-agent is making the wrong fix because the verifier's report is unclear. Edit the spec acceptance criterion to be more specific; re-run.
- The acceptance criterion is impossible to meet with the current stack. Update the spec or change the stack.

## Recovery paths

### Restore session state after a crash

```
ls -lt .claude/session-state/
cat .claude/session-state/last-state.md
```

If `last-state.md` is corrupt, fall back to the most recent archive:
```
ls -lt .claude/session-state/archive/ | head -3
```

Read the archive into the next session prompt.

### Reset hooks without uninstalling the kit

Bash install:
```
bash install.sh --uninstall   # removes kit hooks from settings.json
bash install.sh                # re-registers
```

Plugin install:
```
/plugin uninstall dwarves-kit@dwarves-marketplace
/plugin install dwarves-kit@dwarves-marketplace
```

### Roll back a bad release

The kit ships atomic conventional commits, each scoped to a logical change. `git revert <sha>` per bad commit, then re-tag.

If `tests/test-hooks.sh` or `tests/test-meta.sh` start failing after a revert, that is signal: the change being reverted had cross-cutting test impact. Address the failing test before the next tag.

## When to escalate

File an issue at https://github.com/dwarvesf/dwarves-kit/issues with:
- The failing hook or command name.
- The relevant log file contents (redact paths if needed).
- Output of `DWARVES_KIT_DEBUG=1 ...` for the failing scenario.
- Kit version (`cat VERSION`) and Claude Code version.

Do NOT escalate for cases where the kit is doing exactly what it claims (e.g. blocking a `git push --force` to main). Those are working-as-designed; the runbook entry is for understanding why, not for routing around.
