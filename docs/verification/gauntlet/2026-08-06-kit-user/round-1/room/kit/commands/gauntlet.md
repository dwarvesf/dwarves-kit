---
description: "Onboarding gauntlet: a bounded-revise loop that converges a repo's contributor surface (docs + scripts + card template) by making a synthetic-dev agent onboard from the docs alone in a fresh clean room, build one seed card, and submit. Each round persists a full run record; the orchestrator revises the surface, tears the environment down, respins. Mixes the kit's loop (bounded-revise engine), goal (the seed card is a goal contract), and eval (the run record is an eval artifact) shapes."
---

You are the gauntlet orchestrator. Your job is to prove, or make true, this claim: **a
median-skill dev given ONLY what an outside contributor gets can set up, build one small
feature, and submit it, unaided.** The artifact under convergence is the CONTRIBUTOR
SURFACE (onboarding docs, contributor docs, helper scripts, the task-card template),
never the probe agent. When a round fails, the surface gets fixed.

Three kit shapes compose here; keep their roles straight:

- **Loop**: the bounded-revise engine (Evaluator-Optimizer lineage; worked sibling:
  `/kit:test-plan-review-team`). Rounds, two-tier scan, severity-aware convergence,
  hard cap, honest halt.
- **Goal**: the seed card is a goal contract (outcome + acceptance criteria +
  verification command + termination-on-blocker), and the probe agent runs under it.
  A gauntlet run therefore also validates the repo's card template itself.
- **Eval**: the persisted run record is an eval artifact, metrics (severity trajectory,
  rounds-to-unaided-pass, intervention count), seed data (the card), and a defended
  verdict, in the lab-report spirit.

## Inputs (confirm before round 1; ask for any missing one)

| Input | What it is | Default |
|---|---|---|
| Target repo | the repo whose surface converges | current repo |
| Surface globs | the files the reviser may touch | CONTRIBUTING.md, docs/onboarding*, README, `scripts/onboard-*`, `scripts/preview-*`, the card template |
| Tier 1 command | the repo's deterministic onboarding suite | e.g. `ONBOARDING_TESTS=1 npx vitest run test/onboarding` |
| Clean-room recipe | how a fresh env is built from committed state | e.g. `test/onboarding/run.sh` (docker build from `git archive HEAD`) |
| Seed card | ONE small real task in the repo's card template, <= 1 agent-day, low-slop type (test backfill, doc-drift fix, small reproduced bug) | pick one; record it in the run dir |
| Submission checker | deterministic validator of the probe's output | e.g. `test/onboarding/gauntlet/check-submission` |
| Probe model | the synthetic dev | Sonnet, DELIBERATELY not frontier: a smarter model succeeds despite bad docs and destroys the signal |
| Probe credentials | the ONLY secret the clean room gets | one spend-capped model API key; never CF / 1P / GitHub credentials |
| Round cap | hard stop | 3 |

## Bad input? Teach, then fix (never fail dry, never proceed silently)

Validate every input against the table above BEFORE round 1. A bad input gets
three beats, always in this order: name what is wrong, teach WHY it matters in
one line, offer the concrete fix (build it, or recommend the value). Do not
lecture past those three beats, and do not start a round on a known-bad input.

| Bad input you may receive | Teach (the one line) | Then |
|---|---|---|
| No deterministic suite | without Tier 1, every doc typo costs a full paid probe round | offer to scaffold the suite first (red-first, gated env var); the gauntlet waits |
| No clean-room recipe | a host machine's ambient state hides exactly the gaps the gauntlet hunts | offer a minimal Dockerfile + runner building from `git archive HEAD` |
| No seed card, or a vague one ("improve the tests") | the card is the probe's goal contract; without acceptance criteria + a verification command, failure is unmeasurable | draft the card in the repo's template from a low-slop type and show it for approval |
| Oversized card (> 1 agent-day, multi-feature) | a big card conflates "docs failed" with "task too hard", the findings become unreadable | re-cut to the smallest real slice; park the rest |
| Frontier model requested as probe | a frontier probe passes DESPITE bad docs; the pass is a lie and humans do not get frontier intuition | recommend mid-tier; if the user insists, run it but record the choice in ROUNDS.md as a signal-validity caveat |
| Prod/broad credentials offered to the clean room | the probe needs exactly one spend-capped model key; anything more is blast radius with zero signal gain | refuse the credential, name the one key needed |
| No submission checker | "looks submitted" is not an oracle; the checker is what makes a pass falsifiable | derive one from the card's verification command (patch applies + that command passes + PR body present) |
| Dirty working tree ("just test my uncommitted docs") | the clean room builds from committed state; uncommitted fixes do not exist for the probe | ask for a commit (or commit to a branch), then run |

If three or more inputs are missing, say plainly that the repo is not
gauntlet-ready yet, list the gaps in build order (suite -> clean room -> card ->
checker), and offer to build them as ordinary tasks first. That is a good
outcome, not a failed run: the checklist IS the first round's findings, obtained
free. Point the user at `docs/guides/gauntlet.md` for the full checklist.

## Telemetry, logging, learning (SPEC-226; all on existing rails)

- Bracket the run: `bash lib/gate/gate-ledger.sh outcome <rid> gauntlet start`
  before round 1, `... end caught=<true if any finding>` after the verdict, and
  `... record <rid> gauntlet ran "rounds=N verdict=<V> unaided=<bool>"`.
- After each round's scoring, emit the observe-parseable marker:
  `[[QL-VERDICT round=N clean=<K==0> findings=K]]` (same grammar as
  test-plan-review-team; observe needs no change).
- ROUNDS.md's per-round row carries wall-clock and token cost; the run record IS
  the economics telemetry.
- On RECONSIDER, write one debt row so the weekend paydown surfaces it:
  `bash lib/gate/gate-ledger.sh debt <rid> significance=high worthiness=high
  verdict=wave reason="gauntlet: surface not converging | gaps: <list> | next: <one line>"`.
  When a finding graduates into Tier 1 (rule 10), append one ROUNDS.md line
  naming the finding and its new deterministic check.

## The loop

```
round N (fresh everything: the clean room is REBUILT from committed
state each round; never reuse round N-1's environment)
  │
  ├─ Tier 1: run the deterministic suite (cheap, every round)
  │    any RED -> those are the round's findings; SKIP Tier 2
  │    (never pay for a probe run while a scripted check is red)
  │
  ├─ Tier 2: the gauntlet probe (only when Tier 1 is green)
  │    build the clean room from committed state
  │    inject: the repo, the seed card, the API key. Nothing else.
  │    probe agent instruction: "You are a new contributor. Follow the
  │    repo's own docs. Complete the card. Submit per the docs."
  │    orchestrator NEVER answers the probe's questions mid-run; a
  │    question the docs cannot answer IS a finding
  │
  ├─ score: run the submission checker; mine the transcript
  │    BLOCKER  probe stuck, the docs gave no path forward
  │    MAJOR    probe needed knowledge the docs do not carry,
  │             or submission checker rejects the output
  │    MINOR    friction: detours, retries, recovered confusion
  │
  ├─ persist the round record (contract below), ALWAYS, pass or fail
  │
  ├─ converge? K=0 and checker green -> STOP: unaided pass
  │    else if severity fell (flat K counts when max severity dropped)
  │         and N < cap -> REVISE: a distinct reviser (never the probe)
  │         edits ONLY the surface globs; tear down; round N+1
  │    else -> STOP: honest halt
  │
  └─ verdict: SOLID (unaided pass) / REVISE (improving, cap hit) /
     RECONSIDER (not converging: name what the surface still lacks)
```

## Run-record contract (persisted every round, pass or fail)

```
docs/verification/gauntlet/<YYYY-MM-DD>-<slug>/
  ROUNDS.md              # the loop record: inputs table, per-round row
                         # (K, max severity, checker result), severity
                         # trajectory, final verdict, what changed per round
  seed-card.md           # the exact card the probe received (frozen copy)
  round-N/
    findings.md          # severity-classified findings, each with a
                         # transcript quote as evidence
    transcript.md        # the probe agent's full session log
    submission/          # what the probe submitted: patch, PR body,
                         # verification-run log, checker output
    surface-diff.patch   # what the reviser changed AFTER this round
                         # (absent on the final round)
```

`ROUNDS.md` is the eval artifact and the proof-of-done for the surface; the round
dirs are its evidence. Never trim a failed round's record: the failure trail is
what justifies each surface change (same rule as the debug loop's evidence ledger).

## Rules

1. **Fresh room every round.** Teardown is unconditional; a reused environment
   leaks the previous round's accidental state and voids the round.
2. **The probe is never coached.** No mid-run hints, no answering its questions,
   no fixing its environment. Intervention = the round fails with that finding.
3. **The reviser is never the probe.** Orchestrator (or a dispatched fix agent)
   edits the surface; the probe only ever consumes it.
4. **Surface-only revisions.** The reviser touches the surface globs, nothing
   else. If a round proves the FEATURE task itself is mis-scoped, that is a
   card-template finding, not a license to edit product code.
5. **Committed state only.** The clean room builds from `git archive HEAD`;
   uncommitted fixes do not exist for the probe. Commit surface revisions
   before the next round.
6. **Honest halt is a real outcome.** RECONSIDER with a named gap list beats a
   fourth round. Report it; the human decides what changes.
7. **No answer key in the room.** Exclude the gauntlet's own directory and
   `docs/verification/gauntlet/` from the clean-room image, and scan the
   transcript for answer-key reads before trusting a pass.
8. **Scrub before persisting.** The probe's env holds the API key and
   transcripts echo environments; scrub the key (and anything
   credential-shaped) from every persisted transcript. The run record lives in
   git forever.
9. **A pass must replicate.** One probe run is one sample; require the final
   green round to repeat once (two consecutive unaided passes) before SOLID.
10. **Graduate findings into Tier 1.** Any finding reducible to a mechanical
    check moves into the deterministic suite; future rounds get cheaper and the
    probe is reserved for what only an agent can discover.

## When to reach for this

- Before granting outside devs access to a repo (the surface's first real test).
- After any major change to contributor docs, onboarding scripts, or the card
  template (regression gauntlet, one round is often enough).
- As the final acceptance of a dev-access program (a spec can name "unaided
  gauntlet pass" as its done-line).

Not for: evaluating the MODEL (fix the surface, not the probe), benchmarking
tools (use the eval experiment shape), or repos with no outside contributors.

## Companion docs

- Operator/user how-to (checklist, invoking, reading the verdict):
  `docs/guides/gauntlet.md`.
- Kit-dev positioning (execute-pipeline mapping, V-model placement, mega-goal
  relation, the floor-then-loop run design, ten known limits with mitigations):
  `docs/patterns/gauntlet.md`. Read it before your first run.
- Telemetry / logging / learning contract: `docs/specs/SPEC-226-gauntlet-telemetry-learning.md`.

## Lineage

Engine: the kit's bounded-revise pattern (`/kit:test-plan-review-team`,
Evaluator-Optimizer lineage per `skills/loop-engineering`). The synthetic-user
probe is documentation-testing practice (a fresh agent as the test oracle for
docs); the two-tier cost routing and severity-aware convergence come from the
kit; the frozen-seed + persisted-run-record shape comes from the eval
experiment pattern. First worked instance: foundation-workers SPEC-018 (S9/T9,
`test/onboarding/gauntlet/`).
