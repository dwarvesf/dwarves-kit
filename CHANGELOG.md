# Changelog

All notable changes to dwarves-kit are documented here.

## [1.1.0] - 2026-03-30

### Security

- **permission-auto-approve**: reject commands with pipes, chains, subshells (`|`, `&&`, `;`, `$()`, backticks) before checking whitelist. Prevents injection via chained commands.

### Fixed

- **anti-rationalization**: trimmed from 13 to 5 patterns. Removed 8 false-positive-prone phrases ("out of scope", "pre-existing", "we can revisit", "a future improvement", "for now, this should", "beyond the scope", "outside the current task", "I'll leave that for").
- **auto-format**: no more `npx --yes` network downloads per edit. Detection order: project-local binary > global binary > npx cache only (`npx --no`).
- **install.sh**: fixed jq merge logic that silently replaced user's existing hooks. Now removes dwarves-kit hooks first (idempotent), then concatenates arrays. Backs up settings.json before every modify.
- **context-readiness**: reduced context noise. Only outputs warnings and compact state (branch, dirty count). Healthy project = empty JSON = zero context cost.
- **spec-drift-guard**: shortened warning message, added `.claude/` to skip list.

### Added

- **statusline.sh** (StatusLine): shows `[model] branch | ctx:XX%! | $cost | think:on/off`. Context warning at 60% (`!`) and 80% (`!!`). Bash-only.
- **slop-cleaner.sh** (Stop hook): checks recently modified files for functions >50 lines, deep nesting >4 levels, files >300 lines, duplicate code blocks. Nudge only, never blocks.
- **kit-health command**: self-assessment against PHILOSOPHY.md principles. Checks file count, hook performance, settings validity, source citations, structural health.
- **rules/backend-go.md**: Go backend conventions template (path-scoped rules).
- **rules/frontend-ts.md**: TypeScript frontend conventions template (path-scoped rules).
- **tests/test-hooks.sh**: automated test suite (40+ cases) covering safety-gate, anti-rationalization, permission-auto-approve, auto-format, context-readiness, slop-cleaner, statusline.
- **Hook logging**: safety-gate, spec-drift-guard, slop-cleaner now log decisions to `~/.claude/dwarves-kit/logs/`.
- **Debug mode**: `DWARVES_KIT_DEBUG=1` makes all hooks log to stderr.
- **install.sh --uninstall**: clean removal of hooks, commands, skills from settings.json.

### Changed

- File budget: replaced hard 35-file cap with "every file must justify its existence" rule in PHILOSOPHY.md.
- README: added v1.1 changelog section, testing instructions, debug mode docs, hook log docs, known limitations.
- PHILOSOPHY.md: added indirect lineage documentation, expanded "NOT cover" section for parallel execution.
- v1.1-handoff.md: rewritten from build spec to post-build handoff document.

## [1.0.0] - 2026-03-29

Initial release. 9 hooks + 9 commands + 1 skill.

### Hooks
- safety-gate (PreToolUse): blocks rm -rf, push to main, force push
- context-readiness (SessionStart): project status injection
- anti-rationalization (Stop): catches incomplete work rationalization
- auto-format (PostToolUse): runs formatter on file changes
- spec-drift-guard (PreToolUse): warns on unplanned files
- pre-compact-backup (PreCompact): saves session snapshot
- post-compact-reinject (PostToolUse): re-injects rules after compaction
- notification (Notification): desktop alert when Claude needs input
- permission-auto-approve (PermissionRequest): auto-approves read-only operations

### Commands
- /user:think, /user:spec, /user:spec-validate, /user:execute, /user:next
- /user:review, /user:docs, /user:ship, /user:retro

### Other
- settings.json with all hooks registered
- CLAUDE.md project template with Trail of Bits quality rules
- install.sh idempotent installer
- skills/get-api-docs Context Hub integration
- docs/PHILOSOPHY.md design principles
