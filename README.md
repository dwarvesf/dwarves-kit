# dwarves-kit

> A closed-loop Claude Code workflow: you set the goal and the gates, agents loop until the verifier passes. Worker → verifier → fix-agent retry, by default.

[![CI](https://github.com/dwarvesf/dwarves-kit/actions/workflows/test.yml/badge.svg)](https://github.com/dwarvesf/dwarves-kit/actions/workflows/test.yml)
[![Version](https://img.shields.io/github/v/tag/dwarvesf/dwarves-kit?label=version)](https://github.com/dwarvesf/dwarves-kit/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-blue)](https://code.claude.com)

Agent workflows are shifting from `prompt -> output` to `goal -> loop -> evaluate -> improve -> result`. dwarves-kit is the **closed** kind of that loop: you set the goal and the gates up front, agents iterate inside them. The loop is one spec-driven lifecycle, **think → spec → execute → review → ship → retro**, with a gate at every phase boundary:

```
  goal --> think --> spec --> execute --> review --> ship --> retro --+
            |          |         |           |          |             |
        6 forcing   the spec   worker ->   verdict   ship gate +      |
        questions   is the     verifier -> recorded  push-to-main     |
        (advisory)  contract   fix-agent   (advisory) blocker         |
                               (max 2)                                |
   ^                                                                  |
   +------------------ retro feeds the next cycle --------------------+
```

Every build task runs a verification pipeline (worker → verifier → fix-agent retry), and hooks enforce safety automatically (`rm -rf`, push-to-main, force-push, and secret-file reads are blocked). The worker is also **specialized per task**: when a task needs a role no built-in agent covers (security, migration, a doc writer, ...), the kit synthesizes one on the fly and dispatches it, or `/kit:draft-agent` installs a reusable named agent ([SPEC-089](docs/specs/SPEC-089-dynamic-agent-synthesis.md)).

**You drive it by intent, not by memorizing commands.** Say what you want; the kit reads your intent, runs the right step, and stops only at the real decisions:

```
You: "add a --version flag to the CLI"
Kit: scopes it -> writes the spec -> builds + verifies -> ships,
     pausing only where it needs your call.
```

The `/kit:*` commands below are those same actions named explicitly, for when you prefer to type them. You rarely need to.

It is bash-first (every hook readable in 30 seconds), and every component traces to a proven pattern, no novel inventions. The point of the kit is the handoff: a solo technical lead writes the spec, a contractor runs `/kit:execute` against the *same* spec.

New here? **Install** below, then run **your first cycle**. The full operator reference (every command, hook, and agent, plus troubleshooting) lives in [`MANUAL.md`](MANUAL.md).

## Why a closed loop

An open loop (the agent roams free and judges its own output) is a fast slop machine unless your standard is airtight and your budget is unlimited. The kit takes the closed shape instead: a human designs the path once, agents iterate inside it. What makes the loop trustworthy is that the gates that block are mechanical (bash hooks, tests, read-only verifiers), never the agent grading its own homework. The remaining phase gates advise and route rather than block: detect, don't dictate.

| Open loop | dwarves-kit (closed) |
|-----------|----------------------|
| agent plans its own route | the spec is the contract, written before any build (validated on the full lane) |
| agent grades its own work | hard gates are mechanical: bash hooks, tests, read-only verifiers |
| loops until the budget dies | bounded: fix-agent retries max 2, then escalates to a human |
| one loop size fits all | risk lanes: tiny work skips the ceremony entirely |

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

Requires `jq` (for settings merge) and `git`. Cloning in place is simplest, but `install.sh` also runs from a checkout anywhere. To uninstall: `bash ~/.claude/dwarves-kit/install.sh --uninstall`.

### Pick one (the bash installer is plugin-aware)

The two paths no longer collide. If the plugin is already installed, `install.sh` detects it and does a **compat-only** install: it symlinks the legacy `~/.claude/dwarves-kit/{lib,WORKFLOW.md,AGENTS.md}` paths, so docs that still call `bash ~/.claude/dwarves-kit/lib/<x>.sh` (plain bash, where `${CLAUDE_PLUGIN_ROOT}` is unset) keep resolving, and skips the hook + command registration the plugin already owns. No double-registered hooks. Force the full bash install with `KIT_FORCE_FULL=1 bash install.sh` (e.g. for the `statusLine` HUD, which the v1 plugin schema does not configure).

**Invocation differs by path:** installed as the plugin, commands are namespaced `/kit:<name>` (e.g. `/kit:spec`); via the bash installer they resolve bare `/<name>` (e.g. `/spec`). This README uses the plugin form.

## Your first cycle

After install, open a Claude Code session in your project and run one full lap. A tiny change is the best first try:

1. `/kit:start` orients you and suggests the next step.
2. `/kit:think` and describe the change (e.g. "add a `--version` flag to the CLI"). It throws 6 forcing questions at the idea; answer them.
3. `/kit:spec` writes the contract to `docs/specs/SPEC-NNN-<slug>.md`.
4. `/kit:execute` runs the autonomous build: a worker implements the spec (specialized on-demand per task , a security/migration/etc. role synthesized and injected when the task warrants it, SPEC-089), a verifier checks it against the acceptance criteria, a fix-agent retries fixable failures (max 2).
5. `/kit:review` then `/kit:ship`: review gate, then version bump, changelog, conventional commit, PR.

That is the whole loop. The spec is the unit of handoff: a contractor running `/kit:execute` reads the same `docs/specs/SPEC-NNN-<slug>.md` you wrote. To see the artifact set without running anything, browse [`examples/hello-spec/`](examples/hello-spec/).

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
/kit:review-team    Parallel 3-lens review, confidence-gated + validated findings
/kit:verify         Re-run tests read-only; PASS / FAIL / INCONCLUSIVE
/kit:docs           Update all docs to match code (5 min)
/kit:ship           Review gate, version bump, changelog, commit, PR
/kit:retro          Retrospective (10 min, after shipping)
```

Work is sized by risk lane before it starts (tiny / normal / full / bug, plus a `backfill` lane for reviewing an existing codebase and writing the operating-layer docs without changing behavior). The lanes, the gate at each phase boundary, and the operate-contract the agent follows live in [`AGENTS.md`](AGENTS.md) and [`WORKFLOW.md`](WORKFLOW.md).

## Verification pipeline (/execute)

Every task goes through: worker > task-verifier > fix-agent (if needed). The worker never grades its own work; the verifier is a separate read-only agent.

```
            /kit:execute (orchestrator)
            owns the spec's task list,
            dispatches one task at a time
                       |
                       v
              +----------------+
              | worker         |  implements the task
              +----------------+
                       |
                       v
              +----------------------+
              | task-verifier        |  read-only gate: acceptance
              | (cannot edit code)   |  criteria + tests
              +----------------------+
                 |        |          |
               PASS  FAIL:fixable  FAIL:escalate
                 |        |          |
                 v        v          v
            mark done  +-----------+  stop,
            next task  | fix-agent |  ask the human
                       +-----------+
                            |
                            +--> back to task-verifier
                                 (max 2 retries, then escalate)
```

Within one spec, tasks run sequentially. Across specs, `/kit:dispatch` fans out disjoint `VALIDATED` specs into parallel git worktrees behind a disjointness gate; across sessions, a passive goal registry (`lib/goal-registry.sh`) keeps concurrent same-machine sessions from colliding. The kit deliberately stops short of a DAG scheduler, a coordinating daemon, or cross-machine orchestration. For those, run GSD v2 or Nimbalyst alongside it.

## What it does

<details>
<summary><b>Hooks</b> (17, automatic, event-triggered)</summary>

| Hook | Event | What it does |
|------|-------|-------------|
| safety-gate | PreToolUse(Bash) | Blocks rm -rf (build-artifact allowlist), push to main, force push, DROP TABLE, git reset --hard, kubectl delete |
| secrets-guard | PreToolUse(Read\|Edit\|Bash) | Blocks reads of secret files (.env, ~/.ssh, ~/.aws, .pem); canonicalizes the path first |
| commit-format | PreToolUse(Bash) | Blocks non-conventional / >72-char / spec-ID commit subjects |
| ship-gate | PreToolUse(Bash) | Blocks push/PR without a proof-of-done record + recorded lane gates (ADR-0024 boundary) |
| context-readiness | SessionStart | Detects project + board state (`board:Nq`), suggests the next step intent-first |
| anti-rationalization | Stop | Catches Claude declaring work done prematurely |
| slop-cleaner | Stop | Flags bloated code in recently modified files |
| session-state-save | Stop, SubagentStop | Persists session state, rotates last 10 archives |
| auto-format | PostToolUse(Write\|Edit) | Runs formatter on every file change |
| output-offload | PostToolUse(*) | Offloads a >2k-token tool output to a file + leaves a terse pointer |
| spec-drift-guard | PreToolUse(Write) | Warns when creating files not in the spec |
| pre-compact-backup | PreCompact | Saves structured session snapshot before compaction |
| post-compact-reinject | PostToolUse(compact) | Re-injects critical rules after compaction |
| notification | Notification | Desktop alert when Claude needs input |
| permission-auto-approve | PermissionRequest | Auto-approves read-only operations (pipe-safe) |
| statusline | StatusLine | Shows model, branch, context %, cost, thinking mode |
| codebase-index | SessionStart (opt-in) | Background-indexes the repo into codebase-memory-mcp |

Which hooks BLOCK vs warn vs neither is a declared contract: `docs/architecture.md` "Hook fallback layer" (hard / advisory / convenience, parity-pinned).

</details>

<details>
<summary><b>Commands</b> (27, manual, human-triggered)</summary>

| Command | Phase | What it does |
|---------|-------|-------------|
| /kit:start | Entry | Detect project state, suggest next command |
| /kit:grill | Intake | Universal intake interview: type-shaped questions, one at a time, answers written as they resolve |
| /kit:think | Think | 6 forcing questions to stress-test an idea |
| /kit:design | Design | Opt-in: interactive solution-design beat (one question at a time) before /spec |
| /kit:devs-team | Design | Opt-in: 5-lens parallel critique of the solution (brief or spec), report-only |
| /kit:visual-team | Design | Opt-in: 5-lens parallel critique of a visual/UI design (downstream-facing) |
| /kit:ui-design | Design | Opt-in, downstream: UI brief -> generate (frontend-design) -> critique -> revise loop |
| /kit:assign | Orchestrate | Turn a backlog item (ID-NNN) into a scoped goal draft + route it into the lane |
| /kit:dispatch | Orchestrate | Fire N disjoint VALIDATED specs concurrently, each in its own worktree, behind a disjointness gate; lead-owned merge |
| /kit:mega | Orchestrate | Mirrors the plan-for-mega-goal skill: decompose 3-8 dependent sub-goals, front-load every clarification once, set the per-run merge config, hand off to the bounded loop; ship-layer auto-merge rides the ship-gate via `lib/mega-merge.sh`, never bypasses it |
| /kit:spec | Spec | Generate docs/specs/SPEC-NNN-<slug>.md with 4 parallel research agents |
| /kit:spec-validate | Spec | 5 adversarial reviewers attack the spec (incl. solution-design + extensibility) |
| /kit:test-plan | Spec | Opt-in: coverage matrix from acceptance criteria into the spec's `## Test plan` section |
| /kit:execute | Build | Autonomous: worker > verifier > fix-agent retry loop |
| /kit:next | Build | Lightweight: picks next undone task, loads context, you drive |
| /kit:verify | Verify | Read-only re-run of task-verifier + integration-verifier, no rebuild; verdict PASS / FAIL / INCONCLUSIVE with the claim restated falsifiably |
| /kit:debug | Bug (off-cycle) | Systematic debug loop: root cause before any fix, evidence ledger, 3-fix wall |
| /kit:review | Review | Paranoid single-pass code review |
| /kit:review-team | Review | Parallel 3-lens review (security + architecture + test-coverage); findings confidence-gated, deduped by fingerprint, verdict-driving ones adversarially validated per finding |
| /kit:test-plan-review-team | Verify | 5-lens adversarial critique of the spec's `## Test plan`, bounded revise loop, report-only |
| /kit:adopt | Entry | Retrofit the operate-contract onto an existing repo (AGENTS.md, loader, proof marker, classifiers), idempotently |
| /kit:docs | Docs | Cross-reference diff against all doc files, fix drift |
| /kit:ship | Ship | Review gate, version bump, changelog, commit, PR |
| /kit:retro | Reflect | What worked, what hurt, action items for next cycle |
| /kit:kit-health | Meta | Self-assessment against kit philosophy |
| /kit:absorb | Meta | Maintainer-only: audit upstream sources (Credits drift + seed-rescan) + draft a dated absorption proposal |
| /kit:draft-agent | Meta | Meta-agent agent-builder: generates a subagent (or sub-goal file) from a description and installs it by default (`--draft` to stop at a review draft) |

</details>

<details>
<summary><b>Agents</b> (11, dispatched by commands) and <b>Skill</b> (1, Claude-triggered)</summary>

| Agent | Dispatched by | What it does |
|-------|--------------|-------------|
| task-verifier | /execute | Read-only verification against spec + tests |
| integration-verifier | /execute, /verify | Read-only cross-task wiring + global acceptance check (multi-task specs) |
| fix-agent | /execute | Targeted fixes on FAIL:fixable (max 2 retries) |
| code-reviewer | /review-team | Focused review with configurable lens |
| security-reviewer | /review-team | Deep OWASP-style security audit |
| responding-to-review | /review-team | Verifies review findings, pushes back when wrong, proposes fixes (no performative agreement) |
| doc-verifier | /docs | Read-only check that docs match the live codebase |
| research-stack | /spec | Maps technology stack (brownfield) |
| research-features | /spec | Maps existing features in target area |
| research-architecture | /spec | Maps architecture patterns and conventions |
| research-pitfalls | /spec | Finds landmines before implementation |

| Skill | What it does |
|-------|-------------|
| get-api-docs | Fetches curated API docs via Context Hub before coding |

</details>

## Who this is for

A solo technical lead handing off implementation to contractors. The kit covers the full lifecycle with one shared spec format: the contractor running `/kit:execute` reads the same `docs/specs/SPEC-NNN-<slug>.md` you wrote with `/kit:spec`.

Also for a builder using Claude Code 6-8 hours a day who wants a context-budget HUD, automatic safety guards, session-state persistence across compaction, and slop detection at stop points.

## Who this is NOT for

- **Teams of 10+ with a dedicated DevOps pipeline.** The kit targets one engineer (or one lead + delegated contractors); one lead can still fan out parallel workers (`/kit:dispatch`) and run concurrent same-machine sessions safely. Cross-machine orchestration, 3+ live operators, or goal-ordering chains are out of scope, pair the kit with Nimbalyst or Conductor for that.
- **Anyone who wants a UI.** The kit is bash hooks + markdown commands. Open any file in a text editor; it's all readable.
- **Projects already happy with GSD, gstack, or Trail of Bits' configs as standalone tools.** The kit's value is integration; if format-translation overhead between standalone tools isn't hurting you, don't switch.

## Project structure

<details>
<summary>Directory layout</summary>

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
  agents/                       (11 files) Subagents dispatched by commands
  commands/                     (27 markdown command prompts)
  hooks/                        (14 scripts + hooks.json plugin manifest)
  lib/dispatch-gate.sh          Disjointness gate + drift guard for /kit:dispatch (pure-bash concurrency moat)
  lib/lane-classify.sh          Deterministic task-type -> risk-lane classifier + advisory floor check (used by /kit:assign + /kit:dispatch)
  lib/goal-registry.sh          Cross-session running-goal registry: claim/list/log/release (multi-session moat + monitor)
  lib/goal-drafts.sh            Goal-draft lifecycle: archive shipped drafts to .claude/goals/done/
  lib/lane-telemetry.sh         Read-side lane-effectiveness aggregator over the run ledgers: report + misfires (reviewed at /kit:retro)
  lib/orchestrate.sh            Non-LLM mega-goal driver: one fresh `claude -p` session per sub-goal so no session marathons (SPEC-087); linear + session-per-sub-goal, NOT a DAG scheduler or daemon. `run <dir>` flags: `--dry-run` (plan only), `--step` (pause for the operator between sub-goals), `--stream` (live stream-json tee'd to `.orchestrate/<id>.stream.jsonl`), `--board=roadmap|kanban|both` (event-sourced per-mega-goal kanban derived to `<dir>/BOARD.md` via `lib/backlog.sh`; default detects, ROADMAP stays canonical). Robustness env (advisory): `WATCHDOG_STALL_SECS>0` backgrounds each session + flags it `stalled` after that long with no output (never kills); a dead/incomplete session never advances its box. Emits a `gate-ledger start` per dispatched sub-goal (rid from the goal file's `**Branch:**`) so mega-dispatched runs are tracked in `lane-telemetry`, not `?` (SPEC-101). Gitignore `.orchestrate/` + `BOARD.md` (derived/runtime)
  lib/mega-merge.sh             Ship-layer auto-merge ENFORCEMENT for /kit:mega (ADR-0028 P2/P3): `gate <rid> <lane>` (decision, reuses `lib/gate-ledger.sh check`) + `merge <pr> <rid> <lane> [--execute] [--posture=<val>]` (action; refuses unconditionally on a failing/missing gate, dry-run by default, `MEGA_MERGE_POSTURE` team-review opt-out)
  skills/get-api-docs/          Context Hub integration
  rules/                        Path-scoped coding-standard templates
  examples/hello-spec/          Demo: small CLAUDE.md + SPEC.md walkthrough
  tests/test-hooks.sh           Hook behavior assertions
  tests/test-meta.sh            Structural integrity (manifests, frontmatter, cross-links)
  docs/specs/SPEC-NNN-<slug>.md  Specs, tracked in place via Status header (DRAFT/VALIDATED/SHIPPED); hooks pick the active one by git branch
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

For the full file listing including individual agent/hook/command names, run `git ls-files` or browse the repo on GitHub.

</details>

## Reference

**Debug mode.** Set `DWARVES_KIT_DEBUG=1` and every hook logs its decisions to stderr. Useful when a hook misbehaves or you want to understand why something was blocked or approved.

**Hook logs.** Hooks that make enforcement decisions append to `~/.claude/dwarves-kit/logs/` (`anti-rationalization.log`, `safety-gate.log`, `spec-drift-guard.log`, `slop-cleaner.log`). These build the eval corpus for future optimization.

**Testing.** `bash tests/test-hooks.sh` covers hook behavior (safety-gate blocking, anti-rationalization patterns, permission-auto-approve pipe-injection protection); `bash tests/test-meta.sh` covers structural integrity (manifests, frontmatter, cross-links).

**External dependencies** (install alongside, not bundled):

- [Context Hub](https://github.com/andrewyng/context-hub) - `npm install -g @aisuite/chub`
- [Context7](https://github.com/upstash/context7) - MCP server for library docs
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) - AST-level codebase indexing

**Codebase index (opt-in).** If `codebase-memory-mcp` is installed, the
`codebase-index.sh` SessionStart hook keeps the current repo's structural index fresh
in the background (built on the first session in a repo, incremental refresh after),
so `/kit:spec` and `/kit:execute` query the index (`search_code`, `search_graph`,
`get_architecture`, `trace_path`) instead of grepping, cutting orientation cost. With
the tool absent the hook no-ops and the kit greps exactly as before, nothing to
configure and nothing breaks. Enable: put the binary on `PATH`, run
`claude mcp add --scope user codebase-memory -- codebase-memory-mcp`, then re-run
`install.sh`.

## v2 roadmap (not yet built)

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns)
- /qa command with headless browser testing (requires Playwright)
- Intra-spec parallel task dispatch in /execute (cross-goal fan-out across specs already ships as /kit:dispatch; this is the deferred intra-spec case)
- SessionEnd hook for automatic knowledge capture
- Multi-harness packaging (Codex / Cursor / Gemini / OpenCode), deferred until real demand

## Changelog

See [CHANGELOG.md](CHANGELOG.md). It's the source of truth; the README does not duplicate it.

## Credits

Patterns extracted from:

- [GSD v1 / get-shit-done](https://github.com/gsd-build/get-shit-done) - spec generation, the original planning-dir convention (since unified onto docs/specs/), 4 parallel researchers. Distinct from GSD v2 ([gsd-build/gsd-2](https://github.com/gsd-build/gsd-2), npm `gsd-pi`), a separate standalone agent on the Pi SDK referenced as an external execution runtime, not a pattern source
- [gstack](https://github.com/garrytan/gstack) - /office-hours, /review, /ship patterns; the /kit:ui-design loop shapes (brief schema, injection-wrap, accumulated-feedback)
- [frontend-design](https://github.com/anthropics/skills) - the external UI generator /kit:ui-design delegates to; its aesthetic-direction brief shape
- [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) - /kit:ui-design brief sub-shapes (token ladder, states matrix, a11y bars, voice); generator + tooling rejected per bash-over-binaries
- [Trail of Bits](https://github.com/trailofbits/claude-code-config) - hook implementations, code quality rules, statusline pattern
- [ClaudeKit](https://github.com/mrgoonie/claudekit-skills) - validation gate, adversarial review, session-state pattern
- [Context Hub](https://github.com/andrewyng/context-hub) - API docs skill
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - HUD/statusline, slop-cleaner pattern
- [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) - /start router, path-scoped rules, Collaborative Design Protocol
- [Smart Ralph](https://github.com/smart-ralph) - fix-agent retry pattern (fail-fix-re-verify loop)
- [mattpocock/skills grill-with-docs](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md) - /kit:grill mechanics: one-question-at-a-time with recommended answers, glossary/ADR write-as-you-go, the 3-criteria ADR bar, contradiction-first interviewing
- [repository-harness](https://github.com/hoangnb24/repository-harness) - the FEATURE_INTAKE flag-count lane-classification model (A3: hard-gate + soft-count + auditable `explain`), the `@AGENTS.md` CLAUDE.md import shim (A1), adopt `--dry-run`/`--refresh` modes (A2), and the decision-capture-at-reflect flow (A4-lite, advisory). The enforcing dual of our enforcing/CC-only kit; absorbed 2026-06-10, see [docs/absorption/2026-06-10-repository-harness.md](docs/absorption/2026-06-10-repository-harness.md)

## License

MIT
