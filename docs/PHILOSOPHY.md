# PHILOSOPHY.md

> This document is for the maintainer, not the end user.
> It governs what gets added, what gets rejected, and why.
> Read this before proposing any change to the kit.

---

## 1. Design principles

Each principle resolves a real tradeoff. If it can't be violated, it's not a real principle.

### "Guardrails over guidance"

We believe enforcement beats advice. A rule in CLAUDE.md is followed ~70% of the time. A hook with exit code 2 is followed 100% of the time. Therefore we build hooks for anything safety-critical, and use commands/CLAUDE.md only for things where human judgment matters.

**Decision this already made:** Anti-rationalization is a Stop hook, not a line in CLAUDE.md. Push-to-main blocker is a PreToolUse hook, not a convention.

**Decision this would reject:** "Add a CLAUDE.md rule saying 'always write tests first.'" If it matters enough to enforce, it needs a hook (like tdd-guard). If it's just advice, it belongs in the team wiki, not the kit.

### "Synthesize, don't originate"

We believe cherry-picking battle-tested patterns from mature tools is better than inventing new workflows. Every command and hook in this kit traces its lineage to a specific repo. We don't invent novel approaches; we curate and integrate proven ones.

**Decision this already made:** /think is gstack's /office-hours adapted. /review is gstack's paranoid reviewer + Trail of Bits' quality rules. The safety-gate hook is Trail of Bits' verbatim code. We cited every source in README.md.

**Components with indirect lineage (originated in-kit but grounded in existing patterns):**
- context-readiness.sh: analogous to CI pre-flight checks (GitHub Actions `if:` conditions, Buildkite pre-command hooks). Novel integration, proven pattern.
- spec-drift-guard.sh: analogous to linting rules that flag undeclared variables. The "check against a manifest" pattern exists in package managers (lockfile drift checks), dependency auditing, and Terraform plan drift detection.
- /kit-health: analogous to `npm audit`, `cargo clippy`, self-diagnostic commands in mature CLIs.
- .planning/SPEC.md format: derived from architecture decision records (ADR), user story templates, and GSD's task breakdown convention. The format is a composition, not an invention.

**Decision this would reject:** "I have a new idea for a code review methodology nobody's tried." Test it as a standalone experiment first. If it works in production for 3+ months, then propose merging it into the kit with a source citation.

### "One kit, whole cycle"

We believe a unified kit covering Think-through-Retro is more valuable than 4 best-of-breed tools that don't talk to each other. The spec format that /spec produces is the same format that /execute reads, that /review checks against, and that /docs updates. Data flows through the cycle; nothing is re-entered.

**Decision this already made:** .planning/SPEC.md is the shared contract between /spec, /spec-validate, /execute, /next, /review, and /docs. The spec-drift-guard hook references the same directory.

**Decision this would reject:** "Let's use GSD for planning and a separate tool for execution with its own format." Format translation between tools is where context gets lost. One format, one directory, one kit.

### "Shallow and wide beats deep and narrow"

We believe covering 7 lifecycle phases at 70% depth each is better than covering 2 phases at 100% depth. The biggest failures in AI-assisted development come from skipped phases (no spec, no review, no retro), not from insufficient depth in any one phase.

**Decision this already made:** /execute uses Claude Code's native Task tool for subagent dispatch. It's not as sophisticated as GSD v2's Pi SDK runtime (which has crash recovery, token tracking, and automated git branching). But it exists, and it covers the execution gap that 0 commands would leave.

**Decision this would reject:** "Let's build a custom TypeScript runtime for task execution like GSD v2." That's building a product, not maintaining a kit. If execution depth becomes the bottleneck, adopt GSD v2 as the execution engine and integrate it, don't rebuild it.

### "Bash over binaries"

We believe every hook should be a readable shell script, not a compiled binary or a Node.js project. A contractor should be able to open any .sh file, read it in 30 seconds, and understand what it does. When a hook misbehaves, `bash -x hooks/safety-gate.sh` is the entire debugging workflow.

**Decision this already made:** All 9 hooks are bash scripts using jq for JSON parsing. No Python, no Node, no compiled code. Auto-format detects formatters with `command -v` and runs them directly.

**Decision this would reject:** "Let's rewrite hooks in Python for better JSON handling." Adds a runtime dependency, slows startup, and makes debugging harder. The only exception is upgrading anti-rationalization to a prompt-type hook (which delegates to the LLM, not Python).

**Carve-out:** The HUD/statusline script may use Node.js (via mjs) because StatusLine runs per-turn and needs fast JSON parsing that bash+jq struggles with at scale. This is the only exception. If a second exception is proposed, the principle should be revisited entirely, not bent again.

### "Detect, don't dictate"

We believe the kit should detect the user's current state and suggest the right action, not require them to memorize 9 commands. A full-time coder in flow state doesn't want to remember whether the next step is /review or /docs or /ship. The kit should surface what's relevant based on project state.

**Decision this already made:** context-readiness hook detects whether CLAUDE.md exists, whether a spec is present, which git branch is active, and whether MCP servers are connected. It injects this as context so Claude knows the project state without being asked.

**Decision this would reject:** "Add a phase-locking system that blocks /execute unless /spec-validate has been run." Rigid phase gates annoy experienced coders who know when to skip a step. Detect and suggest, never block workflow progression. The exception is safety hooks (rm-rf, push-to-main) which DO block because the cost of a mistake is irreversible.

### "External tools are dependencies, not features"

We believe the kit should check for external tools and warn when they're missing, but never rebuild their functionality. Context Hub, Context7, codebase-memory-mcp, and MCP servers are separate products that evolve on their own schedule. The kit's job is integration, not duplication.

**Decision this already made:** context-readiness hook checks if chub is installed and if .mcp.json exists. The get-api-docs skill teaches Claude to use chub. Neither rebuilds chub's functionality.

**Decision this would reject:** "Let's build our own API doc fetcher instead of depending on Context Hub." If chub breaks or disappears, we remove the check. We don't maintain a replacement.

---

## 2. Target user and their actual week

### Who this is for

Han at Dwarves Foundation. Two modes, one person.

**Lead mode**: Technical lead managing contractors. Delegates implementation, reviews PRs, plans features. Splits time between ops (Notion, payments, hiring) and engineering (specs, code review, architecture). Touches the kit at phase boundaries: beginning of week (plan), middle (hand off), end (review + ship).

**Coder mode**: Full-time builder using Claude Code 6-8 hours/day. Needs: HUD for context budget awareness, faster permission approvals, slop detection after long sessions, session state persistence across compaction. The cycle is tighter: hours instead of days, per-task instead of per-week.

Both modes share the same spec format, hooks, and commands. The difference is frequency of interaction, not the workflow itself. A contractor using the kit operates in a variant of coder mode.

Not: a team of 10 with a dedicated DevOps pipeline. Not: someone who needs multi-agent orchestration across parallel sessions (that's L5, use Nimbalyst/Conductor).

### What their week looks like

**Lead mode week:**

**Monday**: Review last week's shipped work. Check contractor PRs. Plan the week's features.
Kit touches: /retro (if not done Friday), /think for new features.

**Tuesday-Wednesday**: Spec new features, hand off to contractors. Context: Notion tasks, Slack async, GitHub PRs.
Kit touches: /spec, /spec-validate. Contractor gets spec + CLAUDE.md + kit installed on their machine.

**Wednesday-Thursday**: Contractor builds. Han does ops work (payments, hiring, client calls). Gets desktop notifications when Claude Code needs input on the contractor's machine.
Kit touches: /execute or /next (contractor runs these), hooks enforce during build (safety-gate, auto-format, spec-drift, anti-rationalization). Pre-compact backup protects long sessions.

**Friday**: Review, ship, reflect. Han reviews the contractor's work, updates docs, ships, captures learnings.
Kit touches: /review, /docs, /ship, /retro.

**Coder mode day:**

Morning: /next to pick a task, or /execute for autonomous mode. HUD visible throughout showing context budget.
Midday: Code for 2-4 hours. Hooks enforce continuously. Compaction backup fires at ~50k tokens. Permission auto-approve removes friction for reads.
Afternoon: /review own work, /docs to update documentation, /ship to commit and PR. /next for the next task.
End of day or end of sprint: /retro to capture learnings.

### What the kit does NOT cover

- **Ops work**: Contractor payments, hiring pipeline, client comms. These use Notion + existing Dwarves skills, not the kit.
- **IDE choice**: The kit works from the terminal. VS Code, Neovim, whatever.
- **CI/CD**: The kit produces commits and PRs. GitHub Actions or whatever CI pipeline runs after that is a separate concern.
- **Multi-agent coordination**: When 3+ contractors run Claude Code simultaneously, that's L5 orchestration (Nimbalyst/Intent territory). The kit is for one agent session at a time.
- **Project management**: No sprint boards, no story points, no velocity tracking. Notion handles that.
- **Parallel execution**: /execute dispatches tasks sequentially via the Task tool. It does not batch independent tasks for concurrent dispatch, auto-retry on crash, or coordinate multiple subagents on shared files. For parallel execution use GSD v2 (Pi SDK runtime) or OMC (Ultrapilot). For crash-resilient loops use Smart Ralph. The kit's thesis is lifecycle integration, not competing with agent runtimes.

---

## 3. Design boundaries (the NO list)

### Hard limits

- **Every file must justify its existence.** No file count cap, but every addition must solve a real problem. If a file hasn't been used in 30 days, it's a deprecation candidate.
- **Maximum 500ms per hook execution.** If a hook takes longer, it degrades the coding experience. Profile with `time` before merging.
- **No compiled binaries.** Everything is bash, markdown, or JSON. If a feature requires a binary, it becomes an external dependency, not part of the kit.
- **No paid dependencies.** The kit must work with free tools only. Paid tools (ClaudeKit Engineer Kit, Exa API) can be optional enhancements but never required.
- **No LLM API calls in v1 hooks.** Prompt-type hooks call the LLM, adding latency and cost. Deferred to v2, and only for anti-rationalization where the accuracy gain justifies it.

### Feature rejection criteria

Reject a proposed feature if ANY of these are true:

1. **It duplicates an external tool.** If Context Hub, GSD, gstack, or a plugin already does it well, depend on it instead.
2. **It serves fewer than 2 of the 9 workflow phases.** Single-purpose tools belong as standalone scripts, not kit features.
3. **It requires the user to change their existing Notion/GitHub workflow.** The kit adapts to how Dwarves already works. It doesn't impose a new project management system.
4. **It can't be explained in one sentence.** If you can't describe what the hook/command does in one line of the README table, it's too complex.
5. **It has no source citation.** Per the "synthesize, don't originate" principle, every pattern must trace to a proven implementation.

### When to recommend an external tool instead

- Need browser-based QA? Install gstack for /qa (requires Playwright + Bun).
- Need full autonomous execution with crash recovery? Install GSD v2 (requires Pi SDK).
- Need multi-agent orchestration? Install Nimbalyst or Conductor.
- Need security auditing? Install Trail of Bits plugin marketplace.
- Need TDD enforcement? Install tdd-guard plugin.

The kit is the glue layer. It doesn't compete with specialized tools.

---

## 4. Differentiation thesis

Why pick dwarves-kit over installing GSD + gstack + Trail of Bits separately?

The honest answer: dwarves-kit is less powerful than any of those tools in their area of specialty. GSD's spec generation is deeper. gstack's review is more thorough. Trail of Bits' security config is more comprehensive.

What dwarves-kit offers is **lifecycle continuity**. The spec format that /spec produces flows unchanged into /execute, /review, /docs, and /ship. The hooks reinforce the commands: context-readiness checks for a spec before the build starts, spec-drift-guard warns during the build, anti-rationalization catches premature completion, post-compaction re-injection restores rules after long sessions.

With separate tools, you get: GSD's .planning/ format, gstack's TODOS.md format, Trail of Bits' settings.json. Three tools, three conventions, three directories. The contractor has to learn all three. When something breaks between phases, nobody owns the gap.

With dwarves-kit: one directory (.planning/), one convention, one install. The contractor runs `install.sh` and gets everything. The hooks protect them automatically. The commands guide them through the phases. The data flows.

The thesis is not "better components" but "better integration." If that thesis is wrong -- if the integration overhead isn't worth the depth tradeoff -- then the right answer is to use the specialized tools directly and accept the format translation cost.

---

## 5. Evolution strategy

### Adding a new component

1. **Identify the source.** What existing tool or pattern does this come from? (principle: "synthesize, don't originate")
2. **Score with /eval-tool rubric.** Layer fit + Pain match + Adoption cost + Timing. Must score 10+ to be ADOPT.
3. **Check the NO list.** Does it violate any hard limit or rejection criterion?
4. **File budget check.** Will the kit stay under 35 files? If not, what gets removed?
5. **Performance check.** For hooks: does it complete in under 500ms?
6. **Write the one-sentence description.** If you can't, it's too complex.
7. **Add source citation.** README credits section must be updated.
8. **Test on one real project for 1 week before merging.**

### Deprecating a component

If a component has been unused for 30 days (no contractor reports using it, no signal in retros), it's a candidate for removal. Steps:

1. Move to a `deprecated/` directory (not deleted immediately)
2. Remove from settings.json and README
3. After another 30 days with no complaints, delete entirely
4. Document the removal in CHANGELOG.md with rationale

### AutoResearch optimization

From the SDD handoff: the Karpathy loop can optimize kit components with a measurable metric. This applies to:

- **Command prompts**: The three-file contract (program.md = kit philosophy frozen, skill.md = command prompt modifiable, eval.py = LLM-as-judge scoring). Run 50 iterations overnight, keep the highest-scoring prompt variant. Applicable to /review, /spec-validate, /think.
- **Hook patterns**: Anti-rationalization patterns can be optimized by running against a corpus of Claude outputs and measuring false positive / false negative rates.

The bar for AutoResearch: only run it when manual iteration has plateaued AND you have 10+ real session transcripts to evaluate against. Before that, manual iteration is faster.

### Version strategy

- **v1.x**: Command hooks only. Manual iteration on prompts. Current state.
- **v2.x**: Prompt-type hooks (anti-rationalization upgraded to Haiku evaluation). /qa command with browser testing. Plugin marketplace packaging.
- **v3.x**: Agent-type hooks for deep verification. Multi-runtime support (Codex, Gemini). AutoResearch-optimized prompts.

No timeline commitment. Version bumps happen when real usage exposes the limits of the current version, not on a calendar schedule.
