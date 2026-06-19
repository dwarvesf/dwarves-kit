# Context for implementation

## Stack
- **Bash** for everything (hooks, reviewer wrapper, curator CLI). No build step. See SPEC-103 DEC-001.
- **`claude -p`** (Claude Code headless) as the review/curate engine. Auth = the harness's own
  (no API key in this tool). Flags used: `--bare --no-session-persistence --allowedTools Read,Write
  --model haiku --max-turns 4 --output-format json`.
- **jq** for transcript JSONL parsing + ledger reads (already on both Mini and Air).
- **flock** for the single-flight reviewer lock.
- Optional **launchd** (Phase C weekly curator), BTM-friendly per repo CLAUDE.md.

## Conventions
- ops-toolkit tool layout: `bin/`, `hooks/`, `lib/`, `prompts/`, `config/`, `deploy/`, `docs/`,
  `tests/`. Scaffold via `ops-tool-shape`; docs via `ops-tool-docs`.
- Secrets: none. `op://` only if ever needed; never raw values.
- LaunchAgent authoring: `ProgramArguments[0]` = the script itself (no `.sh` on the top-level
  launcher), `#!/usr/bin/env bash` + `chmod +x`. Helper libs keep `.sh`.
- Done gate (SPEC-016): co-located `docs/proof-of-done.md`, table-first; multi-feature tool → a
  per-feature index. A behavioral change needs a recorded live run + negative control.
- No em dashes in any prose. English artifacts.
- New background job (the Phase C launchd curator) must be wired into vps-mon before "done"
  (`job-monitoring-onboarding`).

## Key files (to be created)
| Path | Purpose |
|---|---|
| `hooks/stop-reviewer.sh` | Stop hook: per-session counter, trigger, detached spawn |
| `hooks/sessionstart-surface.sh` | SessionStart hook: emit `additionalContext` (staged counts + spend) |
| `bin/cc-improve` | CLI: `curate`, `restore`, `status` (no `.sh`, BTM-friendly) |
| `lib/reviewer-run.sh` | runs `claude -p`, parses cost → ledger, writes staging |
| `lib/common.sh` | shared paths, config load, sentinel, lock helpers |
| `lib/transcript.sh` | parse `transcript_path` JSONL → last K turns compact text |
| `prompts/review-memory.md` | reviewer prompt (Phase A) |
| `prompts/review-skill.md` | reviewer prompt (Phase B) |
| `prompts/curator.md` | curator prompt (Phase C) |
| `deploy/install.sh` / `uninstall.sh` | idempotent settings.json merge + dirs + config |
| `deploy/macos/mini.cc-curator.plist` | optional weekly curator (Phase C) |
| `config/config.example.toml` | N interval, model, K cap, paths, enabled flags |
| `tests/test-*.sh` | transcript-parse, async (neg control), reentrancy, staging-gate |

## External dependencies
- Claude Code hooks contract (Stop, SessionStart): stdin JSON has `session_id`,
  `transcript_path`, `cwd`, `hook_event_name`. SessionStart returns `additionalContext`.
- Claude Code headless CLI flags (verified 2026-06-19 against code.claude.com/docs).
- Transcript JSONL at `~/.claude/projects/<slug>/<session_id>.jsonl`, **per-line schema is
  undocumented**; TASK-002 reverse-engineers it against a real sample and locks a fixture test.
- Han's existing accumulate-mode `learned-today.md` format + the `learning-ledger` `/learned`
  flow (the staging buffer must match so `/learned` consumes it unchanged).
- `writing-skills` skill (the promote step delegates to it).
- Billing: on Max plan, `claude -p` draws the same quota as interactive; `total_cost_usd` from the
  JSON result is the proxy metric logged to the ledger.
