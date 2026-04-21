# dwarves-kit

A minimal Claude Code workflow kit for spec-driven development with verification. 12 hooks + 12 commands + 8 agents + 1 skill.

Built for a solo technical lead handing off to contractors. Opinionated, lightweight, no enterprise theater.

## What it does

**Hooks (automatic, event-triggered):**

| Hook | Event | What it does |
|------|-------|-------------|
| safety-gate | PreToolUse(Bash) | Blocks rm -rf, push to main, force push |
| context-readiness | SessionStart | Detects project state, suggests next command |
| anti-rationalization | Stop | Catches Claude declaring work done prematurely |
| slop-cleaner | Stop | Flags bloated code in recently modified files |
| session-state-save | Stop, SubagentStop | Persists session state, rotates last 10 archives |
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
| /user:start | Entry | Detect project state, suggest next command |
| /user:think | Think | 6 forcing questions to stress-test an idea |
| /user:spec | Spec | Generate .planning/SPEC.md with 4 parallel research agents |
| /user:spec-validate | Spec | 4 adversarial reviewers attack the spec |
| /user:execute | Build | Autonomous: worker > verifier > fix-agent retry loop |
| /user:next | Build | Lightweight: picks next undone task, loads context, you drive |
| /user:review | Review | Paranoid single-pass code review |
| /user:review-team | Review | Parallel 3-lens review (security + architecture + test-coverage) |
| /user:docs | Docs | Cross-reference diff against all doc files, fix drift |
| /user:ship | Ship | Review gate, version bump, changelog, commit, PR |
| /user:retro | Reflect | What worked, what hurt, action items for next cycle |
| /user:kit-health | Meta | Self-assessment against kit philosophy |

**Agents (subagents dispatched by commands):**

| Agent | Dispatched by | What it does |
|-------|--------------|-------------|
| task-verifier | /execute | Read-only verification against spec + tests |
| fix-agent | /execute | Targeted fixes on FAIL:fixable (max 2 retries) |
| reviewer | /review-team | Focused review with configurable lens |
| security-auditor | /review-team | Deep OWASP-style security audit |
| research-stack | /spec | Maps technology stack (brownfield) |
| research-features | /spec | Maps existing features in target area |
| research-architecture | /spec | Maps architecture patterns and conventions |
| research-pitfalls | /spec | Finds landmines before implementation |

**Skills (autonomous, Claude-triggered):**

| Skill | What it does |
|-------|-------------|
| get-api-docs | Fetches curated API docs via Context Hub before coding |

## Install

### Option 1: Claude Code plugin (recommended)

In any Claude Code session:

```
/plugin marketplace add dwarvesf/dwarves-kit
/plugin install dwarves-kit@dwarves-marketplace
```

That's it. Hooks, commands, agents, and the skill all install automatically. No bash, no `jq`, no symlinks. Updates via `/plugin update dwarves-kit`.

To get the kit listed on Anthropic's official marketplace (`claude-plugins-official`), submit it via [claude.ai/settings/plugins/submit](https://claude.ai/settings/plugins/submit). One-time manual step; not blocking the self-hosted install above.

### Option 2: Bash installer (alternative)

For environments without Claude Code's plugin system (CI, project templates, older Claude Code versions):

```bash
git clone https://github.com/dwarvesf/dwarves-kit.git ~/.claude/dwarves-kit
cd ~/.claude/dwarves-kit && bash install.sh
```

Requires: `jq` (for settings merge), `git`.

To uninstall:

```bash
bash ~/.claude/dwarves-kit/install.sh --uninstall
```

### Pick one

Don't run both install paths on the same machine -- hooks would register twice. The plugin install does not configure `statusLine` (not in the v1 plugin schema); use the bash install if you want the statusline HUD. This split is documented in ADR-009.

## Workflow

```
/user:start          Detect state, suggest next command (entry point)
/user:think          Challenge the idea (5 min)
/user:spec           Generate the spec + 4 parallel researchers (15-30 min)
/user:spec-validate  Stress-test the spec (10 min)
                     [hand off to contractor]
/user:execute        Autonomous: worker > verifier > fix-agent retry loop
  or
/user:next           Manual: pick next task, load context, you drive
                     [hooks enforce during build]
                     [statusline shows context budget]
                     [session-state-save persists progress on every stop]
                     [slop-cleaner flags bloat at stop points]
/user:review         Single-pass review (10 min)
/user:review-team    Parallel 3-lens review (security + arch + tests)
/user:docs           Update all docs to match code (5 min)
/user:ship           Review gate, version bump, changelog, commit, PR
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

## Verification pipeline (/execute)

Every task goes through: worker > task-verifier > fix-agent (if needed).

```
worker subagent completes task
  -> task-verifier (read-only) checks acceptance criteria + tests
     -> PASS: mark done, continue
     -> FAIL:fixable: dispatch fix-agent (max 2 retries)
     -> FAIL:escalate: stop, ask human
```

Tasks execute sequentially within phases. Parallel dispatch is not yet supported. For parallel execution, use GSD v2 or OMC alongside the kit.

## External dependencies (install alongside, not included)

These tools complement the kit but are installed separately:

- [Context Hub](https://github.com/andrewyng/context-hub) - `npm install -g @aisuite/chub`
- [Context7](https://github.com/upstash/context7) - MCP server for library docs
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - AST-level codebase indexing

## Project structure

```
dwarves-kit/
  agents/
    task-verifier.md            Read-only verification against spec + tests
    fix-agent.md                Targeted fixes on FAIL:fixable verdicts
    reviewer.md                 Focused review with configurable lens
    security-auditor.md         Deep OWASP-style security audit
    research-stack.md           Maps technology stack (brownfield)
    research-features.md        Maps existing features in target area
    research-architecture.md    Maps architecture patterns
    research-pitfalls.md        Finds landmines before implementation
  hooks/
    safety-gate.sh              PreToolUse: rm-rf + push-to-main blocker
    context-readiness.sh        SessionStart: state detection + command suggestion
    anti-rationalization.sh     Stop: catch incomplete work (5 patterns)
    slop-cleaner.sh             Stop: flag bloated code (nudge, not block)
    session-state-save.sh       Stop + SubagentStop: persist session state
    auto-format.sh              PostToolUse: run formatter (no network downloads)
    spec-drift-guard.sh         PreToolUse: warn on unplanned files
    pre-compact-backup.sh       PreCompact: save session snapshot
    post-compact-reinject.sh    PostToolUse(compact): re-inject rules
    notification.sh             Notification: desktop alert
    permission-auto-approve.sh  PermissionRequest: auto-approve reads (pipe-safe)
    statusline.sh               StatusLine: model, branch, context %, cost
  commands/
    start.md                    Entry: detect state, suggest next command
    think.md                    Phase 1: Challenge the idea
    spec.md                     Phase 2a: Generate spec + 4 research agents
    spec-validate.md            Phase 2b: Adversarial review
    execute.md                  Phase 4: Worker > verifier > fix-agent loop
    next.md                     Phase 4: Manual single-task picker
    review.md                   Phase 5: Single-pass code review
    review-team.md              Phase 5: Parallel 3-lens review
    docs.md                     Phase 5.5: Update docs to match code
    ship.md                     Phase 6: Review gate + version + changelog + PR
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
  VERSION                       Current version
  install.sh                    Installer + uninstaller
  README.md                     This file
  docs/
    PHILOSOPHY.md               Design principles, target user, NO list
    COLLABORATIVE-DESIGN.md     Decision protocol for agents
    session_state.md            Code-handoff session state
    tasks.md                    Phased backlog
    decisions.md                4 ADRs
    dependencies.md             Required vs recommended tools
    v1.1-handoff.md             v1.1 session handoff
    v1.2-handoff.md             v1.2 session handoff
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for full version history.

**v1.2.0** - Verification pipeline, 8 agents, /start router, /review-team, session-state-save, Collaborative Design Protocol.

**v1.1.0** - Security fixes, slop-cleaner, statusline, test suite, debug mode.

**v1.0.0** - Initial release. 9 hooks + 9 commands + 1 skill.

## v2 roadmap (not yet built)

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns)
- /qa command with headless browser testing (requires Playwright)
- Agent Teams parallel task dispatch in /execute
- SessionEnd hook for automatic knowledge capture
- Plugin marketplace packaging

## Credits

Patterns extracted from:
- [GSD](https://github.com/gsd-build/get-shit-done) - spec generation, .planning/ convention, 4 parallel researchers
- [gstack](https://github.com/garrytan/gstack) - /office-hours, /review, /ship patterns
- [Trail of Bits](https://github.com/trailofbits/claude-code-config) - hook implementations, code quality rules, statusline pattern
- [ClaudeKit](https://github.com/mrgoonie/claudekit-skills) - validation gate, adversarial review, session-state pattern
- [Context Hub](https://github.com/andrewyng/context-hub) - API docs skill
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - HUD/statusline, slop-cleaner pattern
- [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) - /start router, path-scoped rules, Collaborative Design Protocol
- [OMC](https://github.com/OMC-tools) - task-verifier pattern (architect verification in Ralph loop)
- [Smart Ralph](https://github.com/smart-ralph) - fix-agent retry pattern (fail-fix-re-verify loop)

## License

MIT
