---
title: dwarves-kit spec workflow vs Claude Code builtin planning, and the orchestration gap
date: 2026-05-20
purpose: Clarify how dwarves-kit's planning workflow differs from Claude Code's builtin plan mode, and whether either ships a real orchestration layer. Use when deciding whether the kit's verification pipeline is "real" orchestration or prompt theatre, or when explaining the kit's value vs stock Claude Code.
source_repos: [dwarves-kit]
refresh_cadence: as-needed
next_review: 2026-08-20
status: active
---

# dwarves-kit spec workflow vs Claude Code builtin planning

## Terminology corrections (these change the answer)

- The kit has **no "plan skill."** Its only skill is `get-api-docs` (`skills/get-api-docs/SKILL.md`). Planning is done by **commands** (`/user:think` → `/user:spec` → `/user:execute`) that produce a **spec artifact**.
- Claude Code's builtin is **plan mode** (shift+tab, `EnterPlanMode` + `ExitPlanMode`), plus a read-only **`Plan` subagent**. Neither is a "skill."

So the real comparison is **kit spec-workflow vs Claude plan mode.**

## Side by side

| Dimension | Claude Code plan mode (builtin) | dwarves-kit spec workflow |
|---|---|---|
| Trigger | shift+tab, or `Plan` subagent | `/user:think`, `/user:spec`, `/user:execute` |
| Artifact | None. Plan lives in the chat | `.planning/SPEC.md` (downstream) or `docs/specs/SPEC-NNN.md` (kit itself) |
| Lifecycle | Ephemeral, single conversation | DRAFT → APPROVED/VALIDATED → SHIPPED, tracked in the file header |
| Enforcement | One approval gate, then nothing | Spec is the contract workers + verifiers check against |
| Scope | "Look before you leap" on one task | Multi-phase, task-broken-down, verified per task |
| Survives context loss | No | Yes (file on disk) |

Core difference in one line: **plan mode is a momentary read-only gate; the kit's spec is a persistent, machine-checkable contract.** Plan mode answers "should I do this?" once. SPEC.md keeps answering "did the worker actually do what we agreed?" after every task.

## Orchestration layer

**Claude Code builtin: no.** It ships primitives, not an orchestrator:
- `Task`/`Agent` to dispatch a subagent.
- plan mode as an approval gate.
- No retry-on-failure, no worker→verifier loop, no phase gating. The model improvises sequencing turn by turn.

**dwarves-kit: yes**, an explicit one, encoded in `/user:execute` (`commands/execute.md`):

```
worker (one per task, fresh context)
   ↓
task-verifier (read-only, checks acceptance criteria + tests)
   ├─ PASS ............. mark done in SPEC.md, next task
   ├─ FAIL:fixable .... fix-agent → re-verify   (loop, MAX_RETRIES=2)
   └─ FAIL:escalate ... stop, ask human
   ↓ after each phase
human checkpoint: (A) continue / (B) review / (C) stop
```

`commands/execute.md:140-169` holds the retry state machine (`MAX_RETRIES = 2`, escalate on the 3rd failure). 9 agents back it: `task-verifier`, `fix-agent`, `reviewer`, `security-auditor`, `responding-to-review`, and 4 `research-*` agents (`research-stack`, `research-features`, `research-architecture`, `research-pitfalls`).

## The honest caveat

The kit's "orchestration layer" is **prompt-encoded, not a runtime engine.** The orchestrator *is* Claude following pseudocode in `execute.md`. There is no scheduler process, no event store, no daemon. The retry loop works only as well as the model obeys the markdown. Real limitation: it can drift, skip a step, or miscount retries in a way a compiled engine would not.

For contrast, a true orchestration engine exists as a separate plugin: **Ouroboros** (MCP tools, event sourcing, real execution loops). That is neither the kit nor Claude builtin. If the kit's reliability guarantees ever need to be enforced by code rather than prose, that is the architectural gap to close.
