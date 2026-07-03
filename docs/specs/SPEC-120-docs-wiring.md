# Spec: mega-goal delegate docs + no-orphan wiring check
Generated: 2026-07-03
Status: VALIDATED

## Problem

ADR-0032 (accepted 2026-07-03) commits the kit to a hardened mega-goal execution model:
a DELEGATE run mode (thin conductor, one fresh headless `claude -p` per sub-goal),
per-sub-goal model routing, a ledger-under-delegation guarantee (gate/proof survive by
construction, token capture via stream-to-file, debt split conductor/worker), a mega
TIER-4 close (no-orphan sweep + verifier session + held human gate), and an opt-in tmux
multiplexer for wave visibility. All five pieces landed in `lib/orchestrate.sh` across
sub-goals 01-04 of the `orchestrate-hardening` mega-goal (PRs #139-143, all merged to
master) -- but `WORKFLOW.md` and `AGENTS.md` say nothing about any of it. An operator or
a future goal-loop reading the operate-contract docs today has no way to learn the
delegate model exists, and no defense against the docs later drifting from what actually
dispatches (the exact bug class `kit-hardening c6fbd99` fixed for the V-model right arm:
WORKFLOW.md claimed 3 right-arm agents were "dispatched by /kit:ship" when no command
ever called them).

## Solution

### Approaches considered

1. **Describe the delegate model inline inside the existing "Goal loop" engine
   description** (WORKFLOW.md's three bounded-loops section). Rejected: mega-goal
   delegation is a DIFFERENT scale (multiple dependent sub-goals, each its own session)
   from the single-objective goal loop that section already describes; folding it in
   would conflate "one objective, one session" with "N sub-goals, N sessions,
   1 conductor".
2. **A new standalone section next to "Lead-owned convergence"** (the existing
   multi-worktree fan-out section for `/kit:dispatch`). `/kit:dispatch` already
   documents a sibling multi-session shape (N disjoint specs, N worktree workers, lead
   converges); the mega-goal delegate model is a second multi-session shape (N DEPENDENT
   sub-goals, serial or waved, one THIN conductor absorbing terse results) that belongs
   next to it for contrast, not merged into it (the two have different disjointness /
   ordering contracts: `/kit:dispatch` requires proven-disjoint `## Touches`;
   mega-goal sub-goals are ROADMAP-ordered with explicit `depends`).
3. **A brand-new top-level doc** (`docs/mega-goal-delegate.md`). Rejected: WORKFLOW.md is
   the kit's single canonical home for "the cycle, the lanes, the gates"; a second doc
   fragments the one place an operator already knows to look, and the goal file's Where
   to look explicitly names WORKFLOW.md + AGENTS.md as the docs to update, not a new file.

### Chosen approach + why

**Approach 2**: a new `## Mega-goal delegate execution (ADR-0032)` section in
WORKFLOW.md, placed directly after `## Lead-owned convergence` (the closest existing
sibling: another multi-session fan-out contract) and before `## What this contract does
NOT do`. AGENTS.md gets one pointer sentence added to zone 1 item 4 (no new zone; see
`docs/implementation-notes/SPEC-120-docs-wiring.md` for why).

### Extensibility & boundaries

- Load-bearing dimension: which ADR-0032 guarantee gets added next (e.g. a second pane
  driver per SPEC-119's "Out of Scope"). The wiring-check pattern (one capability -> one
  grep-verifiable corpus fact) is the seam a 6th guarantee would extend, not rework.
- Unit boundaries: the doc section (prose, one purpose: describe the run model
  truthfully) is separate from the wiring test (`tests/test-docs-wiring.sh`, one purpose:
  prove every claim in that prose actually dispatches). Neither implies the other; the
  test still fails if the prose is edited to over-claim later, independent of doc wording
  changes.

### Architecture

```text
WORKFLOW.md "## Mega-goal delegate execution (ADR-0032)"
  |-- run modes (INLINE / DELEGATE) + "/goal stays the official outer loop"
  |-- per-sub-goal model routing (Model: -> --model)
  |-- ledger-under-delegation guarantee (gate/proof by construction, token stream-to-file, debt split)
  |-- mega TIER-4 close (no-orphan sweep -> verifier session -> HOLD)
  \-- opt-in multiplexer (off by default; --stream only to a FILE, never the conductor)

AGENTS.md zone 1 item 4 -- one-sentence pointer to the section above

tests/test-docs-wiring.sh
  |-- AC1-5: doc-presence (WORKFLOW.md/AGENTS.md carry each concept's required vocabulary)
  |-- AC6-9: no-orphan sweep (4 real capabilities, each grep-verified live in lib/orchestrate.sh + lib/gate-ledger.sh)
  \-- AC10 [NEGATIVE CONTROL]: a planted over-claim ("multiplexer on by default") is CAUGHT
      by the same sweep function, proving it is not a rubber stamp
```

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes: `WORKFLOW.md`, `AGENTS.md` (doc text), `lib/orchestrate.sh` +
  `lib/gate-ledger.sh` (the corpus the no-orphan sweep greps against for "does this
  capability actually dispatch").
- Outputs / produces: updated prose in both docs; `tests/test-docs-wiring.sh` (exit 0 on
  every AC, prints PASS/FAIL per assertion like the kit's other `test-*-parity.sh`
  suites).
- Invariants: every capability the docs claim as operational has a grep-verifiable, live
  call site in the named corpus file -- not just a variable definition or a comment
  describing intent. The sweep checks the CALL SITE (e.g. `_tier4_close "$dir"
  "$roadmap"` being invoked), not just the flag's existence (e.g. `TIER4_CLOSE="${TIER4_CLOSE:-1}"`
  alone would pass even if nothing ever called `_tier4_close`).

### Data model changes
None.

### API changes
None (bash lib, no network/API surface).

### UI changes
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Docs
- [ ] TASK-001: add `## Mega-goal delegate execution (ADR-0032)` to WORKFLOW.md (run
      modes, model routing, ledger-under-delegation guarantee, TIER-4 close, opt-in
      multiplexer) -- AC: section exists, covers all 5 sub-points, states the
      multiplexer is opt-in/off-by-default (never default-on).
- [ ] TASK-002: add one pointer sentence to AGENTS.md zone 1 item 4 naming the new
      WORKFLOW.md section -- AC: sentence present, does not restate the delegate model's
      internals (pointer only).

### Phase 2: Wiring check
- [ ] TASK-003: write `tests/test-docs-wiring.sh` with doc-presence assertions (AC1-5)
      and the no-orphan sweep over the 4 real capabilities (AC6-9), each keyed to an
      exact grep pattern against a live call site in `lib/orchestrate.sh` /
      `lib/gate-ledger.sh` -- AC: all pass against current master+this branch's docs.
- [ ] TASK-004 (depends on TASK-003's sweep function): add the over-claim negative
      control (AC10): a planted fixture claim (multiplexer default-on) run through the
      same sweep function, asserted CAUGHT (sweep returns non-wired) -- AC: the fixture
      is provably false today (grep for the claimed corpus fact returns nothing) and the
      test fails loudly if the sweep function is ever weakened to rubber-stamp it.

## After state

- [ ] WORKFLOW.md contains a section naming the DELEGATE run model, `/goal` as the
      official outer loop, per-sub-goal model routing, the ledger-under-delegation
      guarantee (gate/proof/token/debt), the TIER-4 close, and the opt-in multiplexer.
      (Today: none of this exists in WORKFLOW.md.)
- [ ] AGENTS.md points at that section from zone 1. (Today: AGENTS.md has zero mentions
      of mega-goal/delegate/orchestrate.)
- [ ] `bash tests/test-docs-wiring.sh` exits 0, and its output shows the over-claim
      fixture assertion passing (i.e. the sweep correctly flags it as NOT wired).

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `bash tests/test-docs-wiring.sh` is green
- [ ] No regressions in `bash tests/test-meta.sh` (structural integrity, e.g. every
      shipped file justified, doc-impact map consistency)

## Verification

`bash tests/test-docs-wiring.sh`

## Edge Cases

1. A capability's underlying flag exists but its call site was refactored/renamed --
   the sweep must grep the CALL SITE, not just the env-var default line, so a rename
   that silently orphans the capability is caught (this is the exact c6fbd99 bug class:
   the agent/flag existed, but nothing called it).
2. The over-claim fixture's claimed corpus fact must be independently confirmed absent
   from the real corpus (not just "the test author believes it's false") -- the test
   greps for it directly and asserts the grep fails, so the negative control cannot
   silently rot into a false pass if the corpus later happens to grow that string for an
   unrelated reason.

## Out of Scope

- The machinery itself (`lib/orchestrate.sh` model routing / token capture / TIER-4
  close / multiplexer panes) -- already shipped in sub-goals 01-04.
- The mega-goal ROADMAP.md (already written, `ops-toolkit/_meta/megagoals/orchestrate-hardening/`).
- A second pane driver (`PANE_DRIVER=cmux`) -- SPEC-119's own Out of Scope, unchanged here.
- Re-documenting `/goal`'s own internals (ADR-0017: activator-agnostic, not the kit's to own).

## Decision Log

- DEC-001: place the new WORKFLOW.md section after "Lead-owned convergence", not inside
  the three-bounded-loops section. Rationale: different scale (multi-session mega-goal
  vs single-objective in-session loop); alternatives rejected in "Approaches considered".
- DEC-002: AGENTS.md gets a pointer sentence, not a new zone. Rationale: zone stability
  contract + avoid duplicating delegate-model prose in two files (implementation notes).
- DEC-003: skip `/kit:spec`'s research-agent fan-out for this spec; the sub-goal's own
  goal file already named every source file to read, and this session read them directly
  (implementation notes, 2026-07-03 10:20).
- DEC-004: TASK-004 annotated with an explicit `(depends on TASK-003's sweep function)`
  ordering note, per /kit:spec-validate Scope Critic finding (missing dependency
  declaration between an implied-ordered task pair).

## Review

# Spec Validation Report
Date: 2026-07-03
Spec: SPEC-120-docs-wiring

## Critical Issues (must fix before implementation)
(none)

## Warnings (address before shipping)
1. TASK-004 depends on TASK-003's sweep function existing but the dependency was only
   implied by Phase-2 task order, not stated, Scope Critic, fixed: added an explicit
   `(depends on TASK-003's sweep function)` annotation to TASK-004 (DEC-004).

## Passed
- Security Auditor: no auth/authz/secrets/input-validation surface (docs + bash test
  change); nothing to flag.
- Failure Mode Analyst: Edge Case 1 already covers the load-bearing failure class (a
  capability's call site renamed/refactored, silently orphaning the docs claim); no
  external-service or concurrency surface in scope.
- Assumption Destroyer: grep patterns key on exact literal call-site strings (matching
  the kit's own `test-right-arm-parity.sh` convention), not just flag/env-var presence,
  so a comment-only occurrence would not create a false "wired" positive for the
  patterns chosen here (confirmed each pattern's 2 real line numbers before drafting).
- Scope Critic: all 4 tasks atomic (1 file each, <=3-sentence description, <=5 AC
  bullets); global AC fully covered by the 4 tasks; autonomy gate n/a (no loop-reachable
  scope/architecture decision, final gate is human-held per the mega-goal's TIER-4
  close).
- Solution-Design & Extensibility Critic: 3 real, distinct alternatives with honest
  tradeoffs; extensibility dimension named and grounded (a 6th ADR-0032 guarantee slots
  into the same one-capability-one-grep-verifiable-fact pattern); Interfaces section
  concrete (named files + exit-code contract).

## Verdict: APPROVED

## Open questions
(none)
