# ADR-0017: A planning-only mega-decomposition lane; the outer loop stays external

## Status: rejected (2026-05-22). Superseded by SPEC-034 (ID-037).

> **Rejected before review.** The premise was wrong. This ADR treated the
> mega-goal lane as needing a PHILOSOPHY amendment to admit a multi-objective
> effort. On closer reading the lane drives the kit's already-blessed *bounded
> in-session* `/goal` loop (PHILOSOPHY §3, the same primitive as the goal loop and
> the debug loop), not the rejected *unbounded outer* loop, so no amendment is
> needed. The capability is specced instead in **SPEC-034 (ID-037)** as a
> planning-only `/kit:mega`, the sequential/dependent complement to SPEC-032's
> parallel dispatch. This file is kept as a record so the amendment is not
> re-proposed; the body below is the rejected proposal, left intact.

## Context

A multi-objective workflow pattern (plan-for-mega-goal, `zvadaadam/az-skills`
under `skills/productivity/plan-for-mega-goal`, sibling of `plan-for-goal`)
decomposes one destination into 3-8 independent sub-goals and runs them through
an autonomous `/goal` loop that opens one stacked PR per sub-goal over hours or
days. It is the canonical "epic" shape the kit currently has no surface for.

Two structural gaps make the pattern impossible to express in the kit today:

- `_meta/BACKLOG.md` is a flat `ID-NNN` list with no parent/child link (SPEC-005).
- Execution is one-session / one-active-spec: worktree-per-spec, branch-aware
  detection (WORKFLOW.md "Artifact placement and concurrency").

Three principles fence the pattern out:

- "Shallow and wide beats deep and narrow" (PHILOSOPHY §1): do not build a runtime.
- "Loop boundaries: the unbounded outer loop is declined" (§3, refining
  SPEC-003 DEC-005 / SPEC-006): no external loop re-spawning sessions until done.
- "No project management ... Notion handles that" (§2): no roadmap / milestone state.

The §4 differentiation thesis also says the kit is glue, not a runtime, and
defers multi-session orchestration to GSD v2 / Agent OS.

The maintainer wants a first-class in-kit surface for epics and chose to amend
PHILOSOPHY rather than keep the whole pattern external.

## Decision

Amend along the line PHILOSOPHY already draws between **planning** and
**runtime**. Admit the planning half; keep the runtime half fenced out.

**ADMIT (new, in-kit): a planning-only mega-decomposition beat.** One
multi-objective backlog item (an "epic") decomposes into N linked child backlog
rows + N `.claude/goals/<slug>.md` drafts + one lightweight roadmap recording
child IDs and dependency order. This is Think/Spec-phase planning. It owns no
loop, dispatches no worker, opens no PR, and ends the moment the children exist.

**KEEP THE FENCE (unchanged): the runtime half stays external.** The autonomous
outer loop, cross-session sequencing, and the stacked-PR mechanism live in GSD v2
/ Agent OS / a personal ops-toolkit tool. Each child sub-spec runs through the
existing bounded in-session goal loop, one at a time, exactly as today. The kit
stays activator-agnostic (WORKFLOW.md §"Freeform front door").

What this changes in PHILOSOPHY (the only two edits):

1. **§2 "no project management":** add a recorded carve-out for an in-repo
   roadmap that is **build-state, not PM**. It records child spec IDs +
   dependency order (the way CHANGELOG records shipped work and BACKLOG records
   the queue). It carries no story points, velocity, or sprint dates; if it ever
   grows those, it is rejected.
2. **§3 "Loop boundaries":** add a clarifying line that decomposing one epic into
   N bounded in-session loops is **not** an unbounded outer loop. The fence (no
   external `while` re-spawning sessions) is unchanged; this names that the new
   lane sits inside it.

**NOT amended:** "Shallow and wide" (§1) and the §4 differentiation thesis,
because the lane builds no runtime. A future proposal to amend either of those is
the rejected deep-amend below and must return as its own ADR.

## Alternatives considered

1. **Deep amend: admit the autonomous multi-day outer loop into the kit (own the
   runtime). REJECTED.** Collapses the §4 differentiation thesis (the kit defers
   runtime to GSD v2 by design), turns the kit into a product, re-litigates
   SPEC-003 DEC-005 and SPEC-006's loop boundary, and fails NO-list criterion 1
   (duplicates an external tool). The maintainer flagged this "likely wrong";
   this ADR agrees and draws the line here.
2. **No amend, keep entirely external.** Adapt plan-for-mega-goal as an
   ops-toolkit tool that uses the kit per sub-spec. Cheapest and fully
   PHILOSOPHY-compliant; rejected as the PRIMARY answer only because the
   maintainer wants an in-kit epic surface. RETAINED as the home for the runtime
   half: this ADR explicitly sends the loop there.
3. **Ideas-only, no lane.** Port plan-for-mega-goal's "trust the agent on HOW,
   not WHAT" framing and its "cite the failure each rule prevents" style into
   existing docs. Good and orthogonal; does not address the structural gap (flat
   backlog, no epic link). Do it regardless; not a substitute for this decision.

## Consequences

- **Positive:** epics get a first-class decomposition; children reuse every
  existing lane + the verification pipeline unchanged; no new runtime, no new
  dependency; the loop fence and the differentiation thesis hold.
- **Cost:** `BACKLOG.md` gains a parent/child link (a data-model change that
  needs its own SPEC before any code); a roadmap artifact joins the repo and must
  be defined as build-state or it rots into PM; PHILOSOPHY §2/§3 and the
  `commands/kit-health.md` reject-list get edited (doc-impact map); standing risk
  that future work drifts toward the rejected deep-amend (mitigation: this ADR
  names the line and routes the loop external).
- **Follow-ups, gated on accepting this ADR:** a SPEC for the BACKLOG epic schema
  + `/kit:assign` epic mode; a roadmap template defined as build-state; the
  PHILOSOPHY §2/§3 edits; the kit-health carve-out note; README +
  `docs/architecture.md` cross-ref to this ADR.
- **Reversible:** yes. If epics never materialize, revert the two carve-outs and
  remove the lane under the 30-day deprecation rule.

## Source

- plan-for-mega-goal and plan-for-goal, `zvadaadam/az-skills`: the multi-objective
  pattern this ADR scopes.
- SPEC-003 DEC-005, SPEC-005, SPEC-006: the backlog/goal model and the prior
  loop-boundary framing this ADR refines.
- PHILOSOPHY §1 "Shallow and wide", §2 target-user non-coverage, §3 "Loop
  boundaries", §4 differentiation thesis.
- WORKFLOW.md "Artifact placement and concurrency (multi-spec)".
