# Decision Brief: skill fleet (cross-runtime skill management + dispatch visibility)

Date: 2026-07-25 · Source: operator feature ask ("users run Claude Code as daily driver, Codex
for one purpose, pi for another; integrate the skills + dispatching and render it visually").
Status: DRAFT. Consuming rows: ID-431, ID-432. Composes with: ID-396 packaging doctrine (one
core + generated per-host adapter), ID-390 multi-vendor dispatch (Harness: header), ID-407
workflow gallery, ID-399 trace overlay, forge dashboard.

## The problem (real, and the operator lives it)

A developer's agent estate fragments across runtimes: skills installed in Claude Code, a
different set under Codex, another under pi, drifting versions, duplicated bodies, no view of
what lives where or WHICH RUNTIME IS FOR WHAT. The ecosystem's answer today is superpowers-style
per-harness reinstall (our recorded AVOID: hand-maintained duplicates), or nothing.

## The design (three pieces, one plain-file spine)

```
1. SKILL REGISTRY (the source of truth, plain files)
   skills/<name>/SKILL.md            one body per skill (N4: the artifact is the API)
   fleet.toml                        registry: which skills -> which harnesses, versions,
                                     + the ROUTING MAP: purpose -> runtime
                                     (e.g. daily-drive+advisor=claude, bulk-refactor=codex,
                                      experiments=pi)

2. SYNC/ADAPT ENGINE (`fleet sync`)
   generates each harness's loader format FROM the one body:
   CC skill dir · Codex agents/openai.yaml sidecar · pi/opencode format
   detects drift (a hand-edited copy diverging from source), never silently overwrites.
   The antidote to per-harness reinstall: one source, generated adapters
   (mattpocock's dual-harness pattern, generalized).

3. FLEET RENDER (`fleet render` + a dashboard panel)
   the visual: a runtime-by-purpose grid showing which skills are live where, versions,
   drift flags, and the routing map; ASCII in the terminal (no mermaid), a panel in the
   Crew dashboard for teams. Composes with the workflow gallery (ID-407) and, later, the
   trace overlay (ID-399) so a DISPATCH is visible against the same map.
```

## Honesty boundary (same as everywhere)

The skills SYNC everywhere; the ENFORCEMENT does not (hooks stay CC-only until multi-runtime
agent-hooks land). fleet render labels each harness full / advisory, same per-runtime capability
table as the site. Routing is DECLARED (the map is documentation the doctor can read), and only
ENFORCED where a dispatcher exists (ID-390's Harness: header executes it; elsewhere it is a
rendered convention).

## Tier placement (docs/tiers.md updated)

- **Core:** the registry + `fleet sync` + `fleet render` locally (plain files; the sync engine is
  an adoption driver and pure N4).
- **Craft:** synced skills ride the private stream (maintained skill/ladder updates propagate to
  every harness in one pull).
- **Crew:** org-shared packs distributed fleet-wide (already in the tier list) + the dashboard
  fleet panel; the org's routing map becomes policy-as-code (a declared purpose->runtime map the
  gateway can check).

## North-star conformance (§6)

N4 verbatim (one plain-file source, generated adapters, works with any single harness deleted);
N7 (the team's skill estate stops being tribal knowledge); N5 (the routing map feeds ID-390's
dispatcher). Explicitly implements the packaging AVOID ("never per-harness hand copies") as a
product feature.

## Open decisions for Han

1. `fleet.toml` location: one global (~/.forge/) vs per-repo with global fallback (proposed:
   global registry, per-repo overrides, same override stack as everything else).
2. Does `fleet sync` manage THIRD-PARTY skills too (adopted from marketplaces) or only the
   user's own? (proposed: both, with upstream-watch semantics from absorb-watch for the third
   party ones).
3. Dashboard fleet panel: v1 read-only render vs editable routing (proposed: read-only first).
