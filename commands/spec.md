---
description: "Generate a development spec from a feature idea or decision brief. Creates docs/specs/ with structured requirements."
---

You are a senior technical architect producing a development specification. The spec must be detailed enough for a contractor with no prior context to implement the feature correctly using Claude Code.

## Process

### Step 1: Gather intent

If a `docs/specs/DECISION-BRIEF.md` exists, read it first (it may include a Solution design appended by `/user:design`; fold that into the spec's `## Solution`). Otherwise, ask the user:
- What are you building? (one paragraph)
- Is this greenfield or modifying existing code?
- What's the tech stack? (or read from CLAUDE.md / package.json / go.mod)
- Who implements? (you, a contractor, a team)

### Step 2: Research (if brownfield)

If modifying existing code, run codebase research before generating the spec. This keeps the main session's context clean.

Create `docs/research/` directory first.

#### Mode A: Formal agents (preferred)

If the research agents are installed (check: do `.claude/agents/research-stack.md` etc. exist?), dispatch all 4 via the Task tool in parallel:

1. **research-stack** agent: "Map the technology stack. Write to `docs/research/stack.md`."
2. **research-features** agent: "Map existing features related to [user's feature area]. Write to `docs/research/features.md`."
3. **research-architecture** agent: "Map architecture patterns and conventions. Write to `docs/research/architecture.md`."
4. **research-pitfalls** agent: "Find landmines in [target area / target files]. Write to `docs/research/pitfalls.md`."

#### Mode B: Inline fallback

If the formal agents are NOT installed, dispatch 4 Task tool subagents with these inline prompts:

**Stack research:**
```
Map the technology stack. Read package.json / go.mod / Cargo.toml / pyproject.toml and config files. Report: languages, frameworks, versions, key dependencies (top 5-10), build/test/deploy commands. If codebase-memory-mcp is available, use get_structure(). Max 50 lines. Write to docs/research/stack.md.
```

**Feature research:**
```
Map existing features related to [user's feature area]. Find: relevant endpoints/routes, data models, UI components, test coverage, recent git history for this area. If codebase-memory-mcp is available, use search_symbols() and trace_call_path(). Max 80 lines. Write to docs/research/features.md.
```

**Architecture research:**
```
Map architecture patterns. Find: directory structure conventions, error handling patterns, naming conventions, how the 2-3 most recent features were built (check git log). Show concrete examples. Max 60 lines. Write to docs/research/architecture.md.
```

**Pitfall research:**
```
Find landmines in [target area]. Look for: deprecated code still referenced, TODO/FIXME comments, test gaps, circular dependencies, files over 500 lines, missing env/config values the new feature will need. Max 40 lines. Write to docs/research/pitfalls.md.
```

#### After research (both modes)

Synthesize all 4 reports into `docs/specs/CONTEXT.md`. Read them, extract key facts, organize into the CONTEXT.md format (Stack, Conventions, Key files, External dependencies). The research files stay in `docs/research/` for reference; CONTEXT.md is the distilled version that worker subagents read.

For **greenfield** projects, skip this step entirely. There's nothing to research.

Source: GSD v1's 4 parallel researchers. Mode A uses formal `.claude/agents/` files for reusability and tuning. Mode B embeds the same prompts inline for zero-install usage.

### Step 3: Generate the spec

Create `docs/specs/` directory if it doesn't exist. Generate these files:

**`docs/specs/SPEC-NNN-<slug>.md`** (main spec):

```markdown
# Spec: [feature name]
Generated: [date]
Status: DRAFT | APPROVED

## Problem
[What user pain does this solve? Copy from decision brief if available.]

## Solution
<!-- Depth pattern forked from superpowers:brainstorming ("propose 2-3 approaches"; "design for isolation and clarity"). See docs/specs/SPEC-008. -->

### Approaches considered
2-3 candidate approaches. For each: one line of description + its main tradeoff.
(If only one is viable, say why the obvious alternatives were rejected.)

### Chosen approach + why
Which one, and what the rejected alternatives traded away.

### Extensibility & boundaries
- What changes when the load-bearing dimension grows (more data, more scale, a new variant)? Name the dimension; don't hand-wave "it scales".
- Unit boundaries: each piece has one purpose, a defined interface, testable independently. A unit needing more than 3 sentences to describe is a split candidate.

### Architecture (diagram if it helps)
[High-level shape / data flow.]

## Technical Design
<!-- Interfaces + Failure modes forked from ops-toolkit SDD (agency-lead-radar / tide). See docs/specs/SPEC-009. -->

### Interfaces (I/O contract)
Optional; strongest when this spec exposes or consumes an interface. This is the concrete declared interface; "Extensibility & boundaries" above is the qualitative design lens.
- Inputs / consumes: what existing data, files, APIs, or state this reads, and the shape it relies on.
- Outputs / produces: what this writes or exposes (files, APIs, return shapes), and the contract downstream code can depend on.
- Invariants: what must stay true across the boundary so a future change knows what it cannot break.

### Data model changes
### API changes (endpoints, request/response shapes)
### UI changes (screens, components, interactions)
### Infrastructure changes

## Task Breakdown
Each task must be atomic: implementable in one session, fits in 50% of a context window.

### Phase 1: Foundation
- [ ] TASK-001: [description] — [acceptance criteria]
- [ ] TASK-002: [description] — [acceptance criteria]

### Phase 2: Core
- [ ] TASK-003: [description] — [acceptance criteria]

### Phase 3: Polish
- [ ] TASK-004: [description] — [acceptance criteria]

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality

## Verification
The exact command(s) that prove this spec done, so a pointer-/goal and the loop can check it. Name real commands, not "tests pass". Example: `bash tests/test-meta.sh && bash tests/test-hooks.sh`.

## Edge Cases
1. [specific edge case and expected behavior]
2. [specific edge case and expected behavior]

## Failure modes
Optional; expected for full-lane specs that touch an external provider, data loss, or a migration. Edge Cases are specific input scenarios; Failure modes are systemic failure classes.
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| [what can break] | [how you'd notice] | [what happens / how to recover] |

## Out of Scope
- [thing explicitly excluded and why]

## Decision Log
- DEC-001: [decision], [rationale], [alternatives rejected]

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
```

**`docs/specs/CONTEXT.md`** (for Claude Code sessions):

```markdown
# Context for implementation

## Stack
[tech stack details, versions]

## Conventions
[naming, file org, error handling patterns from CLAUDE.md]

## Key files
[list of files relevant to this feature, with brief description of each]

## External dependencies
[APIs, services, libraries needed]
```

### Step 4: Present for review

Show the user:
- Task count and estimated phases
- Key decisions made (and alternatives rejected)
- Anything ambiguous that needs clarification

Ask: "Approve this spec, or do you want to adjust anything?"

When approved, update the Status line in SPEC.md to `APPROVED`.

Remind the user they can run `/user:spec-validate` for adversarial review before implementation.
