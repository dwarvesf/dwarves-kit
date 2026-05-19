# Architecture

How dwarves-kit fits together. Read PHILOSOPHY.md first for the WHY; this file is the WHAT and HOW.

## Component layout

The kit ships five kinds of artifact. Each maps to a Claude Code primitive:

| Kit dir | CC primitive | Trigger | Count (v1.5.1) |
|---|---|---|---|
| `hooks/` | Hook | Event (PreToolUse, Stop, StatusLine, etc.) | 12 |
| `commands/` | Slash command | Human typing `/user:<name>` | 12 |
| `agents/` | Custom subagent | Dispatched by a command via Task tool | 9 |
| `skills/` | Skill | Claude auto-triggered from skill description | 1 |
| `rules/` | Path-scoped rules | Active when Claude reads matching files | 2 templates |

The kit is intentionally flat. Component dirs sit at the top of the repo, not nested under `src/`, because the kit IS a flat set of prompts and bash scripts; there is no compilation step that justifies a `src/` boundary.

## Data flow through `.planning/SPEC.md`

`.planning/SPEC.md` is the shared contract for the full lifecycle. It is the single source of truth that crosses command boundaries:

```
/user:think      reads:  user idea (chat)
                 writes: .planning/DECISION-BRIEF.md  (if BUILD)

/user:spec       reads:  .planning/DECISION-BRIEF.md, codebase via 4 research agents
                 writes: .planning/SPEC.md  (Status: DRAFT)
                         .planning/research/{stack,features,architecture,pitfalls}.md

/user:spec-validate  reads:  .planning/SPEC.md
                     writes: .planning/SPEC.md  (Status: VALIDATED) or comments

/user:execute    reads:  .planning/SPEC.md
                 writes: code, tests, .planning/SPEC.md task checkmarks, decision log
                 dispatches: worker -> task-verifier -> fix-agent (retry max 2)

/user:next       reads:  .planning/SPEC.md
                 writes: code, tests; you drive verification

/user:review     reads:  git diff, .planning/SPEC.md
                 writes: .planning/REVIEW.md

/user:review-team  reads:  git diff
                   dispatches: 3 lens-reviewers in parallel + security-auditor
                   writes:  .planning/REVIEW-{security,architecture,test-coverage}.md

/user:docs       reads:  git diff
                 writes: README.md, CHANGELOG.md, other docs as drift dictates

/user:ship       reads:  .planning/SPEC.md, .planning/REVIEW*.md, VERSION
                 gate:   blocks if review verdict is FIX-REQUIRED
                 writes: VERSION, CHANGELOG.md entry, git tag, PR

/user:retro      reads:  .planning/SPEC.md, git log
                 writes: docs/retro/v<version>.md
```

**Convention split (kit-on-kit vs downstream projects)**: the diagram above describes the downstream-project flow, where hooks/commands write to `.planning/SPEC.md`. For the KIT ITSELF as a project, specs are drafted directly at `docs/specs/SPEC-NNN-<slug>.md` and tracked in place via a `Status:` header (DRAFT / VALIDATED / SHIPPED). No migration step. See ADR-0002.

## Verification pipeline (the load-bearing piece)

```
worker subagent completes task
  v
task-verifier (read-only) checks acceptance criteria + tests
  +--> PASS:  mark done in .planning/SPEC.md, continue
  +--> FAIL:fixable:  dispatch fix-agent (write-scoped, retry_count < 2)
  |     |
  |     v
  |   re-run task-verifier
  +--> FAIL:escalate (or retry >= 2):  stop, ask human
```

Read-only verifier and write-scoped fix-agent are different subagents on purpose. The verifier cannot "fix" things by silently rewriting code; it can only report. The fix-agent is bounded by the scope the verifier names. See ADR-0005.

## Collaborative Design Protocol

When an agent encounters a 2+ way design decision during implementation, it follows this 5-step protocol. Referenced by `agents/reviewer.md`, `agents/security-auditor.md`, `commands/execute.md`. Original ADR: 0007.

### When to invoke
- 2+ valid implementation approaches and the choice materially affects the outcome
- A decision is irreversible or expensive to undo (data model, API contract, architecture pattern)
- The spec is ambiguous and the agent must interpret intent

Do NOT invoke for:
- Obvious single-approach tasks (fix a typo, add a missing import)
- Style decisions covered by project rules (naming, formatting)
- Decisions already made in the spec's Decision Log

### The 5 steps

**Step 1: Question.** State the decision in one sentence.
```
DECISION NEEDED: Should user auth use JWT tokens or session cookies?
```

**Step 2: Options.** 2-3 options, each with what / tradeoff / when-it-wins.
```
OPTION A: JWT tokens
  + Stateless, scales horizontally, good for API-first
  - No server-side revocation without blacklist
  Best when: multiple clients (web + mobile), microservices

OPTION B: Session cookies
  + Server-side revocation, simpler security model
  - Requires session store (Redis), sticky sessions for scale
  Best when: single web app, strong revocation requirements

OPTION C: JWT + refresh token rotation
  + Stateless access + revocable refresh
  - More complex, two token types to manage
  Best when: need both API flexibility and revocation
```

**Step 3: Recommendation.** Which option, and why.
```
RECOMMENDATION: Option A (JWT tokens)
REASON: The spec describes an API consumed by web + mobile. No revocation
requirement is mentioned. JWT is simpler for this use case.
```

**Step 4: Decision.** Mode-dependent.
- **Lead mode**: Pause and ask the human. Use AskUserQuestion if available.
- **Coder mode / subagent**: Orchestrator or verifier picks. If the recommendation aligns with the spec, proceed; if it contradicts, escalate.
- **Autonomous mode** (/execute): Proceed with the recommendation. Log it. The task-verifier will catch misalignment.

**Step 5: Record.** Append to `.planning/SPEC.md` Decision Log:
```
- DEC-[N]: [decision] -- [rationale] -- [alternatives rejected] -- [who decided: human/orchestrator/auto]
```

### Activation lines

In an agent prompt:
```
When you encounter a decision with 2+ valid approaches, follow the
Collaborative Design Protocol in docs/architecture.md. Present options,
recommend one, and proceed according to your mode (lead/coder/autonomous).
```

In a command that dispatches an agent:
```
## Decision mode
[lead: pause for human approval / autonomous: proceed with recommendation and log]
```

The orchestrator in `/execute` defaults to `autonomous` for worker subagents (the verifier catches bad decisions after the fact) and `lead` when the user is running `/next` manually.

## Dependencies

### Required
| Tool | Why | Install |
|---|---|---|
| jq | Parse JSON in hook scripts; merge settings.json | `brew install jq` (macOS), `apt install jq` (Linux) |
| git | Branch detection, diff for review, commit for ship | Pre-installed on most systems |
| Claude Code | The agent runtime the kit extends | `npm install -g @anthropic-ai/claude-code` |

### Recommended
| Tool | Why | Install |
|---|---|---|
| Context Hub (chub) | Curated API docs prevent hallucinated APIs | `npm install -g @aisuite/chub` |
| Context7 | Library docs via MCP (React, Next.js, etc.) | MCP server, connect in Claude Code settings |
| codebase-memory-mcp | AST-level codebase indexing for large projects | MCP server, connect in Claude Code settings |
| trash (macos-trash) | Safe delete alternative (safety-gate suggests it) | `brew install macos-trash` |

### Formatters auto-detected by `hooks/auto-format.sh`
| Formatter | Languages | Install |
|---|---|---|
| prettier | JS, TS, CSS, JSON, MD, HTML | `npm install -g prettier` or project-local |
| gofmt | Go | Bundled with Go |
| ruff | Python | `uv tool install ruff` or `pip install ruff` |
| black | Python (fallback if ruff not found) | `pip install black` |
| rustfmt | Rust | Bundled with Rust toolchain |

The hook detects in this order: project-local binary, global binary, npx cache only (`npx --no`). It never downloads from the network mid-edit (regression fix in v1.1).

## Where things write to disk

Beyond the repo itself, the kit writes to:

| Path | What | Who writes |
|---|---|---|
| `~/.claude/dwarves-kit/logs/anti-rationalization.log` | Blocked Stop-event patterns | anti-rationalization.sh |
| `~/.claude/dwarves-kit/logs/safety-gate.log` | Blocked destructive Bash commands | safety-gate.sh |
| `~/.claude/dwarves-kit/logs/spec-drift-guard.log` | Files created outside the spec | spec-drift-guard.sh |
| `~/.claude/dwarves-kit/logs/slop-cleaner.log` | Bloat detections | slop-cleaner.sh |
| `.claude/session-state/last-state.md` | Latest session snapshot | session-state-save.sh |
| `.claude/session-state/archive/*` | Last 10 rotated snapshots | session-state-save.sh |

Logs are the eval corpus for future prompt optimization. See PHILOSOPHY.md, "AutoResearch optimization" section.

## Install paths

Two paths, do not run both. See ADR-0009.

1. **Plugin install** (recommended): `/plugin marketplace add dwarvesf/dwarves-kit` + `/plugin install dwarves-kit@dwarves-marketplace`. Uses `.claude-plugin/plugin.json` + `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}` references. No `statusLine` (v1 plugin schema gap).
2. **Bash install** (alternative): `bash install.sh`. Uses root `settings.json` with absolute paths. Configures `statusLine`. Requires `jq`, `git`, `bash`.
