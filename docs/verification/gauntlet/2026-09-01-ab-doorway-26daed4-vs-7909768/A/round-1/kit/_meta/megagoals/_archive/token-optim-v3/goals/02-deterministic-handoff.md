# Sub-goal 02: deterministic-handoff

**Merge policy:** gate (dwarves-kit shared repo, team review)
**Time budget:** ~1 session
**Proof:** run-table A/B , a fresh session cold-started from the deterministic handoff resumes the
work without re-discovery, matching or beating the LLM-written handoff (turns-to-first-correct-action
not worse).
**Depends on:** SG-01 (the extractor technique; cross-repo, port not stack)
**Branch:** `feat/v3-det-handoff`
**PR base:** dwarves-kit `main`

## Outcome
The orchestrator's two-tier feed-forward handoff (v2 SG-02: hot HANDOFF + warm DECISIONS, dead-ends
+ next-action + read-pointers) is generated DETERMINISTICALLY from the finishing session's
transcript, instead of relying on the LLM session to write a good handoff. The handoff stops being a
thing the model might forget to do well.

## Quality bar
The deterministic handoff is at least as resumable as the hand-written one: a fresh session reads it
and takes the right next action without re-grepping the codebase. Deterministic + always-produced
beats occasionally-excellent-but-skippable.

## How to close the loop
In the dwarves-kit checkout, wire the extractor (ported from SG-01) into the orchestrator's handoff
step. A/B on the SG-12 benchmark fixture:
```
bash tests/test-orchestrate.sh                 # handoff-generation assertions green
# A/B: run a 2-sub-goal fixture, capture both handoffs
#  arm A: LLM-written handoff (current)   arm B: deterministic handoff
# cold-start a fresh session from each; record turns-to-first-correct-action + rework
```
Capture a run-table: handoff produced deterministically (`cmp`-clean re-run), cold-resume succeeds
for arm B, turns-to-first-correct-action(B) <= (A).

**Done =** the orchestrator emits the two-tier handoff deterministically from the transcript, a
fresh session cold-resumes from it without re-discovery, and the A/B run-table shows arm B's
turns-to-first-correct-action is not worse than the LLM-written arm A.

## Scope edges
**In:** the orchestrator's handoff-generation step (`lib/orchestrate.sh` handoff path) + its test,
consuming the SG-01 extractor.
**Out:** the PoC itself (SG-01), the recall CLI (SG-03), the interactive command (SG-04). Do NOT
rewrite v2 SG-02's hot/warm CONTRACT (the fields); only change how it is GENERATED.
**Not:** an LLM call in the handoff path; a new handoff schema; touching the in-session /goal loop.

## Where to look
v2 SG-02 contract: `_meta/megagoals/token-optim-v2/goals/02-two-tier-handoff.md` + dwarves-kit
SPEC-087 Mech B. The orchestrator: `lib/orchestrate.sh` (#81). pi-vcc sticky-vs-volatile merge (the
handoff IS a sticky/volatile split). SG-01's extractor. `research/2026-06-29-pi-swarm-comparison.md`
("findings in the record" wording).

## PR body
feat(kit): generate the orchestrator's two-tier handoff deterministically from the transcript
(no-LLM, ports pi-vcc extraction). Strengthens v2 SG-02 (#83): handoff is always produced, not
model-dependent. Verification: A/B run-table (cold-resume + turns-to-green parity). Gated for team
review. token-optim-v3 sub-goal 02.

## Notes
