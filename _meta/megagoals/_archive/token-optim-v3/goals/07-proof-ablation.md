# Sub-goal 07: proof-ablation

**Merge policy:** gate (the proof methodology must be human-blessed, anti-cherry-pick; mirrors v2 SG-09)
**Time budget:** ~1 session, AFTER v2 SG-09 + SG-01..04
**Proof:** TEST-REPORT , the ablation numbers for the v3 deterministic-compaction levers vs a
pre-registered threshold, with turns-to-green/rework as the coherence proxy.
**Depends on:** v2 SG-09 (the ablation methodology + threshold) + SG-12 (the fixture, done #595) +
this wave's SG-01..04 (the levers measured).
**Branch:** `test/v3-proof-ablation`
**PR base:** ops-toolkit `main`

## Outcome
v3's central claim is proven the same way v2's is: a token+quality ABLATION over the SG-12 fixed
benchmark against a PRE-REGISTERED threshold. The new question v3 adds: does DETERMINISTIC compaction
(vs LLM compaction vs no compaction) hold coherence? i.e. does recall (SG-03) prevent the rework
that lossy compaction causes, with turns-to-green not worse.

## Quality bar
A naive before/after is rejected (confounded), same as v2. Each v3 lever (deterministic handoff,
recall-backed compaction) is kept ONLY if its isolated delta is a positive win at quality parity,
else dropped. turns-to-green + rework are the coherence proxy: a lever that saves tokens but makes
the agent thrash fails the gate.

## How to close the loop
PRECONDITION: v2 SG-09's harness + threshold exist and SG-01..04 are built. Extend the SG-09
ablation to add the v3 arms:
```
# arms: baseline -> +deterministic-handoff -> +recall-backed-compaction
# over the SG-12 fixture; pre-register the threshold BEFORE running
bash <sg-12-fixture>/run-ablation.sh --arms v3
```
Capture a TEST-REPORT: per-arm tokens + pass-parity + turns-to-green + rework; each lever's isolated
delta; the keep/drop verdict per lever against the pre-registered threshold.

**Done =** the ablation reports each v3 lever's isolated token+quality delta over the SG-12 fixture
vs a pre-registered threshold, with a keep/drop verdict per lever, and the TEST-REPORT shows
turns-to-green is not worse for any kept lever.

## Scope edges
**In:** extending v2 SG-09's ablation harness with the v3 arms + the TEST-REPORT.
**Out:** building the levers (SG-01..04); the v2 levers' own proof (SG-09 owns those).
**Not:** a confounded before/after; cherry-picking a winning run; declaring a win without
pre-registering the threshold.

## Where to look
v2 SG-09: `_meta/megagoals/token-optim-v2/goals/09-measurement.md` (the methodology to extend).
SG-12 fixture: PR #595 / `experiments/token-eval-bench/`. `tools/token-forensic/` (`--loops`).
`research/2026-06-29-token-coherence-design.md` ("How we will KNOW it worked").

## PR body
test: token+quality ablation proving v3's deterministic-compaction levers vs a pre-registered
threshold (extends v2 SG-09 over the SG-12 fixture). Gated (methodology must be human-blessed).
token-optim-v3 sub-goal 07.

## Notes
