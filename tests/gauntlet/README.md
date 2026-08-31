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
(full lane, bug/debug, gate collision, drift, resume, review response,
concurrent, adversarial), cards materialized per row via `make-card.sh <ROW>`,
generated/reconciled via the shipped SPEC-203 test-generation loop
(`docs/patterns/scenario-generation.md`'s three-move pass) rather than
hand-authored. `journey.md` is the spec the loop consumes; `scenarios.md` is
the reconciled matrix, currently J1-J11.

### Campaign shape (SPEC-227 P5)

A multi-row run is a CAMPAIGN, not a new engine: a worklist over the gauntlet
engine, the campaign shape from `skills/loop-engineering`. One campaign =
one pass over the whole matrix.

- **Run order comes from `scenarios.md`**, top to bottom (row order IS blast
  radius: doorway first, then the full-lane happy path, then the
  failure-injection/boundary/recovery/adversarial/concurrent rows). Never
  reorder ad hoc; if a row needs to jump the queue, move its row in the
  matrix and say why.
- **Budget: one probe round per row, per campaign pass.** A row that does not
  converge within its own round cap (see the inputs table's `Round cap`) is a
  finding for that row, not a license to burn a second round on it in the
  same pass, that is the next campaign's job after the surface revision.
- **Findings accumulate on the same surface across rows.** A campaign does
  not reset the surface between rows; a fix landed for J4 stays landed when
  J5 runs. One `ROUNDS.md` per campaign PASS, at
  `docs/verification/gauntlet/<date>-onboarding-campaign/ROUNDS.md` (the pass
  container `gauntlet-campaign` writes and `campaign-current` symlinks to),
  records every row's outcome (SOLID / REVISE / RECONSIDER / BLOCKED) in run
  order , this is the campaign's run record, the per-row cards are frozen
  alongside it.
- **A row's BLOCKER finding pauses the campaign.** If a round on row N ends
  BLOCKED (the probe wrote a valid `BLOCKED.md`, or the checker cannot pass
  for a surface reason, not a probe error), the campaign stops at row N until
  the surface revision that unblocks it lands and is verified , do not skip
  ahead to row N+1 on an open BLOCKER. Rows before N stay recorded as they
  ran; resuming re-enters at row N, not row 1.

J3 (full lane) was the first materialized full-flow card
(`seed-card-user-J3.md`); J4-J11 materialize the same way, one card + checker
pair per row (`make-card.sh J4` .. `make-card.sh J11`).

## Run day (orchestrator checklist)

1. `bash tests/gauntlet/tier1.sh`, must be green before any probe round.
2. Mint the probe key (spend-capped), the room's ONLY secret.
3. Invoke `/kit:gauntlet` with persona A's table, working `scenarios.md`'s
   rows in order (campaign shape above); run records land in
   `docs/verification/gauntlet/<date>-onboarding-campaign/`, one `ROUNDS.md`
   for the whole pass.
4. On a row's BLOCKER finding, pause the campaign, land the surface revision,
   re-verify, then resume at that row.
5. Persona B after A's campaign converges (or its halt is understood).

Rule 7 note (no answer key): the clean-room image excludes `tests/gauntlet/`
and `docs/verification/gauntlet/`; the runner does this, do not undo it.
