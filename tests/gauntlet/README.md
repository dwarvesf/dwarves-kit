# Gauntlet prep: the kit under its own gauntlet

Instance files for running `/kit:gauntlet` against the kit's own contributor
surface. Two personas, two runs, run the USER persona first (it finds the louder
gaps). Guide: `docs/guides/gauntlet.md` (worked example); engine:
`commands/gauntlet.md`.

## Inputs table, persona A: the kit USER

| Input | Value |
|---|---|
| Surface globs | `README.md`, `docs/MANUAL.md`, `docs/guides/**`, `commands/onboard.md`, `commands/adopt.md` |
| Tier 1 | `bash tests/gauntlet/tier1.sh` |
| Clean room | `bash tests/gauntlet/cleanroom/run.sh` (kit arrives as a tarball, NOT pre-installed; installing is part of day one) |
| Seed card | `seed-card-user.md` (adopt into the fixture repo, ship one tiny-lane change through the loop) |
| Submission checker | `bash tests/gauntlet/check-submission-user.sh <fixture-repo>` |
| Probe | mid-tier model, one spend-capped API key, nothing else |
| Round cap | 3 |

## Inputs table, persona B: the kit CONTRIBUTOR

| Input | Value |
|---|---|
| Surface globs | `README.md` (contributing sections), `docs/PHILOSOPHY.md`, `docs/WORKFLOW.md`, `AGENTS.md`, `tests/README*` |
| Tier 1 | `bash tests/gauntlet/tier1.sh` (same suite) |
| Clean room | same runner; the card differs, not the room |
| Seed card | `seed-card-contributor.md` (one small kit fix through the kit's own gates) |
| Submission checker | `bash tests/gauntlet/check-submission-contributor.sh <kit-clone>` |
| Probe | same |
| Round cap | 3 |

## Scenario pack (SPEC-227): beyond the doorway

The doorway card (J1/J2) proves install + adopt + tiny lane. Full-flow coverage
comes from the scenario MATRIX (`scenarios.md`): one row per journey feature
(full lane, bug/debug, gate collision, drift, resume, review response), cards
materialized per row, generated/reconciled via the shipped SPEC-203
test-generation loop rather than hand-authored. A multi-row run is a CAMPAIGN
(worklist over the gauntlet engine, loop-engineering's campaign shape): run rows
in order, doorway first; findings accumulate on the same surface; never pay for
a full-lane probe while a doorway finding is open. J3 (full lane) is the first
materialized full-flow card: `seed-card-user-J3.md` + its checker.

## Run day (orchestrator checklist)

1. `bash tests/gauntlet/tier1.sh`, must be green before any probe round.
2. Mint the probe key (spend-capped), the room's ONLY secret.
3. Invoke `/kit:gauntlet` with persona A's table; the engine handles rounds,
   run records land in `docs/verification/gauntlet/<date>-kit-user/`.
4. Persona B after A converges (or its halt is understood).

Rule 7 note (no answer key): the clean-room image excludes `tests/gauntlet/`
and `docs/verification/gauntlet/`; the runner does this, do not undo it.
