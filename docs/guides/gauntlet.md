# Run the gauntlet (user guide)

You have an artifact that must work for a cold consumer with nobody helping them:
contributor docs before outside devs arrive, a runbook before the incident, a spec
before a cold implementer, an API surface before external integrators. The gauntlet
answers one question before a human finds out the hard way: **can a median-skill
agent, given only what you ship, achieve the outcome, unaided?**

It does this by actually trying it: a probe agent (a mid-tier model, on purpose)
gets a fresh clean room, your artifact, and one task card. It follows the artifact.
Where it gets stuck, your artifact is the bug. The kit revises the artifact, tears
the room down, and tries again with a fresh one, up to three rounds.

For the mechanics (the four slots, presets, rules) read `commands/gauntlet.md`; for
the design rationale and known limits read `docs/patterns/gauntlet.md`. This guide
is only what YOU do.

## Before you run it (the checklist)

| You need | Why | Example |
|---|---|---|
| A deterministic Tier 1 suite | cheap checks run before any paid probe round | a script asserting the artifact's mechanical properties (files exist, commands run, links resolve) |
| A clean-room recipe | the fresh env each round builds from COMMITTED state, matched to the artifact kind | repo: a Dockerfile + runner building from `git archive HEAD`; host: a stripped snapshot/restore procedure |
| One task card | the outcome the probe attempts; small, real, bounded (<= 1 agent-day), with acceptance criteria + a verification command | your card template, filled |
| A deterministic checker | pass/fail oracle on what the probe produces | derived from the card's verification command |
| A spend-capped model API key | the probe's ONLY credential | never CF / 1Password / GitHub credentials |
| The room's runtime available | the clean room needs it | Docker running (repo kind) |

Not ready? Say so, the kit will help you build the missing piece first. Do not
hand-polish the artifact beyond "the suite is green": the gaps a cold consumer hits
are invisible to you (you know too much), and finding them is the gauntlet's job.

## Run it

Say "run the gauntlet" (or `/kit:gauntlet <preset>`). Bare invocation asks which
preset; the kit confirms the inputs table, then loops. Expect per round: an
environment build plus one full agent work session. You do not need to watch; every
round persists its full record.

**Do not help the probe.** If you answer its question, the round is void, that
question was a finding, and now it is lost.

## What you get

Everything lands in `docs/verification/gauntlet/<date>-<preset>-<slug>/`:

- `ROUNDS.md`, the one-page story: what failed each round, how bad, what got
  fixed, what it cost, final verdict. Read this first.
- `round-N/`, the evidence: the probe's full transcript, its output, the
  findings with quotes, and the exact artifact changes made afterward. Failed
  rounds are kept forever, they are the justification for every artifact change.

## Reading the verdict

| Verdict | Meaning | What you do |
|---|---|---|
| SOLID | an unaided pass, replicated twice | ship the artifact to its real consumers; watch the FIRST real one anyway, their friction is your next round |
| REVISE | improving, but the round cap hit | read ROUNDS.md, apply the open findings yourself, rerun later (often one more round) |
| RECONSIDER | not converging; the artifact has a structural gap | the gap list names what is missing; this usually means a missing tool or section, not a wording fix. It also lands on your weekend paydown ledger |

## Worked example: the onboarding preset, gauntleting the kit itself

The reference preset converges a repo's contributor surface: can a new dev, given
only what the repo ships, get set up, build one small feature, and submit it? The
kit's own surface can take it, with one decision made first: **which persona?** The
kit has two, and they need separate runs:

- **The kit USER**: someone adopting the kit in their repo from the docs alone.
- **The kit CONTRIBUTOR**: someone changing the kit's own code.

The user-persona preparation, mapped to the checklist above:

| Input | For the kit it means |
|---|---|
| Artifact globs | README, MANUAL, `/kit:onboard` + `/kit:adopt` docs, this guides/ series |
| Tier 1 suite | deterministic checks that already exist: `kit-health`, `adopt --check` against a fixture repo, install-mode detection; gather them under one runnable entry first |
| Clean room | a container with git + node + the claude CLI + a capped API key; the kit arrives as a tarball, NOT pre-installed, installing it IS part of day one |
| Task card | "adopt the kit into this fixture repo and ship one tiny-lane change through the loop", exercises onboard, adopt, a lane, and the ship gate in one card |
| Checker | assert the artifacts the loop must leave behind: AGENTS.md injected, a spec file exists, gate-ledger rows present, a PR-shaped branch with the change |
| Probe | mid-tier model, as always |

The contributor persona differs in artifact globs (CONTRIBUTING-level docs, lib/
conventions, the proof-gate rules) and card (a small kit fix through the
kit's own gates). Run it second; the user persona finds the louder gaps first.

## Common questions

- **"The probe failed on something obvious."** Obvious to you. That is the curse
  of knowledge, and precisely the signal you paid for.
- **"Can I use a stronger model so it passes?"** No. A frontier model succeeds
  DESPITE a bad artifact; your artifact stays broken and the pass is a lie. Real
  consumers do not get frontier intuition.
- **"It passed once, are we done?"** A pass must replicate (two consecutive
  unaided passes) before the kit calls it SOLID; one pass can be luck.
- **"How often should I rerun?"** One round after any major change to the
  artifact or the card template. A converged artifact is a snapshot, not a
  property.
