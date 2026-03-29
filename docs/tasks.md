# Task Backlog

## Phase 1: Ship v1 (this week)

- [ ] Push to dwarvesf/dwarves-kit GitHub repo -- public, MIT license
- [ ] Test install.sh on clean macOS (no ~/.claude/settings.json) -- verify settings.json created correctly
- [ ] Test install.sh on existing config (with prior hooks) -- verify jq merge preserves existing hooks
- [ ] Run /user:think on a real Dwarves project feature -- capture friction notes
- [ ] Run /user:spec on the same feature -- does the spec format work for contractor handoff?
- [ ] Verify safety-gate blocks rm -rf and push to main in a real session
- [ ] Verify context-readiness outputs valid JSON on SessionStart
- [ ] Verify anti-rationalization does not false-positive on legitimate "out of scope" statements

## Phase 2: Iterate (next 2 weeks)

- [ ] Add --uninstall flag to install.sh (remove symlinks, remove hooks from settings.json)
- [ ] Monitor auto-format hook context noise -- if Claude gets too many "file changed" reminders, move to Stop hook
- [ ] Tune anti-rationalization patterns based on real usage -- track false positives in a log
- [ ] Add .gitignore to kit repo
- [ ] Add LICENSE file (MIT)
- [ ] Test with Go project (gofmt path in auto-format)
- [ ] Test with Python project (ruff path in auto-format)

## Phase 3: v2 (next month)

- [ ] Upgrade anti-rationalization to prompt hook (Haiku evaluation, fewer false positives)
- [ ] Add /qa command with headless browser testing (Playwright, adapted from gstack)
- [ ] Add SessionEnd hook for automatic knowledge capture (trigger knowledge-capture skill)
- [ ] Package as Claude Code plugin for marketplace distribution
- [ ] Vietnamese README for Dwarves team adoption
- [ ] Evaluate if spec-drift-guard needs smarter file-to-task matching (currently grep-based)

## Parking lot (revisit in 30+ days)

- L5 orchestration support (Nimbalyst integration) -- not needed until 3+ concurrent Claude Code sessions
- ClaudeKit paid features evaluation -- wait until v1 gaps are clear
- AutoResearch loop for skill optimization -- manual iteration faster for now
- Agent-type hooks for deep verification -- prompt hooks come first
