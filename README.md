# dwarves-kit

> Spec-driven Claude Code workflow with a verification pipeline. Worker → verifier → fix-agent retry, by default.

[![CI](https://github.com/dwarvesf/dwarves-kit/actions/workflows/test.yml/badge.svg)](https://github.com/dwarvesf/dwarves-kit/actions/workflows/test.yml)
[![Version](https://img.shields.io/github/v/tag/dwarvesf/dwarves-kit?label=version)](https://github.com/dwarvesf/dwarves-kit/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-blue)](https://code.claude.com)

Hooks, slash commands, subagents, and a skill. Every component traces to a proven pattern (no novel inventions). Bash-first hooks (every script readable in 30 seconds). Hook-enforced safety (`rm -rf`, push-to-main, force-push, secret-file reads blocked).

Install in any Claude Code session:

```
/plugin marketplace add dwarvesf/dwarves-kit
/plugin install kit@dwarves-marketplace
```

## Who this is for

A solo technical lead handing off implementation to contractors. The kit covers the full lifecycle (think → spec → execute → review → ship → retro) with one shared spec format. The contractor running `/kit:execute` reads the same `docs/specs/SPEC-NNN-<slug>.md` you wrote with `/kit:spec`.

Also for: a builder using Claude Code 6-8 hours/day who wants a context-budget HUD, automatic safety guards, session-state persistence across compaction, and slop detection at stop points.

See `examples/hello-spec/` for a small, self-contained walkthrough of the artifacts the kit produces. The end-to-end workflow an agent follows (phases, risk-tier lanes, and the gate at each boundary) is the [`WORKFLOW.md`](WORKFLOW.md) contract.

## Who this is NOT for

- Teams of 10+ with a dedicated DevOps pipeline. The kit is for one engineer (or one engineer + delegated contractors). One lead session may fan out N isolated worktree workers over disjoint specs (`/kit:dispatch`, ADR-0019), and one operator may run N concurrent same-machine sessions over disjoint goals coordinated by a passive running-goal registry (`lib/goal-registry.sh`, ADR-0022). Multi-session orchestration across machines, by 3+ live operators, or with goal-ordering chains is L5 territory (Nimbalyst, Conductor), install those alongside, not instead.
- Anyone who wants a UI. The kit is bash hooks + markdown commands. Open any file in a text editor; it's all readable.
- Projects already happily using GSD, gstack, or Trail of Bits' configs as standalone tools. The kit's value is integration; if format-translation overhead between standalone tools isn't actually hurting you, don't switch.

## What it does

**Hooks (automatic, event-triggered):**

| Hook | Event | What it does |
|------|-------|-------------|
| safety-gate | PreToolUse(Bash) | Blocks rm -rf (build-artifact allowlist), push to main, force push, DROP TABLE, git reset --hard, kubectl delete |
| secrets-guard | PreToolUse(Read\|Edit\|Bash) | Blocks reads of secret files (.env, ~/.ssh, ~/.aws, .pem); canonicalizes the path first |
| commit-format | PreToolUse(Bash) | Blocks non-conventional / >72-char / spec-ID commit subjects |
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
| /kit:start | Entry | Detect project state, suggest next command |
| /kit:think | Think | 6 forcing questions to stress-test an idea |
| /kit:design | Design | Opt-in: interactive solution-design beat (one question at a time) before /spec |
| /kit:devs-team | Design | Opt-in: 5-lens parallel critique of the solution (brief or spec), report-only |
| /kit:visual-team | Design | Opt-in: 5-lens parallel critique of a visual/UI design (downstream-facing) |
| /kit:ui-design | Design | Opt-in, downstream: UI brief -> generate (frontend-design) -> critique -> revise loop |
| /kit:assign | Orchestrate | Turn a backlog item (ID-NNN) into a scoped goal draft + route it into the lane |
| /kit:dispatch | Orchestrate | Fire N disjoint VALIDATED specs concurrently, each in its own worktree, behind a disjointness gate; lead-owned merge (ADR-0019) |
| /kit:spec | Spec | Generate docs/specs/SPEC-NNN-<slug>.md with 4 parallel research agents |
| /kit:spec-validate | Spec | 5 adversarial reviewers attack the spec (incl. solution-design + extensibility) |
| /kit:test-plan | Spec | Opt-in: coverage matrix from acceptance criteria into the spec's `## Test plan` section |
| /kit:execute | Build | Autonomous: worker > verifier > fix-agent retry loop |
| /kit:next | Build | Lightweight: picks next undone task, loads context, you drive |
| /kit:verify | Verify | Read-only re-run of task-verifier + integration-checker on the active spec, no rebuild |
| /kit:debug | Bug (off-cycle) | Systematic debug loop: root cause before any fix, evidence ledger, 3-fix wall |
| /kit:review | Review | Paranoid single-pass code review |
| /kit:review-team | Review | Parallel 3-lens review (security + architecture + test-coverage) |
| /kit:docs | Docs | Cross-reference diff against all doc files, fix drift |
| /kit:ship | Ship | Review gate, version bump, changelog, commit, PR |
| /kit:retro | Reflect | What worked, what hurt, action items for next cycle |
| /kit:kit-health | Meta | Self-assessment against kit philosophy |
| /kit:absorb | Meta | Maintainer-only: audit upstream sources (Credits drift + seed-rescan) + draft a dated absorption proposal |

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
/plugin install kit@dwarves-marketplace
```

That's it. Hooks, commands, agents, and the skill all install automatically. No bash, no `jq`, no symlinks. Updates via `/plugin update kit`.

To get the kit listed on Anthropic's official marketplace (`claude-plugins-official`), submit it via [claude.ai/settings/plugins/submit](https://claude.ai/settings/plugins/submit). One-time manual step; not blocking the self-hosted install above.

### Option 2: Bash installer (alternative)

For environments without Claude Code's plugin system (CI, project templates, older Claude Code versions):

```bash
git clone https://github.com/dwarvesf/dwarves-kit.git ~/.claude/dwarves-kit
cd ~/.claude/dwarves-kit && bash install.sh
```

Requires: `jq` (for settings merge), `git`.

Cloning in place (above) is simplest, but `install.sh` also runs from a checkout anywhere (a dev clone, CI, a template dir): it links each hook script into `~/.claude/dwarves-kit/hooks/` so the paths in `settings.json` resolve, and detects the in-place layout to avoid relinking.

To uninstall:

```bash
bash ~/.claude/dwarves-kit/install.sh --uninstall
```

### Pick one

Don't run both install paths on the same machine -- hooks would register twice. The plugin install does not configure `statusLine` (not in the v1 plugin schema); use the bash install if you want the statusline HUD. This split is documented in ADR-009.

**Invocation differs by path:** installed as the plugin, commands are namespaced `/kit:<name>` (e.g. `/kit:spec`); via the bash installer they resolve bare `/<name>` (e.g. `/spec`). The command tables above use the plugin form.

## Quickstart: your first cycle

After install, open a Claude Code session in your project and run one full lap. A tiny change is the best first try:

1. `/kit:start` orients you and suggests the next step.
2. `/kit:think` and describe the change (e.g. "add a `--version` flag to the CLI"). It throws 6 forcing questions at the idea; answer them.
3. `/kit:spec` writes the contract to `docs/specs/SPEC-NNN-<slug>.md`.
4. `/kit:execute` runs the autonomous build: a worker implements the spec, a verifier checks it against the acceptance criteria, a fix-agent retries fixable failures (max 2).
5. `/kit:review` then `/kit:ship`: review gate, then version bump, changelog, conventional commit, PR.

That is the whole loop: **think → spec → execute → review → ship**. The spec is the unit of handoff: a contractor running `/kit:execute` reads the same `docs/specs/SPEC-NNN-<slug>.md` you wrote. To see the artifact set without running anything, browse [`examples/hello-spec/`](examples/hello-spec/). The kit's own `docs/` folder is its design history; you do not need it to use the kit (see [`docs/README.md`](docs/README.md)).

## Workflow

```
/kit:start          Detect state, suggest next command (entry point)
/kit:think          Challenge the idea (5 min)
/kit:design         Opt-in: shape the solution with you before /spec
/kit:spec           Generate the spec + 4 parallel researchers (15-30 min)
/kit:spec-validate  Stress-test the spec (10 min)
                     [hand off to contractor]
/kit:execute        Autonomous: worker > verifier > fix-agent retry loop
  or
/kit:next           Manual: pick next task, load context, you drive
                     [hooks enforce during build]
                     [statusline shows context budget]
                     [session-state-save persists progress on every stop]
                     [slop-cleaner flags bloat at stop points]
/kit:review         Single-pass review (10 min)
/kit:review-team    Parallel 3-lens review (security + arch + tests)
/kit:verify         Re-run the tests read-only, no rebuild (on demand)
/kit:docs           Update all docs to match code (5 min)
/kit:ship           Review gate, version bump, changelog, commit, PR
/kit:retro          Retrospective (10 min, after shipping)
```

Work is sized by risk lane before it starts (tiny / normal / full / bug, plus a `backfill` lane for brownfield: review an existing codebase and write the operating-layer docs without changing app behavior). The lanes, the gate at each phase boundary, and the operate-contract the agent follows live in [`AGENTS.md`](AGENTS.md) and [`WORKFLOW.md`](WORKFLOW.md).

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

Within one spec, tasks execute sequentially (`/kit:execute` is not parallelized). **Across** independent specs, `/kit:dispatch` fans out N disjoint `VALIDATED` specs concurrently, each in its own git worktree behind a disjointness gate + drift guard, with lead-owned convergence and human-gated merge (ADR-0019). **Across** independent *sessions*, one operator can open several Claude sessions on one machine (one goal each) and a passive running-goal registry (`lib/goal-registry.sh`, ADR-0022) keeps them from colliding: each session claims its goal, an overlapping claim is refused, and `bash lib/goal-registry.sh list` (surfaced in `/kit:start`) is the cross-session monitor. What the kit deliberately does NOT do is a DAG / wave scheduler / crash-recovery runtime, a coordinating daemon, or coordination across machines / 3+ live operators / goal-ordering chains: for those use GSD v2 (the standalone [gsd-build/gsd-2](https://github.com/gsd-build/gsd-2) agent, npm `gsd-pi`, a separate Pi-SDK runtime, not a newer version of the GSD plugin below) or Nimbalyst / Claude Code's experimental Agent Teams, alongside the kit.

## External dependencies (install alongside, not included)

These tools complement the kit but are installed separately:

- [Context Hub](https://github.com/andrewyng/context-hub) - `npm install -g @aisuite/chub`
- [Context7](https://github.com/upstash/context7) - MCP server for library docs
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - AST-level codebase indexing

## Project structure

```
dwarves-kit/
  tool.toml                     Kit metadata (name, version, language=bash, deps)
  AGENTS.md                     Tool-agnostic operate-contract front door (any runtime reads it first)
  WORKFLOW.md                   The cycle, the risk-tier lanes, the gates, and the flow/loop reference (ASCII diagrams)
  MANUAL.md                     Operator reference: commands, hooks, agents, natural-language scenarios, troubleshooting
  README.md / CONTRIBUTING.md / CHANGELOG.md / VERSION / LICENSE
  CLAUDE.md                     Project template; the Claude-Code layer on top of AGENTS.md
  install.sh / settings.json    Bash install path
  .claude-plugin/               Plugin install path (plugin.json, marketplace.json)
  .github/workflows/test.yml    CI: macOS + Ubuntu test matrix
  agents/                       (9 files) Subagents dispatched by commands
  commands/                     (15 markdown command prompts)
  hooks/                        (12 scripts + hooks.json plugin manifest)
  lib/dispatch-gate.sh          Disjointness gate + drift guard for /kit:dispatch (pure-bash concurrency moat)
  lib/lane-classify.sh          Deterministic task-type -> risk-lane classifier (used by /kit:assign + /kit:dispatch)
  lib/goal-registry.sh          Cross-session running-goal registry: claim/list/log/release (multi-session moat + monitor, ADR-0022)
  lib/goal-drafts.sh            Goal-draft lifecycle: archive shipped drafts to .claude/goals/done/ (ADR-0023)
  skills/get-api-docs/          Context Hub integration
  rules/                        Path-scoped coding-standard templates
  examples/hello-spec/          Demo: small CLAUDE.md + SPEC.md walkthrough
  tests/test-hooks.sh           Hook behavior assertions
  tests/test-meta.sh            Structural integrity (manifests, frontmatter, cross-links)
  docs/specs/SPEC-NNN-<slug>.md  Specs, tracked in place via Status header (DRAFT/VALIDATED/SHIPPED); hooks pick the active one by git branch (SPEC-005)
  docs/                         The kit's design record (not needed to USE the kit; see docs/README.md)
    README.md                   Map of docs/: what each file is, and that you can skip it to use the kit
    PHILOSOPHY.md               Design principles, target user, rejection list
    architecture.md             Components, data flow, the SDLC state machine, Collaborative Design Protocol, deps
    decisions/                  One ADR per file (NNNN-<slug>.md); supersession recorded in the Status line
    specs/                      Specs (SPEC-NNN-<slug>.md); also the live spec store the hooks detect
    retro/                      Per-cycle retrospectives (output of /kit:retro)
    research/                   Dated deep-scans that fed specific specs
  _meta/BACKLOG.md              Phased task backlog
```

For the full file listing including individual agent/hook/command names, run `git ls-files` or browse the repo on GitHub. The previous embedded tree was a drift surface that lost sync with reality across 5 releases.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). It's the source of truth; the README does not duplicate it.

## v2 roadmap (not yet built)

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns)
- /qa command with headless browser testing (requires Playwright)
- Intra-spec parallel task dispatch in /execute (cross-goal fan-out across specs already shipped as /kit:dispatch, ADR-0019; this is the deferred intra-spec case)
- SessionEnd hook for automatic knowledge capture
- Multi-harness packaging (Codex / Cursor / Gemini / OpenCode) -- defer until real demand

## Credits

Patterns extracted from:
- [GSD v1 / get-shit-done](https://github.com/gsd-build/get-shit-done) - the Claude Code plugin (skills/agents/hooks): spec generation, the original planning-dir convention (since unified onto docs/specs/, ADR-0010), 4 parallel researchers. Distinct from GSD v2 ([gsd-build/gsd-2](https://github.com/gsd-build/gsd-2), npm `gsd-pi`), a separate standalone agent on the Pi SDK, referenced elsewhere as an external execution runtime, not a pattern source
- [gstack](https://github.com/garrytan/gstack) - /office-hours, /review, /ship patterns; the /kit:ui-design loop shapes (brief schema, injection-wrap, accumulated-feedback)
- [frontend-design](https://github.com/anthropics/skills) - the external UI generator /kit:ui-design delegates to; its aesthetic-direction brief shape
- [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) - /kit:ui-design brief sub-shapes (token ladder, states matrix, a11y bars, voice); generator + tooling rejected per bash-over-binaries
- [Trail of Bits](https://github.com/trailofbits/claude-code-config) - hook implementations, code quality rules, statusline pattern
- [ClaudeKit](https://github.com/mrgoonie/claudekit-skills) - validation gate, adversarial review, session-state pattern
- [Context Hub](https://github.com/andrewyng/context-hub) - API docs skill
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - HUD/statusline, slop-cleaner pattern
- [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) - /start router, path-scoped rules, Collaborative Design Protocol
- [Smart Ralph](https://github.com/smart-ralph) - fix-agent retry pattern (fail-fix-re-verify loop)

## License

MIT
