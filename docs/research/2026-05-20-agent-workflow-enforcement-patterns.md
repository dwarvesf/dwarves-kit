---
title: Agent Workflow Enforcement Patterns, SDD frameworks, orchestration layers, and how instruction files actually force compliance
date: 2026-05-20
purpose: >
  Cross-repo landscape survey of the AI-coding-agent ecosystem (spec-driven
  development frameworks, agent-orchestration frameworks, and the
  instruction-file "harness/orchestration layer" pattern). Captures the
  enforcement-mechanism taxonomy distilled from reading the actual instruction
  files of the popular repos. Use this when designing dwarves-kit's
  orchestration layer, or when evaluating any "make the agent follow a
  workflow" tooling. Verbatim enforcement quotes preserved deliberately, they are the irreplaceable signal.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: as-needed
next_review: 2026-11-20
status: active
---

# Agent Workflow Enforcement Patterns

Snapshot of the AI-coding-agent SDD + orchestration landscape as of May 2026, plus
the core finding: **how instruction files make a stochastic agent comply with a
multi-step workflow.** All GitHub numbers verified against the API on 2026-05-20.

Context: this came out of a dwarves-kit session researching "Claude + agents + SDD
for SDLC." dwarves-kit is a minimal Claude Code workflow kit (hooks + commands +
agents + 1 skill) whose differentiator is an enforced verification pipeline
(worker → task-verifier → fix-agent retry, max 2).

---

## Part 1, The three axes (mental model)

The biggest clarification: people lump three different things under "Claude + agents + SDD."

```
SPEC-DRIVEN              DISCIPLINE-DRIVEN           HARNESS-DRIVEN
"what to build"          "how the agent works"       "make the repo agent-ready"
Spec Kit, OpenSpec       superpowers                 harness-experimental, AGENTS.md
   │                          │                            │
artifact = spec.md       artifact = enforced          artifact = AGENTS.md +
                         process (TDD, review)        story packets + decision records
```

SDD itself has a sub-spectrum (from Martin Fowler's team's reference comparison):

| Stance | Meaning | Example |
|---|---|---|
| spec-first | spec generates code once, then you edit code | Kiro, mostly Spec Kit |
| spec-anchored | spec persists and evolves across the feature's life | OpenSpec |
| spec-as-source | code is disposable, regenerated from spec (`// DO NOT EDIT`) | Tessl |

dwarves-kit sits at the seam: spec-driven lifecycle + a slice of discipline (the verification loop).

---

## Part 2, Landscape inventory (verified counts, 2026-05-20)

### Official Anthropic (primitives, not a product)
Anthropic ships **no product called "SDD."** Canonical spec pattern: have Claude
interview you with `AskUserQuestion` → write `SPEC.md` → start a *fresh session* to execute.
Primitives: plan mode, subagents, hooks, Skills (now an open standard, agentskills.io, Dec 2025),
plugins + marketplaces (public beta), Claude Agent SDK (renamed from Claude Code SDK, Sep 2025).
Methodology docs worth reading: "Building Effective Agents" (Dec 2024, prefer simple composable
patterns over frameworks) and "Building agents with the Claude Agent SDK" (Sep 2025, verify loop
tiered **rules/code > visual > LLM-as-judge**, directly endorses dwarves-kit's worker→verifier→fix shape).

### Spec-first frameworks
| Tool | Maintainer | Stars | Flow | Claude fit |
|---|---|---|---|---|
| GitHub Spec Kit | GitHub | 103.3k | `/constitution → /specify → /plan → /tasks → /implement` | model-agnostic, 30+ agents |
| OpenSpec | Fission-AI | 49.3k | `propose → apply → archive` (delta specs for brownfield) | agnostic, MIT |
| BMAD-METHOD | BMad Code LLC | 47.7k | agent personas (PM/Architect/SM/Dev/QA) + agile workflows | agnostic; custom license |
| Kiro | AWS | (closed) | `requirements.md → design.md → tasks.md` + steering + hooks | Bedrock-only, Claude under hood |
| Tessl | Guy Podjarny (ex-Snyk) | (closed beta) | spec-as-source-of-truth; $125M funded | agnostic via MCP |
| spec-workflow-mcp | Pimzino (solo) | 4.2k | Requirements→Design→Tasks + approval dashboard | any MCP host |

### Agent orchestration (CC-native + parallel UIs)
| Tool | Stars | Adds | Spec discipline |
|---|---|---|---|
| Claude-Flow / Ruflo | 53.2k | swarm + SPARC methodology | high |
| Ouroboros | 4.2k | Seed-spec → execute → evaluate → evolve; "Ralph" loop | highest |
| SuperClaude | 22.9k | `/sc:brainstorm → design → workflow → implement → test` + personas | medium |
| Conductor / Vibe Kanban / Claude Squad | mixed | N agents in parallel worktrees, diff-review | none |

Churn worth knowing: Roo Code **archived 2026-05-15** (migrate to Kilo Code); Vibe Kanban's
company shut down ~Apr 2026 (community-maintained now); Claudia → opcode (stalled since Oct 2025);
claude-flow renamed to ruflo.

### Autonomous coding agents (model-agnostic, Claude-friendly)
OpenHands (74.2k, ex-OpenDevin), Cline (62.0k, Plan/Act modes), Aider (45.0k, architect/editor
two-model split), Goose (45.6k, Block/aaif). LangGraph / CrewAI / AutoGen are the lower-level
libraries you'd use to *build* one.

### Personal/opinionated harnesses
- **obra/superpowers** (Jesse Vincent / Prime Radiant), most popular CC plugin; discipline-driven,
  auto-triggering skills, mandatory TDD, subagent dispatch with two-stage review. The framework
  that runs in our own Claude Code sessions.
- **hoangnb24/harness-experimental** (269★, 100% shell, v0), "Harness Engineering": the repo
  itself is the operating environment. Risk-tiered intake + decision records the next agent inherits.

---

## Part 3, The harness/orchestration layer (the core finding)

The thing dwarves-kit is missing is the **orchestrator layer**: a single instruction file
(`AGENTS.md` / `CLAUDE.md` / `using-superpowers` SKILL) that sequences atomic skills into an
enforced end-to-end workflow. Atomic skills = capabilities. Orchestrator = the law that says
"these phases, this order, do not skip, here are the gates."

```
┌─────────────────────────────────────────────────────────┐
│  ORCHESTRATOR  (AGENTS.md / CLAUDE.md / using-superpowers)│  ← the missing layer
│  "follow these phases, in this order, do not skip"        │
├─────────────────────────────────────────────────────────┤
│  ATOMIC SKILLS / COMMANDS  (test, debug, commit, review)  │  ← what dwarves-kit has
├─────────────────────────────────────────────────────────┤
│  ENFORCEMENT SUBSTRATE  (loop / state-file / test-gate)   │  ← what actually works
└─────────────────────────────────────────────────────────┘
```

### harness-experimental's AGENTS.md, distilled

Required reading order (source-of-truth hierarchy): `README → HARNESS.md → FEATURE_INTAKE.md →
user spec → product/ → ARCHITECTURE.md → stories/ → TEST_MATRIX.md → decisions/`.

Task loop: classify input (6 types) → restate as work item → locate affected docs → check
TEST_MATRIX for proof gaps → pick a lane → do work → gate questions.

Risk-tiered lanes (the best idea in the repo):

| Lane | Trigger | Requires |
|---|---|---|
| tiny | 0-1 risk flags | patch directly, quick checks |
| normal | 2-3 flags | story file + validation expectations |
| high-risk | 4+ flags OR any hard gate | story folder + execution plan + design + ADR |

Risk checklist (10 dims): auth, authz, data models, audit/security, external systems, API
contracts, cross-platform, existing-behavior changes, weak coverage, multi-domain.
Decision logic verbatim: *"0-1 flags: tiny or normal, based on code impact. 2-3 flags: normal
with stronger validation. 4+ flags: high-risk."* Hard gates (auth, authz, data loss,
audit/security, external providers, weakened validation) force high-risk unless scope explicitly narrowed.

Enforcement quotes (verbatim):
- Completion: *"A task is done only when"* change completed/blocker documented, docs current,
  *"validation commands executed,"* harness gaps backlogged, final response details what changed.
- Anti-fabrication: *"Agents must not claim these commands pass until they exist and have been run."*
- Confirmation gates: ask before changing architecture, removing validation, changing source-of-truth
  hierarchy, altering risk rules, replacing workflows.
- Self-growth: *"The harness grows from friction."*

---

## Part 4, Verbatim enforcement quotes from the popular repos

These are the irreplaceable signal. Each repo treats the instruction file as a **state machine the
agent must walk**, not a reference doc.

### agent-os v1.x (buildermethods, Brian Casel), XML `<process_flow>/<step>`
- pre-flight: *"Read and execute every numbered step in the process_flow EXACTLY as the instructions
  specify."* / *"For any step that specifies a subagent ... you MUST use the specified subagent."*
- execute-task verify gate: *"VERIFY: 100% pass rate for task-specific tests"*; blocking after
  *"maximum 3 different approaches"*.
- post-flight self-audit: *"IF you notice a step wasn't executed according to its instructions,
  report your findings and explain which part ... were misread or skipped and why."*

### obra/superpowers, tone + rationalization-rebuttal
- `<EXTREMELY-IMPORTANT>` *"If you think there is even a 1% chance a skill might apply ... you
  ABSOLUTELY MUST invoke the skill ... This is not negotiable. You cannot rationalize your way out of this."*
- brainstorming `<HARD-GATE>`: *"Do NOT ... write any code ... until you have presented a design and
  the user has approved it. This applies to EVERY project regardless of perceived simplicity."*
- next-step lock-in: *"The terminal state is invoking writing-plans. ... The ONLY skill you invoke
  after brainstorming is writing-plans."*
- Red Flags table pre-rebuts the model's excuses: *"'This is just a simple question' → Questions are
  tasks. Check for skills."*

### github/spec-kit, externalized machine-checkable gates
- Every command opens: *"You MUST consider the user input before proceeding (if not empty)."*
- specify.md execution flow: *"If empty: ERROR 'No feature description provided'"*; quality loop
  *"Re-run validation until all items pass (max 3 iterations)."*
- plan.md constitution gate: *"Evaluate gates (ERROR if violations unjustified) ... Re-evaluate
  Constitution Check post-design."* (constitution.md is an externalized rule set, not inline prose.)
- implement.md STOP gate: *"If any checklist is incomplete ... STOP and ask ... Wait for user response
  ... If user says 'no' or 'wait' or 'stop', halt execution."*

### BMAD-METHOD, identity reprogramming + anti-deception
- V4 activation: *"alter your state of being, stay in this being until told to exit"*; *"STAY IN CHARACTER!"*
- *"MANDATORY INTERACTION RULE: Tasks with elicit=true require user interaction ... never skip
  elicitation for efficiency."*
- develop-story order-of-execution: *"Read next task → Implement → Write tests → Execute validations
  → Only if ALL pass, then update the task checkbox with [x]."*
- completion: *"Validations and full regression passes (DON'T BE LAZY, EXECUTE ALL TESTS and CONFIRM)."*
- v6 anti-deception: *"NEVER mark a task complete unless ALL conditions are met - NO LYING OR
  CHEATING"*; *"Verify ALL tests ... ACTUALLY EXIST and PASS 100%."*

### Cline Memory Bank, identity framing + forced re-read
- *"My memory resets completely between sessions ... I MUST read ALL memory bank files at the start
  of EVERY task - this is not optional."*
- *"REMEMBER: ... The Memory Bank is my only link to previous work."*
- Named trigger: *"update memory bank (MUST review ALL files)."*

### Ralph (Geoffrey Huntley), the outer loop IS the enforcement
- *"Ralph is a technique. In its purest form, Ralph is a Bash loop. `while :; do cat PROMPT.md |
  claude-code ; done`"*
- *"Before making changes search codebase (don't assume not implemented) using subagents."*
- *"DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS. DO IT OR
  I WILL YELL AT YOU."*
- self-updating runbook: *"When you learn something new ... update @AGENT.md using a subagent but keep it brief."*
- Honest caveat: *"There is no such thing as a perfect prompt ... it has evolved through continual
  tuning based on observation of LLM behaviour."*

### steipete/agent-rules, numbered Process + checklist self-audit
- check.mdc: *"DO NOT commit any code during this process ... Continue until all checks pass."*
- implement-task.mdc ends with a `- [ ]` checklist gate forcing a final self-audit pass.

### AGENTS.md standard, deliberately NOT an enforcement engine
- *"AGENTS.md is a README for agents."* Punts hard enforcement to the harness. Only guarantee:
  *"the agent will attempt to execute relevant programmatic checks and fix failures before finishing."*
- Structural mechanic it owns: *"the closest one takes precedence"* (nearest-file-wins).

---

## Part 5, The enforcement taxonomy (the learnable part)

Ranked by how much each actually raises compliance.

| Mechanism | Who uses it | Why it works |
|---|---|---|
| **Programmatic backpressure** (tests/lint gate completion) | Ralph, spec-kit, steipete, AGENTS.md | deterministic reject signal the model must satisfy |
| **Forced state-file re-read** every cycle | Cline, harness, Ralph | survives context reset; ground truth on disk not in window |
| **Outer bash `while` loop** | Ralph | process restart with fresh context; model can't "forget to continue" |
| **Harness re-injects rules each turn** | AGENTS.md / CLAUDE.md / .clinerules | rules keep biasing tokens as conversation grows |
| **Self-audit pass** | agent-os post-flight, steipete checklist | agent grades own compliance, reports skipped steps |
| **Pre-written excuse rebuttals** | superpowers Red Flags | pre-empts the rationalizations the model generates to skip steps |
| **Anti-fabrication clauses** | harness, BMAD ("NO LYING OR CHEATING") | targets the agent faking green tests |
| **Next-step lock-in** | superpowers ("terminal state") | each phase names the one legal next phase |
| **Identity / stake framing** | Cline, BMAD | role-played self-interest beats a bare imperative |

**The one insight:** *markdown cannot enforce a workflow on a stochastic agent, it only biases the
next token. Real enforcement comes from a mechanism outside the prose: an outer loop, a
re-read-this-file-every-time discipline, or a test gate that blocks completion. The markdown is the
intent; the loop/state/gate is the law.*

---

## Part 6, Implications for dwarves-kit

- dwarves-kit's verification pipeline (worker → task-verifier → fix-agent retry) is the
  **programmatic-backpressure** row, the strongest mechanism in the taxonomy. That is the moat;
  defend and sharpen it.
- What's missing is the **orchestrator layer** that sequences the atomic commands/agents into an
  enforced lifecycle. The harness-experimental AGENTS.md pattern is the model to study. **Update
  2026-05-24:** a better reference exists, `affaan-m/ECC`'s `ecc2/` Rust runtime (worktree-isolated
  multi-session manager + SQLite store, alpha). See `research/2026-05-24-ecc-vs-dwarves-kit.md`.
- Two ideas to lift directly:
  1. **Risk-tiered intake** (tiny/normal/high lanes + hard-gate list), solves the "full ceremony on
     a one-line fix" problem Anthropic explicitly warns about.
  2. **Decision records the next agent inherits**, institutional memory; neither Spec Kit nor
     superpowers emphasize it.
- dwarves-kit already does orchestrator-layer writing without naming it (its CLAUDE.md "When to ask
  vs act" decision tree, tool-selection order).

### Reference URLs
- Spec Kit: github.com/github/spec-kit · OpenSpec: github.com/Fission-AI/OpenSpec
- superpowers: github.com/obra/superpowers · harness-experimental: github.com/hoangnb24/harness-experimental
- agent-os: github.com/buildermethods/agent-os · BMAD: github.com/bmad-code-org/BMAD-METHOD
- Cline Memory Bank: docs.cline.bot/prompting/cline-memory-bank · Ralph: ghuntley.com/ralph
- steipete/agent-rules · agents.md · Martin Fowler "Understanding SDD": martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html
- ECC: github.com/affaan-m/ECC (added 2026-05-24, see `research/2026-05-24-ecc-vs-dwarves-kit.md`)
