# Context for implementation

## Stack
- **Bash** for everything (hooks, reviewer wrapper, curator CLI). No build step. See SPEC-103 DEC-001.
- **`claude -p`** (Claude Code headless) as the review/curate engine. Auth = the harness's own
  (no API key in this tool). Flags used: `--bare --no-session-persistence --allowedTools ""
  --model haiku --max-turns 2 --output-format json` (the model has NO write tool; DEC-008 / ADR-0001).
- **jq** for transcript JSONL parsing + ledger reads (already on both Mini and Air).
- **atomic mkdir lock** for the single-flight reviewer lock (macOS has no `flock(1)`; see ADR-0004).
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
| `hooks/skill-review.sh` | PreCompact/SessionEnd hook: reentrancy + enabled gate, payload to tempfile, detached spawn, return fast |
| `hooks/sessionstart-surface.sh` | SessionStart hook: emit `additionalContext` (staged counts + spend) |
| `bin/cc-improve` | CLI: `status`, `curate [--apply]`, `restore` (no `.sh`, BTM-friendly) |
| `bin/skill-review` | CLI: `list`, `promote`, `reject`, `auto` (the human promote gate) |
| `lib/reviewer-run.sh` | runs `claude -p`, two-layer parse, secret-drop, writes staging + cost ledger |
| `lib/reviewer-spawn.sh` | thin detached wrapper the hook spawns: run reviewer-run, then rm the temp payload |
| `lib/promote.sh` | the trusted promote core (the only writer of `~/.claude/skills/`) |
| `lib/curate.sh` | the curator (inventory, plan, report, git-mv archive, restore) |
| `lib/surface.sh` | build the SessionStart status line (read-only counts) |
| `lib/common.sh` | shared paths, config load, sentinel, mkdir-lock helpers |
| `lib/transcript.sh` | parse `transcript_path` JSONL → last K turns compact text |
| `prompts/review-skill.md` | reviewer prompt (Phase A) |
| `prompts/curator.md` | curator prompt (Phase C) |
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
