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

## Routing

- Board rows ID-448 (prototype), ID-449 (code-review deltas), ID-450
  (wayfind) on the kit board, queued. Three independent items, no shared
  destination: no mega umbrella.
- Watch marker table in `2026-07-25-skills-repos-onboarding-absorption.md`
  corrected (last seen = v1.1.0 + 9 pending changesets).
- ops-toolkit keeps the VERDICTS row + a pointer stub
  (`research/2026-07-31-mattpocock-trio-adoption.md`) per the ID-399
  co-location rule.
