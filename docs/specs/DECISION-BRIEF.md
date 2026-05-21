# Decision Brief: Recurring open-discovery absorption (SPEC-004 lane B)

Produced by `/user:think` + `/user:design` (dogfooded), 2026-05-21. Feeds the SPEC-004 widening (already drafted; this brief is the upstream framing the spec should match).

## Verdict: BUILD (scope-narrowed)

## Core thesis
The kit's "synthesize from the best" promise decays without a recurring re-scan; SPEC-002/014 proved the survey's value as one-shots, so make it recurring, but only as far as the kit's tools can honestly support.

## Strongest argument for
SPEC-014's wide survey (12 repos, ~90 components) found 3 real adoptions; the ecosystem moves weekly across the now-broader interest areas (agents/QA/UI), and nothing re-checks it. The recurring engine mechanizes the next survey.

## Strongest argument against
It mechanizes a cadence that has run once (PHILOSOPHY "no speculative features"), and true open *discovery* of brand-new sources is tool-weak (WebFetch fetches known URLs; it does not discover). An occasional manual SPEC-014-style survey may suffice.

## Recommended scope for v1 (the Q3/Q4 narrowing)
- **IN:** lane B = re-scan a **pinned seed set** (SPEC-014's 12 repos union README Credits) for new/changed patterns since the last run; auto-score against the inline rubric; auto-draft a **ranked, capped** proposal; weight **agents + workflow** (high absorb yield) over **QA/UI** (which route to "recommend external" per PHILOSOPHY §3).
- **CUT for v1:** open web-**search** discovery of unknown sources (no kit discovery primitive; noisy/rate-limited/injection-prone); deep UI/design scanning (low absorb yield); any cadence automation (stays maintainer-triggered).
- **GATE:** discovery + scoring + drafting are automatic; **adoption, and growing the seed list, are human-approved** (preserves "synthesize, don't originate").

## Exit criteria
Over 2-3 runs, lane B surfaces >=1 genuinely-adopted pattern the maintainer would otherwise have missed, AND proposals stay scannable (~<=15 ranked candidates). If runs produce only ignored noise, it failed -> revert to occasional manual surveys.

## Solution

### Approaches considered
- **A (chosen): pinned seed list in `docs/ABSORPTION.md`.** Lane B re-scans a pinned list (SPEC-014's 12 repos union README Credits); the list grows only by maintainer edit. Scores, ranks, caps the proposal, weights agents/workflow over QA/UI. Tradeoff: one more list to hand-maintain, but simplest and no fragile parse.
- **B: derive the seed from SPEC-014 + Credits at runtime.** No pinned list, but couples to SPEC-014's point-in-time prose (fragile parse); SPEC-014 is a frozen doc, not a living source list. Rejected.
- **C: structured `docs/absorption/SOURCES.md` watchlist.** Cleanest data surface, but adds a file and is the curated-list option trimmed in Think. Rejected for v1 (revisit if the pinned list outgrows ABSORPTION.md).

### Chosen approach + why
A. It is the seed-rescan MVP with the smallest honest surface: no new discovery primitive, no fragile runtime parse, and the seed grows only by a maintainer edit, which keeps the human gate that protects "synthesize, don't originate." Noise (the Q5 risk) is controlled by ranking + a proposal cap + interest-area weighting, not by scanning less.

### Extensibility & boundaries
- **Load-bearing dimension:** the seed list size + ecosystem velocity. When the pinned list outgrows readability in ABSORPTION.md, promote it to the structured `SOURCES.md` (approach C) without changing the command's logic. When web-search discovery becomes worth it (a real "we keep missing brand-new repos" signal), add it as a third lane behind the same merge gate.
- **Unit boundaries:** lane A (Credits drift) and lane B (seed-rescan) are separate scan units feeding one proposal; the rubric/gate is shared and unchanged; the seed list is data, the command is logic. Adding web-search later is a new lane, not a rewrite.
- **Out:** auto-adoption, web-search discovery (v1), cadence automation, deep UI scanning.
