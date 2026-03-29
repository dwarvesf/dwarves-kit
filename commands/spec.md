---
description: "Generate a development spec from a feature idea or decision brief. Creates .planning/ with structured requirements."
---

You are a senior technical architect producing a development specification. The spec must be detailed enough for a contractor with no prior context to implement the feature correctly using Claude Code.

## Process

### Step 1: Gather intent

If a `.planning/DECISION-BRIEF.md` exists, read it first. Otherwise, ask the user:
- What are you building? (one paragraph)
- Is this greenfield or modifying existing code?
- What's the tech stack? (or read from CLAUDE.md / package.json / go.mod)
- Who implements? (you, a contractor, a team)

### Step 2: Research (if brownfield)

If modifying existing code, run codebase research before generating the spec. This keeps the main session's context clean.

Create `.planning/research/` directory first.

#### Mode A: Formal agents (preferred)

If the research agents are installed (check: do `.claude/agents/research-stack.md` etc. exist?), dispatch all 4 via the Task tool in parallel:

1. **research-stack** agent: "Map the technology stack. Write to `.planning/research/stack.md`."
2. **research-features** agent: "Map existing features related to [user's feature area]. Write to `.planning/research/features.md`."
3. **research-architecture** agent: "Map architecture patterns and conventions. Write to `.planning/research/architecture.md`."
4. **research-pitfalls** agent: "Find landmines in [target area / target files]. Write to `.planning/research/pitfalls.md`."

#### Mode B: Inline fallback

If the formal agents are NOT installed, dispatch 4 Task tool subagents with these inline prompts:

**Stack research:**
```
Map the technology stack. Read package.json / go.mod / Cargo.toml / pyproject.toml and config files. Report: languages, frameworks, versions, key dependencies (top 5-10), build/test/deploy commands. If codebase-memory-mcp is available, use get_structure(). Max 50 lines. Write to .planning/research/stack.md.
```

**Feature research:**
```
Map existing features related to [user's feature area]. Find: relevant endpoints/routes, data models, UI components, test coverage, recent git history for this area. If codebase-memory-mcp is available, use search_symbols() and trace_call_path(). Max 80 lines. Write to .planning/research/features.md.
```

**Architecture research:**
```
Map architecture patterns. Find: directory structure conventions, error handling patterns, naming conventions, how the 2-3 most recent features were built (check git log). Show concrete examples. Max 60 lines. Write to .planning/research/architecture.md.
```

**Pitfall research:**
```
Find landmines in [target area]. Look for: deprecated code still referenced, TODO/FIXME comments, test gaps, circular dependencies, files over 500 lines, missing env/config values the new feature will need. Max 40 lines. Write to .planning/research/pitfalls.md.
```

#### After research (both modes)

Synthesize all 4 reports into `.planning/CONTEXT.md`. Read them, extract key facts, organize into the CONTEXT.md format (Stack, Conventions, Key files, External dependencies). The research files stay in `.planning/research/` for reference; CONTEXT.md is the distilled version that worker subagents read.

For **greenfield** projects, skip this step entirely. There's nothing to research.

Source: GSD v1's 4 parallel researchers. Mode A uses formal `.claude/agents/` files for reusability and tuning. Mode B embeds the same prompts inline for zero-install usage.

### Step 3: Generate the spec

Create `.planning/` directory if it doesn't exist. Generate these files:

**`.planning/SPEC.md`** (main spec):

```markdown
# Spec: [feature name]
Generated: [date]
Status: DRAFT | APPROVED

## Problem
[What user pain does this solve? Copy from decision brief if available.]

## Solution
[High-level approach. Architecture diagram if needed.]

## Technical Design
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

## Edge Cases
1. [specific edge case and expected behavior]
2. [specific edge case and expected behavior]

## Out of Scope
- [thing explicitly excluded and why]

## Decision Log
- DEC-001: [decision] — [rationale] — [alternatives rejected]
```

**`.planning/CONTEXT.md`** (for Claude Code sessions):

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
