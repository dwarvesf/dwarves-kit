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

If modifying existing code:
- Read the relevant source files
- Understand current architecture before proposing changes
- Note existing patterns, naming conventions, test patterns
- List files that will be modified

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
