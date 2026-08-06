# Gauntlet campaign: kit-user persona, J3 (full lane)

Card: `seed-card-user-J3.md` (add a `--repeat N` flag the way this repo's
process says features ship). Checker: `check-submission-user-J3.sh` (11
assertions covering the DISCIPLINE: spec with acceptance criteria +
verification command, feature incl. bad-input handling the spec decides,
tests green via the repo's own test command, review verdict, proof-of-done or
override, PR shape). Runner: `mini-tieubao`, probe cap raised to 45 min for
the full lane.

## Rounds

| Round | Host | K | Checker | Wall clock | Cost | Turns | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | Mini | 0 | **GREEN 11/11** | 13m59s | $6.44 | 132 | Full lane completed unaided, first attempt |
| 2 | Mini | 0 | **GREEN 11/11** | 10m50s | $4.48 | 82 | Clean replication; commit order even stricter |

[[QL-VERDICT round=1 clean=true findings=0]]
[[QL-VERDICT round=2 clean=true findings=0]]

## VERDICT: SOLID

Two consecutive unaided passes (rule 9). Ordering verified from each
fixture's own commit history, not just the checker:

- Round 1: adopt + spec + validation report BEFORE the feature commit; a test
  commit cites assertions from a review pass the probe ran on its own work;
  ship commit carries proof-of-done + version bump.
- Round 2: spec -> validate (Status flip) -> test-plan coverage matrix ->
  feat -> review verdict recorded -> proof-of-done WITH a negative control ->
  PR + retro. The probe produced the coverage matrix and the negative control
  without the checker asking for either.

Zero interventions, zero credential hits, both rounds.

## Reading

The doorway row proved the INSTALL path; J3 proves the PROCESS path: the
kit's docs alone steer a median-model dev through spec-first, validation,
tested build, self-review, and gate leave-behinds. The next campaign rows
(J4-J8) are failure-injection: the probe is SUPPOSED to struggle there, and
the findings will be about how the docs handle a dev in trouble rather than a
dev on the happy path.

Cost telemetry: full-lane rounds run 2-3x a doorway round ($4.5-6.5 vs
$2-2.9). Campaign spend to date across both rows: ~$18.2 on the shared
Toolkit key (capped probe item still pending, B7).
