# Decision Brief: low-steering operating model (three human gates, autonomous middle)

Date: 2026-07-18 · Source: operator direction in-session ("implementation and
architecture decisions with as little human involvement as possible; I will not
keep steering the AI through feature work"). Companion evidence: ops-toolkit
`research/2026-06-03-multica-engagement-report.md` (Multica eval) and
`research/2026-07-12-loop-engineering-codila-absorption.md` (loop-engineering
thread). Status: RECORDED IDEA. When ID-304 is picked up for real setup, run a
`/kit:grill` interview round against this brief first; the defaults below are
working assumptions until that interview, not settled contract.

## Verdict: ADOPT AS DIRECTION (v1 = re-shape where the human sits, not new machinery)

## Core thesis

The kit's pipeline keeps exactly THREE human gates. Everything between them
runs autonomous, with the kit's existing trust layer standing in for the human:

```
 [GATE 1: brief]          autonomous middle              [GATE 2: test design]         autonomous          [GATE 3: end review]
 requirement intake   →   architecture decisions,    →   test plan quality        →    build, verify,  →   visual proofs,
 collaborative verify     spec, design record            approved by human             ship-gate           retro, telemetry,
 (think/grill/design)     recorded NOT paused            (test-plan + review-team)     (no human)          lessons + debt
```

- Gate 1 (front): the human shapes and verifies requirements with the agent
  (`/kit:think`, `/kit:grill`, `/kit:design`). This is where steering happens.
- Gate 2 (test design): the human approves the test plan, because the tests
  are the contract the autonomous middle is verified against.
- Gate 3 (end): the human reviews visual proofs, the run report, retro and
  telemetry, lessons, and the debt ledger. Steering feedback goes into the
  NEXT loop, not into the running one.

In between, the agent decides. Architecture and implementation decisions are
made autonomously, RECORDED (design record, ADR draft, implementation-notes
delta), and surfaced at Gate 3 for review. A wrong call is caught by the
verifier arm or at Gate 3 and comes back as a new brief, not by mid-run
steering.

## What substitutes for the human mid-flight (already built)

The reason this is safe today and was not two months ago: the trust layer is
shipped. Worker/verifier/fix separation with a hard retry cap, the V-model
right arm (task/integration/acceptance/system verifiers), recheck-verifier
fresh-context re-audit, claim-verifier skeptic panel, proof-of-done +
gate-ledger ship enforcement (ADR-0024/0025), safety hooks. The human is
removed from the middle because these are there, not instead of them.

## What changes in the kit (the delta)

1. **AGENTS.md zone 4 "Pause if" narrows.** Today it pauses on architecture
   decisions. Under this model an architecture decision inside an approved
   brief's scope is decide + record + continue; pausing remains only for
   scope changes beyond the brief, risk-reclassification upward, privacy/money
   surfaces, and irreversible external actions. Needs an ADR (it bends a
   standing contract).
2. **Gate 2 becomes a real approval point.** `/kit:test-plan` output is
   presented for explicit operator approval before `/kit:execute` on normal+
   lanes (today review-team critique exists but approval is implicit).
3. **Gate 3 needs its artifacts auto-produced.** Visual proof lands in-kit
   (ID-300) and the run report + retro + telemetry surface as one review
   packet. The operator reads a packet, not a transcript.
4. **ID-302 is resolved by this brief**: no per-stage entry gates. The
   pipeline story doc (ID-301) records the three-gate model as the answer.

## Reference: Multica (illustration of the idea, not an integration decision)

Multica is cited here only as the reference shape for "file a task on a board,
an agent executes it like a teammate, the human sees a review surface". It
shows the model works as a product; it also shows exactly what the autonomous
middle must add on top of that shape: its daemon runs providers unsandboxed
with auto-approve (RCE for anyone who can file an issue), it has no verifier
gate and no retry cap, and its status field can read completed on a silent
no-op. The kit's trust layer is the answer to those gaps. Whether the live
board-only pilot at multica.d.foundation ever fronts kit backlogs stays a
separate track (ID-290); nothing in this brief depends on Multica.

## Non-goals

- No new orchestration runtime (ID-303 owns the in-kit path; wavefront is
  shipped via ADR-0030).
- No Multica daemon on shared hosts; no Multica as a quality gate.
- Not removing Gate 1: requirement shaping stays collaborative and human-led.
  Low-steering means no steering DURING the build, not no human at all.

## Working defaults (self-resolved 2026-07-18; revisit in the setup interview)

1. **Gate 2 scope: risk-tiered.** Full lane and any new AI-behavior suite get
   a blocking test-plan approval. Normal lane auto-proceeds; its test plan
   rides the Gate 3 packet for after-the-fact review. Tiny/bug lanes skip
   Gate 2 (the failing-test-first rule already covers bug lanes).
2. **Architecture fork inside the brief's scope: pick + record.** The agent
   chooses, writes the alternative and the reason into the design record /
   implementation-notes delta, and continues. Parking is reserved for forks
   that change scope, risk tier, or an irreversible external surface.
3. **Gate 3 rejection re-entry: auto-drafted follow-up brief.** Rejection
   notes become a drafted brief + a queued board row (staged via the normal
   promote gate, never auto-executed). Steering enters the next loop as
   structured intake, not mid-run correction.
4. **Packet shape: an index, not a mega-file.** One packet index linking the
   existing RUN_REPORT + proof-of-done + retro + telemetry snapshot; no new
   artifact format, the packet is a front page over what the kit already
   produces.

## Backlog wiring

- New row: adopt this model (ADR + AGENTS.md zone 4 amendment + Gate 2
  approval point + Gate 3 packet), references this brief.
- ID-300 (visual proof in-kit) becomes a Gate 3 prerequisite.
- ID-301 (pipeline story doc) documents the three-gate model.
- ID-302 closes as resolved-by-this-brief.
- ID-303 (own orchestration) unchanged, parallel track.
