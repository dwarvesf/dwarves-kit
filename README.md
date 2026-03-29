# dwarves-kit

A minimal Claude Code workflow kit for spec-driven development. 9 hooks + 9 commands + 1 skill.

Built for a solo technical lead handing off to contractors. Opinionated, lightweight, no enterprise theater.

## What it does

**Hooks (automatic, event-triggered):**

| Hook | Event | What it does |
|------|-------|-------------|
| safety-gate | PreToolUse(Bash) | Blocks rm -rf, push to main, force push |
| context-readiness | SessionStart | Checks CLAUDE.md, spec, git branch; injects status |
| anti-rationalization | Stop | Catches Claude declaring work done prematurely |
| auto-format | PostToolUse(Write\|Edit) | Runs formatter on every file change |
| spec-drift-guard | PreToolUse(Write) | Warns when creating files not in the spec |
| pre-compact-backup | PreCompact | Saves structured session snapshot before compaction |
| post-compact-reinject | PostToolUse(compact) | Re-injects critical rules after compaction |
| notification | Notification | Desktop alert when Claude needs input |
| permission-auto-approve | PermissionRequest | Auto-approves read-only operations |

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

## Workflow

```
/user:think          Challenge the idea (5 min)
/user:spec           Generate the spec (15-30 min)
/user:spec-validate  Stress-test the spec (10 min)
                     [hand off to contractor]
/user:execute        Autonomous: subagent per task, phase checkpoints
  — or —
/user:next           Manual: pick next task, load context, you drive
                     [hooks enforce during build]
                     [compaction backup + re-injection protect long sessions]
/user:review         Review before merge (10 min)
/user:docs           Update all docs to match code (5 min)
/user:ship           Test, commit, PR (5 min)
/user:retro          Retrospective (10 min, after shipping)
```

## External dependencies (install alongside, not included)

These tools complement the kit but are installed separately:

- [Context Hub](https://github.com/andrewyng/context-hub) - `npm install -g @aisuite/chub`
- [Context7](https://github.com/upstash/context7) - MCP server for library docs
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - AST-level codebase indexing

## Uninstall

```bash
cd ~/.claude/dwarves-kit && bash install.sh --uninstall
# Or manually:
rm -rf ~/.claude/dwarves-kit
rm ~/.claude/commands/{think,spec,spec-validate,review,ship}.md
rm -rf ~/.claude/skills/get-api-docs
# Remove dwarves-kit hooks from ~/.claude/settings.json manually
```

## Project structure

```
dwarves-kit/
  hooks/
    safety-gate.sh              PreToolUse: rm-rf + push-to-main blocker
    context-readiness.sh        SessionStart: project status injection
    anti-rationalization.sh     Stop: catch incomplete work
    auto-format.sh              PostToolUse: run formatter
    spec-drift-guard.sh         PreToolUse: warn on unplanned files
    pre-compact-backup.sh       PreCompact: save session snapshot
    post-compact-reinject.sh    PostToolUse(compact): re-inject rules
    notification.sh             Notification: desktop alert
    permission-auto-approve.sh  PermissionRequest: auto-approve reads
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
  skills/
    get-api-docs/SKILL.md       Context Hub integration
  settings.json                 Hook registration
  CLAUDE.md                     Project template
  install.sh                    Installer
  README.md                     This file
```

## v2 roadmap (not yet built)

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns)
- /qa command with headless browser testing (requires Playwright)
- SessionEnd hook for automatic knowledge capture
- Plugin marketplace packaging
- Vietnamese documentation for team adoption

## Credits

Patterns extracted from:
- [GSD](https://github.com/gsd-build/get-shit-done) - spec generation, .planning/ convention
- [gstack](https://github.com/garrytan/gstack) - /office-hours, /review, /ship patterns
- [Trail of Bits](https://github.com/trailofbits/claude-code-config) - hook implementations, code quality rules
- [ClaudeKit](https://github.com/mrgoonie/claudekit-skills) - validation gate, adversarial review
- [Context Hub](https://github.com/andrewyng/context-hub) - API docs skill

## License

MIT
