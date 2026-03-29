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
