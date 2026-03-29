# ADR-001: Command hooks only for v1

## Status: accepted

## Context
Claude Code supports 4 hook handler types: command, http, prompt, agent. Prompt hooks delegate decisions to an LLM (Haiku). Agent hooks spawn subagents with tool access. Both add latency and cost per hook invocation.

## Decision
v1 uses command hooks exclusively. All 5 hooks are bash scripts that read JSON from stdin, pattern-match, and return exit codes.

## Alternatives considered
- Prompt hooks for anti-rationalization: better accuracy but adds ~2-5s latency per Stop event and costs tokens. Deferred to v2.
- Agent hooks for spec-drift-guard: could verify file intent with codebase analysis. Overkill for a grep-based check.
- HTTP hooks for team-wide enforcement: useful but requires a shared server. Not needed for solo/small team.

## Consequences
- Anti-rationalization hook uses grep patterns, which will have some false positives on legitimate "out of scope" mentions.
- All hooks run in under 500ms, keeping sessions fast.
- No external API calls or LLM costs from hooks.

---

# ADR-002: .planning/ directory convention (from GSD)

## Status: accepted

## Context
Spec output needs a predictable location that hooks and commands can reference. GSD uses `.planning/`, other tools use `docs/`, `specs/`, or inline CLAUDE.md sections.

## Decision
Adopted GSD's `.planning/` convention. Spec files live there. Hooks (context-readiness, spec-drift-guard) check for this directory.

## Alternatives considered
- `docs/specs/`: more traditional but buried. Hooks would need deeper path matching.
- Inline in CLAUDE.md: pollutes the main config file. CLAUDE.md should reference specs, not contain them.
- `.gsd/`: too coupled to GSD's specific format. We want our own spec format.

## Consequences
- Compatible with GSD if user also installs GSD (both check .planning/).
- context-readiness hook also checks for `.gsd/` as a fallback.
- Contractors see specs in a predictable location across all Dwarves projects.

---

# ADR-003: User-level install with symlinks

## Status: accepted

## Context
Kit can be installed globally (~/.claude/) or per-project (.claude/). Global means available everywhere. Per-project means committed to git, shared with team.

## Decision
Default install is user-level (~/.claude/dwarves-kit/) with symlinks to ~/.claude/commands/ and copies to ~/.claude/skills/. The kit itself is a standalone directory, not scattered across ~/.claude/.

## Alternatives considered
- Per-project install: better for team sharing but requires copying to every repo. Can add later.
- Plugin marketplace format: requires packaging as a plugin. v2 goal.
- npx installer (like GSD): nice UX but adds npm dependency for installation. Bash is simpler.

## Consequences
- Commands appear as /user:think, /user:spec, etc. (not /project:think).
- Kit updates are a git pull in one directory.
- Team members must each install individually (no auto-sharing via repo).
- Can add project-level install mode later without breaking user-level installs.

---

# ADR-004: Adversarial spec validation as a separate command

## Status: accepted

## Context
Spec generation (/spec) and spec validation (/spec-validate) could be one command or two. ClaudeKit bundles validation into the plan phase. GSD keeps them separate.

## Decision
Two separate commands. /spec generates, /spec-validate attacks. User chooses whether to validate.

## Alternatives considered
- Auto-validate after spec generation: adds 5+ minutes to every spec. Not always wanted for quick features.
- Validation as a hook (PreToolUse on implementation): too late. Validation should happen before coding starts.

## Consequences
- User might skip validation. That's fine for small features, risky for large ones.
- /spec ends with a reminder to run /spec-validate.
- The 4-reviewer pattern (security, failure, assumptions, scope) is thorough but takes time.

---

# ADR-005: Separate verifier subagent instead of worker self-verification

## Status: accepted (v1.2)

## Context
After a worker subagent completes a task, the orchestrator needs to know if the work meets the spec. Two options: (A) have the worker self-verify, or (B) dispatch a separate read-only verifier.

## Decision
Separate task-verifier subagent with read-only access. It checks acceptance criteria, runs tests, and checks scope compliance. Returns PASS, FAIL:fixable, or FAIL:escalate.

## Alternatives considered
- Worker self-verification: cheaper (no extra subagent) but biased. The worker's context is saturated with its own implementation. It normalizes its own shortcuts.
- Orchestrator inline verification: keeps it in the main session, but the orchestrator's context should stay lean for coordination, not deep code reading.

## Consequences
- Every task costs one extra subagent dispatch (task-verifier). Roughly 2x the token cost per task.
- Verification is independent: the verifier has no knowledge of the worker's reasoning, only the spec and the code.
- The verifier cannot modify code. If it finds issues, it reports them for the fix-agent.
- Source: OMC's architect verification in the Ralph loop, adapted to Claude Code custom subagents.

---

# ADR-006: Custom subagents via .claude/agents/ directory

## Status: accepted (v1.2)

## Context
v1.2 introduces 8 agent roles (task-verifier, fix-agent, reviewer, security-auditor, 4 researchers). These need prompt definitions that commands can reference.

## Decision
Agent definitions live in `.claude/agents/` as markdown files with YAML frontmatter (name, description, tools, model). install.sh copies them to `~/.claude/agents/`. Commands dispatch them via the Task tool.

## Alternatives considered
- Inline prompts in command files: works but duplicates content. Can't tune agent prompts independently.
- MCP server agents: more powerful but requires a running server. Too heavy for this kit.
- Skill files: skills are Claude-triggered, not command-triggered. Agents are dispatched by commands.

## Consequences
- Requires Claude Code v2.0.60+ (custom subagent support).
- Agent prompts can be tuned independently from commands.
- Model selection per agent: research-stack uses haiku (cheap), others use sonnet.
- install.sh handles agent install/uninstall alongside commands and skills.

---

# ADR-007: Collaborative Design Protocol for agent decisions

## Status: accepted (v1.2)

## Context
Worker subagents encounter design decisions during implementation (which library, which data model, which API pattern). Without structure, they either guess silently or block on every decision.

## Decision
Shared protocol (docs/COLLABORATIVE-DESIGN.md) with 5 steps: Question > Options > Recommendation > Decision > Record. Agents reference this protocol in their prompts. In autonomous mode (/execute), agents proceed with their recommendation and log it. The task-verifier catches misalignment after the fact.

## Alternatives considered
- Always block on decisions: too slow for autonomous /execute. Every non-trivial task has 2-3 decisions.
- Never structure decisions: agents make silent choices that are hard to review.
- Per-agent decision rules: inconsistent. A shared protocol means all agents speak the same decision language.

## Consequences
- Worker subagents can make decisions autonomously in /execute mode.
- Decisions are logged in .planning/SPEC.md Decision Log for audit.
- task-verifier checks whether decisions align with the spec.
- In manual /next mode, agents pause for human approval on decisions.
- Source: CCGS Collaborative Design Principle, adapted to fit the verification pipeline.
