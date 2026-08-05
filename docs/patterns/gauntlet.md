# The gauntlet pattern: where it sits in the kit

`/kit:gauntlet` (commands/gauntlet.md) is the mechanics: a bounded-revise loop that
converges a repo's contributor surface by making a synthetic-dev probe onboard from
the docs alone, build one seed card, and submit. This doc is the positioning: how the
gauntlet relates to the orchestration workflow, the V-model, and mega-goals, how to
run it right, and where its known limits are. Read this before your first run; read
the command during one.

## 0. The round, drawn once

The three composed shapes, labeled where each lives:

```
 ┌────────────────────────────── round N ───────────────────────────────┐
 │                                                                      │
 │   TIER 1 · deterministic suite (cheap, every round)                  │
 │      red? ──> findings recorded, probe never runs this round         │
 │      green ▼                                                         │
 │                                                                      │
 │   TIER 2 · the probe                                 [GOAL shape]    │
 │   ┌──────────────── fresh clean room ─────────────┐                  │
 │   │ built from git archive HEAD, nothing reused   │                  │
 │   │ synthetic dev (mid-tier model) + capped key   │                  │
 │   │ receives: repo + ONE seed card (goal contract:│                  │
 │   │   outcome + acceptance + verification cmd)    │                  │
 │   │ must: set up -> implement -> verify -> submit │                  │
 │   │ NEVER coached: an unanswerable question       │                  │
 │   │ IS a finding                                  │                  │
 │   └───────────────────┬───────────────────────────┘                  │
 │                       ▼                                              │
 │   SCORE: submission checker (deterministic) + transcript mining      │
 │      BLOCKER stuck · MAJOR knowledge gap · MINOR friction            │
 │                       ▼                                              │
 │   PERSIST the round record, pass or FAIL          [EVAL shape]       │
 │      ROUNDS.md ledger + round-N/{findings, transcript,               │
 │      submission, surface-diff} + cost columns                        │
 │                       ▼                                              │
 │   CONVERGE?                                        [LOOP shape]      │
 │      checker green + K=0 (replicated) ──> STOP: unaided pass (SOLID) │
 │      severity fell, N < 3 ──> REVISE: reviser (never the probe)      │
 │                               edits surface globs ONLY, commits,     │
 │                               TEARS DOWN, respins ──> round N+1      │
 │      else ──────────────────> STOP: honest halt (RECONSIDER,         │
 │                               naming what the surface still lacks)   │
 └──────────────────────────────────────────────────────────────────────┘
```

## 1. Relation to the orchestration workflow

The gauntlet is an opt-in side-flow (WORKFLOW.md, side-flow 11), never a lane phase.
Inside a run, its roles are the execute pipeline's roles, pointed backward:

| Execute pipeline | Gauntlet | Same rule carried over |
|---|---|---|
| worker subagent | the probe (synthetic dev) | fresh context, does the task, never judges itself |
| task-verifier | submission checker + transcript mining | verification is separate from production |
| fix-agent | orchestrator-as-reviser | distinct from the producer, scoped edits only |
| retry cap (2) | round cap (3) | bounded, honest halt past the cap |

The inversion is the point: in `/kit:execute` the artifact is the code and the
verifier checks the worker's output. In the gauntlet the artifact is the DOCS, and
the worker's whole run is the verification. A probe that fails has not failed the
gauntlet; it has produced the gauntlet's findings.

## 2. Relation to the V-model

The gauntlet is a right-arm element: it is the ACCEPTANCE TEST of a dev-access
program, the mirror of the original requirement, not of any task.

```
 LEFT · BUILD                              RIGHT · TEST
 requirement: "outside devs      ◄──────►  GAUNTLET: an unaided synthetic
 can maintain this estate"                 dev ships a card  ← the done-line
   spec: access model, docs,     ◄──────►  clean-room day-one replay
   scripts, card template                  (system test)
     tasks: write the docs,      ◄──────►  deterministic onboarding suite
     build the scripts                     (unit/task level, Tier 1)
```

Consequences of taking this placement seriously:

- The gauntlet runs LAST, after the left arm is built and the lower right-arm rungs
  are green. Running it early wastes probe runs on findings a cheap script would
  have caught (that is what the two-tier scan enforces mechanically).
- Its verdict binds to the requirement altitude. A SOLID pass means the PROGRAM is
  acceptable, not that any individual task was well built; a RECONSIDER means the
  requirement is not yet met even though every task may be individually green. That
  gap, all tasks green yet the program failing, is exactly what acceptance testing
  exists to catch, and it is invisible to task-level verification.

## 3. Relation to mega-goals

A dev-access program is usually mega-goal shaped before anyone names it: multiple
workstreams, multiple repos, multi-session. The mapping:

- The program's spec (workstreams W1..Wn) is the roadmap; each workstream is a
  sub-goal shaped like a normal goal contract.
- **The gauntlet is the mega-goal's exit criterion**: the hardest verify, kept at
  the orchestrator level, run once the sub-goals report done. Sub-goal completion
  is necessary, never sufficient; the mega-goal closes on an unaided gauntlet pass.
- A second gauntlet-shaped consumer in the same program (another repo granting
  outside access) reuses the engine with its own inputs table; the run records
  stay per-repo.

## 4. How to run it: the floor-then-loop rule

The recurring question: design the surface carefully first, or just define the
output and let the loop drive? The answer is structural, not a preference:

**Build the floor deterministically; let the loop find everything above it.**

- The floor = whatever makes Tier 1 green: docs exist, scripts run, the suite
  passes. This much is designable up front because the checks are mechanical.
- Above the floor, hand-polishing is polishing blind. The gaps that stop a new
  contributor are unknown-unknowns to the author, the curse of knowledge: you
  cannot simulate not-knowing your own estate. Speculative doc-perfecting before
  round 1 spends effort exactly where you have no signal.
- So the run design is goal-shaped on purpose: define the done-line ("unaided
  pass, checker green, zero interventions"), run the loop, and let each round's
  evidence, not taste, drive each revision.

Command sequence for a first run, concretely: execute the program's spec until the
deterministic suite is green, then invoke the gauntlet as the finale. No extra
design beat between them.

## 5. Known limits and improvement room

Named honestly, per the kit's honest-halt ethos. Each is a real gap; none blocks a
first run.

1. **One probe run is one sample.** A pass can be luck; a failure can be model
   variance. Cheapest mitigation: require the FINAL green round to replicate once
   (two consecutive unaided passes) before calling SOLID. N-probe rounds are the
   expensive upgrade if replication proves noisy.
2. **Seed-card overfitting.** The surface converges on the path THAT card
   exercises. Rotate cards across runs (keep a small pool of card types: test
   backfill, doc fix, small bug); a regression gauntlet should use a different
   card than the run that converged the surface.
3. **Probe-model overfitting.** Docs tuned to Sonnet's failure modes are not
   proven for humans. The probe is a proxy: the first REAL contributor's day one
   is round N+1. Capture their friction in the same findings format and feed it
   back through the same reviser path; do not treat SOLID as the end of learning.
4. **The probe can read the answer key.** The gauntlet's own runner, checker, and
   prior run records ship in the repo. Mitigate: exclude the gauntlet directory
   and `docs/verification/gauntlet/` from the clean room image, and scan the
   transcript for answer-key reads before trusting a pass. The checker testing
   real properties (patch applies, tests pass) limits the damage, gaming it
   mostly means doing the work, but the transcript check keeps the pass honest.
5. **Transcript secret hygiene.** The probe's env holds the API key, and
   transcripts echo environments. Scrub the key (and any credential-shaped
   string) from every persisted transcript before commit; the run record lives in
   git forever.
6. **Doc-bloat convergence.** A lazy reviser answers every probe confusion by
   appending a paragraph; three rounds later the docs are a FAQ swamp that is
   WORSE for a human. Reviser rule: prefer restructuring over appending, and run
   an instruction-compaction pass after SOLID if total surface length grew.
7. **Severity classification drifts.** BLOCKER/MAJOR/MINOR is judgment. The
   findings-carry-transcript-quotes rule is the anchor; when in doubt between two
   severities across rounds, re-read the prior round's findings first so the
   scale stays consistent within a run.
8. **Clean room is not a contributor's machine.** Linux container vs a human's
   macOS laptop; docker-in-the-loop vs a dev without docker. A container-proven
   surface can still fail on a real laptop (toolchain, shell, case-sensitivity).
   Treat limit 3's real-dev telemetry as the check on this gap too.
9. **Post-SOLID rot.** The surface drifts as the repo evolves; a converged
   gauntlet is a snapshot. Cadence: one regression round after any major
   contributor-surface change (the command's "When to reach for this" already
   names this), and wire the surface files into the repo's doc-drift audit set so
   ordinary drift detection covers the quiet periods.
10. **Round economics need measuring.** A round = docker build + agent run.
    Record per-round wall-clock and token cost in ROUNDS.md from the first run;
    if Tier 2 rounds are expensive, the fix is a better Tier 1 (promote every
    mechanizable finding into the deterministic suite), not a cheaper probe.

Improvement 10 is the flywheel worth internalizing: **every gauntlet finding that
can be turned into a deterministic check should graduate into Tier 1.** The suite
grows, future rounds get cheaper, and the probe is reserved for what only an agent
can discover. That is the same cheap-first verification-cost routing the kit
applies everywhere else.

## Lineage

Engine shape: the kit's bounded-revise pattern (worked sibling
`commands/test-plan-review-team.md`; Evaluator-Optimizer lineage per
`skills/loop-engineering`). Synthetic-user documentation testing is established
practice; the kit's deltas here are the two-tier cost routing, the
severity-aware convergence, the frozen-seed + persisted-run-record contract, and
the floor-then-loop run design. First worked instance: foundation-workers
SPEC-018 (`test/onboarding/gauntlet/`).
