# Spec: v1.4.0 Claude Code plugin packaging
Generated: 2026-04-21
Status: VALIDATED
Source: Claude Code plugin docs (https://code.claude.com/docs/en/plugins.md, plugin-marketplaces.md, hooks.md)
Note: Previous spec (v1.3 superpowers adoption) preserved in git history at commit 5315b0f.

## Problem

dwarves-kit currently installs via `git clone + bash install.sh`. This is two manual steps and requires a shell. Users discovering the kit on GitHub have no in-Claude-Code install path. Compare: superpowers ships via `/plugin install` and gets one-line install in any Claude Code session.

The Claude Code plugin format (`.claude-plugin/plugin.json`) standardized in mid-2025 closes this gap. Adding plugin packaging to the kit is **additive**: no existing files removed, no breaking changes for current bash-install users.

## Solution

Add 3 new files. Update 1 existing file (README). Bump version. No removals.

| Action | File |
|---|---|
| Create | `.claude-plugin/plugin.json` |
| Create | `hooks/hooks.json` (plugin-format hook registration using `${CLAUDE_PLUGIN_ROOT}`) |
| Create | `.claude-plugin/marketplace.json` (self-hosted marketplace pointing at this repo) |
| Modify | `README.md` (new "Install (plugin, recommended)" section + keep existing bash section as fallback) |
| Bump | `VERSION` 1.3.0 → 1.4.0 (minor: additive feature, no breaking changes) |

Existing `install.sh` and root `settings.json` stay untouched. Both install paths work in v1.4.

## Technical Design

### File: `.claude-plugin/plugin.json`

Required field: `name`. We add `version`, `description`, `author`, `homepage`, `repository`, `keywords` for marketplace discoverability and version pinning. Auto-discovery handles `skills/`, `commands/`, `agents/` directories.

```json
{
  "name": "dwarves-kit",
  "version": "1.4.0",
  "description": "Spec-driven Claude Code workflow with verification pipeline. 12 hooks + 12 commands + 9 agents.",
  "author": { "name": "Dwarves Foundation", "url": "https://dwarves.foundation" },
  "homepage": "https://github.com/dwarvesf/dwarves-kit",
  "repository": "https://github.com/dwarvesf/dwarves-kit",
  "keywords": ["workflow", "spec-driven", "verification", "subagents", "hooks"]
}
```

### File: `hooks/hooks.json`

Same hook registrations as root `settings.json`, but commands use `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh` (path-portable; resolves at install time). 12 hooks register across 8 events (SessionStart, PreToolUse with 2 matchers, PostToolUse with 2 matchers, PreCompact, Stop with 3 hooks, SubagentStop, Notification, PermissionRequest). Note: `statusLine` is not a hook in the plugin schema and stays in root `settings.json` only (the bash install path); the plugin install path inherits the user's existing statusLine config.

### File: `.claude-plugin/marketplace.json`

Lets the repo serve as its own marketplace. Users add it via `/plugin marketplace add dwarvesf/dwarves-kit`, then install via `/plugin install dwarves-kit@dwarves-marketplace`.

```json
{
  "name": "dwarves-marketplace",
  "owner": { "name": "Dwarves Foundation" },
  "plugins": [
    {
      "name": "dwarves-kit",
      "source": ".",
      "description": "Spec-driven Claude Code workflow with verification pipeline."
    }
  ]
}
```

### File: `README.md` Install section rewrite

Two install sections. Plugin path is presented first (recommended). Bash path moved below as fallback for non-Claude-Code-plugin contexts (older installs, CI, project-template propagation). Add a one-line note pointing to Anthropic's official marketplace submission form for users who want broader discovery.

## Task Breakdown

### Phase 1: Plugin packaging (4 tasks, all independent)

- [ ] **TASK-A1: Create `.claude-plugin/plugin.json`**
  - Acceptance criteria:
    - [ ] File exists at `.claude-plugin/plugin.json`
    - [ ] `jq . .claude-plugin/plugin.json` exits 0 (valid JSON)
    - [ ] `name` field equals `"dwarves-kit"`
    - [ ] `version` field equals `"1.4.0"`
    - [ ] `repository` field present and points to dwarvesf org

- [ ] **TASK-A2: Create `hooks/hooks.json`**
  - Acceptance criteria:
    - [ ] File exists at `hooks/hooks.json`
    - [ ] `jq . hooks/hooks.json` exits 0 (valid JSON)
    - [ ] Hook count: 12 hooks total registered (matching root settings.json)
    - [ ] All hook commands use `${CLAUDE_PLUGIN_ROOT}/hooks/` prefix (greppable, no `$HOME/.claude/dwarves-kit` paths)
    - [ ] Same 8 event types covered as root settings.json: SessionStart, PreToolUse, PostToolUse, PreCompact, Stop, SubagentStop, Notification, PermissionRequest
    - [ ] `bash tests/test-hooks.sh` still passes 42/42 (no underlying script change)

- [ ] **TASK-A3: Create `.claude-plugin/marketplace.json`**
  - Acceptance criteria:
    - [ ] File exists at `.claude-plugin/marketplace.json`
    - [ ] `jq . .claude-plugin/marketplace.json` exits 0
    - [ ] `name` field equals `"dwarves-marketplace"`
    - [ ] `plugins[0].name` equals `"dwarves-kit"`
    - [ ] `plugins[0].source` equals `"."` (self-reference; the marketplace lives in the same repo as the plugin)

- [ ] **TASK-A4: README install section rewrite**
  - Acceptance criteria:
    - [ ] New "Install (Claude Code plugin, recommended)" section above the existing bash section
    - [ ] Plugin install command literal in README: `/plugin marketplace add dwarvesf/dwarves-kit`
    - [ ] Plugin install command literal in README: `/plugin install dwarves-kit@dwarves-marketplace`
    - [ ] Bash install section retained, labeled as "alternative" or "legacy"
    - [ ] One-line note about Anthropic official marketplace submission with URL https://claude.ai/settings/plugins/submit
    - [ ] Repo URL `dwarvesf/dwarves-kit` (not the old `tieubao/dwarves-kit`) used everywhere in install commands

### Phase 2: Verify, docs, ship

- [ ] All 4 task acceptance criteria met
- [ ] `bash tests/test-hooks.sh` exit 0 (42/42)
- [ ] `find . -name "*.json" -path "*/.claude-plugin/*" -o -path "*/hooks/*.json" | xargs -I {} jq . {} > /dev/null` exits 0
- [ ] CHANGELOG entry under `[1.4.0]`
- [ ] `docs/decisions.md` ADR-009 documenting the dual-ship deviation from PHILOSOPHY's "Replace, don't deprecate" with rationale + sunset trigger
- [ ] `docs/dependencies.md` unchanged (no new deps)
- [ ] `VERSION` → `1.4.0`
- [ ] Atomic commits: 1 per TASK + 1 docs commit + 1 version bump = 6 commits total
- [ ] `git tag -a v1.4.0 -m "..."`

## Acceptance Criteria (global)

- [ ] All 4 task acceptance criteria met
- [ ] All JSON files valid
- [ ] No existing file deleted, no behavioral change to existing install path
- [ ] tests pass 42/42
- [ ] `install.sh` continues to work (unchanged)
- [ ] Plugin format files are sufficient for `/plugin marketplace add` + `/plugin install` flow per Claude Code docs (cannot be tested locally without a fresh Claude Code session; verified by spec compliance with cited docs)

## Edge Cases

1. **Plugin install + bash install both run on same machine.** Hooks would register twice (once at the plugin location, once at $HOME/.claude/dwarves-kit). Mitigation: README warns users to pick one install path, not both. The kit's own `safety-gate` won't fire twice in practice (Claude Code dedupes by command string), but it's still a config smell.
2. **`statusLine` not in plugin format.** Plugin schema has no statusLine equivalent in v1 of the plugin spec. Plugin-installed users keep whatever statusLine they had in their settings.json. Documented in README that the bash install also configures statusLine; plugin install does not.
3. **Anthropic official marketplace submission.** Form-based, manual. Han submits via https://claude.ai/settings/plugins/submit when ready. Not blocking v1.4 ship; documented in README and ADR-009.
4. **`source: "."` in marketplace.json.** This means "the plugin lives at the repo root". Per docs this is valid for single-plugin marketplaces. If Claude Code rejects the value, fallback: use `"./plugins/dwarves-kit"` and move plugin files into a subfolder. Defer the fix until first install failure surfaces.

## Out of Scope

- Removing `install.sh` and root `settings.json` (user override: keep both for now; sunset trigger documented in ADR-009).
- Multi-harness packaging (Codex/Cursor/Gemini/OpenCode). Defer per PHILOSOPHY: single Han audience.
- Submitting to Anthropic's official marketplace (Han does manually via web form).
- GitHub Actions CI workflow (separate v1.4 line item; can be a follow-up).
- Migration script that auto-converts an existing bash install to a plugin install (low value: users uninstall + reinstall in 30 seconds).
- Plugin update notifications (handled by Claude Code's plugin runtime, not us).

## Decision Log

- **DEC-001 (override)**: Keep `install.sh` and root `settings.json` rather than replace per PHILOSOPHY's "Replace, don't deprecate".
  - **Rationale**: User explicit instruction (2026-04-21). Avoids forcing existing contractors to re-install on v1.4 upgrade.
  - **Sunset trigger**: Remove in v2.0 OR after 30 days of zero bash-install usage signal in `~/.claude/dwarves-kit/logs/install.log` (not yet instrumented; will require a tracker hook in a future task), whichever comes first.
  - **Documented in**: ADR-009.

- **DEC-002**: Self-hosted marketplace (single-plugin) at the kit repo, not a separate marketplace repo.
  - **Rationale**: Single plugin, single repo. Splitting the marketplace into its own repo (like superpowers does with `obra/superpowers-marketplace`) only pays off when the marketplace hosts 2+ plugins. We have 1.
  - **Rejected alternative**: Separate `dwarvesf/dwarves-marketplace` repo. Adds an empty repo for no current value.

- **DEC-003**: Use `${CLAUDE_PLUGIN_ROOT}` (not `$HOME/.claude/dwarves-kit/`) in `hooks/hooks.json`.
  - **Rationale**: Documented Claude Code plugin convention. Path-portable; resolves at install time. Citation: https://code.claude.com/docs/en/hooks.md.

- **DEC-004**: Bump to v1.4.0, not v2.0.0.
  - **Rationale**: User explicit instruction. Additive change (no breaking removal). Conventional commits: `feat(plugin): ...` is minor, not major.

- **DEC-005**: `statusLine` stays out of `hooks/hooks.json` (not a plugin schema field).
  - **Rationale**: Per Claude Code plugin docs, hooks.json schema covers hook events only. statusLine config remains in root settings.json (bash install) and is not auto-applied by the plugin install. README documents this.

## Source citations

- https://code.claude.com/docs/en/plugins.md
- https://code.claude.com/docs/en/plugin-marketplaces.md
- https://code.claude.com/docs/en/hooks.md (`${CLAUDE_PLUGIN_ROOT}` documented here)
- Reference implementation: obra/superpowers v5.0.7 (single-plugin self-hosted marketplace pattern)
