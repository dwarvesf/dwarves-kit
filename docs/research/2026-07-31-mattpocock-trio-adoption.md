---
title: Adoption design, mattpocock/skills wayfinder + code-review + prototype
date: 2026-07-31
purpose: >
  Han asked to adopt three named skills from mattpocock/skills into the
  workflow and the kit. Focused re-read of only those three (dedup gate: the
  repo was fully mined 2026-07-08 and delta-read 2026-07-25), a correction to
  the watch marker, per-mechanism verdicts, and the smallest adoption design
  for each. Board rows ID-448/449/450.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: as-needed
next_review: 2026-10-01
status: active
---

# mattpocock trio adoption (2026-07-31)

Prior touches (dedup gate): full mine 2026-07-08 (ops-toolkit
`research/2026-07-08-mattpocock-skills-design-patterns.md`, ID-119), delta
2026-07-25 (`2026-07-25-skills-repos-onboarding-absorption.md` §1, VERDICTS
row 2026-07-25). This pass is an adoption design for three named skills, not a
re-evaluation of the repo. Han's explicit adopt ask overrides the 2026-07-25
park on wayfinder.

## Watch marker correction

The 2026-07-25 marker recorded "v1.2 (plugin shipped)". Wrong: upstream
CHANGELOG has only 1.0.0 / 1.0.1 / 1.1.0. The plugin ship, the Codex metadata,
the prototype primary-source change, and the wayfinder research-subagents
change are nine UNRELEASED changesets on main (5 minor + 4 patch); the next
release will be 1.2.0. Corrected in the 07-25 marker table. Watch signal
unchanged: re-read on the 1.2.0 CHANGELOG entry. License: MIT (mechanisms and
adapted text both fine; keep a Credits line per docs/ABSORPTION.md).

## 1. wayfinder

Upstream mechanism (pre-1.2.0 main): a decision map for work bigger than one
agent session. One map issue (Destination / Notes / Decisions-so-far gists /
Not-yet-specified fog / Out of scope), child "decision tickets" typed
research | prototype | grilling | task, each sized to one session. Claim by
assignment. Frontier = open, unblocked, unclaimed. HITL/AFK split per type (a
grilling agent that answers its own questions has broken the contract). One
ticket per session, except research tickets which fan out to parallel
subagents on throwaway `research/<name>` branches. On map-clear, hand off to
spec, never straight to implement. Upstream ships a local-markdown fallback:
one file per ticket at `.scratch/<feature>/issues/<NN>-<slug>.md`.

| Mechanism | Verdict | Design |
|---|---|---|
| Decision-map beat (map-as-index, decide-vs-do split, fog section) | ABSORB | New `/kit:wayfind` command, file-based (upstream's own fallback shape, zero new infra): `docs/wayfinder/<slug>/map.md` + `tickets/NN-<slug>.md` |
| Typed tickets routing to owned skills | ABSORB | grilling -> `/kit:grill`, prototype -> `/kit:prototype` (ID-448), research -> parallel research subagents, task -> normal lane |
| Claim + frontier semantics | ABSORB (map, do not build) | claim = the existing kanban `claimed` state; frontier = queued rows with no open blocker. No new state machine |
| One-ticket-per-session, research excepted; map-clear hands to `/kit:spec` | ABSORB (contract lines) | two lines in the wayfind command body |
| Tracker-native storage, native blocking edges, fog rendered in tracker UI | PARK (unchanged) | tripwire unchanged from 07-25: the Multica pilot outgrows flat cards and needs dependency/frontier queries. ID-425 (board-github adapter work) is the natural unpark vehicle |

Row: ID-450. Upstream's own admitted failure mode is over-reach ("slower and
denser than a single grill"); the command body must carry that router line: a
well-scoped feature goes to `/kit:grill` + `/kit:spec`, not wayfind.

## 2. code-review

Upstream mechanism: review since a fixed point along two axes, Standards and
Spec, in two parallel context-isolated subagents; reports side by side, never
merged or reranked ("Don't pick a single winner across axes , that's the
reranking the separation exists to prevent"). Fail-fast before dispatch
(`git rev-parse` the fixed point + non-empty diff). Standards axis carries an
always-on Fowler 12-smell baseline (Refactoring ch.3) with three binding
rules: the repo's documented standard overrides the baseline; every smell is a
labelled judgement call ("possible Feature Envy"), never a hard violation;
skip anything tooling already enforces.

The kit already owns this surface: `/kit:review` (5 weighted lenses,
stale-ADR inversion, rejected-findings ledger) and `/kit:review-team`
(parallel isolated lenses incl. spec-compliance in the architecture lens).
Wholesale adoption fails the "reason a small re-implementation cannot
satisfy" test. Deltas that are genuinely new:

| Mechanism | Verdict | Design |
|---|---|---|
| Fowler 12-smell baseline + the three binding rules | ABSORB (tiny) | inline the named smell list into `/kit:review` Quality/Architecture sections; paste it into review-team's architecture-lens brief (subagents have no other access to it) |
| Fail-fast ref check before parallel dispatch | ABSORB (one line) | review-team Step 1 gains `git rev-parse <fixed-point>` + non-empty-diff check before any Agent call |
| Per-axis no-rerank reporting | ABSORB (one line) | review-team merge step keeps per-lens attribution and never ranks across lenses; dedup within a lens only |
| Two-axis Standards/Spec split as a command | SKIP | review-team's lens architecture is a superset |

Row: ID-449.

## 3. prototype

Upstream mechanism: throwaway code that answers a design question; the
question decides the shape. Thin router (26 lines) branching to LOGIC.md
(pure portable module behind a full-frame TUI, no I/O in the logic, no tests,
no real DB) or UI.md (3-5 structurally different variants on one route,
`?variant=` param + floating switch bar gated out of production builds).
Shared rules: throwaway from day one, one command to run, no persistence,
surface full state after every action. Since the pending 1.2.0 change the
prototype is captured as a primary source: committed to a `prototype/<name>`
branch out of main, context pointer left on the implementation issue; main
keeps only the validated decision.

The kit has no spike beat (think -> design -> spec -> execute goes straight
from prose to spec), and ID-450's prototype tickets need a target. The
ops-toolkit experiments gradient is a different animal (tool trials in a
dedicated repo, not in-repo design spikes).

| Mechanism | Verdict | Design |
|---|---|---|
| Whole skill (router + LOGIC + UI references) | ABSORB | new `/kit:prototype` command + two reference files, re-voiced to kit conventions, MIT attribution in Credits |
| Primary-source capture on `prototype/<name>` branch | ABSORB (inside) | pointer lands on the owning board row / spec, matching the kit's flat-card tracker |
| NODE_ENV-gated variant bar, structural-difference rule, wrong-branch warning | ABSORB (inside) | kept verbatim-in-spirit in the reference files |

Row: ID-448.

## 4. Wiring into the SDLC (added 2026-07-31, same pass)

The three land at three altitudes of the existing workflow (docs/WORKFLOW.md).
Prototype is a new opt-in phase instrument next to /kit:design. The
code-review deltas are in-place edits to existing phase commands, zero
workflow change. Wayfind is not a phase: it is a pre-cycle intake shape
beside the board, feeding /kit:spec or /kit:mega.

```
                        WHERE WORK COMES FROM
  board (_meta/BACKLOG.md) ──────────────┐
                                         │
  /kit:wayfind  ← NEW, pre-cycle         │   too foggy for one grill?
  map.md + decision tickets              │   /kit:think or /kit:grill
  (research|prototype|grilling|task)     │   escalates UP to wayfind
        │  map clear = nothing           │
        │  left to decide                ▼
        └──────────────► THE CYCLE (per work item)
                         Phase 0: /kit:grill → done scenario
                              │
                         /kit:think ──► /kit:design (opt-in)
                              │              │ "can't settle this in prose"
                              │              ▼
                              │         /kit:prototype  ← NEW, opt-in beat
                              │         answer on prototype/<name> branch,
                              │         fold DECISION into the brief
                              ▼
                         /kit:spec → validate → test-plan
                              │
                         /kit:execute
                              │
                         /kit:review, /kit:review-team  ← ID-449 edits land
                              │
                         /kit:docs → /kit:ship → /kit:retro
```

Wiring contract, per piece:

- **ID-449 (code-review deltas)**: edits inside /kit:review and
  /kit:review-team only. Nothing enters the phase table. The upstream "Spec
  axis" already exists as the architecture lens + stale-ADR inversion.
- **ID-448 (/kit:prototype)**: new opt-in phase-table row, advisory
  enforcement, same class as /kit:design. Exit = validated decision folded
  into the brief/spec + `prototype/<name>` branch pointer. Entry from
  /kit:design when an approach question resists prose, and from wayfind
  prototype tickets. Proof class: inert on main (the branch is the artifact;
  nothing behavioral merges), so the ship-gate never demands a proof-of-done
  for a spike. HITL by contract.
- **ID-450 (/kit:wayfind)**: intake shape at the board layer. One umbrella
  board row per map; tickets live in the map folder and are never duplicated
  as board rows (the markdown board stays the one source of truth).
  Escalation trigger: /kit:think or a grill keeps producing questions that
  cannot be stated precisely yet, or the brief carries 3+ unresolved
  decisions. Exit: map clear hands to /kit:spec (single feature) or /kit:mega
  (roadmap); Decisions-so-far becomes the brief's Context.

Three composition decisions, so this composes instead of bolting on:

1. **Co-locate the map with the mega-goal folder.** The map lives at
   `_meta/megagoals/<slug>/map.md`, not a new `docs/wayfinder/` tree
   (supersedes the §1 path). Wayfind is the decide-half of the shape the
   mega-goal already owns as the do-half; graduation = write ROADMAP.md next
   to map.md in the same folder.
2. **Reuse the type loops as ticket executors.** A research ticket IS the
   research type loop, runnable AFK via the same DELEGATE `claude -p`
   machinery as the mega conductor, and it is the one multi-ticket-per-session
   exception. Grilling and prototype tickets are HITL; the conductor must
   never delegate a grilling ticket (an agent answering its own grill
   questions is the upstream's documented failure mode). No new executor
   machinery.
3. **Phase 0 stays universal.** Wayfind does not replace the per-item grill;
   each ticket that graduates into a work item still enters the cycle through
   /kit:grill and the done-scenario definition. The map spares re-deriving
   context; it never skips the gate.

Build order: ID-449 (one-file edits) -> ID-448 (wayfind depends on it) ->
ID-450.

## Routing

- Board rows ID-448 (prototype), ID-449 (code-review deltas), ID-450
  (wayfind) on the kit board, queued. Three independent items, no shared
  destination: no mega umbrella.
- Watch marker table in `2026-07-25-skills-repos-onboarding-absorption.md`
  corrected (last seen = v1.1.0 + 9 pending changesets).
- ops-toolkit keeps the VERDICTS row + a pointer stub
  (`research/2026-07-31-mattpocock-trio-adoption.md`) per the ID-399
  co-location rule.
