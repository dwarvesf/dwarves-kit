# SPEC-089: Dynamic agent synthesis (same-run specialists)

Status: DRAFT (Han 2026-07-01)
Related: SG-05 meta-agent (token-optim-v3), ADR-0022 (multi-session boundary), the mega-goal
orchestration audit (section 7, feeds this).

## Problem

During SDD execution a task often needs a SPECIALIST role (security, migration, frontend, ...) that
no predefined agent covers. Today the kit dispatches every task worker as a GENERIC Task-tool call
with a generic "You are implementing a single task" preamble (`execute.md` 2b). We want: when a task
needs a specialist, synthesize that role and dispatch it FOR THAT TASK, immediately, this run.

## Governing philosophy (Han 2026-07-01)

The kit is an instrument for CLEAR specs and easy-to-medium goals: it supplies the structure (lanes,
gates, verification, roles). For HARD or unclear goals, no fixed process can figure the task out; the
agent must reason DYNAMICALLY, and the kit's job narrows to ensuring the docs + decisions get logged
(proof-of-done, impl-notes, ADRs). Dynamic agent synthesis is the "reason dynamically" half made
concrete: the set of roles a hard goal needs is unknowable up front, so it must be synthesized on
demand, not enumerated. This is why the role space below is OPEN-ENDED, not a fixed menu.

## The hard constraint (why "install a file" does not work)

Claude Code loads the subagent registry at **session start**. A subagent is dispatchable by
`subagent_type` only if its file was present when the session began. So a file written mid-run is
NOT triggerable this session, it is live next session. Therefore same-run specialization CANNOT go
through file install. It must go through prompt injection into an already-generic worker.

## Mechanism

Two complementary paths, deliberately separate:

| Path | What | When live | Tools | Use |
|---|---|---|---|---|
| **Use-now** (this spec) | meta-agent **Mode C** returns an inline role spec (`NAME`/`TOOLS(advisory)`/`PREAMBLE`); the caller injects `PREAMBLE` into the task worker | THIS run | advisory only (an inline general worker cannot be tool-restricted) | auto, per task |
| **Reuse-by-name** (SG-05 install) | `/kit:draft-agent` writes `agents/<name>.md` + roster-sync + `cp` to `~/.claude/agents/` | next session | enforced by frontmatter | deliberate, reviewed, shared |
| **Cache** (bridge) | after a Mode-C dispatch, write the spec to `~/.claude/agents/<name>.md` | next session | enforced | automatic, local reuse |

The cache bridges them: a synthesized specialist used now becomes a named, dispatchable agent next
session, with no repo churn. Promoting it into the SHARED kit (`agents/` + roster + review) stays the
deliberate `/kit:draft-agent` path.

## Open-ended roles: the classifier is a fast path, the meta-agent is the authority

The role space is UNBOUNDED. A fixed enum (security, frontend, ...) can never cover the tail
(`technical-doc-writer`, `typescript-dev`, `ui-designer`, `solidity-auditor`, `market-researcher`, ...).
So authority is split:

- **`lib/classify/role-classify.sh` = a cheap FAST-PATH hint** for high-frequency domains only. Deterministic
  keyword heuristic, no LLM. It is NOT the role universe. Its `generic` output means "no fast-path
  match, escalate", NOT "use a generic worker". A third peer of `lib/classify/lane-classify.sh` (which LANE) and
  `lib/classify/task-type-classify.sh` (which WORK TYPE), so every command classifies the common domains the
  same cheap way.
- **`meta-agent` Mode C = the OPEN-ENDED authority.** Given any task (+ the optional hint), it infers
  the best-fit role BY NAME, whatever it is, or returns `NO_SPECIALIST` for a genuinely plain task.
  Only `NO_SPECIALIST` falls through to a generic worker.

The classifier is thus purely a cost optimization (skip the LLM for the ~7 common domains); the role
coverage is unbounded because the LLM names the long tail. The `~/.claude/agents/` cache accumulates
the roles actually hit into a growing, reusable role library , the system gets cheaper the more it is
used (more cache hits, fewer synthesis calls).

The classification logic must NOT live inside `execute.md`; it is the shared `lib/` primitive so any
command reuses it.

### The dispatch contract (any command follows these 4 steps)

```
1. hint = bash lib/classify/role-classify.sh classify "<task desc + acceptance criteria>"   # fast-path only
2. reuse: a predefined agent fits (dispatch by name), OR a cached ~/.claude/agents/*<role>*.md fits
   (use its body as PREAMBLE). If hit, skip synthesis.
3. synthesize: dispatch meta-agent Mode C (task + hint). It returns EITHER a role
   (NAME/TOOLS/PREAMBLE) OR NO_SPECIALIST.
     - NO_SPECIALIST        -> dispatch the generic worker (unchanged). STOP.
     - a role               -> inject PREAMBLE into the worker NOW.
4. cache the synthesized spec to ~/.claude/agents/<name>.md for next-session reuse.
```
Note: `generic` from step 1 is NOT a stop condition , it escalates to step 3. Only the meta-agent's
`NO_SPECIALIST` verdict falls through to a generic worker.

### Consumers

| Command | Status | Notes |
|---|---|---|
| `/kit:execute` (2b-0) | DONE (this PR) | the reference consumer |
| `/kit:next` | TODO | single-task path, same 4-step contract |
| `/kit:dispatch` | TODO | fan-out workers, classify each |
| mega-goal orchestrator (`lib/queue/orchestrate.sh` per-sub-goal `claude -p`) | TODO, pending §7 audit | a sub-goal is a task; classify it before dispatching its session |

## Trigger policy

**Auto-classify every task** (Han 2026-07-01, chosen over spec-opt-in / complex-only). Mis-fire + cost
guarded by: classification is inline + deterministic (no LLM hop), synthesis fires only on a clear
domain match, and `generic` is the default fall-through, so plain tasks are unchanged.

## Constraints / non-goals

- Tool minimization on the use-now path is ADVISORY, not enforced (registry limitation). Enforced
  minimal tools require the reuse-by-name path (a registered file).
- No auto-promotion into the shared kit. Auto-synthesis caches locally (`~/.claude/agents/`);
  sharing stays PR-reviewed via `/kit:draft-agent`.
- Not a fleet generator: one bounded meta-agent call per specialist-worthy task, not a loop.

## Verification

- `bash tests/test-role-classify.sh` , 15/15 (one positive case per domain + generic fall-through +
  interface).
- `bash tests/test-meta-agent.sh` , Mode C structural + golden `inline-role-spec.txt` fixture.
- `bash tests/test-meta.sh` , 508/508 (roster + structural guards unaffected).

## 7. Mega-goal <-> kit orchestration audit (Han flagged 2026-07-01)

Read-only audit of the `plan-for-mega-goal` skill, the token-optim-v3 POINTER_PROMPT + goal files,
`lib/queue/orchestrate.sh`, WORKFLOW.md, and the ship-gate.

### The seam: two orchestrators, one used

```
/goal loop (built-in)         ── USED by v3 ──   re-injects POINTER_PROMPT each turn; the agent
                                                 builds sub-goals FREEFORM (no /kit:* SDD run)
lib/queue/orchestrate.sh (kit, PR#81) ── DORMANT ──    non-LLM driver: fresh `claude -p` per sub-goal,
                                                 injects goal+HANDOFF+pointer, waits for the box flip
        both feed →  ship-gate hook (PreToolUse on push) reads the gate-ledger, blocks on missing gates
```

### Finding: the mega-goal loop bypasses `/kit:*` BY DESIGN

The POINTER_PROMPT says: *"Kit-adopted repos: read AGENTS.md + WORKFLOW.md, classify via lane-classify,
record gates via `lib/gate/gate-ledger.sh`. `/kit:*` binds to cwd; for a sub-goal in another repo, drive
`lib/` + gate-ledger directly."* So the SDD order (`/kit:spec → execute → review → ship`) is
intentionally NOT run per sub-goal; the loop builds + verifies + opens a PR, and the ship-gate enforces
proof-of-done at push. This is a lighter-by-design path, not a bug. The real gaps are in enforcement,
not intent:

| # | Gap | Severity | Correct today? |
|---|---|---|---|
| G1 | The subgoal-TEMPLATE does not REQUIRE `lib/gate/gate-ledger.sh record` calls, so ledger population is ad-hoc. If an agent skips it, the ship-gate blocks at push (recover via retro-fit/override). | HIGH | this session recorded gates by hand for SG-05/06/07; the template doesn't mandate it |
| G2 | The pointer says "drive `lib/` directly" (implies don't use `/kit:*` cross-repo) but never EXPLICITLY forbids it, and is silent on the same-repo case (a dwarves-kit sub-goal run from the dwarves-kit cwd COULD run `/kit:*`, should it?). Ambiguous. | MED | mostly covered by the "binds to cwd" line; sharper wording would remove the ambiguity |
| G3 | Two orchestrators (`/goal` used, `lib/queue/orchestrate.sh` dormant) with no reconciliation , which is canonical? | MED (strategic) | unreconciled; this is the kit-hardening charter |

### Fixes + routing

- **G1 (do here or in the skill):** the `plan-for-mega-goal` `subgoal-template.md` "How to close the
  loop" should, for kit-adopted repos, REQUIRE the ledger calls (`gate-ledger.sh start` + `record` per
  phase). Cheap, high-value. Lands in the SKILL (dotfiles), not this kit repo.
- **G2 (do here or in the skill):** add one explicit line to the pointer/template: "kit-adopted
  sub-goal , run the lane + record gates via `lib/`; do NOT invoke `/kit:*` for a cross-repo sub-goal
  (cwd-bind); same-repo `/kit:*` is allowed but optional." Also skill-side.
- **G3 (route to kit-hardening):** reconciling `/goal` vs `lib/queue/orchestrate.sh` as the canonical runner
  is exactly the kit-hardening mega-goal's charter (ADR-0028 + SPEC-088). NOT this spec's job.

### Bearing on SPEC-089

The dispatch contract (§Generalization) is orchestrator-agnostic: it is a `lib/` primitive + a 4-step
pattern, so it works whether the runner is `/goal` or `lib/queue/orchestrate.sh`. The mega-goal orchestrator
becomes a §Consumers row the day it classifies each sub-goal before dispatching its session , that
adoption waits on G3 (which runner) and is deferred to kit-hardening. No SPEC-089 change is blocked by
the audit; the audit's own fixes (G1/G2) are mega-goal-skill edits, tracked here for the record.
