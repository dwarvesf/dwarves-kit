---
title: Standalone-yet-composable packaging in coding-agent frameworks (July 2026 refresh)
date: 2026-07-25
purpose: >
  Prior-art refresh for the standalone-first packaging doctrine (board ID-396,
  pilot ID-395 visual proof). How spec-kit, BMAD, agent-os v3, superpowers,
  claude-flow/Ruflo, the CC Skills/MCP/Plugin ladder, OpenSpec, Taskmaster and
  Conductor package capabilities as standalone tools that also compose, what
  users complain about, and the ranked pickup/avoid lists. Produced by a
  dispatched research subagent 2026-07-25; sibling of the 2026-05-20
  enforcement-patterns survey.
status: active
---

# Standalone-yet-composable packaging in coding-agent frameworks (July 2026)

Companion assessment: ops-toolkit `research/2026-07-24-workflow-pattern-and-assessment.md`
(Part 4). Consuming rows: ID-396 (doctrine), ID-395 (visual-proof pilot).

## (a) Per-project findings

### 1. github/spec-kit
CLI (`specify-cli`, uv/pipx) that renders per-agent artifacts: slash-command prompt files by default, or native agent **skills** with `--integration-options="--skills"`. Individual commands (`/speckit.specify` alone, etc.) are independently usable. Composition layer: **presets** (customize existing workflow) and **extensions** (add new commands) resolve through a 4-tier override stack (`project overrides > presets > extensions > core defaults`), removable non-destructively. **Bundles** (`bundle.yml`) package curated preset+extension sets, installed/removed atomically, dependency-aware. 30+ agent integrations, 70+ community extensions, 111k stars.

Complaints: rigid 6-step gate (constitution -> specify -> clarify -> plan -> tasks -> implement) forced even for small changes; a Scott Logic review reported "a sea of markdown," a 406-line duplicative research doc, and being "~10x faster" with plain prompting; reinvents waterfall; no path from spec back to debugging.

Sources: [github/spec-kit](https://github.com/github/spec-kit) · [spec-kit issues](https://github.com/github/spec-kit/issues) · [Discussion #1784 "illusion of work"](https://github.com/github/spec-kit/discussions/1784) · [Discussion #1686](https://github.com/github/spec-kit/discussions/1686)

### 2. BMAD-METHOD
Unit = **module** (BMM core + specialized modules like Test Architect, Game Dev Studio) containing agents/workflows/templates; **expansion packs** extend it to non-software domains. Distributed via npm (`npx bmad-method install`), modules selectable at/after install, `--set module.key=value` config overrides, registry-like `--list-options`. Not cleanly standalone: packs assume the BMAD core orchestrator + persona-handoff runtime is present; installation model is init-then-select, not pick-one-file-and-go.

Complaints: steep learning curve (~2 months to master vs "a day or two" for spec-kit), 6-7 agent personas + YAML config + branching workflow; own maintainers acknowledge a v6 "design hole" (assumes technical competence users don't have); issue #2003 catalogs structural gaps/contradictions.

Sources: [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) · [expansion-packs](https://github.com/bmad-code-org/BMAD-METHOD/tree/main/expansion-packs) · [Issue #2003](https://github.com/bmad-code-org/BMAD-METHOD/issues/2003) · [Issue #446](https://github.com/bmad-code-org/BMAD-METHOD/issues/446)

### 3. agent-os (buildermethods)
**v3 is the most relevant exemplar for the standalone-first question.** Unit = markdown **standards files** (`agent-os/` dir) + a small command layer. v2 tried to own spec-writing, task breakdown, *and* implementation orchestration; **v3 explicitly retired the orchestration/implementation phases and deferred to the host agent's native Plan Mode**, keeping only what it does uniquely well: discover/inject/index standards. `/inject-standards` bakes standards into subagents, Claude Skills, or any prompt. For Cursor/Windsurf (no command layer), users just reference the `agent-os/` files directly: the standalone path is literally "read the markdown." Free/open, install-script distribution.

Complaints: little documented in current v3 discourse, because the redesign IS the answer to the complaint: "don't rebuild what the frontier model already does."

Sources: [agent-os](https://github.com/buildermethods/agent-os) · [buildermethods.com/agent-os](https://buildermethods.com/agent-os) · [Discussion #310 "v3, leaner and more aligned"](https://github.com/buildermethods/agent-os/discussions/310) · [What's new in v3](https://buildermethods.com/agent-os/migration)

### 4. superpowers (obra)
Unit = **skill** (`SKILL.md`, one file, standalone-readable). Discovery/composition is **implicit**: skills self-describe and the agent is instructed to check for relevant skills before any task ("mandatory workflows, not suggestions"), no explicit registry, no skill-to-skill references. Distribution is **per-harness**: separate plugin-marketplace installs for Claude Code, Codex, Cursor, Kimi, plus git-clone and npm paths: "if you use more than one [harness], install Superpowers separately for each one."

Complaints: top complaint is "bloated," not "wrong": users pay token cost for process on models that already plan competently; full clarify -> plan -> TDD -> verify cycle runs even for tiny tasks; in long sessions Claude "forgets" it has the skills and starts skipping steps; general 2026 discourse on "context rot" from skill files grown too large/dense.

Sources: [obra/superpowers](https://github.com/obra/superpowers) · [obra/superpowers-marketplace](https://github.com/obra/superpowers-marketplace) · [mcp.directory review](https://mcp.directory/blog/superpowers-skill-worth-it-2026) · [mindstudio.ai context rot](https://www.mindstudio.ai/blog/context-rot-claude-code-skills-bloated-files)

### 5. claude-flow / Ruflo (ruvnet)
SPARC methodology packaged into a swarm orchestrator; rewritten from claude-flow into Rust as **Ruflo** with 300+ MCP tools, hive-mind swarms, persistent memory. **The cautionary tale, not a model to imitate.** A public audit found only 3 of the entire tool surface provide real value; agent spawn, task execution, swarm coordination, hive-mind consensus, WASM agents, and neural training are stubs, unwired state records, or cosmetic token-burning output. Beginners report 15-agent swarms that "run" and consume zero tokens; three separate uncoordinated agent-management implementations; three websocket stacks with auth bugs.

Complaints: "Nothing is working, this codebase is so highly cursed I don't even know where to start" (issue #1425); "paradox of choice and confusion as a beginner" (#1196); Claude sometimes refuses to use the framework at all (#1476).

Sources: [ruvnet/ruflo](https://github.com/ruvnet/ruflo) · [Issue #1425](https://github.com/ruvnet/ruflo/issues/1425) · [Issue #1196](https://github.com/ruvnet/ruflo/issues/1196) · [Audit gist: "99% theater"](https://gist.github.com/roman-rr/ed603b676af019b8740423d2bb8e4bf6)

### 6. Claude Code plugins/marketplaces + Skills (the native CC packaging ladder)
Three distinct layers, not competitors: **Skill** = a procedural-knowledge unit (30-50 tokens, loaded on-demand only when relevant), the natural "standalone capability" unit. **MCP server** = an external tool connection, loaded up-front every session (can cost 50k+ tokens), so N co-installed MCP servers cost N servers' worth of context whether used or not. **Plugin** = an *optional* distribution bundle that can package skills+hooks+MCP configs+subagents+slash-commands+LSP defs into one installable unit, explicitly "not a required wrapper": every piece a plugin bundles can also be added directly. Marketplace mechanics: `/plugin marketplace add` then `/plugin install <name>@<marketplace>`. As of July 2026: 425 plugins / 2,810 skills / 200 agents across marketplaces (tonsofskills.com, obra's, Anthropic's official). Skills shipped Oct 2025, Plugins Oct 2025 (~9-10 months old at research time).

Sources: [buildtolaunch: MCP vs Plugins vs Skills](https://buildtolaunch.substack.com/p/claude-code-mcp-vs-plugins-vs-skills) · [claudefa.st plugin distribution](https://claudefa.st/blog/tools/mcp-extensions/plugins-distribution) · [jeremylongshore/claude-code-plugins-plus-skills](https://github.com/jeremylongshore/claude-code-plugins-plus-skills)

### 7. Notable "standalone but composes" exemplars: OpenSpec, Taskmaster, Conductor
- **OpenSpec** (Fission-AI, npm `@fission-ai/openspec`): core artifact is plain markdown in an `openspec/` folder, zero-tooling readable. CLI is a thin generator; `.agents/skills/` holds per-tool skill wrappers; works across 25+ agent tools with **no MCP server required**. Explicitly "brownfield-first" vs spec-kit's greenfield bias. Composes with Linear/Jira/Taskmaster via a dedicated integration skill rather than owning task-tracking itself. **The closest existing analogue to the standalone-first vision: markdown-as-source-of-truth + thin per-host skill shim.**
  Sources: [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec/) · [openspec.dev](https://openspec.dev/) · [Thoughtworks Radar entry](https://www.thoughtworks.com/en-us/radar/tools/openspec)
- **Taskmaster** (task-master-ai, npm + MCP): fully standalone with the user's own API keys; exposes an MCP server *and* a CLI from the same core. Composition-cost control via `TASK_MASTER_TOOLS=core|standard|all` env var, letting an operator scope how much of the tool surface loads: a direct answer to the "N MCP servers = N-times context tax" problem.
  Sources: [mamba-mental/taskmaster-ai-mcp](https://github.com/mamba-mental/taskmaster-ai-mcp) · [tryhamster.com/docs/taskmaster](https://tryhamster.com/docs/taskmaster/capabilities/mcp)
- **Conductor.build**: standalone macOS app running parallel Claude Code agents in isolated workspaces/lanes; lanes compose slash-commands sequentially (`/research -> /validate -> /scaffold`), framed by commentators as Unix-philosophy composability. (The `gemini-cli-extensions/conductor` SDD plugin is an unrelated name collision.)
  Sources: [rustman.org: Conductor and the 2026 ecosystem](https://rustman.org/wiki/conductor-parallel-agents/) · [Augment Code: 9 open-source orchestrators](https://www.augmentcode.com/tools/open-source-agent-orchestrators)

## (b) Comparison table

| Project | Packaging unit | Standalone w/ zero framework? | Discovery/compose mechanism | Distribution |
|---|---|---|---|---|
| spec-kit | CLI + per-agent slash-cmd/skill files | Yes, per-command | layered override stack (project > preset > extension > core), non-destructive | PyPI (uv/pipx) + `bundle.yml` |
| BMAD-METHOD | module / expansion pack | No, assumes core orchestrator | npm install-time module selection, `--set`/`--list-options` registry | npm (`npx bmad-method`) |
| agent-os v3 | markdown standards file(s) | Yes, literally just read the files | `/inject-standards` bakes into any subagent/skill/prompt | install script, git |
| superpowers | one `SKILL.md` per skill | Yes, per-skill file | implicit: agent self-selects by description, no registry | per-harness marketplace / git / npm (reinstall per harness) |
| claude-flow/Ruflo | MCP tool + swarm agent | Nominally yes, in practice much is stub | hive-mind memory + 300+ MCP tools | npm / git |
| CC Skills | `SKILL.md` (30-50 tok, on-demand) | Yes | model reads skill description, decides relevance | copy file into `.claude/skills/` |
| CC MCP server | server + tool defs (loaded upfront) | Yes | explicit tool-call routing | `mcp add`, config JSON |
| CC Plugin | bundle manifest (`plugin.json`) | No, by design (it IS the composition layer) | `/plugin marketplace add` + `/plugin install` | marketplace repo (git-backed) |
| OpenSpec | markdown convention + thin CLI/skill | Yes, plain files, CLI optional | per-tool skill wrapper generated from one core | npm (`@fission-ai/openspec`) |
| Taskmaster | CLI + MCP server, same core | Yes, own API keys | `TASK_MASTER_TOOLS` env var scopes exposed surface | npm |
| Conductor | app orchestrating slash-cmd lanes | Yes (it is the top-level app) | sequential lane composition of independent commands | standalone macOS app |

## (c) Ranked PICKUP list

1. **Split "capability" from "bundle," per the CC Skills/MCP/Plugin layering.** Each kit module (proof-capture, test-corpus, backlog CLI, gate-ledger) is a self-contained unit that works with the plugin literally deleted; `kit.toml [modules]` becomes the *optional* bundle manifest, never the load-bearing container. The single biggest structural unlock, and it is already how Anthropic ships their own ecosystem.
2. **Adopt agent-os v3's "defer, don't own" discipline.** v3's whole rewrite deleted the parts that duplicated what the host agent already does well and kept only the irreducible unique value. Apply the same test to each module: does proof-capture need to own verification-flow orchestration, or just capture+embed the artifact and hand back a path? Cut to the irreducible core.
3. **Make the artifact plain files first, tool second (OpenSpec's model).** Backlog rows, gate-ledger entries, test-corpus: keep them markdown/jsonl/csv, inspectable and greppable with zero framework running; the CLI/skill is a thin generator/renderer, not the source of truth. This is what makes a tool genuinely adoptable standalone (a developer can `cat` the state) and safely composable (another tool reads the same file without an API).
4. **Borrow Taskmaster's exposed-surface scoping for co-installed modules.** `kit.toml [modules]` entries declare what each module *exposes* (commands, hooks, ledger paths) into the shared registry, not what it *requires*; avoids the N-MCP-servers context tax.
5. **Reuse spec-kit's non-destructive override-stack for composition conflicts.** When two modules extend the same hook/command, priority-tiered override (module-local > project > kit-default) that cleanly reverts on uninstall beats ad-hoc merge logic; proven at 111k-star scale.

## (d) AVOID list

1. **Ruflo's kitchen-sink tool surface.** Never ship a module whose command list outruns what is wired and tested; a "99% theater" audit is the worst outcome a tool can get, and it is a direct consequence of packaging aspirational scope as shipped capability.
2. **BMAD's core-coupled expansion packs.** If a module's file format or config only makes sense with the kit's orchestrator running, it is not standalone, it is a plugin wearing a standalone label. Test: "does this work if dwarves-kit is uninstalled and only this module's files remain?"
3. **Superpowers' per-harness reinstall model.** One packaging format; generate the thin per-host adapters from it (CC skill, bare CLI, MCP wrapper only if genuinely useful). Never hand-maintained duplicates per harness.
4. **spec-kit's mandatory full-pipeline gate.** A standalone tool must be invokable for exactly the slice needed (just test-gen, just proof-capture) without forcing upstream phases; "sea of markdown" is what happens when a tool won't let you skip steps.
5. **Superpowers' implicit, registry-less discovery.** Model-noticed skills get silently skipped as context grows. An explicit registry (the module manifest) that hooks/commands check against beats model self-selection.

## (e) Recommendation

Structure each capability as a **standalone tool whose primary artifact is plain, git-trackable files** (markdown/jsonl/csv, per OpenSpec and agent-os v3) plus **one script/binary that reads and writes those files with zero dwarves-kit present**; that pair is the whole tool, fully useful alone. Ship exactly one **thin per-host adapter** generated from that same core (a `SKILL.md` for Claude Code, a bare CLI entry for shell use, an MCP wrapper only if genuinely useful), never hand-maintained duplicates. The **only** thing dwarves-kit itself owns is the composition layer: the `kit.toml` module manifest declaring what each installed tool exposes (commands, hooks, ledger paths) into the shared registry/lane-classifier/gate-ledger, with spec-kit's non-destructive override stack for conflicts.

**The acceptance test of the doctrine: deleting dwarves-kit leaves every tool fully functional (degraded convenience, not degraded capability), and deleting any one tool leaves the kit merely missing one capability, never broken.**
