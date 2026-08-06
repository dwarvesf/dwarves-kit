---
title: GStack product-thinking skills vs dwarves-kit, and the two-part seam
date: 2026-06-12
purpose: >
  Source-read analysis of Garry Tan's GStack (github.com/garrytan/gstack) against
  the dwarves-kit lifecycle kit, to decide what product-thinking capability to add.
  Conclusion: keep product-thinking and build as two separate parts joined only at
  the DECISION-BRIEF.md seam; use GStack as-is for the product front and hook into
  dwarves-kit for build. Reference for backlog ID-051 when it unparks.
source_repos: [ops-toolkit, dwarves-kit]
refresh_cadence: none
next_review: null
status: active
---

# GStack product skills vs dwarves-kit

Captured from a 2026-06-12/13 session. Backlog item: **ID-051** (parked). This note
is the durable record; the backlog row is the index.

## Why this exists

dwarves-kit is strong on the **build** half of the lifecycle (think -> spec -> execute
-> review -> ship -> retro, plus the proof-of-done gate, lane classification, worktree
discipline). It is thin on the **product-thinking** front: no founder-mode scope-up, no
demand/PMF interrogation, no DX lens. Han wanted to fill that gap, prompted by GStack.

## The two kits Garry Tan published

- **GStack** (github.com/garrytan/gstack): 30+ Claude Code skills turning Claude into a
  full startup team (CEO, Designer, Eng Manager, QA, Release). This is the product-relevant
  one. Philosophy: explicit cognitive gears, ship velocity (~10K LOC/week claim),
  completeness ("AI makes completeness cheap, so the complete thing is the goal").
- **GBrain**: agent memory/retrieval system (MIT, SOTA on LongMemEval). NOT product. If a
  "second product kit" is remembered, it is likely a conflation; GBrain is memory.

## The funnel: each kit wins a different half

```
DISCOVER -- THINK -- DESIGN -- SPEC -- BUILD -- REVIEW -- SHIP -- REFLECT
  GAP      ~overlap  ~partial  ######  ######   ######   ####   ######
  \________ GStack wins here ________/      \___ dwarves-kit wins here (+ proof gate) ___/
            scope-UP, exploratory                    scope-DOWN, disciplined
```

## Skill-by-skill (read from source, not blog summaries)

| GStack skill | Lens it brings | Closest dwarves-kit | Gap verdict |
|---|---|---|---|
| `/office-hours` | Demand/PMF: "would they be upset if it vanished?", "name the actual human", "smallest version someone pays for this week", + a separate **Builder mode** for side-projects/hackathons | `/think` (6 Q, but **feasibility**-centric: pain, 10x, MVP, cut, scale, metric) | Same shape, different lens. Net-new = market-demand interrogation + builder mode (fits experiments) |
| `/plan-ceo-review` | **Founder mode, scope-UP**: 4 modes (expansion / selective / hold / reduction), "10-star product hiding inside", premise challenge, 12-month dream-state, CEO mental models (Bezos one/two-way doors, Munger inversion, Jobs subtraction) | none | **Full gap.** The crown jewel for "think about + critique product". Kit only knows scope-DOWN |
| `/plan-devex-review` | **DX for CLI/API/SDK**: Time-to-Hello-World tiers, magical-moment design, empathy narrative, 7 DX characteristics, Discover->Upgrade journey trace | none | **Full gap.** High fit: ops-toolkit is full of agent-callable CLIs (a DX surface) |
| `/plan-design-review` | Design rating 0-10 at **plan stage** | `/visual-team` (5 lenses, **post-build**) | Partial: only the plan-stage gate is missing |
| `/design-consultation`, `/design-shotgun` | Zero-to-one design system + variant generation | `website-brand`, `image-spec`, `/ui-design` | Covered differently. Low value |
| `/autoplan` | Orchestrate CEO -> design -> eng | `/devs-team` (eng lenses only) | Partial: missing the CEO orchestration layer |
| `/review` `/ship` `/qa` `/cso` `/retro` | eng / ship / test / security | `/kit:*` equivalents + proof gate | **Skip, duplicate** |

### Key detail: /think vs /office-hours

`/think` asks build-feasibility questions and emits `docs/specs/DECISION-BRIEF.md`
(verdict BUILD / RETHINK / KILL). `/office-hours` asks demand-reality questions and emits
a design doc to `~/.gstack/projects/{slug}/`, with a mandatory 2-3 alternatives pass and a
hard gate ("produces design clarity only; do NOT implement"). The demand lens is the real
gap; the shape is otherwise similar.

## Philosophy clash (the load-bearing caveat)

`/plan-ceo-review` carries "boil the ocean one lake at a time, the complete thing is the
goal." That directly opposes Han's coding discipline (Simplicity first / minimum infra /
surgical changes). GStack's whole back half is velocity + completeness + auto-fix. So the
value is additive **only at the front of the funnel** (product thinking / critique), where
dwarves-kit is genuinely thin. Do NOT import GStack's build/ship half.

## Decision: two separate parts, joined at one seam

Keep product-thinking (scope-UP, exploratory, allowed to dream big) and build (dwarves-kit,
scope-DOWN, proof-of-done) as **two separate parts**. They communicate only through one
artifact, mirroring how GStack itself stops at a design doc for downstream consumption.

```
GSTACK (product front)              SEAM                       DWARVES-KIT (build)
/office-hours      (demand/PMF) ┐
/plan-ceo-review   (scope 10★)  ├─► design doc / CEO plan ──► docs/specs/        ──► /kit:spec
/plan-devex-review (DX for CLI) │    (~/.gstack/projects/)     DECISION-BRIEF.md      → /kit:execute
/plan-design-review(UI plan)    ┘         │                         ▲                 → /kit:review
                                          └── bridge: copy + map ────┘                 → /kit:ship
                                              (Problem + Approaches)                    (proof-of-done gate)
```

### Why the seam is near-free (verified against source)

`/kit:spec` Step 1 (`kit/1.6.0/commands/spec.md`): *"If a `docs/specs/DECISION-BRIEF.md`
exists, read it first ... fold that into the spec's `## Solution`. Otherwise, ask the user."*
The build entry contract is just a `DECISION-BRIEF.md` with `## Problem` + `## Solution`.
GStack's design doc already emits Problem statement + Alternative approaches + Recommended
approach + rationale, which is exactly what the spec's `## Solution` wants ("Approaches
considered" + "Chosen approach + why"). The bridge is **relocate + reheading, not translate**.

## Recommended path (when ID-051 unparks)

1. Use GStack as-is for the product front. Use only `/office-hours`, `/plan-ceo-review`,
   `/plan-devex-review`, `/plan-design-review`. **Skip** GStack `/review` `/ship` `/qa`
   `/cso` and the **eng tail of `/autoplan`** (that is `/kit:*`'s job).
2. Start the seam **manual**: after a product command, copy the doc from
   `~/.gstack/projects/{slug}/` into `docs/specs/DECISION-BRIEF.md`, then run `/kit:spec`.
   Zero infra (honors minimum-infra-first). Validate the flow once.
3. Codify a ~30-line **bridge skill** only if it repeats (reads the latest GStack design
   doc / CEO plan, normalizes into in-repo `DECISION-BRIEF.md`, suggests `/kit:spec`). This
   also pulls the artifact **into the repo**, fixing GStack's `~/.gstack/` writes that
   violate "reproducible from repo".

### Watch at install time (unverified, GStack not yet installed)

Full GStack pulls a browser daemon, gbrain, iOS tooling, a **Continuous Checkpoint Mode that
auto-commits `[gstack-context]` WIP**, and an **ExitPlanMode gate** (blocks until a
`## GSTACK REVIEW REPORT` heading exists). The last two can collide with worktree discipline,
the dotfiles S-64 atomic-commit watcher, and plan-mode. Mitigation: disable those hooks, or
vendor just the 4 product-skill directories instead of a full install. No slash collision:
GStack commands are bare (`/office-hours`), dwarves-kit is namespaced (`/kit:*`).

## Source files read

- dwarves-kit: `kit/1.6.0/commands/{think,devs-team,spec}.md`.
- GStack: `{office-hours,plan-ceo-review,plan-devex-review}/SKILL.md` + `docs/skills.md` +
  README (via raw.githubusercontent + GitHub tree API).
