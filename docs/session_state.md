# Session State

Generated: 2026-03-28
Project: dwarves-kit
Session type: planning + scaffolding

## POSITION

### Phase
Scaffolding complete. Ready for testing and iteration.

### What is decided
- Kit structure: 5 hooks (command-type only) + 5 commands + 1 skill
- Hook events used: SessionStart, PreToolUse(Bash), PreToolUse(Write), PostToolUse(Write|Edit), Stop
- Commands follow GSD's .planning/ convention for spec output
- Install mechanism: bash script with jq-based settings.json merge
- CLAUDE.md template uses Trail of Bits code quality rules
- v1 is command hooks only. Prompt/agent hooks are v2.
- Target: user-level install (~/.claude/dwarves-kit/) with symlinks to commands/skills
- Open source later via dwarvesf/dwarves-kit GitHub repo

### What is NOT decided
- Whether to also publish as a Claude Code plugin (marketplace format)
- Whether /review should spawn a subagent for parallel file review
- Whether auto-format hook should run on commit (Stop) instead of every edit (PostToolUse) to reduce context noise
- Anti-rationalization: v1 uses grep patterns (false positive risk). When to upgrade to prompt hook (v2)?

## CONTEXT

### Key constraints
- Solo tech lead + contractors workflow at Dwarves Foundation
- Must work with: Notion, GitHub, Claude Code, tmux
- No external runtime dependencies beyond jq and git
- Hooks must complete in under 500ms each (performance budget)
- v1 must be usable this week on a real project

### Prior art synthesized
- GSD: .planning/ directory, discuss-to-plan traceability, atomic task breakdown, fresh subagent contexts
- gstack: /office-hours forcing questions, /review paranoid reviewer with completeness scoring, /ship release flow
- Trail of Bits: rm-rf blocker, push-to-main blocker, anti-rationalization Stop hook, CLAUDE.md quality rules
- ClaudeKit: /ck:plan validate interview gate, /ck:plan red-team adversarial review (4 personas)
- Context Hub: chub CLI skill, annotation persistence, agent-readable doc format

### Rejected approaches
- BMAD: too heavy for solo dev. 12+ agent personas, sprint ceremonies. Overkill.
- Full ClaudeKit paid kit: wait until gaps identified from using lighter tools
- GSD v2 (standalone CLI on Pi SDK): interesting but a different product. We want hooks+commands, not a new agent runtime.
- Browser QA (gstack /qa): requires Playwright + Bun binary build. Too heavy for v1.
- AutoResearch loop: manual iteration faster for 5 commands. Revisit when optimizing 20+ skills.

## INTENT

### What to do next
1. Push to dwarvesf/dwarves-kit GitHub repo (public)
2. Test install.sh on a clean machine (Mac, no prior Claude Code config)
3. Test on one real Dwarves project: run /user:think + /user:spec on a new feature
4. Monitor anti-rationalization hook for false positives over 1 week
5. Monitor auto-format hook for context window noise (does Claude get "file changed" warnings too often?)

### Priority order
1. Push to GitHub (5 min)
2. Test install on clean env (10 min)
3. Real project test (30 min)
4. Iterate based on friction (ongoing)

### Blockers
- None. Kit is scaffold-complete.

### Open questions
1. Should auto-format move from PostToolUse to a Stop hook that formats all changed files at once? (Reduces per-edit noise)
2. Is the jq merge in install.sh robust enough for users with complex existing settings.json?
3. When to add --uninstall flag to install.sh?
