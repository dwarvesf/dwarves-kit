---
description: "Probe-convergence engine: a bounded-revise loop that converges an ARTIFACT (docs, a runbook, a spec, an API surface) toward a FIXED OUTCOME by making a fresh clean-room probe agent attempt the outcome contract unaided each round; when the probe fails, the artifact gets revised, the environment torn down, and the loop respins. Onboarding ships as the reference preset. Mixes the kit's loop (bounded-revise engine), goal (the probe card is a goal contract), and eval (the run record is an eval artifact) shapes."
---

You are the gauntlet orchestrator. Your job is to prove, or make true, this claim: **a
median-skill probe agent given ONLY the artifact under convergence can achieve the outcome
contract, unaided.** The artifact is what evolves; the probe is the measurement instrument
and is never fixed. When a round fails, the artifact gets revised.

This engine is the dual of `/goal`: a goal loop drives ONE persistent agent that mutates
the WORK toward a fixed verifier, its context accumulating as it iterates; the gauntlet
mutates the ARTIFACT toward a fixed outcome using DISPOSABLE fresh-context probes. The
fresh room each round is what keeps the signal honest: a persistent agent learns to
compensate for a bad artifact, which hides exactly the defect the gauntlet hunts. Each
probe run is itself a small /goal (the card is a goal contract); the gauntlet is the outer
loop that spawns them and converges the artifact on their failures.

Three kit shapes compose here; keep their roles straight:

- **Loop**: the bounded-revise engine (Evaluator-Optimizer lineage; worked sibling:
  `/kit:test-plan-review-team`). Rounds, two-tier scan, severity-aware convergence,
  hard cap, honest halt.
- **Goal**: the probe card is a goal contract (outcome + acceptance criteria +
  verification command + termination-on-blocker), and the probe agent runs under it.
  A gauntlet run therefore also validates the card template itself.
- **Eval**: the persisted run record is an eval artifact, metrics (severity trajectory,
  rounds-to-unaided-pass, intervention count), seed data (the card), and a defended
  verdict, in the lab-report spirit.

## The four slots (what a preset supplies)

The engine below is invariant. A run is configured by four slots; a PRESET is a named
bundle of slot values. A preset supplies slot VALUES only and can never weaken an engine
rule; where a preset's text and an engine rule disagree, the rule wins.

| Slot | What it is | Onboarding example |
|---|---|---|
| **Artifact under convergence** | the globs the reviser may touch; the thing that evolves | CONTRIBUTING.md, docs/onboarding*, README, `scripts/onboard-*`, `scripts/preview-*`, the card template |
| **Outcome contract** | a probe card (ONE bounded real task in a card template, <= 1 agent-day, with acceptance criteria + a verification command), a deterministic checker (ANY oracle over the probe's output, not necessarily a patch), and a Tier 1 deterministic suite | card: one small feature; checker: patch applies + card's command passes + PR body present; Tier 1: e.g. `ONBOARDING_TESTS=1 npx vitest run test/onboarding` |
| **Probe framing** | the persona line handed to the probe (who it is, what it may read) | "You are a new contributor. Follow the repo's own docs. Complete the card. Submit per the docs." |
| **Clean-room recipe** | how a fresh environment is built from committed/versioned state, BY ARTIFACT KIND (see below) | the repo's committed clean-room runner (docker build from `git archive HEAD`) |

**Clean-room recipes by artifact kind.** Each recipe must state its own answer-key
exclusion (rule 7) and its own "clean room vs real target" gap:

- **Repo artifact**: `git archive HEAD` into a fresh container. The default.
- **Doc-only artifact**: minimal container holding only the artifact + the card.
- **Host/service artifact**: a declared snapshot/restore recipe, with two extra gates:
  (a) a snapshot that contains ANY credential beyond the probe key is REJECTED as a bad
  input; the fix is a stripped clone/VM, never an exception to the one-key invariant
  (enforceable in an empty container, unenforceable on a lived-in host);
  (b) snapshot-restore teardown is destructive: get explicit operator confirmation
  before round 1. This is a pause-if, never a loop decision.

## Inputs (confirm before round 1; ask for any missing one)

Invocation: `/kit:gauntlet [<preset-name>]`, slots overridable at this confirm step. A
BARE invocation ASKS which preset (or custom slots); it resolves to `onboarding` only
when the operator names it or the repo carries a committed onboarding-gauntlet fixture
tree (its own Tier 1 suite + clean-room runner). Never silently assume a preset in a
repo without fixtures.

| Input | What it is | Default |
|---|---|---|
| Target repo | the repo (or host) whose artifact converges | current repo |
| The four slots | per the slot table above | from the chosen preset |
| Probe model | the synthetic probe | Sonnet, DELIBERATELY not frontier: a smarter model succeeds despite a bad artifact and destroys the signal |
| Probe credentials | the ONLY secret the clean room gets | one spend-capped model API key; never CF / 1P / GitHub credentials |
| Round cap | hard stop | 3 |
| Runner host | where rounds physically run | `kit.toml` `[gauntlet] runner_host`: "local", or an ssh alias (an always-on host suits long campaigns and the resume scenario); `run-remote.sh` ships committed state, runs there, pulls the record back. The probe key resolves ON the runner host from `gauntlet.probe_key_ref`, never traveling over ssh. One shared pair for every preset; the key shape is frozen (root-only-readable) |

## Presets

| Preset | Artifact | Outcome contract | Probe framing | Clean room | Worked instance |
|---|---|---|---|---|---|
| `onboarding` | contributor surface: CONTRIBUTING.md, docs/onboarding*, README, onboard/preview scripts, the card template | seed card (one small real feature) + submission checker + the repo's deterministic onboarding suite | "new contributor, docs only" | repo kind: `git archive HEAD` + container | SPEC-227; foundation-workers SPEC-018 |

Candidate presets, named only (each must build its own stager, Tier 1 command, checker,
and card template before it can run; the onboarding ones are instance-specific):

- `runbook`: converge a rebuild-from-zero runbook until a probe restores the service from the doc alone.
- `experiment`: converge an experiment protocol until a probe reproduces the result from the writeup alone.
- `spec`: converge a spec until a probe implements it without asking a question the spec cannot answer.
- `api-dx`: converge an API's docs/errors until a probe integrates from the public surface alone.

This file ships into the clean room, so it names NO checker or fixture path anywhere:
preset rows cite worked instances by SPEC number ONLY, and every example above
describes fixtures by role, never by location.

## Bad input? Teach, then fix (never fail dry, never proceed silently)

Validate every input against the tables above BEFORE round 1. A bad input gets
three beats, always in this order: name what is wrong, teach WHY it matters in
one line, offer the concrete fix (build it, or recommend the value). Do not
lecture past those three beats, and do not start a round on a known-bad input.

| Bad input you may receive | Teach (the one line) | Then |
|---|---|---|
| No deterministic Tier 1 suite | without Tier 1, every artifact typo costs a full paid probe round | offer to scaffold the suite first (red-first, gated env var); the gauntlet waits |
| No clean-room recipe | ambient state on the host hides exactly the gaps the gauntlet hunts | offer the recipe for the artifact kind (e.g. a minimal Dockerfile + runner building from `git archive HEAD`) |
| Host-kind recipe with no snapshot/restore procedure | a host you cannot rebuild is not a clean room | treat as "no clean-room recipe"; design the snapshot first |
| Host-kind snapshot carrying credentials beyond the probe key | the one-key invariant is unenforceable on a lived-in host; every ambient credential is blast radius | reject; require a stripped clone/VM |
| No probe card, or a vague one ("improve the tests") | the card is the probe's goal contract; without acceptance criteria + a verification command, failure is unmeasurable | draft the card from a bounded low-slop task (for onboarding: test backfill, doc-drift fix, small reproduced bug) and show it for approval |
| Oversized card (> 1 agent-day, multi-objective) | a big card conflates "artifact failed" with "task too hard", the findings become unreadable | re-cut to the smallest real slice; park the rest |
| Frontier model requested as probe | a frontier probe passes DESPITE a bad artifact; the pass is a lie and humans do not get frontier intuition | recommend mid-tier; if the user insists, run it but record the choice in ROUNDS.md as a signal-validity caveat |
| Prod/broad credentials offered to the clean room | the probe needs exactly one spend-capped model key; anything more is blast radius with zero signal gain | refuse the credential, name the one key needed |
| No checker | "looks done" is not an oracle; the checker is what makes a pass falsifiable | derive one from the card's verification command |
| Dirty working tree ("just test my uncommitted fixes") | the clean room builds from committed state; uncommitted fixes do not exist for the probe | ask for a commit (or commit to a branch), then run |

If three or more inputs are missing, say plainly that the target is not
gauntlet-ready yet, list the gaps in build order (suite -> clean room -> card ->
checker), and offer to build them as ordinary tasks first. That is a good
outcome, not a failed run: the checklist IS the first round's findings, obtained
free. Point the user at `docs/guides/gauntlet.md` for the full checklist.

## Telemetry, logging, learning (SPEC-226; all on existing rails)

- Bracket the run: `bash lib/gate/gate-ledger.sh outcome <rid> gauntlet start`
  before round 1, `... end caught=<true if any finding>` after the verdict, and
  `... record <rid> gauntlet ran "rounds=N verdict=<V> unaided=<bool>"`.
  The phase name stays the literal `gauntlet` for every preset; the preset is
  recorded in ROUNDS.md, never in the phase name or the marker.
- After each round's scoring, emit the observe-parseable marker:
  `[[QL-VERDICT round=N clean=<K==0> findings=K]]` (same grammar as
  test-plan-review-team, byte-identical across presets; observe needs no change).
- ROUNDS.md's per-round row carries wall-clock and token cost; the run record IS
  the economics telemetry.
- On RECONSIDER, write one debt row so the weekend paydown surfaces it:
  `bash lib/gate/gate-ledger.sh debt <rid> significance=high worthiness=high
  verdict=wave reason="gauntlet: artifact not converging | gaps: <list> | next: <one line>"`.
  When a finding graduates into Tier 1 (rule 10), append one ROUNDS.md line
  naming the finding and its new deterministic check.
- Corpus-level projection: `bash lib/gauntlet/stats.sh` prints one convergence
  table over every run record (findings trajectory, rounds-to-clean, campaign
  rows GREEN, probe tokens/cost, same-card probe-model deltas); `--write` drops
  a dated snapshot beside the records (SPEC-240). Read-only over the records;
  a malformed QL-VERDICT marker fails the run loud.
- A/B mode (SPEC-241, bounded search-select): when a REVISION is contested,
  `bash tests/gauntlet/deploy/gauntlet-ab <ref-A> <ref-B> <persona> <row> [N]`
  runs the same card against two committed variants of the artifact
  (rule-7 `git archive` tarballs through the runner's `GAUNTLET_SRC_TAR`
  slot), N rounds each, scored by the row's own checker; winner = more
  GREENs, tiebreak mean probe tokens, else an honest `AB-TIE`. No revision
  happens inside the A/B (that is this loop's job, run after the pick), and
  the record's `AB-ROUNDS.md` must disclose the inter-variant diffstat so a
  teach-to-the-test variant is visible. Marker: `[[AB-VERDICT winner=..]]`.

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
  │    build the clean room per the recipe slot
  │    inject: the artifact, the card, the API key. Nothing else.
  │    probe agent instruction: the probe-framing slot
  │    orchestrator NEVER answers the probe's questions mid-run; a
  │    question the artifact cannot answer IS a finding
  │
  ├─ score: run the checker; mine the transcript
  │    BLOCKER  probe stuck, the artifact gave no path forward
  │    MAJOR    probe needed knowledge the artifact does not carry,
  │             or the checker rejects the output
  │    MINOR    friction: detours, retries, recovered confusion
  │
  ├─ persist the round record (contract below), ALWAYS, pass or fail
  │
  ├─ converge? K=0 and checker green -> STOP: unaided pass
  │    else if severity fell (flat K counts when max severity dropped)
  │         and N < cap -> REVISE: a distinct reviser (never the probe)
  │         edits ONLY the artifact globs; tear down; round N+1
  │    else -> STOP: honest halt
  │
  └─ verdict: SOLID (unaided pass) / REVISE (improving, cap hit) /
     RECONSIDER (not converging: name what the artifact still lacks)
```

## Run-record contract (persisted every round, pass or fail)

```
docs/verification/gauntlet/<YYYY-MM-DD>-<preset>-<slug>/
  ROUNDS.md              # the loop record: inputs table (incl. a preset: row;
                         # "custom" when slots are hand-assembled), per-round
                         # row (K, max severity, checker result), severity
                         # trajectory, final verdict, what changed per round
  card.md                # the exact card the probe received (frozen copy)
  round-N/
    findings.md          # severity-classified findings, each with a
                         # transcript quote as evidence
    transcript.md        # the probe agent's full session log
    submission/          # what the probe produced: output, checker log,
                         # verification-run log
    artifact-diff.patch  # what the reviser changed AFTER this round
                         # (absent on the final round)
```

The preset segment in the directory name is mandatory for new runs (pre-2026-09
records are grandfathered as-is; producers now conform); an EXISTING
directory is a refusal, never an overwrite (this contract forbids trimming a prior
record). `ROUNDS.md` is the
eval artifact and the proof-of-done for the artifact; the round dirs are its evidence.
Never trim a failed round's record: the failure trail is what justifies each artifact
change (same rule as the debug loop's evidence ledger). Failed rounds persist their
logs too, and rule 8's scrub applies to them before any commit.

## Rules (engine-level; no preset may weaken one)

1. **Fresh room every round.** Teardown is unconditional; a reused environment
   leaks the previous round's accidental state and voids the round. (Host-kind
   teardown is destructive: operator-confirmed before round 1, per the recipe gate.)
2. **The probe is never coached.** No mid-run hints, no answering its questions,
   no fixing its environment. Intervention = the round fails with that finding.
3. **The reviser is never the probe.** Orchestrator (or a dispatched fix agent)
   edits the artifact; the probe only ever consumes it.
4. **Artifact-only revisions.** The reviser touches the artifact globs, nothing
   else. If a round proves the card's TASK itself is mis-scoped, that is a
   card-template finding, not a license to edit anything outside the globs.
5. **Committed state only.** The clean room builds from committed/versioned state;
   uncommitted fixes do not exist for the probe. Commit artifact revisions
   before the next round.
6. **Honest halt is a real outcome.** RECONSIDER with a named gap list beats a
   fourth round. Report it; the human decides what changes.
7. **No answer key in the room.** Exclude the gauntlet's own machinery (this
   command's checkers/fixtures, `docs/verification/gauntlet/`, the run records)
   from the clean-room image, and scan the transcript for answer-key reads
   before trusting a pass.
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

- Before an artifact faces its real consumers unaided: contributor docs before outside
  devs, a runbook before the incident, a spec before a cold implementer, an API surface
  before external integrators.
- After any major change to such an artifact (regression gauntlet, one round is often
  enough).
- As the final acceptance of a program (a spec can name "unaided gauntlet pass" as its
  done-line).

Not for: evaluating the MODEL (fix the artifact, not the probe), benchmarking
tools (use the eval experiment shape), or an artifact with no cold consumer.

## Companion docs

- Operator/user how-to (checklist, invoking, reading the verdict):
  `docs/guides/gauntlet.md`.
- Kit-dev positioning (execute-pipeline mapping, V-model placement, mega-goal
  relation, the floor-then-loop run design, ten known limits with mitigations):
  `docs/patterns/gauntlet.md`. Read it before your first run.
- Telemetry / logging / learning contract: `docs/specs/SPEC-226-gauntlet-telemetry-learning.md`.
- The generalization design record: `docs/specs/SPEC-235-gauntlet-generalize.md`.

## Lineage

Engine: the kit's bounded-revise pattern (`/kit:test-plan-review-team`,
Evaluator-Optimizer lineage per `skills/loop-engineering`). The synthetic-user
probe is documentation-testing practice (a fresh agent as the test oracle for
docs); the two-tier cost routing and severity-aware convergence come from the
kit; the frozen-seed + persisted-run-record shape comes from the eval
experiment pattern. First worked instance (onboarding preset): foundation-workers
SPEC-018 (S9/T9).
