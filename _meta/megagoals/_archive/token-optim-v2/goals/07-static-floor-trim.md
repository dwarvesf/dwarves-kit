# SG-07: static-floor trim + MCP prune (measure-then-trim)

Merge policy: gate (stacked; reviewed at end of wave with the rest, per Han 2026-06-29)
Time budget: ~1 session
Depends on: (none hard)
Stacking: dotfiles repo, standalone (cannot git-stack with the ops-toolkit chain); branch off dotfiles main, held open for the end-of-wave review.
Model: sonnet
Effort: medium

## Directional outcome
Shrink the always-loaded per-turn floor (CLAUDE.md + connected MCP surface), SELECTIVELY and
measured. This is the small lever (the forensic says static trims are minor), so the bar is
"measure, cut only genuine fat, prove the delta", not aggressive trimming.

## Done =
A measured before/after of CLAUDE.md size + connected MCP surface; a SELECTIVE trim (move
genuinely-rarely-used inline blocks to on-demand skills) + a per-project MCP allowlist; the
measured delta recorded. The always-consulted sections (Tool selection, security, machine
routing) are NOT trimmed. PR opened.

## Close the loop (verification)
```
wc -c ~/.claude/CLAUDE.md            # before vs after
# the trimmed CLAUDE.md still ends with the canary line + keeps the always-consulted sections
```

## Scope edges
dotfiles CLAUDE.md + MCP config only. NEVER trim always-consulted sections (memory
`feedback_keep_critical_claude_md_inline`). Measure first; cut only what is genuinely rarely
used. Selective, reversible.

## Where to look
`~/.claude/CLAUDE.md` (dotfiles, chezmoi `modify_CLAUDE.md.tmpl`), MCP registry locations
(memory `feedback_mcp_registry_locations`: `~/.claude.json`, Desktop config, `~/.codex/`).

## Proof expectation
Before/after size + (if measurable) spend numbers + a diff of what moved. Scale: this is a
config trim, so the proof is the measured delta + the diff. Surface what was moved, not silently.

## PR body
chore(dotfiles): selective static-floor trim + per-project MCP prune (measured). Small lever;
keeps all always-consulted sections inline.
