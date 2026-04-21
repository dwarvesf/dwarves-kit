# Changelog

All notable changes to dwarves-kit are documented here.

## [1.5.1] - 2026-04-21

Audit-fix release. Same-day patch following a retroactive `/review-team` and `/retro` that surfaced gaps in the v1.4/v1.5 SDLC application.

### Fixed

- **`plugin.json` version drift**: `.claude-plugin/plugin.json` was still declaring `1.4.0` after VERSION bumped to `1.5.0`. Now bumped to `1.5.1` and asserted by `tests/test-meta.sh` (parity check between VERSION and plugin manifest). The bug shipped briefly in v1.5.0; v1.5.0 tag is preserved in history.

### Added

- **`tests/test-meta.sh`**: 62 new assertions covering structural integrity that grep-only checks miss. Validates: plugin manifest schema (including version-matches-VERSION parity), hooks.json/settings.json hook count parity, all hooks.json paths use `${CLAUDE_PLUGIN_ROOT}`, every agent/command markdown file has YAML frontmatter with required fields, CLAUDE.md Subagents list bidirectionally matches `agents/*.md`, demo project files have all required template sections, workflow has explicit permissions block, CONTRIBUTING.md cross-links resolve. Test suite total: 42 → 104.
- **CI hardening**: workflow now runs `tests/test-meta.sh` alongside `tests/test-hooks.sh`. `actions/checkout` pinned to release SHA (supply-chain best practice). Explicit `permissions: contents: read` (least privilege).
- **`docs/retro/v1.3-v1.5.md`**: cycle retrospective covering what worked, what hurt, action items. First retro since the kit started; addresses the action item to make `/retro` part of the release ritual.

### Changed

- **README "Project structure" section**: replaced the embedded file tree (drifted across 5 releases — last accurate at v1.0) with a concise top-level overview pointing at `git ls-files` for the canonical listing. Removes a recurring drift surface.
- **README "Changelog" section**: removed the duplicated highlight bullets (last updated at v1.2.0). CHANGELOG.md is now sole source of truth for version history.
- **README "v2 roadmap"**: removed "Plugin marketplace packaging" (shipped in v1.4); added "Multi-harness packaging" deferred line.
- **`examples/hello-spec/README.md`**: added a one-line synthetic-demo disclaimer at the bottom (the `spm` package is fictional; the file shapes are real).

## [1.5.0] - 2026-04-21

### Added

- **GitHub Actions CI** (`.github/workflows/test.yml`): runs `bash tests/test-hooks.sh` on push to `master` and on every PR. Matrix: macOS + Ubuntu. Also validates all JSON files (`plugin.json`, `marketplace.json`, `hooks.json`, `settings.json`) parse cleanly.
- **CI status badge in README** (top of file alongside version, license, Claude Code plugin badges).
- **README hero section**: tagline, badge row, value prop, "Who this is for" / "Who this is NOT for" sections, prominent plugin install command. First-screen visible to anyone landing on the repo.
- **Demo project at `examples/hello-spec/`**: small self-contained walkthrough showing real `CLAUDE.md`, `.planning/SPEC.md`, and a README that explains how the kit picks each file up. Demo subject: a Python CLI's `--version` flag.
- **`CONTRIBUTING.md`** at repo root: rejection-first voice (adapted from superpowers v5.0.7 AGENTS.md, same source as v1.3 kit-health). Numbered MUST list before opening a PR. "What we will not accept" enumerates PHILOSOPHY.md's actual rejection criteria with cross-links.

### Notes

- All changes are additive. No breaking changes. No removals.
- No new ADR: every change fits within existing principles. PHILOSOPHY.md unchanged.
- README's component count line updated to "9 agents" (was "8") — tracks the `responding-to-review` agent added in v1.3.
- CI is **descriptive**, not enforcing: PRs that fail CI are flagged but not auto-blocked. Enforcement still lives in the `safety-gate` hook locally.

## [1.4.0] - 2026-04-21

### Added

- **Claude Code plugin packaging**: Kit now installs via `/plugin marketplace add dwarvesf/dwarves-kit` + `/plugin install dwarves-kit@dwarves-marketplace`. No `git clone`, no bash, no `jq` required. Updates via `/plugin update dwarves-kit`.
- **`.claude-plugin/plugin.json`**: Plugin manifest with name, version, description, author, homepage, repository, keywords. Auto-discovers `agents/`, `commands/`, `skills/` directories.
- **`.claude-plugin/marketplace.json`**: Self-hosted marketplace manifest. Single-plugin marketplace named `dwarves-marketplace` pointing at the repo root.
- **`hooks/hooks.json`**: Plugin-format hook registration. Same 12 hooks across 8 event types as the bash install path. Uses `${CLAUDE_PLUGIN_ROOT}` for path-portable script references.
- **README dual install section**: Plugin install presented first as recommended path. Bash install retained as alternative for CI / older Claude Code versions / non-plugin contexts. One-line note about Anthropic official marketplace submission via https://claude.ai/settings/plugins/submit.

### Changed

- **`docs/decisions.md`**: Added ADR-009 documenting the dual-ship deviation from PHILOSOPHY's "Replace, don't deprecate" with explicit rationale and sunset trigger.

### Notes

- This is an additive release. The bash installer (`install.sh`) and root `settings.json` are unchanged. Existing installs continue to work without action.
- **Do not run both install paths on the same machine.** Hooks would register twice. Pick one.
- Plugin install does not configure `statusLine` (not in v1 plugin schema). Use the bash install if you want the statusline HUD.

## [1.3.0] - 2026-04-21

### Added

- **`responding-to-review` agent**: New subagent that responds to code review findings with verify-before-implement, no performative agreement, YAGNI check, and push-back-when-wrong. Wired into `/review-team` Step 5 so the FIX-THEN-SHIP path can dispatch it. Source: superpowers v5.0.7 `skills/receiving-code-review/SKILL.md`, adapted from a Skill (auto-discovered) to a custom subagent (dispatched on demand).
- **`task-verifier` "Extra / unneeded work" check (Section 3b)**: Verifier now explicitly checks whether the worker built features that weren't requested, over-engineered, or added nice-to-haves outside the spec. Distinct from the existing file-scope check. Source: superpowers v5.0.7 `skills/subagent-driven-development/spec-reviewer-prompt.md`.
- **`reviewer` (architecture lens) decomposition + contribution checks**: New bullets for "decomposed for independent testability" and "what this change contributed (don't flag pre-existing file size)". Source: superpowers v5.0.7 `skills/subagent-driven-development/code-quality-reviewer-prompt.md`.
- **`commands/kit-health` rejection-first verdict**: Output template now produces `SHIP / FIX-REQUIRED / REJECT` verdicts with explicit gate rules. New Step 4 "What this kit will reject" section enumerates 10 auto-REJECT conditions grounded in PHILOSOPHY.md. Source framing: superpowers v5.0.7 `AGENTS.md` "What We Will Not Accept".

### Changed

- **`task-verifier` Rules**: Added "Verify by reading code, not by trusting the worker's report" as the first rule. Source: superpowers v5.0.7 spec-reviewer-prompt.
- **`commands/review-team` Step 5**: FIX-THEN-SHIP path now suggests dispatching `responding-to-review` to handle the findings without performative agreement.
- **`CLAUDE.md`**: Added `responding-to-review` to the Subagents inventory.
- **`docs/decisions.md`**: Added ADR-008 covering the superpowers v5.0.7 adoption.

### Fixed

- **`tests/test-hooks.sh`**: Stale assertion `expected 10 event hooks` updated to `12` to match actual settings.json count (drift since v1.2 added SubagentStop and StatusLine entries). Test suite now reports 42/42 instead of 41/42.

## [1.2.0] - 2026-03-30

### Added

- **Verification pipeline**: /execute now runs worker > task-verifier > fix-agent retry loop (max 2) for every task. No task is accepted without verification.
- **8 custom agents**: task-verifier (read-only verification), fix-agent (targeted fixes), reviewer (configurable lens), security-auditor (OWASP audit), research-stack, research-features, research-architecture, research-pitfalls (4 parallel brownfield researchers).
- **/start command**: entry point router that detects project state and suggests next command. Source: CCGS /start.
- **/review-team command**: parallel 3-lens review dispatching security + architecture + test-coverage reviewers simultaneously.
- **session-state-save.sh** (Stop + SubagentStop): persists session state to `.claude/session-state/`, rotates last 10 archives. Fail-open.
- **docs/COLLABORATIVE-DESIGN.md**: shared protocol for structured decision-making (Question > Options > Recommendation > Decision > Record).
- **SubagentStop event** in settings.json for session-state-save.

### Changed

- **/execute**: complete rewrite with verification pipeline, Collaborative Design Protocol integration, codebase-memory-mcp awareness.
- **/ship**: added review gate (checks REVIEW.md verdict), version bump detection, automatic changelog entry generation.
- **/spec**: added 4 parallel research subagents for brownfield projects (Mode A: formal agents, Mode B: inline fallback).
- **/spec-validate**: enhanced Scope Critic with aggressive atomicity check, dependency declaration checking, testability criteria.
- **context-readiness.sh**: v2 upgrade. Reads spec status, counts completed tasks, suggests next command ("detect, don't dictate").
- **install.sh**: added agents install/uninstall, path-scoped rules auto-copy to `.claude/rules/`.
- **PHILOSOPHY.md**: added "Verify before proceeding" and "Verify, then trust" principles. Updated version strategy.
- **rules/*.md**: YAML `paths` changed to multi-line list format.

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
