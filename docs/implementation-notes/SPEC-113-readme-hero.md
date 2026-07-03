# Implementation notes: SPEC-113 readme-hero

Delta from the spec. References, does not restate.

## 2026-07-03 deltas

- **Count is 24, not the goal's "18".** The goal title said "agents 11->18"; docs run LAST, so the
  FINAL live count (after 09 added 6 agents) is 24. Fixed to 24 (this is why the docs sub-goals run
  after all machinery , they reflect final state).
- **The agents directory-layout pin is NEW; hooks already had one.** test-meta already carried a
  SPEC-085 hooks parity pin (README hooks summary/rows == hook files), which is why hooks stayed at
  the right count. The AGENTS directory-layout count had NO pin , which is exactly why it drifted to
  11. SPEC-113 adds the agents (and a redundant-but-harmless hooks) layout-count pin.
- **Render "capture" is the gh markdown API tag**, not a pixel screenshot (uncapturable from the
  loop): `gh api -X POST /markdown` returns `class="highlight highlight-source-mermaid"` for the
  fence, i.e. GitHub renders it as a mermaid diagram. The parity pin is the durable guarantee (a
  screenshot rots; the pin does not).
- **architecture.md:77 prose total** ("15 agents / 40 entries", flagged in the 09 review) is a
  DIFFERENT surface (docs/architecture.md prose, not README) , left for sub-goal 02 (docs index) or
  TIER-4; out of 01's README-scoped surgical change. Noted in mega NOTES.
