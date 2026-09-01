# ADR-0009: Claude Code plugin packaging (additive, dual-ship with bash installer)

## Status: accepted (v1.4)

## Context
Until v1.3, dwarves-kit installed only via `git clone + bash install.sh`. This is a two-step manual install requiring a shell, jq, and git. By contrast, Claude-Code-native plugins install with a single in-session command (`/plugin install ...`) and reach a much wider audience automatically.

The plugin format standardized in mid-2025 uses `.claude-plugin/plugin.json` + `hooks/hooks.json` + an optional `.claude-plugin/marketplace.json`. Hook script paths reference `${CLAUDE_PLUGIN_ROOT}` for install-location portability.

## Decision
Add full plugin packaging in v1.4.0 as an **additive** change. Both install paths work simultaneously:

- **Recommended**: `/plugin marketplace add dwarvesf/dwarves-kit` + `/plugin install dwarves-kit@dwarves-marketplace`
- **Alternative (legacy)**: `bash install.sh`

The repo serves as its own single-plugin marketplace (`dwarves-marketplace`), so users can install without waiting for Anthropic's official marketplace acceptance.

## Deviation from PHILOSOPHY
PHILOSOPHY.md states "Replace, don't deprecate. When a new implementation replaces an old one, remove the old one entirely." This decision deliberately deviates by keeping `install.sh` and root `settings.json` alongside the new plugin manifests.

**Rationale for deviation** (per maintainer instruction 2026-04-21):
- Existing contractor installs would be broken by an immediate cutover.
- `install.sh` configures `statusLine`, which the v1 plugin schema does not support. The bash installer is the only way to get the HUD until the plugin schema gains a statusLine field.
- Bash install remains useful for CI environments and project templates where `/plugin install` is unavailable.

**Sunset trigger**: Remove `install.sh` and root `settings.json` in v2.0 OR when Claude Code's plugin schema gains `statusLine` support AND ~/.claude/dwarves-kit/logs/install.log shows zero bash-install invocations for 30 days, whichever comes first. ADR to be filed at sunset.

## Alternatives considered
- **Replace cleanly (PHILOSOPHY-pure)**: Delete `install.sh` and root `settings.json`, ship as plugin-only. Rejected per maintainer instruction; would break existing installs and lose the statusline.
- **Multi-harness packaging** (Codex/Cursor/Gemini/OpenCode like obra/superpowers): Defer per PHILOSOPHY's "external tools are dependencies, not features" plus single Han audience. Build when there's real cross-harness demand.
- **Submit to Anthropic's `claude-plugins-official` marketplace**: Requires manual web-form submission; not blocking. Documented in README; maintainer submits when ready.
- **Separate marketplace repo** (`dwarvesf/dwarves-marketplace` like superpowers' pattern): Splitting the marketplace into its own repo only pays off with 2+ plugins. We have 1.

## Consequences
- New audience reachable: anyone running Claude Code can install in one command.
- Hooks must use `${CLAUDE_PLUGIN_ROOT}` in `hooks/hooks.json` (different from absolute paths in root `settings.json`). Two hook registration files to keep in sync until sunset; sunset trigger above forces eventual cleanup.
- README has two install paths. Users must pick one (running both registers hooks twice).
- `statusLine` discrepancy documented; plugin install users miss the HUD.
- File budget: +3 files (`plugin.json`, `marketplace.json`, `hooks.json`). Each justified per `every file must justify its existence`: each is required by the plugin distribution model.
- Source citation: https://code.claude.com/docs/en/plugins.md, plugin-marketplaces.md, hooks.md. Reference implementation: obra/superpowers v5.0.7.
