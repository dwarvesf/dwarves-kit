# Implementation notes: runs-dashboard

Delta from `docs/specs/SPEC-215-runs-dashboard.md`. Only what the spec did not say, or said differently.

## 2026-07-31 16:20 Discovery gained a fourth artifact shape

Context: the spec's Design named three sources: `_meta/megagoals/**/RUN_REPORT.md`, `**/docs/proof-of-done.md`, and `docs/verification/**/runs/*.md`. The first estate run over those three produced 119 cards from 4 repos.

Decision: added a fourth shape, the flat `docs/verification/<slug>.md`.

Why: `docs/verification/README.md` documents that shape as still accepted by the ship gate, and it turned out to be the DOMINANT shape in the live estate. Adding it took the estate render from 119 cards across 4 repos to 492 across 7. It also unlocked the only other capture-bearing document in the estate. A dashboard that silently hides most of the corpus is worse than no dashboard, because it reads as complete.

Alternatives: leave it out and document the gap. Rejected. The gap was not a rounding error, it was the majority of the data.

Impact: `README.md` and `test-design.md` are excluded by name inside that shape, since both are design documents rather than run records. Pinned by the test that asserts exactly four cards from a fixture containing both.

## 2026-07-31 16:25 Per-image embed cap raised to 3 MB

Context: the drafted cap was 512 KB per image.

Decision: 3 MB per image, total page budget unchanged at 12 MB.

Why: measured against the real corpus rather than a round number. The estate's richest visual proof (`tools/dictate`) carries retina screenshots between 1.0 and 2.0 MB each. At 512 KB the single most visual tool in the estate rendered zero pictures and five "over budget" links, which inverted the point of the feature.

Impact: the current full-estate page is about 11 MB with 42 images embedded and exactly one honest over-budget fallback. The total budget, not the per-image cap, is now the binding constraint.

## 2026-07-31 16:25 Known ceiling: the total budget is spent in scan order

Not a deviation, a recorded limitation. Once the 12 MB total budget is exhausted, the captures that degrade to links are whichever repos happen to sort last, not the least valuable ones. Marked with a `ponytail:` comment at the allocation site. Acceptable while the estate degrades one capture in forty. If that ratio grows, allocate a per-repo share before embedding instead of first-come.

## 2026-07-31 16:30 mega-review.py extends by import, confirmed against the code

The spec predicted this in DEC-003; recording that it held after reading the module. `mega-review.py`'s render path is bound to one mega's ROADMAP sub-goal rows and the per-rid gate ledger, and exposes no seam that accepts an unrelated document set. What genuinely transferred: `_CSS`, `_e`, and `_run`, imported through the same `importlib` convention that module itself uses for `lib/gate/proof-table-gen.py`. The dashboard layers a grid stylesheet ON TOP of the imported `_CSS` rather than restating the palette, so the two surfaces cannot drift apart on colour or dark-scheme handling.

## 2026-07-31 16:35 Test count differs from the spec's matrix

The spec's `## Test plan` listed 14 rows. The suite runs 21 checks: several matrix rows expand into more than one assertion (the empty-state row covers both an empty directory and a nonexistent one), and two checks were added that the matrix did not name, both asserting the verb is actually reachable through `mega runs` and documented in `mega --help`. No matrix row is unimplemented.

## Pre-existing failure, not caused by this branch

`tests/test-bin-forwarders.sh` fails one check: its `bin/` census expects a list that omits `activate` and `release`, both of which exist on master. This branch adds no `bin/` entry (`mega runs` rides the existing `bin/mega`) and `git diff master -- bin/` is empty. Left alone per the surgical-changes rule; it wants its own row.
