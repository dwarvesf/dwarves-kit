# Operating-layer vision + SDLC state machine

> Design-first north-star for the kit's natural-language operating layer. Vision and
> model, not implementation. The implementing specs (SPEC-026 +) trace here. Operator
> behavior derives from this; `docs/PLAYBOOK.md` is the operator-facing projection of
> the state machine below, `docs/ORCHESTRATION.md` is the flow/loop view, `WORKFLOW.md`
> is the rules contract, `docs/PHILOSOPHY.md` is the why.

## 1. Vision

Today the kit is driven through an **interpret-and-bridge** layer: the operator types
intent in chat, Claude maps it to a `/user:*` command or skill, and the hooks act as
guardrails. That works, but the operator cannot *see* the machine: there is no explicit
notion of "what state am I in, what transitions are available from here, what guards each
one, and how do I trigger it." The mapping lives only in Claude's interpretation, so it is
inconsistent run to run and invisible to the operator.

**The vision:** make the operating layer a **legible state machine** the operator can drive
from natural language. At any moment the operator (and Claude) can answer four questions
without guessing:

1. **Where am I?** (the current state)
2. **Where can I go?** (the available transitions)
3. **What does each cost / require?** (the guard + the stop condition)
4. **How do I trigger it?** (the phrase or command)

The machine does not replace the interpret layer; it gives that layer a **declared model**
to interpret against, so the same intent produces the same transition every time, and the
operator can learn the map instead of re-deriving it.

## 2. Principles (inherited + new)

Inherited from `docs/PHILOSOPHY.md` and `WORKFLOW.md`:
- **Guardrails over guidance.** Transitions are guarded by hooks where the cost is irreversible; everything else suggests and routes.
- **BACKLOG-ID-first.** Every unit of work has an ID before it ships; freeform intent is bridged to an ID (SPEC-026 makes that bridge native).
- **Bounded loops.** Sub-machines (build, debug) terminate on a model-evaluated stop, never an unbounded outer driver.
- **Detector vs mutator.** Reading state never changes it; exactly one mutator advances it.

New UX invariants this vision adds:
- **State is always answerable.** Claude can always name the current state and the legal next transitions.
- **Guards are explicit, not implicit.** A transition that cannot fire says *why* (the guard that blocks it), never silently stalls.
- **The 4 hard stops are transition guards, not surprises.** They are drawn into the machine, so an operator running autonomously knows exactly the edges that will pause for them.

## 3. The SDLC state machine

### 3.1 States

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

### 3.2 Master diagram

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

### 3.3 Transition table (the contract)

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

### 3.4 Sub-machines

- **BUILDING** expands to: `worker -> task-verifier -> {PASS | FAIL:fixable -> fix-agent (<=2) | FAIL:escalate} -> integration-checker`. See `docs/ORCHESTRATION.md` 5.3.
- **DEBUGGING** expands to: `Phase 1 Root cause -> Phase 2 Pattern -> Phase 3 Hypothesis -> Phase 4 Implementation`, under the iron law (no fix without a recorded root cause), guarded by the guess-fix guard. See `docs/ORCHESTRATION.md` 5.2.

### 3.5 Hard stops as guards (the only blockers)

| Hard stop | Guards the transition | Effect |
|---|---|---|
| safety-gate | any transition running destructive Bash | blocks the command |
| push-to-main | SHIPPING -> (the push) | blocks the push |
| anti-rationalization | BUILDING -> REVIEWING; any -> "done" | blocks premature/false done |
| verification pipeline | BUILDING -> REVIEWING | blocks if a task fails |

Everything else is advisory: it suggests the transition, it does not block it.

## 4. Scenario catalog (all 15, mapped to transitions)

The five from the original playbook, plus ten that complete the SDLC. Each is "trigger -> from-state -> guard -> to-state".

| # | Scenario | Trigger | From -> To | Notes |
|---|---|---|---|---|
| 1 | What's next / left | "what's next" | IDLE -> IDLE (detector) | renders queue; no transition until you pick |
| 2 | Apply SDD to a feature | "apply SDD to X" | IDLE -> TRIAGING -> SPECIFYING | freeform; bridged to an ID (SPEC-026) |
| 3 | Autonomous full flow | "run the lane, your call" | TRIAGING -> ... -> SHIPPED | advisory checkpoints skipped; hard stops remain |
| 4 | Iterate the design | "discuss / revisit design" | DESIGNING ⇄ DESIGNING | human-in-loop, per-section |
| 5 | Vague brief | "rough idea about X" | IDLE -> TRIAGING | interview (`/think` + brainstorming) before any row |
| 6 | Resume after interruption | "where were we" | (any) -> same | session-state restore + `/start`; mostly supported |
| 7 | Mid-flight scope change | "also do Y" | BUILDING -> SPECIFYING | **gap**: amend the active spec mid-build |
| 8 | Blocked / park | "park this", "I'm stuck" | (any) -> BLOCKED | supported (parked status + Open questions) |
| 9 | Context switch across specs | "switch to the other feature" | (any) -> (other worktree) | **gap**: worktree-per-spec is the model, no switch command |
| 10 | Urgent hotfix | "prod is down, fix X now" | IDLE -> DEBUGGING | bug lane exists; **minor gap**: a declared fast path |
| 11 | Review someone else's work | "review this PR" | IDLE -> REVIEWING | supported (`/review` on any diff); note the base ref |
| 12 | Abandon | "kill this" | (any) -> ABANDONED | **minor gap**: no explicit abandon terminal (vs park) |
| 13 | Re-open shipped | "follow-up on shipped X" | SHIPPED -> TRIAGING | **gap**: convention for a follow-up spec |
| 14 | Status during a run | "how's it going" | (running) -> same | report progress; no state change |
| 15 | Knowledge capture | "save this learning" | (any) -> same | side-effect (`/learned` + skills); no state change |

## 5. Gap analysis (what has no clean path today -> implementing specs)

Most transitions already have a path. The real gaps, in priority order:

| Gap | Scenario | Why it is a gap | Proposed |
|---|---|---|---|
| Freeform front door | 2, 5 | `/assign` is ID-only; freeform is bridged by hand | **SPEC-026 / ID-022** (drafted) |
| Mid-flight spec amend | 7 | no path to amend a `VALIDATED`/building spec without restarting | **ID-023** (new) |
| Context switch across specs | 9 | worktree-per-spec is the model but no switch affordance | **ID-024** (new) |
| Re-open shipped | 13 | a `SHIPPED` spec has no follow-up convention | **ID-025** (new) |
| Abandon terminal | 12 | only `parked` exists; no explicit drop | folded into ID-024 (state hygiene) or a tiny lane |

Scenarios 6, 8, 10, 11, 14, 15 are supported or near-supported today; the doc records them so the machine is complete, no new spec required.

## 6. How this gets built (the kickoff path, design-first)

The kit dogfoods itself. The order:

```text
  1. THIS doc (vision + state machine)        <- design-first, done now
  2. /user:assign ID-022   -> SPEC-026 (freeform front door): /spec-validate (drafted) -> /execute
  3. /user:assign ID-023   -> mid-flight spec amend (spec it, then build)
  4. /user:assign ID-024   -> context-switch affordance (+ abandon terminal)
  5. /user:assign ID-025   -> re-open-shipped convention
  6. align docs/PLAYBOOK.md to the shipped state machine (regenerate the scenario cards from it)
```

Each row runs the normal/full lane (Section 3). The state machine in this doc is the
acceptance reference: a transition is "done" when an operator can trigger it by phrase and
the guard/stop behaves as the table says.

## See also
- `docs/PLAYBOOK.md` - the operator-facing projection (what you say -> what happens).
- `docs/ORCHESTRATION.md` - the flow/loop view (the sub-machines in detail).
- `WORKFLOW.md` - the rules contract.
- `docs/PHILOSOPHY.md` - the why behind the guards and the bounded loops.
- `docs/specs/SPEC-026-freeform-front-door.md` - the first implementing spec.
