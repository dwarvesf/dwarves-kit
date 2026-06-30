# Architecture

How dwarves-kit fits together. Read PHILOSOPHY.md first for the WHY; this file is the WHAT and HOW.

## Component layout

The kit ships five kinds of artifact. Each maps to a Claude Code primitive:

| Kit dir | CC primitive | Trigger |
|---|---|---|
| `hooks/` | Hook | Event (PreToolUse, Stop, StatusLine, etc.) |
| `commands/` | Slash command | Human typing `/kit:<name>` |
| `agents/` | Custom subagent | Dispatched by a command via Task tool |
| `skills/` | Skill | Claude auto-triggered from skill description |
| `rules/` | Path-scoped rules | Active when Claude reads matching files |

The kit is intentionally flat. Component dirs sit at the top of the repo, not nested under `src/`, because the kit IS a flat set of prompts and bash scripts; there is no compilation step that justifies a `src/` boundary.

Two dirs hold bash that is not a CC primitive: `tests/` (the suites) and `lib/` (deterministic command-helper bash that a command invokes but that is not event-triggered, so it does not belong in `hooks/`). Today `lib/` holds `dispatch-gate.sh` (the pure-bash disjointness gate + drift guard `/kit:dispatch` runs, ADR-0019), `lane-classify.sh` (the deterministic task-type -> risk-lane classifier `/kit:assign` + `/kit:dispatch` call, plus the advisory `check` floor guard `/kit:assign` runs after a lane is chosen to flag an under-sized choice; warn + log, never block), `backlog.sh` (the Active queue rendered as a kanban board + the mechanical state flips behind `/kit:assign --next`, SPEC-055), and `goal-registry.sh` (the cross-session running-goal registry `/kit:assign` claims into and `/kit:start` lists, ADR-0022; it sources `dispatch-gate.sh` to reuse the one disjointness rule), `task-type-classify.sh` (the deterministic task -> work-type classifier, SPEC-054/057/060), `gate-ledger.sh` (the per-run gate ledger + START routing record, ADR-0024/SPEC-061), `proof-gate.sh`/`proof-ledger.sh` (the proof-of-done class + ship-gate ledger, SPEC-016 line), and `lane-telemetry.sh` (the read-side aggregator over the run ledgers: `report` + `misfires`, reviewed at `/kit:retro` Step 1d, SPEC-061). A helper earns a place in `lib/` only when it must be unit-testable in isolation (all are); one-off bash a command runs inline stays inline (kit-health, ship).

## Data flow through `docs/specs/SPEC-NNN-<slug>.md`

> The front door to all of this is [`AGENTS.md`](../AGENTS.md) (repo root): the tool-agnostic operate-contract that any runtime reads first; `CLAUDE.md` and `WORKFLOW.md` point at it rather than restate it. The imperative companion to the descriptive map below is [`WORKFLOW.md`](../WORKFLOW.md) (repo root): the same lifecycle phrased as the contract an agent follows, with risk-tier lanes (including the `backfill` brownfield lane: review an existing codebase and write the operating-layer docs, doc-output only, no app-behavior change) and the gate at each boundary.

`docs/specs/SPEC-NNN-<slug>.md` is the shared contract for the full lifecycle. It is the single source of truth that crosses command boundaries:

```
/kit:think      reads:  user idea (chat)
                 writes: docs/specs/DECISION-BRIEF.md  (if BUILD)

/kit:spec       reads:  docs/specs/DECISION-BRIEF.md, codebase via 4 research agents
                 writes: docs/specs/SPEC-NNN-<slug>.md  (Status: DRAFT)
                         docs/research/{stack,features,architecture,pitfalls}.md

/kit:spec-validate  reads:  docs/specs/SPEC-NNN-<slug>.md
                     writes: docs/specs/SPEC-NNN-<slug>.md  (Status: VALIDATED) or comments

/kit:execute    reads:  docs/specs/SPEC-NNN-<slug>.md
                 writes: code, tests, docs/specs/SPEC-NNN-<slug>.md task checkmarks, decision log
                 dispatches: worker -> task-verifier -> fix-agent (retry max 2)

/kit:next       reads:  docs/specs/SPEC-NNN-<slug>.md
                 writes: code, tests; you drive verification

/kit:review     reads:  git diff, docs/specs/SPEC-NNN-<slug>.md
                 writes: ## Review section in the active spec (else inline)

/kit:review-team  reads:  git diff
                   dispatches: security-auditor (security) + reviewer agent x2 (architecture, test-coverage)
                   writes:  ## Review section (per-lens subsections) in the active spec (else inline)

/kit:docs       reads:  git diff
                 writes: README.md, CHANGELOG.md, other docs as drift dictates

/kit:ship       reads:  docs/specs/SPEC-NNN-<slug>.md (incl. its ## Review verdict), VERSION
                 gate:   blocks if the spec's ## Review verdict is DO NOT SHIP
                 writes: VERSION, CHANGELOG.md entry, git tag, PR

/kit:retro      reads:  docs/specs/SPEC-NNN-<slug>.md, git log
                 writes: docs/retro/v<version>.md
```

**Unified convention (ADR-0010)**: the diagram above applies to both the kit itself and downstream projects, which now share one spec location: `docs/specs/SPEC-NNN-<slug>.md`, tracked in place via a `Status:` header (DRAFT / VALIDATED / SHIPPED). No planning-dir split, no migration step. `docs/specs/` is the sole spec location; the legacy planning-dir deprecation fallback has been removed (SPEC-010). See ADR-0010 (supersedes ADR-0002).

**V-model lifecycle lens (ADR-0018, reframed 2026-05-23)**: the kit's workflow is shaped as a V: a **BUILD arm** (left, decompose + implement) and a **TEST arm** (right, plan + execute + report), with Code at the vertex. Each static-review gate verifies one artifact at its phase (not a separate lane); they are not test levels. The V-model is a lens over WORKFLOW.md's cycle table, not a second phase list. Feature-rejection criterion #2 is count-agnostic: "serves fewer than 2 lifecycle phases." See ADR-0018 (SPEC-031 C2; build-left/test-right reframe 2026-05-23).

**Concurrency boundary (ADR-0019 + ADR-0020 + ADR-0022)**: the kit permits concurrency along two axes and stops short of a DAG / wave scheduler / crash-recovery runtime (handed to GSD v2).
- **In-session (ADR-0019 + ADR-0020):** **bounded cross-goal fan-out**, one lead session orchestrating N isolated worktree workers over disjoint `VALIDATED` specs, behind a disjointness gate, with lead-owned convergence. ADR-0019 supersedes the four standing "one session / sequential" boundaries (SPEC-032 C1); ADR-0020 locks the dispatch primitive to in-session `Agent(run_in_background, isolation:worktree)` workers (Path A, proven by the SPEC-033 spike), not the read-only `claude agents` view. The implementing surface is `/kit:dispatch` (SPEC-032); the convergence contract is SPEC-031.
- **Cross-session (ADR-0022):** **one operator's N concurrent same-machine sessions over disjoint goals**, coordinated by a passive **running-goal registry** (`lib/goal-registry.sh`), one single-writer file per goal under `.git/kit-goals/`, reusing the same disjointness rule to refuse a goal that overlaps an active one, and serving as the cross-session monitor (`list`, surfaced in `/kit:start`) plus each goal's attempt log. ADR-0022 supersedes the "multi-session stays L5" boundary (SPEC-036 C4) for exactly this case. What stays L5 (Nimbalyst / GSD v2): coordination across machines, 3+ live human operators, and goal-ordering chains. The registry records and compares; it never schedules, sequences, or merges.

Where they meet: the native `claude agents` view monitors the subagents inside *one* session; the running-goal registry is the kit-level roll-up that lists every concurrent goal *across* sessions, tagged with its goal + lane. `/kit:dispatch` also registers its in-session workers, so one `goal-registry list` shows both axes.

## Command and agent V-phase inventory

Every command and agent mapped to its V-model arm, grouped so the left side (BUILD) and the right side (TEST) read at a glance. The **left arm** decomposes and implements; the **right arm** plans, executes, and reports the tests; **Code** is the vertex. **Static quality gates** verify each artifact by review (not test execution) at its phase; **cross-phase** entries sit outside it.

Total: 25 commands + 11 agents = **36 entries** (10 build · 3 code · 6 test · 9 gate · 8 cross-phase).

### Left arm: BUILD (decompose + implement)

| Entry | Type | V-phase | Arm | Note |
|---|---|---|---|---|
| `/kit:think` | command | Brief | build | Stress-tests the idea before any spec; primary output is `DECISION-BRIEF.md` |
| `/kit:assign` | command | Requirement | build | Turns a backlog item into a goal draft; routes it into the right lane |
| `/kit:grill` | command | Requirement (intake) | build | Universal intake interview between type classification and the phase-0 Done=; type-shaped one-question-at-a-time, write-as-you-go (SPEC-058) |
| `/kit:design` | command | Solution-design | build | Opt-in interactive beat between think and spec; shapes the solution one decision at a time |
| `/kit:spec` | command | Spec | build | Produces `SPEC-NNN-<slug>.md` (Status: DRAFT); dispatches 4 research agents for brownfield context |
| `/kit:ui-design` | command | UI design | build | Opt-in; writes UI brief, delegates generation, routes through visual-team, auto-revises (bounded) |
| `research-architecture` | agent | Spec (brownfield) | build | Maps architecture patterns; dispatched by /spec; read-only |
| `research-features` | agent | Spec (brownfield) | build | Maps existing features in target area; dispatched by /spec; read-only |
| `research-pitfalls` | agent | Spec (brownfield) | build | Finds landmines and risks before new work; dispatched by /spec; read-only |
| `research-stack` | agent | Spec (brownfield) | build | Maps technology stack; dispatched by /spec; read-only |

### Vertex: BUILD (code)

| Entry | Type | V-phase | Arm | Note |
|---|---|---|---|---|
| `/kit:execute` | command | Build + test dispatch | code | The vertex; dispatches worker → task-verifier → fix-agent per task (max 2 retries); the test agents it dispatches are listed under the TEST arm |
| `/kit:next` | command | Build | code | Manual-drive variant of execute; loads next undone task, lets the human control the loop |
| `fix-agent` | agent | Build (targeted fix) | code | Applies bounded fixes named by task-verifier; scoped to specific files/issues; no feature additions |

### Right arm: TEST (plan, execute, report)

| Entry | Type | V-phase | Arm | Note |
|---|---|---|---|---|
| `/kit:test-plan` | command | Test design (write tests) | test | Opt-in; derives the coverage matrix from AC before /execute so the build has a planned target; the kit's single test-design step |
| `/kit:test-plan-review-team` | command | Test design (review) | test | Opt-in; 5 lenses adversarially critique the `## Test plan` + bounded revise loop, between /test-plan and /execute; report-only (SPEC-052) |
| `task-verifier` | agent | Unit / task test | test | Runs each task's AC + the project suite after each worker; read-only; primary enforcer in the verification pipeline |
| `integration-checker` | agent | Integration test | test | Verifies cross-task wiring at /execute Step 4 for multi-task specs; read-only |
| `/kit:ship` | command | Acceptance test (gate) | test | Executes the acceptance check; blocks on DO-NOT-SHIP; bumps version, writes changelog, cuts PR |
| `/kit:verify` | command | Test re-run (on demand) | test | Read-only re-run of the unit + integration levels (dispatches `task-verifier` + `integration-checker`) against the active spec; no rebuild, no fix; the right arm on demand |

### Static quality gates (static verification of each artifact; review, not test execution)

| Entry | Type | V-phase | Arm | Note |
|---|---|---|---|---|
| `/kit:spec-validate` | command | Spec review | gate | Adversarial pre-build gate; 5 lenses attack the spec; sets Status: VALIDATED |
| `/kit:devs-team` | command | Design critique | gate | Opt-in; 5 engineering lenses stress-test the solution design before the spec hardens |
| `/kit:review` | command | Code review | gate | Single-pass paranoid review; security, architecture, regressions, edge cases |
| `/kit:review-team` | command | Code review | gate | Parallel variant; dispatches the `reviewer` agent x3 (security / architecture / test-coverage lenses) |
| `/kit:visual-team` | command | Visual critique | gate | Opt-in; 5 design lenses critique UI output; mirrors review-team for visual work |
| `/kit:docs` | command | Doc sync | gate | Diffs code vs docs and patches drift; dispatches doc-verifier before committing |
| `reviewer` | agent | Code review | gate | Focused single-lens reviewer; dispatched by /review-team with a lens (architecture / test-coverage; security now uses security-auditor) |
| `security-auditor` | agent | Security review | gate | Deep security analysis; dispatched by `/kit:review-team` as the security reviewer (replacing the generic reviewer security lens); also invocable directly for an ad-hoc deep pass |
| `doc-verifier` | agent | Docs verification | gate | Verifies doc claims against live codebase after /docs updates; read-only; the doc-sync twin of task-verifier |

### Cross-phase (outside the V)

| Entry | Type | V-phase | Arm | Note |
|---|---|---|---|---|
| `/kit:retro` | command | Reflect | cross-phase | Post-ship narrative mirror of the entire V; captures learnings, not a gate |
| `/kit:start` | command | Session entry | cross-phase | Detects project state and recommends the right next command; never executes |
| `/kit:adopt` | command | Repo onboarding | cross-phase | Injects the operate-contract + proof marker + a CLAUDE.md pointer into a target repo (idempotent, via `lib/adopt.sh`); wires the classifiers so the ship-gate engages there |
| `/kit:kit-health` | command | Maintainer audit | cross-phase | Self-assessment against PHILOSOPHY.md; run before tagging; not part of the normal cycle |
| `/kit:absorb` | command | Upstream maintenance | cross-phase | Audits Credits drift + seed-rescan; proposal-only; maintainer-only connective tissue |
| `/kit:debug` | command | Bug lane (off-cycle) | cross-phase | Off-cycle loop: root cause before any fix; evidence ledger; 3-fix architecture wall |
| `/kit:dispatch` | command | Concurrent fan-out | cross-phase | Fans out N disjoint VALIDATED specs into isolated worktree workers behind the disjointness gate (`lib/dispatch-gate.sh`); drift-guards each; lead-owned convergence; no DAG / no auto-merge (ADR-0019) |
| `responding-to-review` | agent | Review response | cross-phase | Responds to review feedback with technical rigor; proposes fixes, does not apply them |
| `/kit:draft-agent` | command | Meta-tooling | cross-phase | Generates a subagent (or sub-goal file) via the `meta-agent`; installs the subagent by default (roster-sync + `cp` to `~/.claude/agents/`); `--draft` stops at a staged draft |
| `meta-agent` | agent | Meta-tooling | cross-phase | Drafts a new subagent definition or mega-goal sub-goal file from a one-line description; determines minimal tools; the subagent writes to staging only, the command promotes/installs |

**Classification notes:**
- The right arm is *test execution*; the static gates are *review*. Both are "verification" loosely, but only the right arm runs tests. `/kit:spec-validate`, `/kit:review`, `/kit:docs` review; `task-verifier`, `integration-checker`, `/kit:ship` test.
- `/kit:execute` is the vertex (code); it also dispatches the right-arm test agents (`task-verifier`, `integration-checker`), which are listed once, under the TEST arm.
- Cross-phase entries span arms or sit outside the V (debug, maintenance, session routing). Forcing them onto one arm would misrepresent them.
- A new command or agent adds exactly one row; the parity check asserts row count == live file count to keep this table from drifting.

## Command vs agent (the layering rule)

A **command** is a control-plane *trigger*: a human or the `/goal` loop invokes it to enter a phase, gate a decision, or orchestrate work (it may dispatch agents). An **agent** is a data-plane *actor* a command (or Claude) dispatches to do one job in an isolated context; it is never invoked directly.

Decision test, in order:

1. Does a human or the loop **trigger it directly**? -> command.
2. Does the work need a **fresh / isolated context** (read-only verification so the author's bias cannot leak) or **parallel fan-out** (N lenses at once)? -> agent.
3. Does it **sequence or gate** other steps? -> command.
4. Is it a **repeatable single-job actor** invoked by a step? -> agent.

The load-bearing reason agents exist is **isolation**, not "sub-functions" (PHILOSOPHY "verify with a fresh context, not self-report"). A job needing neither isolation nor parallelism is steps inside a command, not an agent (that is why `/kit:spec-validate`'s 5 lenses are inline: they share the spec's context).

Two failure modes this rule catches:

- **Phantom command**: a command for something only ever dispatched by a step (you would never type `/kit:task-verify`). Verification is an agent, not a command.
- **Orphan agent**: an agent no command dispatches and the user cannot invoke is dead code. Every agent needs a trigger.

This is the command/agent half of the ID-036 layering contract (orchestration / agents / hooks); the hook half is declared in the next section.

## Hook fallback layer (closing the layering contract)

The three layers compose orchestration-first (SPEC-084 / ID-036):

```
Layer 1  ORCHESTRATION  AGENTS.md operate-contract + commands + type loops.
         (LLM-driven)   Decides and acts. ALL guidance lives here.
Layer 2  AGENTS         Isolated step-actors (previous section). Exist for
                        fresh-context verification and parallel fan-out.
Layer 3  HOOKS          Fallback enforcement ONLY. A hook exists when, and
         (fallback)     only when, prose instruction is not enough.
```

Hooks are the bottom layer by design: each one costs latency on every matching
event and risks false-positive friction, so the kit reaches for one last, as
fallback for failure modes that survive prose instruction (rationalizing
"done", rushing a destructive command, reading a secret "just to check",
shipping without proof). Everything an instructed LLM reliably does belongs in
Layer 1.

**Placement decision test** for the next proposed hook, in order:

1. Can the orchestration layer be trusted to do it every time when told in
   prose? -> Layer 1 (AGENTS.md / a command). Not a hook.
2. Does the failure mode survive prose AND the damage is irreversible
   (destroyed files, leaked secret, polluted main, false "done")? -> HARD hook:
   blocks (exit 2 / deny).
3. Does it survive prose but the drift is recoverable and a human may
   legitimately override? -> ADVISORY hook: warns (exit 0 + context), never
   blocks.
4. Is there no judgment involved at all (formatting, state save, HUD)? ->
   CONVENIENCE hook: declared non-enforcement, so nobody mistakes auto-format
   for a guardrail.

**The inventory** (one row per `hooks/*.sh`; the parity check pins row count to
file count so this table cannot drift):

| Hook | Event | Class | Failure mode it backstops |
|---|---|---|---|
| `safety-gate` | PreToolUse Bash | hard | destructive deletes, push-to-main, force-push under deadline pressure |
| `secrets-guard` | PreToolUse Read/Edit/Bash | hard | reading secret files "just to check"; transcript is plaintext |
| `ship-gate` | PreToolUse Bash | hard | shipping without proof of done / recorded gates (ADR-0024 boundary) |
| `commit-format` | PreToolUse Bash | hard | drifting commit subjects (type, length, ticket-tag leakage) |
| `anti-rationalization` | Stop | hard | declaring work complete while rationalizing known-incomplete work |
| `spec-drift-guard` | PreToolUse Write | advisory | creating files the active spec never mentions |
| `slop-cleaner` | Stop | advisory | long-session code bloat; suggests, never blocks |
| `context-readiness` | SessionStart | advisory | starting blind: injects spec/board state + an intent-first next step (SPEC-083) |
| `auto-format` | PostToolUse Write/Edit | convenience | none (idempotent formatting) |
| `output-offload` | PostToolUse * | advisory | oversized tool output bloating context; offloads the full payload to a file + nudges, never blocks |
| `statusline` | StatusLine | convenience | none (HUD) |
| `notification` | Notification | convenience | none (desktop notify) |
| `permission-auto-approve` | PermissionRequest | convenience | none (removes approve-20-times friction for read-only ops) |
| `session-state-save` | Stop | convenience | none (state persistence) |
| `pre-compact-backup` | PreCompact | convenience | none (session snapshot) |
| `post-compact-reinject` | PostToolUse compact | convenience | none (re-injects rules compaction stripped) |
| `codebase-index` | SessionStart (opt-in) | convenience | none (background indexing) |

**C3 reconciled.** PHILOSOPHY's "Guardrails over guidance" is bounded, not
blanket: guardrail = the hard subset, where trust fails AND damage is
irreversible. Everything else stays guidance in Layer 1, because a hard hook
is the most expensive enforcement the kit has (every event, every repo, every
false positive). ADR-0024 is the boundary discipline that keeps it cheap:
gates collect advisory evidence mid-flight and enforce once, at ship.

**Folded concerns, dispositioned.** ID-012 P2 (the autonomous-loop QA gate) is
a worked example of the placement test, not a new hook: the loop's QA is
Layer 1 (`/kit:verify` inside the loop) plus the existing `ship-gate` at the
boundary; rule 1 says prose suffices for the loop's own verify step, rule 2
already covers the ship boundary. ID-027 (the autonomy-gate lens) lands in
Layer 1 as a `/kit:spec-validate` Reviewer 4 bullet: a spec whose behavior
runs inside an autonomous loop must not let the loop make a scope /
architecture / risk decision without a human gate.

## State model

The kit keeps a small set of distinct state stores. Keeping them distinct prevents the "what's left vs what's active vs the contract" confusion (SPEC-005). Review output is not a separate store: it lives in the active spec as a `## Review` section (so concurrent worktrees and sessions never share a review file).

| Store | Committed? | Lifetime | Role |
|---|---|---|---|
| `_meta/BACKLOG.md` | yes (git) | durable | the queue of committed work ("what's left"); schema lives in that file |
| `docs/specs/SPEC-NNN-<slug>.md` | yes (git) | durable | the design contract per cycle ("the contract"); also carries the on-demand `## Review` section |
| `.claude/goals/<slug>.md` | no (gitignored) | ephemeral | candidate goal **drafts** ("what's active"); filesystem-authoritative, archive-on-ship lifecycle (ADR-0011, ADR-0023) |
| `.claude/goals/done/<slug>.md` | no (gitignored) | ephemeral | archived drafts whose `target_spec` shipped; moved here (never deleted), skipped by the render commands |
| `.git/kit-goals/<slug>.goal` | no (under `.git`, untracked) | run-time | the cross-session running-goal **registry** claim ("what's executing now"); the lock that keeps N same-machine sessions disjoint (ADR-0022) |
| `.claude/last-goal.md` | no (gitignored) | ephemeral | the built-in `/goal`'s single active slot; the kit never writes it |

**Draft vs registry, the two "goal" stores side by side.** A goal **draft** (`.claude/goals/<slug>.md`) is design-time candidate work, "what's active." A registry **claim** (`.git/kit-goals/<slug>.goal`) is the run-time lock, "what's executing now" across concurrent same-machine sessions. They are not duplicates: the slug is the shared key tying a draft to its claim. A draft is filesystem-authoritative (no derived cache, ADR-0023) and is moved to `done/` once its `target_spec` ships (`lib/goal-drafts.sh archive`, run by `/kit:ship`); a claim is created by `lib/goal-registry.sh claim` and released when the goal completes.

The active spec among these is resolved by the SPEC-005 rule (`docs/specs/`, branch-selected when several are live). The `/kit:start`/`/kit:next` rendering of the backlog queue + goal drafts is wired in SPEC-006; both enumerate top-level `.claude/goals/*.md` (a non-recursive glob), so archived drafts under `done/` are skipped.

## Verification pipeline (the load-bearing piece)

```
worker subagent completes task
  v
task-verifier (read-only) checks acceptance criteria + tests
  +--> PASS:  mark done in docs/specs/SPEC-NNN-<slug>.md, continue
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

**Step 5: Record.** Append to `docs/specs/SPEC-NNN-<slug>.md` Decision Log:
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
| `~/.claude/dwarves-kit/logs/secrets-guard.log` | Blocked secret-file reads (path + tool, never contents) | secrets-guard.sh |
| `~/.claude/dwarves-kit/logs/commit-format.log` | Blocked non-conventional commit subjects | commit-format.sh |
| `~/.claude/dwarves-kit/logs/spec-drift-guard.log` | Files created outside the spec | spec-drift-guard.sh |
| `~/.claude/dwarves-kit/logs/slop-cleaner.log` | Bloat detections | slop-cleaner.sh |
| `.claude/session-state/last-state.md` | Latest session snapshot | session-state-save.sh |
| `.claude/session-state/archive/*` | Last 10 rotated snapshots | session-state-save.sh |
| `.claude/debug/<slug>.md` | Per-bug evidence ledger (Symptoms / Root cause / Evidence / Eliminated / Fix attempts / Resolution) | /kit:debug |
| `.claude/debug/<slug>.log` | `[DEBUG Hn]`-tagged instrumentation output | /kit:debug |

All `.claude/` paths are gitignored (the kit ignores `.claude/`); downstream templates ignore it too.

Logs are the eval corpus for future prompt optimization. See PHILOSOPHY.md, "AutoResearch optimization" section.

## Install paths

Two paths, do not run both. See ADR-0009.

1. **Plugin install** (recommended): `/plugin marketplace add dwarvesf/dwarves-kit` + `/plugin install kit@dwarves-marketplace`. Uses `.claude-plugin/plugin.json` + `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}` references. No `statusLine` (v1 plugin schema gap).
2. **Bash install** (alternative): `bash install.sh`. Uses root `settings.json` with absolute paths. Configures `statusLine`. Requires `jq`, `git`, `bash`.

## SDLC state machine

The "## State model" above is the *data* state (the three stores). This is the *process*
state: the states a single unit of work moves through, and the guarded transitions
between them. It is the formal model behind `WORKFLOW.md`'s cycle/lanes (the rules) and
`MANUAL.md`'s "## Operator scenarios" (the operator-facing projection). The point of
declaring it is that at any moment Claude (and the operator) can answer four questions
without guessing: where am I, where can I go, what does each transition cost/require (the
guard), and how do I trigger it.

### States

| State | Meaning | Entry | Exit |
|---|---|---|---|
| `IDLE` | no active unit of work | session start; an item shipped/abandoned | intake |
| `TRIAGING` | intake: intent -> lane + (eventually) an ID | `/assign`, `/think`, "apply SDD", a vague brief | lane chosen |
| `DESIGNING` | solution exploration (iterative) | full lane, or "let's design" | solution approved |
| `SPECIFYING` | the spec is being written | `/spec` | spec `DRAFT` exists |
| `VALIDATING` | adversarial spec review | `/spec-validate` | `VALIDATED` or NEEDS REVISION |
| `BUILDING` | execution sub-machine (worker -> verifier -> fix -> integration) | `/execute`, `/next` | all tasks + integration PASS |
| `REVIEWING` | code review | `/review`, `/review-team` | verdict recorded |
| `DOCUMENTING` | doc sync + doc-verifier | `/docs` | docs match code |
| `SHIPPING` | ship pipeline | `/ship` | tagged/PR; spec `SHIPPED` |
| `REFLECTING` | retrospective | `/retro` | retro written |
| `DEBUGGING` | off-cycle debug sub-machine (iron law) | `/debug` | root cause + fix + human-confirm |
| `BLOCKED` | meta-state: parked, awaiting a human | "park", "I'm stuck", a hard stop, escalate | unblock / abandon |
| `SHIPPED` | terminal: the item is done | `/ship` completes | (re-open -> TRIAGING) |
| `ABANDONED` | terminal: the item is dropped | "kill it" | none |

### Master diagram

```text
                          ┌────────────────────────── re-open ("follow-up") ──────────────────────────┐
                          ▼                                                                            │
   ┌──────┐  intake     ┌──────────┐  lane=full      ┌───────────┐  approved   ┌────────────┐         │
   │ IDLE │ ──────────▶ │ TRIAGING │ ─────────────▶  │ DESIGNING │ ──────────▶ │ SPECIFYING │         │
   └──────┘             └────┬─────┘                 │ ⇄ iterate │             └─────┬──────┘         │
      ▲                      │ lane=normal           └───────────┘                   │ DRAFT          │
      │ shipped              │ (skip design)                                          ▼                │
      │                      ├──────────────────────────────────────────────▶  VALIDATING            │
      │                      │ lane=tiny: edit->verify->done (no spec)               │ VALIDATED       │
      │                      │ lane=bug ─────────────▶ DEBUGGING                      │  ▲ NEEDS        │
      │                      │ lane=backfill: docs only, no app code                  │  │ REVISION     │
      │                      ▼                                                        ▼  │              │
      │            ┌──────────────────────────────────────────────────────────▶ BUILDING ────────────┘
      │            │  guard: all tasks PASS + integration PASS                       │ ⇄ retry (fix<=2)
      │            │  guard (hard): verification pipeline, anti-rationalization      │ escalate
      │            ▼                                                                  ▼
      │        REVIEWING ◀── FIX THEN SHIP / DO NOT SHIP (loop back to SPECIFYING/BUILDING)
      │            │ SHIP / fixes applied
      │            ▼
      │       DOCUMENTING ──▶ SHIPPING ──▶ REFLECTING ──▶ (SHIPPED) ──▶ IDLE
      │                       │  guard (hard): DO-NOT-SHIP verdict, push-to-main blocker
      │                       │
   (any state) ──"park"/"stuck"/escalate──▶ BLOCKED ──resume──▶ (prior state)
   (any state) ──"kill it"──▶ ABANDONED (terminal)
   (any state) ──bug found──▶ DEBUGGING ──root cause+fix+confirm──▶ (prior state)
```

### Transition table (the contract)

| From | Trigger (phrase / command) | Guard | To |
|---|---|---|---|
| IDLE | "what's next" then pick; `/assign ID`; "apply SDD X"; vague brief | none | TRIAGING |
| TRIAGING | lane = full | scope confirmed | DESIGNING |
| TRIAGING | lane = normal | scope confirmed | SPECIFYING |
| TRIAGING | lane = tiny | trivial edit | BUILDING (no spec) |
| TRIAGING | lane = bug | a defect | DEBUGGING |
| DESIGNING | "iterate", redirect | per-section approval pending | DESIGNING |
| DESIGNING | "design is good, write the spec" | solution approved | SPECIFYING |
| SPECIFYING | `/spec` done | spec `DRAFT` exists | VALIDATING (full) / BUILDING (normal) |
| VALIDATING | `/spec-validate` verdict | VALIDATED | BUILDING |
| VALIDATING | NEEDS REVISION | revisions required | SPECIFYING |
| BUILDING | task FAIL:fixable | retries < 2 | BUILDING (fix-agent) |
| BUILDING | task FAIL:escalate / retries == 2 | unfixable | BLOCKED |
| BUILDING | "also do Y" / "amend the spec" | at a task checkpoint; completed tasks frozen; Status stays VALIDATED | SPECIFYING (amend, not restart) |
| SPECIFYING | resume via `/next` | amend recorded | BUILDING (resume) |
| BUILDING | all tasks done | **all PASS + integration PASS** (hard) | REVIEWING |
| REVIEWING | verdict SHIP / FIX-applied | not DO-NOT-SHIP | DOCUMENTING |
| REVIEWING | FIX THEN SHIP / DO NOT SHIP | findings open | SPECIFYING / BUILDING |
| DOCUMENTING | `/docs` done | doc-verifier PASS | SHIPPING |
| SHIPPING | `/ship` | **not DO-NOT-SHIP, not push-to-main** (hard) | REFLECTING |
| REFLECTING | `/retro` done | retro written | SHIPPED -> IDLE |
| any | "park" / "I'm stuck" | a blocker exists | BLOCKED |
| any | "kill it, not worth it" | operator confirms | ABANDONED |
| any | a bug surfaces | a defect | DEBUGGING |
| SHIPPED | "the shipped X needs a follow-up" | none | TRIAGING (new spec) |

### Sub-machines

- **BUILDING** expands to: `worker -> task-verifier -> {PASS | FAIL:fixable -> fix-agent (<=2) | FAIL:escalate} -> integration-checker`. The diagram is in `WORKFLOW.md` "## Flow and loop reference" (the execute pipeline), and the read-only contract is in "## Verification pipeline" above.
- **DEBUGGING** expands to: `Phase 1 Root cause -> Phase 2 Pattern -> Phase 3 Hypothesis -> Phase 4 Implementation`, under the iron law (no fix without a recorded root cause), guarded by the guess-fix guard. The diagram is in `WORKFLOW.md` "## Flow and loop reference" (the debug loop).

### Hard stops as guards (the only blockers)

| Hard stop | Guards the transition | Effect |
|---|---|---|
| safety-gate | any transition running destructive Bash | blocks the command |
| push-to-main | SHIPPING -> (the push) | blocks the push |
| anti-rationalization | BUILDING -> REVIEWING; any -> "done" | blocks premature/false done |
| verification pipeline | BUILDING -> REVIEWING | blocks if a task fails |

Everything else is advisory: it suggests the transition, it does not block it. The
implementing specs for the gap-closing transitions (the freeform front door, the
mid-flight amend) are in `docs/specs/`; this model is their acceptance reference.
