# dwarves-kit

A minimal Claude Code workflow kit for spec-driven development. 11 hooks + 10 commands + 1 skill.

Built for a solo technical lead handing off to contractors. Opinionated, lightweight, no enterprise theater.

## What it does

**Hooks (automatic, event-triggered):**

| Hook | Event | What it does |
|------|-------|-------------|
| safety-gate | PreToolUse(Bash) | Blocks rm -rf, push to main, force push |
| context-readiness | SessionStart | Checks project state, injects warnings only |
| anti-rationalization | Stop | Catches Claude declaring work done prematurely |
| slop-cleaner | Stop | Flags bloated code in recently modified files |
| auto-format | PostToolUse(Write\|Edit) | Runs formatter on every file change |
| spec-drift-guard | PreToolUse(Write) | Warns when creating files not in the spec |
| pre-compact-backup | PreCompact | Saves structured session snapshot before compaction |
| post-compact-reinject | PostToolUse(compact) | Re-injects critical rules after compaction |
| notification | Notification | Desktop alert when Claude needs input |
| permission-auto-approve | PermissionRequest | Auto-approves read-only operations (pipe-safe) |
| statusline | StatusLine | Shows model, branch, context %, cost, thinking mode |

**Commands (manual, human-triggered):**

| Command | Phase | What it does |
|---------|-------|-------------|
| /user:think | Think | 6 forcing questions to stress-test an idea |
| /user:spec | Spec | Generate .planning/SPEC.md from intent |
| /user:spec-validate | Spec | 4 adversarial reviewers attack the spec |
| /user:execute | Build | Autonomous: spawns subagent per task, phase checkpoints |
| /user:next | Build | Lightweight: picks next undone task, loads context, you drive |
| /user:review | Review | Paranoid code review with severity scoring |
| /user:docs | Docs | Cross-reference diff against all doc files, fix drift |
| /user:ship | Ship | Test, commit, update docs, open PR |
| /user:retro | Reflect | What worked, what hurt, action items for next cycle |
| /user:kit-health | Meta | Self-assessment against kit philosophy |

**Skills (autonomous, Claude-triggered):**

| Skill | What it does |
|-------|-------------|
| get-api-docs | Fetches curated API docs via Context Hub before coding |

## Install

```bash
git clone https://github.com/dwarvesf/dwarves-kit.git ~/.claude/dwarves-kit
cd ~/.claude/dwarves-kit && bash install.sh
```

Requires: `jq` (for settings merge), `git`.

To uninstall:

```bash
bash ~/.claude/dwarves-kit/install.sh --uninstall
```

## Workflow

```
/user:think          Challenge the idea (5 min)
/user:spec           Generate the spec (15-30 min)
/user:spec-validate  Stress-test the spec (10 min)
                     [hand off to contractor]
/user:execute        Autonomous: subagent per task, phase checkpoints
  or
/user:next           Manual: pick next task, load context, you drive
                     [hooks enforce during build]
                     [statusline shows context budget]
                     [compaction backup + re-injection protect long sessions]
                     [slop-cleaner flags bloat at stop points]
/user:review         Review before merge (10 min)
/user:docs           Update all docs to match code (5 min)
/user:ship           Test, commit, PR (5 min)
/user:retro          Retrospective (10 min, after shipping)
```

## Debug mode

Set `DWARVES_KIT_DEBUG=1` to see what every hook is doing:

```bash
export DWARVES_KIT_DEBUG=1
```

All hooks log decisions to stderr when debug mode is active. Useful when a hook misbehaves or you want to understand why something was blocked/approved.

## Hook logs

Hooks that make enforcement decisions log to `~/.claude/dwarves-kit/logs/`:

| Log file | What it captures |
|----------|-----------------|
| anti-rationalization.log | Blocked patterns and timestamps |
| safety-gate.log | Blocked destructive commands |
| spec-drift-guard.log | Files created outside the spec |
| slop-cleaner.log | Bloat detections and file counts |

These logs build the eval corpus for future AutoResearch optimization.

## Testing

Run the hook test suite:

```bash
bash tests/test-hooks.sh
```

Tests cover: safety-gate blocking, anti-rationalization patterns (including v1.1 false-positive fixes), permission-auto-approve pipe injection protection, and basic sanity checks for all hooks.

## What the execution layer does NOT cover

The execution layer (/execute) dispatches tasks sequentially via the Task tool. It does not support parallel subagent dispatch, crash recovery, or multi-agent coordination. If you need:

- Parallel execution: install GSD v2 (Pi SDK runtime) or OMC (Ultrapilot mode)
- Crash-resilient autonomous loops: install Smart Ralph
- Multi-agent coordination: install Nimbalyst or OMC Swarm

The kit's job is spec generation and lifecycle hooks, not competing with agent runtimes.

## External dependencies (install alongside, not included)

These tools complement the kit but are installed separately:

- [Context Hub](https://github.com/andrewyng/context-hub) - `npm install -g @aisuite/chub`
- [Context7](https://github.com/upstash/context7) - MCP server for library docs
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - AST-level codebase indexing

## Project structure

```
dwarves-kit/
  hooks/
    safety-gate.sh              PreToolUse: rm-rf + push-to-main blocker
    context-readiness.sh        SessionStart: project status (warnings only)
    anti-rationalization.sh     Stop: catch incomplete work (5 patterns)
    slop-cleaner.sh             Stop: flag bloated code (nudge, not block)
    auto-format.sh              PostToolUse: run formatter (no network downloads)
    spec-drift-guard.sh         PreToolUse: warn on unplanned files
    pre-compact-backup.sh       PreCompact: save session snapshot
    post-compact-reinject.sh    PostToolUse(compact): re-inject rules
    notification.sh             Notification: desktop alert
    permission-auto-approve.sh  PermissionRequest: auto-approve reads (pipe-safe)
    statusline.sh               StatusLine: model, branch, context %, cost
  commands/
    think.md                    Phase 1: Challenge the idea
    spec.md                     Phase 2a: Generate spec
    spec-validate.md            Phase 2b: Adversarial review
    execute.md                  Phase 4: Autonomous subagent execution
    next.md                     Phase 4: Manual single-task picker
    review.md                   Phase 5: Paranoid code review
    docs.md                     Phase 5.5: Update docs to match code
    ship.md                     Phase 6: Test + commit + PR
    retro.md                    Phase 7: Retrospective + learning capture
    kit-health.md               Meta: Self-assessment against philosophy
  rules/
    backend-go.md               Template: Go backend coding standards
    frontend-ts.md              Template: TypeScript frontend standards
  skills/
    get-api-docs/SKILL.md       Context Hub integration
  tests/
    test-hooks.sh               Automated hook test suite
  settings.json                 Hook + statusline registration
  CLAUDE.md                     Project template
  CHANGELOG.md                  Version history
  VERSION                       Current version (1.1.0)
  install.sh                    Installer + uninstaller
  README.md                     This file
  docs/
    PHILOSOPHY.md               Design principles, target user, NO list
    session_state.md             Code-handoff session state
    tasks.md                     Phased backlog
    decisions.md                 4 ADRs
    dependencies.md              Required vs recommended tools
    v1.1-handoff.md             Session handoff document
```

## v1.1 changelog

- **[SECURITY]** permission-auto-approve: reject commands with pipes, chains, subshells
- **[FIX]** anti-rationalization: trimmed from 13 to 5 patterns (removed 8 false-positive-prone phrases)
- **[FIX]** auto-format: no more `npx --yes` (no network downloads per edit)
- **[FIX]** install.sh: proper array concat (doesn't overwrite user's existing hooks), backup before modify
- **[FIX]** context-readiness: reduced context noise (warnings only, not full inventory)
- **[NEW]** install.sh --uninstall: clean removal of hooks, commands, skills
- **[NEW]** statusline: model, branch, context %, cost, thinking mode
- **[NEW]** slop-cleaner: Stop hook that flags bloated code (nudge, not block)
- **[NEW]** Hook logging: safety-gate, spec-drift-guard, slop-cleaner log decisions
- **[NEW]** DWARVES_KIT_DEBUG=1: all hooks log to stderr in debug mode
- **[NEW]** tests/test-hooks.sh: automated test suite for all hooks

## v2 roadmap (not yet built)

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns)
- /qa command with headless browser testing (requires Playwright)
- Spec-aware parallel task dispatch in /execute
- Crash recovery for subagent failures (Smart Ralph pattern)
- SessionEnd hook for automatic knowledge capture
- Plugin marketplace packaging
- Vietnamese documentation for team adoption

## Credits

Patterns extracted from:
- [GSD](https://github.com/gsd-build/get-shit-done) - spec generation, .planning/ convention
- [gstack](https://github.com/garrytan/gstack) - /office-hours, /review, /ship patterns
- [Trail of Bits](https://github.com/trailofbits/claude-code-config) - hook implementations, code quality rules, statusline pattern
- [ClaudeKit](https://github.com/mrgoonie/claudekit-skills) - validation gate, adversarial review
- [Context Hub](https://github.com/andrewyng/context-hub) - API docs skill
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - HUD/statusline, slop-cleaner pattern
- [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) - path-scoped rules concept (documented, not extracted)

## License

MIT
