# Task Backlog

## Completed

### v1.0 (2026-03-29)
- [x] Push to tieubao/dwarves-kit GitHub repo (public, MIT license)
- [x] Test install.sh on clean macOS
- [x] Test install.sh on existing config (jq merge preserves existing hooks)
- [x] Add .gitignore and LICENSE
- [x] Verify safety-gate, context-readiness, anti-rationalization in real session

### v1.1 (2026-03-30)
- [x] Add --uninstall flag to install.sh
- [x] Fix permission-auto-approve pipe injection vulnerability
- [x] Trim anti-rationalization to 5 unambiguous patterns
- [x] Fix auto-format network downloads (npx --yes removal)
- [x] Fix install.sh merge logic (preserve user hooks)
- [x] Add statusline, slop-cleaner, hook logging, debug mode
- [x] Add test suite (tests/test-hooks.sh)
- [x] Add kit-health command, path-scoped rules templates

### v1.2 (2026-03-30)
- [x] Verification pipeline (task-verifier + fix-agent + retry loop)
- [x] 8 custom agents (verifier, fix, reviewer, security-auditor, 4 researchers)
- [x] /start entry point router
- [x] /review-team parallel 3-lens review
- [x] session-state-save Stop + SubagentStop hook
- [x] Collaborative Design Protocol
- [x] Enhanced /spec with 4 parallel research agents for brownfield
- [x] Enhanced /ship with review gate, version bump, changelog
- [x] context-readiness v2 with command suggestions

## Next: Real-world validation

- [ ] Install on one real Dwarves project and run full cycle (think > spec > execute > review > ship)
- [ ] Monitor ~/.claude/dwarves-kit/logs/ for false positives (1 week)
- [ ] Verify task-verifier catches intentional spec violations
- [ ] Verify fix-agent retry cap works (max 2, then escalate)
- [ ] Verify /start correctly detects all 8 project states
- [ ] Test /review-team parallel dispatch (3 lenses run simultaneously)
- [ ] Test /spec research agents on brownfield Go + TypeScript projects
- [ ] Collect 30+ real verification transcripts for verifier prompt optimization

## v2 (pending real usage data)

- [ ] Prompt-type anti-rationalization (Haiku evaluation instead of grep)
- [ ] /qa command with headless browser testing (Playwright)
- [ ] Agent Teams parallel task dispatch in /execute
- [ ] SessionEnd hook for automatic knowledge capture
- [ ] AutoResearch optimization of task-verifier prompt (needs 30+ transcripts)
- [ ] Plugin marketplace packaging

## Parking lot (revisit in 30+ days)

- L5 orchestration (Nimbalyst integration) -- not needed until 3+ concurrent sessions
- AutoResearch loop for command prompt optimization -- manual iteration faster for now
- Agent-type hooks for deep verification -- custom subagents handle this now
