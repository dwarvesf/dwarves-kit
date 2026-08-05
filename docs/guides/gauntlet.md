# Run the gauntlet on your repo (user guide)

You are about to let outside contributors into a repo, or you just rewrote its
contributor docs. The gauntlet answers one question before a human finds out the
hard way: **can a new dev, given only what your repo ships, get set up, build one
small task, and submit it, with nobody helping them?**

It does this by actually trying it: a synthetic dev (a mid-tier model, on purpose)
gets a fresh clean room, your repo, and one task card. It follows your docs. Where
it gets stuck, your docs are the bug. The kit fixes the docs, tears the room down,
and tries again with a fresh one, up to three rounds.

For the mechanics read `commands/gauntlet.md`; for the design rationale and known
limits read `docs/patterns/gauntlet.md`. This guide is only what YOU do.

## Before you run it (the checklist)

| You need | Why | Example |
|---|---|---|
| A deterministic onboarding suite | cheap checks run before any paid probe round | `ONBOARDING_TESTS=1 npx vitest run test/onboarding` |
| A clean-room recipe | the fresh env each round builds from COMMITTED state | a Dockerfile + runner building from `git archive HEAD` |
| One seed card | the task the probe builds; small, real, low-slop (test backfill, doc fix), with acceptance criteria + a verification command | your repo's card template, filled |
| A submission checker | deterministic pass/fail on what the probe hands back | "patch applies + tests pass + PR body present" |
| A spend-capped model API key | the probe's ONLY credential | never CF / 1Password / GitHub credentials |
| Docker running | the clean room needs it | |

Not ready? Say so, the kit will help you build the missing piece first. Do not
hand-polish your docs beyond "the suite is green": the gaps a new dev hits are
invisible to you (you know too much), and finding them is the gauntlet's job.

## Run it

Say "run the gauntlet on this repo" (or `/kit:gauntlet`). The kit confirms the
inputs table, then loops. Expect per round: a container build plus one full agent
work session. You do not need to watch; every round persists its full record.

**Do not help the probe.** If you answer its question, the round is void, that
question was a finding, and now it is lost.

## What you get

Everything lands in `docs/verification/gauntlet/<date>-<slug>/`:

- `ROUNDS.md`, the one-page story: what failed each round, how bad, what got
  fixed, what it cost, final verdict. Read this first.
- `round-N/`, the evidence: the probe's full transcript, its submission, the
  findings with quotes, and the exact doc changes made afterward. Failed rounds
  are kept forever, they are the justification for every doc change.

## Reading the verdict

| Verdict | Meaning | What you do |
|---|---|---|
| SOLID | an unaided pass, replicated twice | grant access; the surface is proven. Watch the FIRST real dev anyway, their friction is your next round |
| REVISE | improving, but the round cap hit | read ROUNDS.md, apply the open findings yourself, rerun later (often one more round) |
| RECONSIDER | not converging; the docs have a structural gap | the gap list names what is missing; this usually means a missing tool or doc, not a wording fix. It also lands on your weekend paydown ledger |

## Worked example: gauntleting the kit itself

The kit's own contributor surface can take the gauntlet, with one decision made
first: **which persona?** The kit has two, and they need separate runs:

- **The kit USER**: someone adopting the kit in their repo from the docs alone.
- **The kit CONTRIBUTOR**: someone changing the kit's own code.

The user-persona preparation, mapped to the checklist above:

| Input | For the kit it means |
|---|---|
| Surface globs | README, MANUAL, `/kit:onboard` + `/kit:adopt` docs, this guides/ series |
| Tier 1 suite | deterministic checks that already exist: `kit-health`, `adopt --check` against a fixture repo, install-mode detection; gather them under one runnable entry first |
| Clean room | a container with git + node + the claude CLI + a capped API key; the kit arrives as a tarball, NOT pre-installed, installing it IS part of day one |
| Seed card | "adopt the kit into this fixture repo and ship one tiny-lane change through the loop", exercises onboard, adopt, a lane, and the ship gate in one card |
| Submission checker | assert the artifacts the loop must leave behind: AGENTS.md injected, a spec file exists, gate-ledger rows present, a PR-shaped branch with the change |
| Probe | mid-tier model, as always |

The contributor persona differs in surface (CONTRIBUTING-level docs, lib/
conventions, the proof-gate rules) and seed card (a small kit fix through the
kit's own gates). Run it second; the user persona finds the louder gaps first.

## Common questions

- **"The probe failed on something obvious."** Obvious to you. That is the curse
  of knowledge, and precisely the signal you paid for.
- **"Can I use a stronger model so it passes?"** No. A frontier model succeeds
  DESPITE bad docs; your docs stay broken and the pass is a lie. Human contributors
  do not get frontier intuition.
- **"It passed once, are we done?"** A pass must replicate (two consecutive
  unaided passes) before the kit calls it SOLID; one pass can be luck.
- **"How often should I rerun?"** One round after any major change to contributor
  docs, onboarding scripts, or the card template. A converged surface is a
  snapshot, not a property.
