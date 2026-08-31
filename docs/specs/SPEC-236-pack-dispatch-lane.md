# Spec: /kit:pack, the plan-rich-dispatch-cheap packaging lane

<!-- renumbered 235 -> 236: parallel session claimed 235 for gauntlet-generalize on feat/gauntlet-generalize -->

Generated: 2026-08-31
Status: DRAFT
References: ops-toolkit `_meta/megagoals/cluster-notify-wiring/` (the hand-run this lane automates: roadmap.md + dispatch-G*.md + fixture, produced 2026-08-31 across 4 repos; imitate its file shapes verbatim); ops-toolkit `docs/specs/SPEC-128-*` + dfoundation `SPEC-107` + event-bridge `SPEC-018` + foundation-workers `SPEC-238` (what "pack-ready" specs look like after the cold-start audit closed their gaps).

## Problem

The estate's division of labor is: the expensive orchestrator model does ALL planning (think, design, spec, validate, test plan), cheap workers (Sonnet tier) implement test-first and follow the written design. The kit has every planning lane and the execution lanes (`/kit:mega`, `/kit:execute`, `/kit:dispatch`), but the PACKAGING step between them is manual: cold-start auditing each spec for cheap-model self-containedness, enriching context blocks, extracting operator-input stops, writing per-goal dispatch prompts with the test-first contract, and sequencing cross-repo dependencies. On 2026-08-31 this took a full orchestrator session to do by hand for 4 specs. The owner wants one command: "prepare this for dispatch."

## Solution

### Approaches considered

1. New command `/kit:pack`: takes 1+ validated specs (or the active mega-goal), runs a cold-start audit reviewer per spec, patches gaps into the specs' context blocks, emits the dispatch pack (roadmap + per-goal prompts). Tradeoff: one more command in the roster.
2. Extend `/kit:mega` with a `--pack` output mode. Tradeoff: mega is roadmap-first (decompose before specs exist); packing happens AFTER specs validate, a different lifecycle moment; bolting it on muddies mega's one job.
3. Fold into `/kit:execute` as a pre-flight. Tradeoff: execute runs IN one repo for one spec; packing is cross-repo and pre-dispatch; the wrong altitude.

### Chosen approach + why

Approach 1. Packing is its own lifecycle moment (after validate, before dispatch) with its own artifact class; the roster cost is honest. Mega stays decomposition, execute stays per-goal build.

### Extensibility & boundaries

- Load-bearing dimension: number of goals in a pack. Each goal = one audit dispatch + one prompt file; O(goals), independent.
- Units: (a) cold-start audit step, two strengths: DEFAULT one-shot auditor agent (read-only, refute-briefed) and, for high-stakes packs, the generalized gauntlet (SPEC-235) run with a 'spec-dispatch readiness' preset, artifact = the spec + context blocks, outcome contract = a clean-room Sonnet probe executes a designated task slice, probes failing -> spec context revised -> respin. Probe-convergence is strictly stronger than one review pass; /kit:pack names which strength it used in the roadmap. (b) pack emitter (templates), (c) operator-input extractor. Each testable alone.

## Picture

```
validated specs (1..N, possibly N repos)
        │  /kit:pack <spec paths | active mega-goal>
        ▼
  ┌─ per spec: cold-start-auditor agent (read-only, fresh context) ─┐
  │   "could a Sonnet worker with ONLY this repo + this spec        │
  │    execute? name every missing path/command/secret/cross-repo   │
  │    pin/fixture"                                                 │
  └───────────────┬───────────────────────────────────────────────┘
                  ▼ gaps
  lead patches spec context blocks (## Context for implementation)
                  ▼
  emit _meta/megagoals/<slug>/ in the COCKPIT repo:
    roadmap.md      order + dependency edges + merge config + exit criteria
    dispatch-G*.md  per goal: spec path, worker model (Sonnet default),
                    TEST-FIRST contract (matrix tests RED before code),
                    design-adherence clause (uncovered decision -> STOP,
                    append ## Open questions), do-not-touch fences,
                    ship-gate reminder
    operator-inputs table (extracted STOP-and-ask items, status=pending)
                  ▼
  hand off: paste a dispatch file into a worker session, or /kit:dispatch
```

## Design

### Approaches considered + chosen
See `## Solution`.

### Diagram
The Picture above (flow); ASCII.

### ADR link(s)
Records the estate's plan-rich/execute-cheap doctrine as a kit lane; reversible, no ADR required. The doctrine's proven run is the References line.

### Boundaries & failure modes
Out of bounds: running the workers (that stays `/kit:dispatch` / manual paste), writing tests or fixtures itself (it PROMPTS the lead to capture fixtures where a spec's parser/contract surface warrants one, listing them in the roadmap as pre-dispatch TODOs), and modifying spec content beyond context blocks.

## Technical Design

### Interfaces (I/O contract)

- Inputs: spec file paths (flags) or the active mega-goal folder; each spec must be `Status: VALIDATED` with a `## Test plan` (refuse otherwise, naming the missing lane, `/kit:spec-validate` or `/kit:test-plan`).
- Outputs: `_meta/megagoals/<slug>/{roadmap.md, dispatch-G<n>.md...}` in the invoking (cockpit) repo; context-block patches committed to each spec's repo on a branch (one small PR per repo, or direct when the lead says so).
- Invariants: dispatch prompts always carry the test-first contract and the STOP-on-uncovered-decision clause verbatim; worker model defaults to Sonnet and never names a stateless-glue model for implementation; an operator input is never guessed, always extracted into the pending table.

### Data model changes
New agent def `agents/cold-start-auditor.md` (read-only roster: Read, Grep, Glob, Bash(git log/diff, ls, find, cat, head)). New templates under `lib/pack/templates/{roadmap.md, dispatch.md}` seeded from the 2026-08-31 hand-run files.

### API changes
New command `commands/pack.md`; registry row; WORKFLOW.md lane entry (post-validate, pre-dispatch).

### Infrastructure changes
None.

## Task Breakdown

### Phase 1
- [ ] TASK-001: `agents/cold-start-auditor.md` (the audit charter distilled from the 2026-08-31 fork prompt: locate-every-file, runnable-verification, no-session-knowledge, CONTEXT-presence checks)., Acceptance: agent-effectiveness review passes; a dry audit of ops-toolkit SPEC-128 post-enrichment returns READY.
- [ ] TASK-002: `lib/pack/templates/` seeded from ops-toolkit `_meta/megagoals/cluster-notify-wiring/` with placeholders (`<slug>`, `<spec-path>`, `<order-graph>`, `<fences>`, `<operator-inputs>`)., Acceptance: rendering the templates against the four 2026-08-31 specs reproduces the hand-written pack's structure (diff shows only content placeholders).

### Phase 2
- [ ] TASK-003: `commands/pack.md` orchestration (refuse-unvalidated gate, per-spec auditor dispatch, patch loop, pack emission, operator-input extraction) + registry/WORKFLOW rows., Acceptance: `/kit:pack` on a fixture pair of validated specs emits a complete pack; on a DRAFT spec it refuses with the lane pointer.

### Phase 3
- [ ] TASK-004: docs (FEATURES row, workflow-paths) + gate-ledger phase records (`pack ran`)., Acceptance: topology-drift audit clean.

## After state

- [ ] "Prepare this for dispatch" is one command: `/kit:pack` on validated specs emits roadmap + prompts + pending-inputs table, checkable by running it on two fixture specs. (Today: a full manual orchestrator session.)
- [ ] A DRAFT or test-plan-less spec is refused with the missing lane named, checkable by the TASK-003 negative case. (Today: nothing checks readiness.)

## Acceptance Criteria (global)
- [ ] All tasks pass their acceptance criteria
- [ ] The four 2026-08-31 specs, run through `/kit:pack`, produce a pack equivalent to the hand-built one
- [ ] No change to mega/execute/dispatch behavior

## Verification
`bash tests/test-pack.sh` (fixtures: one validated + one draft spec) + the TASK-002 template-render diff.

## Edge Cases
1. Single-spec pack (no dependencies) -> roadmap degenerates to one goal, still emitted (uniform artifact class).
2. Specs across repos where one repo lacks the kit -> dispatch prompt says "hand-write tests in the repo's framework" instead of `/kit:test-write` (the 2026-08-31 G1 shape).
3. Auditor finds a gap the lead cannot close from written sources (true session-only knowledge) -> becomes an operator-input row, never silently dropped.
4. Re-running pack on an already-packed slug -> regenerates prompts, preserves the operator-inputs table's filled values.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Auditor rubber-stamps (cheap-model audit too shallow) | workers stall mid-execute on missing context | auditor briefed to REFUTE readiness (brief-source-readers-to-refute discipline); audit runs at Sonnet minimum |
| Template drift from evolving estate conventions | packs stop matching repo reality | templates are files, edited like any kit surface; topology-drift covers the registry rows |

## Out of Scope
- Auto-launching workers (stays `/kit:dispatch` or manual paste).
- Fixture generation (prompted as pre-dispatch TODOs, lead-captured).
- Any change to the gauntlet/cleanroom runner.

## Decision Log
- DEC-001: Separate command over extending mega/execute, packing is its own lifecycle moment (post-validate, pre-dispatch) with its own artifact class.
- DEC-002: The pack lands in the invoking cockpit repo's `_meta/megagoals/<slug>/`, matching the estate's existing mega-goal container; the kit does not invent a new location.
- DEC-003: Context-block patches go to each spec's own repo, specs stay the single source a worker reads; the pack never duplicates spec content.
- DEC-004 (parallel-session reconciliation): the audit step composes with the gauntlet generalization instead of competing. One-shot auditor = cheap default; the gauntlet's spec-readiness preset = the escalation for packs where a stalled worker is expensive. The preset itself is a preset-table row under that spec's rules, not built here.

## Open questions
(none)
